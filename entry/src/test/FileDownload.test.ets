/*
 * 文件下载 / 路径 / 设置 / 清理缓存的单测（1-5 五块的可测部分）。
 *
 * 全部用**注入替身**：DownloadPort（脚本化响应）、FileStore（内存文件系统）、
 * FileSettingsSource（固定设置）、AuthedTaskExecutor（模拟 SessionGate 的重登 / 只重试一次）。
 * 于是"落盘 / 不落盘"这件事可以在**没有设备**的情况下被断言：
 *   - 命中 text/html 时 openSink 一次都没被调用（= 真的没落盘，不是"落了再删"）；
 *   - 失败路径下目标路径不存在（= 不留下损坏文件）；
 *   - 会话失效时任务结果被翻成 requiresEnrollment=true（= 界面回登录页的机制）。
 *
 * 列表排序由既有的
 * FileParser.test.ets -> sortsByUploadTimeDescendingWithIdTieBreak 钉住，这里不重复。
 */

import { describe, it, expect } from '@ohos/hypium';
import { Logger } from '../main/ets/core/log/Logger';
import { CourseFile } from '../main/ets/domain/model/ContentItem';
import {
  appendCsrfToken, evaluateDownloadContentType, evaluateDownloadResponse, evaluateDownloadStatus,
  isSessionLossReason, parseContentLength, redactCsrfToken
} from '../main/ets/domain/files/FileDownloadPolicy';
import {
  cacheKeyFor, canPreviewInApp, FileKind, fileKindOf, fileMetaLine, formatSize, learnXFilesRoot
} from '../main/ets/domain/files/FilePath';
import { DownloadHeaders, DownloadPort, DownloadSink, DownloadStreamResult } from '../main/ets/data/remote/DownloadPort';
import { Session } from '../main/ets/data/remote/Requests';
import { ClearCacheResult, FileDownloader, FileDownloadRequest } from '../main/ets/data/files/FileDownloader';
import { FileRoots, FileSink, FileStore } from '../main/ets/data/files/FileStorePort';
import { FileFetchResult, FileFetchSource } from '../main/ets/data/files/FileFetchSource';
import { FileDownloadReport, FileSnapshot } from '../main/ets/data/files/FileRepository';
import { RealFileRepository } from '../main/ets/data/files/RealFileRepository';
import { AuthedTaskExecutor } from '../main/ets/data/notices/RealNoticeRepository';
import { AuthedRunResult, SessionTask } from '../main/ets/data/auth/SessionRestore';
import { TaskOutcome } from '../main/ets/data/auth/ReAuth';
import { FailReason } from '../main/ets/data/auth/AuthTypes';
import {
  DEFAULT_FILE_SETTINGS, FileSettings, FileSettingsKey, FileSettingsPort, FileSettingsSource,
  FileSettingsStore, InMemoryFileSettingsPort, applyFileSettingsOverride, clearRuntimeFileSettingsOverride,
  describeFileSettings, parseBooleanSwitch, setRuntimeFileSettingsOverride
} from '../main/ets/data/settings/FileSettings';

const SESSION: Session = { cookie: 'JSESSIONID=fixture', csrfToken: 'csrf-fixture-1234567890' };

/** 真实形状的课程文件下载地址（带查询串，于是 _csrf 必须是"参数级替换"）。 */
const DOWNLOAD_URL: string =
  'https://learn.tsinghua.edu.cn/b/wlxt/kj/wlkc_kjxxb/student/downloadFile?sfgk=0&wjid=WJID-1';

/** 路径形态的作业附件地址（**没有** fileId/wjid 查询参数 ⇒ 附件 id 会是空串）。 */
const PATH_FORM_URL: string =
  'https://learn.tsinghua.edu.cn/b/wlxt/kczy/zy/student/downloadFile/2025-2026-2151371080/'
  + '2023011272_ZY_178014313120047eacdb87a-%E4%BD%9C%E4%B8%9A1.pdf';

/* ------------------------------------------------------------------ *
 * 替身
 * ------------------------------------------------------------------ */

