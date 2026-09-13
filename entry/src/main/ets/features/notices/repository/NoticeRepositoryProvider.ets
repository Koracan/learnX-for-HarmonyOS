/*
 * 公告数据源的组装点（composition root）。
 *
 * 界面（features/notices/NoticesPage.ets）只依赖 NoticeRepository 接口，且只从
 * 这里拿实现 —— 以后换真实实现时只改本文件，界面不动。
 *
 * ## 现在换成了什么
 *
 * 返回 **data/notices/RealNoticeRepository**（真实抓取 + 快照），它自己接
 * `AuthedTaskRunner`（data/auth/SessionRestore 的数据路径统一入口：先确保有会话，
 * 会话失效时重登且只重试一次，失败显式降级）。**这里不重新实现重登/重试/降级**。
 *
 * ## 两个取证开关（遗留至今）
 *
 * 它们只在启动时调应用级 setColorMode/setLanguage，用于深色/英文截图，
 * **不碰设备全局设置**（避免影响并行工作的其他 agent）。提交态都是 false。
 * 设置与 Mock 模式的用户可见开关落地时应把它们替换掉。
 *
 * 注：早先的 `MOCK_EMPTY_FOR_EVIDENCE` / `SLOW_MOCK_FOR_EVIDENCE` 已随
 * Mock 数据源一起删除（它们只对 Mock 有意义）；快照路径的"慢"不需要开关——
 * 冷启动先渲染快照本身就是可截的帧。
 */

import { common } from '@kit.AbilityKit';
import { Logger } from '../../../core/log/Logger';
import { authServices } from '../../auth/AuthServices';
import { decodeBase64Text } from '../../../core/codec/TextCodec';
import { HttpFetchPort } from '../../../data/remote/HttpFetchPort';
import { NoticeRepository, NoticeSnapshot } from '../../../data/notices/NoticeRepository';
import { AuthedTaskExecutor, RealNoticeRepository } from '../../../data/notices/RealNoticeRepository';
import { AuthedRunResult, AuthedTaskRunner, SessionTask } from '../../../data/auth/SessionRestore';
import { HttpNoticeFetchSource } from '../../../data/notices/NoticeFetchSource';
import {
  COURSE_LIST_LOG_DOMAIN, HttpCourseListSource, HttpSemesterSource
} from '../../../data/notices/CourseListFetcher';
import { NoticeSnapshotFileStore } from '../../../data/notices/NoticeSnapshotFileStore';
import { MockNoticeRepository } from '../../../data/mock/MockNoticeRepository';
import { isMockMode } from '../../mock/MockMode';

/** 取证开关：启动时强制深色（深色截图）。提交态 false。 */
export const FORCE_DARK_FOR_EVIDENCE: boolean = false;

/** 取证开关：启动时切应用语言到英文（英文截图）。提交态 false。 */
export const FORCE_ENGLISH_FOR_EVIDENCE: boolean = false;

/**
 * 把两个取证开关的**实际生效值**打进 hilog（AGENTS.md 的取证要点：开关必须自证生效）。
 * 踩过一次"以为开关生效了、其实是常量内联/增量编译没跟上"，所以这行是必要的，
 * 而不是可选的噪音。它在 aboutToAppear 里被调用（见 ShellTabs）。
 */
export function logEvidenceSwitchState(): void {
  logger.info('evidence switches: FORCE_DARK_FOR_EVIDENCE=' + FORCE_DARK_FOR_EVIDENCE.toString()
    + ' FORCE_ENGLISH_FOR_EVIDENCE=' + FORCE_ENGLISH_FOR_EVIDENCE.toString());
}

const logger: Logger = new Logger('features.notices.provider');

/** 取宿主 Context：优先 UIContext（推荐接口），拿不到时退回 getContext()。 */
function hostContext(): common.Context | null {
  try {
    return getContext() as common.Context;
  } catch (error) {
    logger.error('no host context for the notice snapshot store: ' + (error as Error).message);
    return null;
  }
}

/**
 * 当前生效的公告数据源。
 *
 * Context 拿不到时**不回落到 Mock**：那会把"平台没就绪"显示成"你有一堆公告"。
 * 这里返回一个"永远失败"的仓储，界面走错误态（与 RealNoticeRepository 的降级口径一致）。
 */
export function createNoticeRepository(): NoticeRepository {
  // Mock 模式：样例数据，**不发任何请求**。判据只有 features/mock/MockMode 一处。
  if (isMockMode()) {
    logger.info('notice repository wired: source=mock (guest mode, zero network)');
    return new MockNoticeRepository();
  }
  const context: common.Context | null = hostContext();
  if (context === null) {
    return new MissingContextNoticeRepository();
  }
  const port: HttpFetchPort = new HttpFetchPort();
  // 学期解析已单独成模块（data/courses/SemesterFetcher）；公告路径仍需
  // "站点当前学期 + 课程名表"，所以这里把同一个 port 同时喂给两者——**没有第二份取数逻辑**。
  const semesters: HttpSemesterSource = new HttpSemesterSource(new Logger(COURSE_LIST_LOG_DOMAIN), port);
  const courses: HttpCourseListSource =
    new HttpCourseListSource(new Logger(COURSE_LIST_LOG_DOMAIN), port, semesters);
  const source: HttpNoticeFetchSource = new HttpNoticeFetchSource(port, courses, decodeBase64Text);
  const snapshots: NoticeSnapshotFileStore = new NoticeSnapshotFileStore(context);
  logger.info('notice repository wired: source=real snapshotStore=preferences contextAvailable=true');
  const executor: AuthedTaskExecutor = new RunnerTaskExecutor(authServices.runner);
  return new RealNoticeRepository(executor, source, snapshots,
    new Logger('data.notices.repository'));
}

/**
 * 把 AuthedTaskRunner 显式适配成 AuthedTaskExecutor。
 *
 * 为什么不直接赋值：ArkTS 不做结构类型（arkts-no-structural-typing），
 * 两个形状相同的接口也不能互相赋值（实测）。适配器只有一行转发，
 * 并让 数据路径只经过 AuthedTaskRunner 这件事在类型上可见。
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

/** Context 不可用时的显式失败实现（不返回空列表、不返回 Mock）。 */
class MissingContextNoticeRepository implements NoticeRepository {
  async loadSnapshot(): Promise<NoticeSnapshot | null> {
    return null;
  }

  async refresh(): Promise<NoticeSnapshot> {
    throw new Error('notice repository unavailable: no host context for the snapshot store');
  }

  /** 没有存储可写：吞掉即可（界面侧的已读刷新由 store 自己完成）。 */
  async markRead(noticeId: string): Promise<void> {
  }
}
