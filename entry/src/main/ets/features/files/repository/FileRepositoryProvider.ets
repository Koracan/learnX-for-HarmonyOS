/*
 * 文件数据源与设置的**组装点**（composition root）。
 *
 * 与 `features/courses/repository/CourseRepositoryProvider` 同一模式：
 * 界面只依赖 `FileRepository` 接口；数据路径**只经过** `AuthedTaskRunner`
 * （data/auth/SessionRestore），这里不重新实现重登/重试/降级。
 *
 * 三件东西在这里接起来：
 *   1. `HttpFileFetchSource`（学期 → 课程列表 → FilesFetcher）；
 *   2. `FileDownloader`（`HttpDownloadPort` + `DeviceFileStore` + 设置）；
 *   3. `FileSettingsStore`（值/语义在 `data/settings/FileSettings`，**持久化入口只此一处**；
 *      界面入口归全局设置）。
 *
 * Context 拿不到时**不回落成"能下载"**：返回一个"永远失败"的仓储，界面走错误态。
 */

import { common } from '@kit.AbilityKit';
import { Logger } from '../../../core/log/Logger';
import { COURSE_LIST_LOG_DOMAIN, HttpCourseListSource } from '../../../data/courses/CourseListFetcher';
import { HttpSemesterSource } from '../../../data/courses/SemesterFetcher';
import { DeviceFileStore } from '../../../data/files/DeviceFileStore';
import {
  ClearCacheResult, DownloadProgressSink, FileDownloadRequest, FileDownloader
} from '../../../data/files/FileDownloader';
import { HttpFileFetchSource } from '../../../data/files/FileFetchSource';
import { FileDownloadReport, FileRepository, FileSnapshot } from '../../../data/files/FileRepository';
import { RealFileRepository } from '../../../data/files/RealFileRepository';
import { AuthedTaskExecutor } from '../../../data/notices/RealNoticeRepository';
import { HttpDownloadPort } from '../../../data/remote/HttpDownloadPort';
import { HttpFetchPort } from '../../../data/remote/HttpFetchPort';
import { AuthedRunResult, AuthedTaskRunner, SessionTask } from '../../../data/auth/SessionRestore';
import {
  FileSettingsPort, FileSettingsStore, InMemoryFileSettingsPort
} from '../../../data/settings/FileSettings';
import { PreferencesFileSettingsPort } from '../../../data/settings/PreferencesFileSettings';
import { MockFileRepository } from '../../../data/mock/MockFileRepository';
import { isMockMode } from '../../mock/MockMode';
import { authServices } from '../../auth/AuthServices';

const logger: Logger = new Logger('features.files.provider');

/** 取宿主 Context：优先 UIContext，拿不到时退回 getContext()。 */
function hostContext(): common.Context | null {
  try {
    return getContext() as common.Context;
  } catch (error) {
    logger.error('no host context for the file store: ' + (error as Error).message);
    return null;
  }
}

/* ------------------------------------------------------------------ *
 * 文件设置（进程内单例：下载器与设置页读的是**同一个** store）
 * ------------------------------------------------------------------ */

let settingsStore: FileSettingsStore | null = null;

/** 当前生效的文件设置 store（值/语义在 data/settings；界面入口归全局设置）。 */
export function fileSettingsStore(): FileSettingsStore {
  if (settingsStore === null) {
    const context: common.Context | null = hostContext();
    const port: FileSettingsPort = context === null
      ? new InMemoryFileSettingsPort()
      : new PreferencesFileSettingsPort(context);
    settingsStore = new FileSettingsStore(port);
    logger.info('file settings store wired: persistence=' + (context === null ? 'memory' : 'preferences'));
  }
  return settingsStore;
}

/* ------------------------------------------------------------------ *
 * 文件仓储（进程内单例：列表页与详情页共用同一份设置与同一份 FileStore）
 * ------------------------------------------------------------------ */

let repository: FileRepository | null = null;

/** 真实实现（进程内单例）。 */
function realFileRepository(): FileRepository {
  if (repository !== null) {
    return repository;
  }
  const context: common.Context | null = hostContext();
  if (context === null) {
    repository = new MissingContextFileRepository();
    logger.error('file repository wired: source=missing-context (all operations fail explicitly)');
    return repository;
  }
  const fetchPort: HttpFetchPort = new HttpFetchPort();
  const semesters: HttpSemesterSource =
    new HttpSemesterSource(new Logger(COURSE_LIST_LOG_DOMAIN), fetchPort);
  const courses: HttpCourseListSource =
    new HttpCourseListSource(new Logger(COURSE_LIST_LOG_DOMAIN), fetchPort, semesters);
  const source: HttpFileFetchSource =
    new HttpFileFetchSource(fetchPort, semesters, courses, new Logger('data.files.source'));
  const store: DeviceFileStore = new DeviceFileStore(context);
  const settings: FileSettingsStore = fileSettingsStore();
  const downloader: FileDownloader = new FileDownloader(
    new HttpDownloadPort(new Logger('data.files.download')), store, settings,
    new Logger('data.files.downloader'));
  const executor: AuthedTaskExecutor = new RunnerTaskExecutor(authServices.runner);
  logger.info('file repository wired: source=real (semesters + course list + files + http download)');
  repository = new RealFileRepository(executor, source, downloader, new Logger('data.files.repository'));
  return repository;
}

/**
 * 当前生效的文件数据源。
 *
 * Mock 模式返回一个**每次新建**的薄包装：取数走样例、下载直接短路，
 * 文件系统三件事委托给真实实现。为什么每次都新建而不是缓存：真实实现是单例，
 * 而 mock 开关可能在同一进程里被登出/再登录改掉（guest → 真实账号），
 * 缓存住 mock 包装会让第二次登录继续看样例数据。
 */
export function fileRepository(): FileRepository {
  const real: FileRepository = realFileRepository();
  if (isMockMode()) {
    logger.info('file repository wired: source=mock (sample data + short-circuited download, zero network)');
    return new MockFileRepository(real);
  }
  return real;
}

/**
 * 把 `AuthedTaskRunner` 显式适配成 `AuthedTaskExecutor`。
 *
 * 为什么不直接赋值：ArkTS 不做结构类型（arkts-no-structural-typing），两个形状相同的接口
 * 也不能互相赋值（实测）。适配器只有一行转发，并让"数据路径只经过
 * AuthedTaskRunner"这件事在类型上可见。
 */
class RunnerTaskExecutor implements AuthedTaskExecutor {
  private readonly runner: AuthedTaskRunner;

  constructor(runner: AuthedTaskRunner) {
    this.runner = runner;
  }

  run(task: SessionTask): Promise<AuthedRunResult> {
    return this.runner.run(task);
  }
}

/** Context 不可用时的显式失败实现（不返回空列表、不假装能下载）。 */
class MissingContextFileRepository implements FileRepository {
  async refresh(): Promise<FileSnapshot> {
    throw new Error('file repository unavailable: no host context for the file store');
  }

  async download(request: FileDownloadRequest,
    onProgress?: DownloadProgressSink): Promise<FileDownloadReport> {
    throw new Error('file repository unavailable: no host context for the file store');
  }

  targetPath(request: FileDownloadRequest): string {
    return '';
  }

  cacheRoot(): string {
    return '';
  }

  clearCache(): ClearCacheResult {
    return { ok: false, root: '', error: 'no host context for the file store' };
  }
}