/** 脚本化下载端口：会真的调用 sink 的两个回调（于是"落盘 / 不落盘"可判）。 */
class FakeDownloadPort implements DownloadPort {
  status: number = 200;
  contentType: string = 'application/octet-stream';
  contentLength: number = -1;
  chunks: ArrayBuffer[] = [];
  calls: number = 0;
  headersDelivered: number = 0;
  chunksDelivered: number = 0;

  async download(session: Session, url: string, sink: DownloadSink): Promise<DownloadStreamResult> {
    this.calls++;
    const headers: DownloadHeaders = {
      contentType: this.contentType, contentLength: this.contentLength
    };
    const accepted: boolean = sink.onHeaders(headers);
    this.headersDelivered++;
    if (!accepted) {
      return {
        ok: false, status: this.status, contentType: this.contentType,
        contentLength: this.contentLength, receivedBytes: 0, rejected: true
      };
    }
    let received: number = 0;
    for (let i = 0; i < this.chunks.length; i++) {
      sink.onChunk(this.chunks[i]);
      received += this.chunks[i].byteLength;
      this.chunksDelivered++;
    }
    return {
      ok: this.status === 200, status: this.status, contentType: this.contentType,
      contentLength: this.contentLength, receivedBytes: received, rejected: false
    };
  }
}

/** 内存文件 sink。 */
class FakeFileSink implements FileSink {
  private readonly files: Map<string, number>;
  private readonly path: string;
  private bytes: number = 0;

  constructor(files: Map<string, number>, path: string) {
    this.files = files;
    this.path = path;
  }

  write(chunk: ArrayBuffer): void {
    this.bytes += chunk.byteLength;
    this.files.set(this.path, this.bytes);
  }

  close(): void {
  }

  abort(): void {
  }
}

/** 内存文件系统。 */
class FakeFileStore implements FileStore {
  readonly files: Map<string, number> = new Map<string, number>();
  readonly paths: string[] = [];
  readonly dirs: string[] = [];
  readonly removedFiles: string[] = [];
  readonly removedTrees: string[] = [];
  openCalls: number = 0;
  failOpen: boolean = false;
  private readonly filesRoot: string = '/data/app/files';
  private readonly cacheRootPath: string = '/data/app/cache';

  /** 预置一个文件（测"命中缓存"用）。 */
  seed(path: string, bytes: number): void {
    this.files.set(path, bytes);
    this.paths.push(path);
  }

  roots(): FileRoots {
    return { filesDir: this.filesRoot, cacheDir: this.cacheRootPath };
  }

  ensureDir(dir: string): void {
    this.dirs.push(dir);
  }

  exists(path: string): boolean {
    return this.files.has(path);
  }

  openSink(path: string): FileSink {
    if (this.failOpen) {
      throw new Error('fake open failure');
    }
    this.openCalls++;
    if (this.paths.indexOf(path) < 0) {
      this.paths.push(path);
    }
    return new FakeFileSink(this.files, path);
  }

  remove(path: string): void {
    this.removedFiles.push(path);
    this.files.delete(path);
  }

  removeTree(path: string): void {
    this.removedTrees.push(path);
    for (let i = 0; i < this.paths.length; i++) {
      if (this.paths[i].startsWith(path)) {
        this.files.delete(this.paths[i]);
      }
    }
  }

  fileSize(path: string): number {
    const value: number | undefined = this.files.get(path);
    return value === undefined ? 0 : value;
  }
}

/** 固定设置来源（下载器读它）。 */
class FakeSettings implements FileSettingsSource {
  private readonly value: FileSettings;

  constructor(value: FileSettings) {
    this.value = value;
  }

  current(): FileSettings {
    return applyFileSettingsOverride(this.value);
  }
}

/** 持久化替身，记录写回次数。 */
class RecordingSettingsPort implements FileSettingsPort {
  saves: number = 0;
  stored: FileSettings | null = null;

  async load(): Promise<FileSettings | null> {
    return this.stored;
  }

  async save(value: FileSettings): Promise<boolean> {
    this.saves++;
    this.stored = value;
    return true;
  }
}

/** 模拟 SessionGate：首次 403 时重登并**只重试一次**（与 data/auth/ReAuth 的触发并集一致）。 */
class FakeExecutor implements AuthedTaskExecutor {
  readonly statuses: number[] = [];
  private readonly retry: boolean;

  constructor(retry: boolean) {
    this.retry = retry;
  }

  async run(task: SessionTask): Promise<AuthedRunResult> {
    const first: TaskOutcome = await task(SESSION);
    this.statuses.push(first.status);
    if (this.retry && first.status === 403) {
      const second: TaskOutcome = await task(SESSION);
      this.statuses.push(second.status);
      if (second.status === 403) {
        return AuthedRunResult.degraded(FailReason.NOT_LOGGED_IN, true, 'still noLogin after reAuth');
      }
      return AuthedRunResult.success(second.body, true, 'status=' + second.status.toString());
    }
    return AuthedRunResult.success(first.body, false, 'status=' + first.status.toString());
  }
}

/** 固定文件取数源。 */
class FakeFileFetchSource implements FileFetchSource {
  private readonly files: CourseFile[];

  constructor(files: CourseFile[]) {
    this.files = files;
  }

  async fetchWithSession(session: Session): Promise<FileFetchResult> {
    return { files: this.files, semesterId: '2026-2027-1', siteCurrentSemesterId: '2026-2027-1' };
  }
}

/* ------------------------------------------------------------------ *
 * 夹具
 * ------------------------------------------------------------------ */

function chunkOf(size: number): ArrayBuffer {
  return new ArrayBuffer(size);
}

function fileOf(): CourseFile {
  return {
    id: 'kjxxid-1',
    fileId: 'WJID-1',
    title: '第 1 章 绪论',
    description: '课程讲义',
    size: '1.50KB',
    uploadTime: '2026-09-01 10:00',
    fileType: 'pdf',
    courseId: '2026-2027-1152226210',
    courseName: '通信与网络',
    courseTeacherName: '周世东',
    isNew: true,
    downloadUrl: DOWNLOAD_URL
  };
}

function requestOf(refresh: boolean): FileDownloadRequest {
  return {
    downloadUrl: DOWNLOAD_URL,
    cacheKey: cacheKeyFor('WJID-1', DOWNLOAD_URL),
    courseName: '通信与网络',
    title: '第 1 章 绪论',
    fileType: 'pdf',
    refresh: refresh
  };
}

function downloaderWith(port: FakeDownloadPort, store: FakeFileStore,
  settings: FileSettings): FileDownloader {
  return new FileDownloader(port, store, new FakeSettings(settings),
    new Logger('test.files.download'));
}

/** 目标路径（与下载器内部一致；单测里用它断言"到底写没写那个文件"）。 */
function expectedPath(useDocumentDir: boolean, omitCourseName: boolean): string {
  const root: string = learnXFilesRoot('/data/app/files', '/data/app/cache', useDocumentDir);
  const name: string = omitCourseName ? '第 1 章 绪论.pdf' : '通信与网络-第 1 章 绪论.pdf';
  return root + '/通信与网络/' + cacheKeyFor('WJID-1', DOWNLOAD_URL) + '/' + name;
}

export default function fileDownloadTest() {
  describe('domain.filePolicy', () => {
    it('rejectsHtmlAndJsonBeforeAcceptingAnythingElse', 0, () => {
      expect(evaluateDownloadContentType('text/html; charset=gb2312').accept).assertFalse();
      expect(evaluateDownloadContentType('text/html; charset=gb2312').reason).assertEqual('html-login-page');
      expect(evaluateDownloadContentType('TEXT/HTML').accept).assertFalse();
      expect(evaluateDownloadContentType('application/xhtml+xml').accept).assertFalse();
      expect(evaluateDownloadContentType('application/json').accept).assertFalse();
      expect(evaluateDownloadContentType('application/json').reason).assertEqual('json-error-page');
      // 合法文件类型（含 text/plain —— 课程里真的有 .txt）必须放行。
      expect(evaluateDownloadContentType('application/octet-stream').accept).assertTrue();
      expect(evaluateDownloadContentType('application/pdf').accept).assertTrue();
      expect(evaluateDownloadContentType('image/png').accept).assertTrue();
      expect(evaluateDownloadContentType('text/plain').accept).assertTrue();
      // Content-Type 缺失：**不猜**，按接受处理（判定边界写清在 policy 的文件头）。
      expect(evaluateDownloadContentType('').accept).assertTrue();
    });

    it('rejectsNonOkStatusAndComposesBothRules', 0, () => {
      expect(evaluateDownloadStatus(200).accept).assertTrue();
      expect(evaluateDownloadStatus(403).reason).assertEqual('status:403');
      expect(evaluateDownloadStatus(500).reason).assertEqual('status:500');
      expect(evaluateDownloadResponse(200, 'application/pdf').accept).assertTrue();
      expect(evaluateDownloadResponse(403, 'text/html').reason).assertEqual('status:403');
      expect(evaluateDownloadResponse(200, 'text/html').reason).assertEqual('html-login-page');
      expect(isSessionLossReason('html-login-page')).assertTrue();
      expect(isSessionLossReason('status:403')).assertTrue();
      expect(isSessionLossReason('status:500')).assertFalse();
      expect(isSessionLossReason('json-error-page')).assertFalse();
    });

    it('appendsCsrfLikeUrlSearchParamsSet', 0, () => {
      expect(appendCsrfToken(DOWNLOAD_URL, 'tok'))
        .assertEqual(DOWNLOAD_URL + '&_csrf=tok');
      expect(appendCsrfToken('https://x/y', 'tok')).assertEqual('https://x/y?_csrf=tok');
      // 已有 _csrf 时**替换**而不是追加第二个（参考实现用 searchParams.set）。
      expect(appendCsrfToken('https://x/y?a=1&_csrf=old&b=2', 'new'))
        .assertEqual('https://x/y?a=1&_csrf=new&b=2');
      // 空 token 也写成 _csrf=（set 的语义）。
      expect(appendCsrfToken('https://x/y', '')).assertEqual('https://x/y?_csrf=');
      // fragment 保留在末尾。
      expect(appendCsrfToken('https://x/y?a=1#frag', 'tok')).assertEqual('https://x/y?a=1&_csrf=tok#frag');
    });

    it('redactsCsrfValueButKeepsTheParameterName', 0, () => {
      const url: string = appendCsrfToken(DOWNLOAD_URL, 'super-secret-token');
      const redacted: string = redactCsrfToken(url);
      expect(redacted.includes('super-secret-token')).assertFalse();
      expect(redacted.includes('_csrf=***')).assertTrue();
      expect(redacted.includes('wjid=WJID-1')).assertTrue();
    });

    it('parsesContentLengthHonestly', 0, () => {
      expect(parseContentLength('2048')).assertEqual(2048);
      expect(parseContentLength('')).assertEqual(-1);
      expect(parseContentLength('0')).assertEqual(-1);
      expect(parseContentLength('-5')).assertEqual(-1);
      expect(parseContentLength('not-a-number')).assertEqual(-1);
    });

    it('formatsSizeLikeTheReference', 0, () => {
      expect(formatSize(0)).assertEqual('0 B');
      expect(formatSize(-1)).assertEqual('0 B');
      expect(formatSize(512)).assertEqual('512 B');
      expect(formatSize(1024)).assertEqual('1 KB');
      expect(formatSize(1536)).assertEqual('1.5 KB');
      expect(formatSize(139.54 * 1024)).assertEqual('139.54 KB');
    });

    it('fallsBackToTheDownloadUrlTailWhenTheIdIsEmpty', 0, () => {
      // 作业附件的 id 可能是空串。
      const key: string = cacheKeyFor('', PATH_FORM_URL);
      expect(key).assertEqual('2023011272_ZY_178014313120047eacdb87a-作业1.pdf');
      expect(key.length > 0).assertTrue();
      expect(cacheKeyFor('   ', PATH_FORM_URL)).assertEqual(key);
      // 有 id 时用 id。
      expect(cacheKeyFor('WJID-1', DOWNLOAD_URL)).assertEqual('WJID-1');
      // 两者都取不到时也不产生空片段。
      expect(cacheKeyFor('', '')).assertEqual('file');
      expect(cacheKeyFor('', 'https://x/y/')).assertEqual('file');
    });

    it('buildsChineseAndSpacePathsFromTheSettings', 0, () => {
      const withCourse: string = expectedPath(false, false);
      expect(withCourse).assertEqual('/data/app/cache/learnX-files/通信与网络/WJID-1/通信与网络-第 1 章 绪论.pdf');
      const documentRoot: string = expectedPath(true, false);
      expect(documentRoot.startsWith('/data/app/files/learnX-files/')).assertTrue();
      const omitted: string = expectedPath(false, true);
      expect(omitted.endsWith('/WJID-1/第 1 章 绪论.pdf')).assertTrue();
      // 中文与空格**逐字保留**。
      expect(withCourse.includes('通信与网络')).assertTrue();
      expect(withCourse.includes('第 1 章 绪论')).assertTrue();
    });

    it('classifiesPreviewableTypesAndMetaLine', 0, () => {
      expect(fileKindOf('pdf')).assertEqual(FileKind.PDF);
      expect(fileKindOf('PDF')).assertEqual(FileKind.PDF);
      expect(fileKindOf('PNG')).assertEqual(FileKind.IMAGE);
      expect(fileKindOf('jpeg')).assertEqual(FileKind.IMAGE);
      expect(fileKindOf('docx')).assertEqual(FileKind.OTHER);
      expect(canPreviewInApp('pdf')).assertTrue();
      expect(canPreviewInApp('jpg')).assertTrue();
      expect(canPreviewInApp('zip')).assertFalse();
      // "显示大小与类型"的那一行。
      expect(fileMetaLine('pdf', '1.50KB')).assertEqual('PDF 1.50KB');
      expect(fileMetaLine('', '1.50KB')).assertEqual('1.50KB');
      expect(fileMetaLine('pdf', '')).assertEqual('PDF');
      expect(fileMetaLine('', '')).assertEqual('');
    });
  });

  describe('data.fileDownload', () => {
    it('writesTheFileWhenTheResponseIsARealFile', 0, async () => {
      clearRuntimeFileSettingsOverride();
      const port: FakeDownloadPort = new FakeDownloadPort();
      port.contentType = 'application/pdf';
      port.contentLength = 3000;
      port.chunks = [chunkOf(1024), chunkOf(1976)];
      const store: FakeFileStore = new FakeFileStore();
      const progress: number[][] = [];
      const downloader: FileDownloader = downloaderWith(port, store, DEFAULT_FILE_SETTINGS);
      const outcome = await downloader.download(SESSION, requestOf(false),
        (received: number, total: number): void => {
          progress.push([received, total]);
        });
      expect(outcome.ok).assertTrue();
      expect(outcome.rejectedReason).assertEqual('');
      expect(store.openCalls).assertEqual(1);
      expect(store.fileSize(outcome.path)).assertEqual(3000);
      expect(outcome.path).assertEqual(expectedPath(false, false));
      // 真进度：回调收到的是**已接收字节 + Content-Length**，不是估算。
      expect(progress.length).assertEqual(2);
      expect(progress[0][0]).assertEqual(1024);
      expect(progress[1][0]).assertEqual(3000);
      expect(progress[1][1]).assertEqual(3000);
      expect(port.calls).assertEqual(1);
    });

    it('neverOpensTheFileGateWhenTheResponseIsALoginPage', 0, async () => {
      clearRuntimeFileSettingsOverride();
      const port: FakeDownloadPort = new FakeDownloadPort();
      port.status = 200;
      port.contentType = 'text/html; charset=gb2312';
      port.chunks = [chunkOf(1280)];
      const store: FakeFileStore = new FakeFileStore();
      const downloader: FileDownloader = downloaderWith(port, store, DEFAULT_FILE_SETTINGS);
      const outcome = await downloader.download(SESSION, requestOf(false));
      // 判据一：**一个字节都没写**（不是"写了再删"）。
      expect(store.openCalls).assertEqual(0);
      expect(store.files.size).assertEqual(0);
      // 判据二：明确的原因 + 没有任何残留文件。
      expect(outcome.ok).assertFalse();
      expect(outcome.rejectedReason).assertEqual('html-login-page');
      expect(store.exists(outcome.path)).assertFalse();
      expect(store.fileSize(outcome.path)).assertEqual(0);
    });

    it('removesTheFileWhenTheStatusIsNotOk', 0, async () => {
      clearRuntimeFileSettingsOverride();
      const port: FakeDownloadPort = new FakeDownloadPort();
      port.status = 500;
      port.contentType = 'application/octet-stream';
      port.contentLength = 20;
      port.chunks = [chunkOf(20)];
      const store: FakeFileStore = new FakeFileStore();
      const downloader: FileDownloader = downloaderWith(port, store, DEFAULT_FILE_SETTINGS);
      const outcome = await downloader.download(SESSION, requestOf(false));
      expect(outcome.ok).assertFalse();
      expect(outcome.rejectedReason).assertEqual('status:500');
      // 状态码只能在流结束后判定（平台只在 requestInStream 的 promise 里给），
      // 所以这一条是"写了再删"——留下的仍然是**没有文件**。
      expect(store.openCalls).assertEqual(1);
      expect(store.exists(outcome.path)).assertFalse();
      expect(store.removedFiles.includes(outcome.path)).assertTrue();
    });

    it('treatsAnEmptyBodyAsFailureWithoutLeavingAFile', 0, async () => {
      clearRuntimeFileSettingsOverride();
      const port: FakeDownloadPort = new FakeDownloadPort();
      port.contentType = 'application/pdf';
      port.contentLength = 0;
      port.chunks = [];
      const store: FakeFileStore = new FakeFileStore();
      const downloader: FileDownloader = downloaderWith(port, store, DEFAULT_FILE_SETTINGS);
      const outcome = await downloader.download(SESSION, requestOf(false));
      expect(outcome.ok).assertFalse();
      expect(outcome.error).assertEqual('empty file');
      expect(store.exists(outcome.path)).assertFalse();
    });

    it('hitsTheCacheAndSkipsTheRequestUnlessRefreshIsAsked', 0, async () => {
      clearRuntimeFileSettingsOverride();
      const port: FakeDownloadPort = new FakeDownloadPort();
      port.contentType = 'application/pdf';
      port.chunks = [chunkOf(64)];
      const store: FakeFileStore = new FakeFileStore();
      store.seed(expectedPath(false, false), 4096);
      const downloader: FileDownloader = downloaderWith(port, store, DEFAULT_FILE_SETTINGS);
      const cached = await downloader.download(SESSION, requestOf(false));
      expect(cached.ok).assertTrue();
      expect(cached.fromCache).assertTrue();
      expect(cached.bytes).assertEqual(4096);
      expect(port.calls).assertEqual(0);
      // refresh=true 忽略缓存（参考实现 handleDownload(true)）。
      const refreshed = await downloader.download(SESSION, requestOf(true));
      expect(port.calls).assertEqual(1);
      expect(refreshed.fromCache).assertFalse();
    });

    it('appliesBothFileSettingsToThePathAndTheRoot', 0, async () => {
      clearRuntimeFileSettingsOverride();
      const port: FakeDownloadPort = new FakeDownloadPort();
      port.contentType = 'application/pdf';
      port.chunks = [chunkOf(10)];
      const store: FakeFileStore = new FakeFileStore();
      const settings: FileSettings = { useDocumentDir: true, omitCourseName: true };
      const downloader: FileDownloader = downloaderWith(port, store, settings);
      const outcome = await downloader.download(SESSION, requestOf(false));
      expect(outcome.ok).assertTrue();
      // 落盘根目录 = 文档目录（不是缓存）。
      expect(outcome.path.startsWith('/data/app/files/learnX-files/')).assertTrue();
      expect(outcome.path.endsWith('/第 1 章 绪论.pdf')).assertTrue();
      expect(outcome.path).assertEqual(expectedPath(true, true));
    });

    it('clearsTheWholeLearnXFilesRoot', 0, () => {
      clearRuntimeFileSettingsOverride();
      const store: FakeFileStore = new FakeFileStore();
      const seeded: string = expectedPath(false, false);
      store.seed(seeded, 2048);
      const downloader: FileDownloader = downloaderWith(new FakeDownloadPort(), store, DEFAULT_FILE_SETTINGS);
      expect(store.exists(seeded)).assertTrue();
      const result: ClearCacheResult = downloader.clearCache();
      expect(result.ok).assertTrue();
      expect(result.root).assertEqual('/data/app/cache/learnX-files');
      expect(store.exists(seeded)).assertFalse();
      expect(store.removedTrees.includes('/data/app/cache/learnX-files')).assertTrue();
      // 文档目录打开时清的是文档那一份（参考实现 removeFileDir 删的是同一个根）。
      const documentStore: FakeFileStore = new FakeFileStore();
      const documentDownloader: FileDownloader = downloaderWith(new FakeDownloadPort(), documentStore,
        { useDocumentDir: true, omitCourseName: false });
      expect(documentDownloader.clearCache().root).assertEqual('/data/app/files/learnX-files');
    });

    it('reportsOpenFailureInsteadOfWriting', 0, async () => {
      clearRuntimeFileSettingsOverride();
      const port: FakeDownloadPort = new FakeDownloadPort();
      port.contentType = 'application/pdf';
      port.chunks = [chunkOf(8)];
      const store: FakeFileStore = new FakeFileStore();
      store.failOpen = true;
      const downloader: FileDownloader = downloaderWith(port, store, DEFAULT_FILE_SETTINGS);
      const outcome = await downloader.download(SESSION, requestOf(false));
      expect(outcome.ok).assertFalse();
      expect(outcome.error.includes('open failed')).assertTrue();
      expect(store.exists(outcome.path)).assertFalse();
    });
  });

  describe('data.fileRepository', () => {
    it('turnsALoginPageIntoRequiresEnrollmentWithoutLeavingAFile', 0, async () => {
      clearRuntimeFileSettingsOverride();
      const port: FakeDownloadPort = new FakeDownloadPort();
      port.status = 200;
      port.contentType = 'text/html';
      port.chunks = [chunkOf(1000)];
      const store: FakeFileStore = new FakeFileStore();
      const downloader: FileDownloader = downloaderWith(port, store, DEFAULT_FILE_SETTINGS);
      const executor: FakeExecutor = new FakeExecutor(true);
      const repository: RealFileRepository = new RealFileRepository(executor,
        new FakeFileFetchSource([fileOf()]), downloader, new Logger('test.files.repository'));
      const report: FileDownloadReport = await repository.download(requestOf(false));
      // 机制：命中 HTML -> 任务结果 403 -> SessionGate 重登并**只重试一次**（两次都为 403）。
      expect(executor.statuses.length).assertEqual(2);
      expect(executor.statuses[0]).assertEqual(403);
      expect(executor.statuses[1]).assertEqual(403);
      expect(report.requiresEnrollment).assertTrue();
      expect(report.outcome.ok).assertFalse();
      expect(report.outcome.rejectedReason).assertEqual('html-login-page');
      // 不留下损坏文件。
      expect(store.files.size).assertEqual(0);
      expect(store.openCalls).assertEqual(0);
    });

    it('doesNotTriggerReAuthForNonSessionFailures', 0, async () => {
      clearRuntimeFileSettingsOverride();
      const port: FakeDownloadPort = new FakeDownloadPort();
      port.status = 500;
      port.contentType = 'application/octet-stream';
      port.chunks = [chunkOf(4)];
      const store: FakeFileStore = new FakeFileStore();
      const downloader: FileDownloader = downloaderWith(port, store, DEFAULT_FILE_SETTINGS);
      const executor: FakeExecutor = new FakeExecutor(true);
      const repository: RealFileRepository = new RealFileRepository(executor,
        new FakeFileFetchSource([fileOf()]), downloader, new Logger('test.files.repository'));
      const report: FileDownloadReport = await repository.download(requestOf(false));
      expect(executor.statuses.length).assertEqual(1);
      expect(executor.statuses[0]).assertEqual(200);
      expect(report.requiresEnrollment).assertFalse();
      expect(report.outcome.ok).assertFalse();
      expect(store.files.size).assertEqual(0);
    });

    it('refreshesAndReportsTheFetchedFiles', 0, async () => {
      clearRuntimeFileSettingsOverride();
      const port: FakeDownloadPort = new FakeDownloadPort();
      const store: FakeFileStore = new FakeFileStore();
      const downloader: FileDownloader = downloaderWith(port, store, DEFAULT_FILE_SETTINGS);
      const executor: FakeExecutor = new FakeExecutor(true);
      const repository: RealFileRepository = new RealFileRepository(executor,
        new FakeFileFetchSource([fileOf()]), downloader, new Logger('test.files.repository'));
      const snapshot: FileSnapshot = await repository.refresh();
      expect(snapshot.files.length).assertEqual(1);
      expect(snapshot.files[0].title).assertEqual('第 1 章 绪论');
      expect(snapshot.semesterId).assertEqual('2026-2027-1');
    });
  });

  describe('data.fileSettings', () => {
    it('defaultsToTheReferenceValuesAndPersistsChanges', 0, async () => {
      clearRuntimeFileSettingsOverride();
      const port: RecordingSettingsPort = new RecordingSettingsPort();
      const store: FileSettingsStore = new FileSettingsStore(port);
      const initial: FileSettings = await store.load();
      expect(initial.useDocumentDir).assertEqual(DEFAULT_FILE_SETTINGS.useDocumentDir);
      expect(initial.omitCourseName).assertEqual(DEFAULT_FILE_SETTINGS.omitCourseName);
      expect(await store.set(FileSettingsKey.USE_DOCUMENT_DIR, true)).assertTrue();
      expect(await store.set(FileSettingsKey.OMIT_COURSE_NAME, true)).assertTrue();
      expect(port.saves).assertEqual(2);
      expect(store.current().useDocumentDir).assertTrue();
      expect(store.current().omitCourseName).assertTrue();
      // 只改一项时另一项保持。
      expect(await store.set(FileSettingsKey.OMIT_COURSE_NAME, false)).assertTrue();
      expect(store.current().useDocumentDir).assertTrue();
      expect(store.current().omitCourseName).assertFalse();
    });

    it('loadsPersistedValuesAndAppliesTheRuntimeOverride', 0, async () => {
      clearRuntimeFileSettingsOverride();
      const port: RecordingSettingsPort = new RecordingSettingsPort();
      port.stored = { useDocumentDir: true, omitCourseName: false };
      const store: FileSettingsStore = new FileSettingsStore(port);
      const loaded: FileSettings = await store.load();
      expect(loaded.useDocumentDir).assertTrue();
      expect(store.stored().useDocumentDir).assertTrue();
      // 覆盖优先（取证用脚本入口），且**只**盖被设置的那一项。
      expect(setRuntimeFileSettingsOverride('0', '')).assertTrue();
      expect(store.current().useDocumentDir).assertFalse();
      expect(store.current().omitCourseName).assertFalse();
      expect(store.stored().useDocumentDir).assertTrue();
      expect(describeFileSettings(store.current()).includes('source=runtime-want-param')).assertTrue();
      expect(describeFileSettings(store.current()).includes('useDocumentDir=false')).assertTrue();
      clearRuntimeFileSettingsOverride();
      expect(store.current().useDocumentDir).assertTrue();
      // 非法值不生效（避免把打字错误当成"生效"）。
      expect(setRuntimeFileSettingsOverride('maybe', '')).assertFalse();
      expect(parseBooleanSwitch('1')).assertTrue();
      expect(parseBooleanSwitch(' TRUE ')).assertTrue();
      expect(parseBooleanSwitch('0')).assertFalse();
      expect(parseBooleanSwitch('off')).assertFalse();
      expect(parseBooleanSwitch('') === undefined).assertTrue();
    });

    it('keepsTheInMemoryPortUsableWithoutAPlatformStore', 0, async () => {
      clearRuntimeFileSettingsOverride();
      const store: FileSettingsStore = new FileSettingsStore(new InMemoryFileSettingsPort());
      await store.load();
      await store.set(FileSettingsKey.USE_DOCUMENT_DIR, true);
      const reloaded: FileSettingsStore = new FileSettingsStore(new InMemoryFileSettingsPort());
      expect(reloaded.stored().useDocumentDir).assertFalse();
      const value: FileSettings = applyFileSettingsOverride({ useDocumentDir: false, omitCourseName: true });
      expect(value.omitCourseName).assertTrue();
    });
  });
}
