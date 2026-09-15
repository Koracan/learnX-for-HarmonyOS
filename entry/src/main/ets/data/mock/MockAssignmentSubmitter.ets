/*
 * Mock 模式的提交出口（data/mock）：**零网络的本地样例服务**。
 *
 * ## 为什么需要它
 *
 * notice / course / file 三条线在 provider 里对 `isMockMode()` 分支，**提交这条线此前没有**：
 * `features/assignments/repository/AssignmentSubmissionProvider.createAssignmentSubmitter()`
 * 永远装配真实 HTTP 路径（`HttpFetchPort` + `AuthedTaskRunner`）。mock 账号（guest/guest）
 * 根本没有会话，于是提交必然走到降级（"需要重新验证"），界面弹「提交失败」。
 * 本类补上"第四个消费点"：mock 模式下点提交 ⇒ 本地记一笔 ⇒ 成功。
 *
 * ## 行为（与真实实现逐条对应）
 *
 * | 情形 | 真实实现 | 本类 |
 * | --- | --- | --- |
 * | `plan === undefined` | 一行日志、**不发请求**、`noop` | 一行日志、**不写台账**、`noop` |
 * | 正常提交 | multipart POST，回 `success(status)` | 发几次进度、写台账、`success(200)` |
 * | 带附件提交 | `SubmitAssignment.send` 先 `AttachmentBytesSource.read(uri)`，再把字节放进 multipart | **同一个端口类型**、同一个读法：把字节连同提交一起写进台账 |
 * | 附件读失败 | 整次提交失败（读不到就发不出去） | 照常记下这次提交（正文/时间），**不写附件**并 warn |
 * | 结果类型 | `SubmitOutcome` 的静态工厂 | **同一套** `SubmitOutcome`（不新造并行结果类型） |
 *
 * ## 附件为什么"读不到就不写"（而不是写一条占位）
 *
 * mock 模式下附件的可观察后果是"点开自己刚提交的附件能打开"：下载链路只会照着地址要字节。
 * 如果读字节失败还硬写一条附件，那条作业就会带一条**谁也打不开的死链**——这正是本轮
 * 收口的缺陷形态之一。所以：要么是用户真的选中的字节，要么明确没有附件（并说明原因）。
 * 0 字节同理（空资产会被下载端口显式拒绝）。
 *
 * **零网络**：本文件不 import 任何 http 端口（`HttpFetchPort` / `HttpDownloadPort` 都不在），
 * 一个字节都不发；每次提交把 `networkAttemptCount()` 打进日志与 diagnostic，
 * 单测钉死"全过程计数不变"。
 *
 * ## 为什么 extends `AssignmentSubmitter`（而不是新写一个接口）
 *
 * ArkTS **不做结构类型**（arkts-no-structural-typing）：形状相同的两个类型也不能互相赋值。
 * 界面（`AssignmentSubmissionPage`）持有的字段类型就是 `data/assignments/SubmitAssignment`
 * 里的类 `AssignmentSubmitter`，而那个文件不在本 ticket 的改动范围内；mock 想被赋给同类型的
 * 变量，只能 `extends` 它并覆写 `submit`。
 *
 * 基类构造函数要"执行器 + 用例 + 日志"三件套，于是下面有三个**永不被调用**的替身。
 * 它们不是端口实现的一部分：本类覆写了唯一的对外方法 `submit`，一个都不会被走到；
 * 真被走到（说明有人改回了基类实现）就返回明确的失败 / 抛错，而**不是**偷偷回到真实路径。
 */

import { Logger } from '../../core/log/Logger';
import { SubmissionPlan } from '../../domain/assignments/SubmissionState';
import { AuthedRunResult, SessionTask } from '../auth/SessionRestore';
import { FailReason } from '../auth/AuthTypes';
import {
  AssignmentSubmitter, AttachmentBytesSource, AuthedTaskExecutor, SubmitAssignment, SubmitOutcome
} from '../assignments/SubmitAssignment';
import {
  FetchOutcome, FetchPort, GetSpec, PostFormSpec, UploadProgress, UploadProgressSink, UploadSpec
} from '../remote/Port';
import { HttpOutcome, Session } from '../remote/Requests';
import { networkAttemptCount } from '../remote/NetworkAudit';
import { recordSubmission } from './MockSubmissionJournal';

/** 日志域与真实提交同一格（`data.assignments.submit`），便于 hdc 全量拉日志后本地筛。 */
const LOG_DOMAIN: string = 'data.assignments.submit';

/**
 * 每一步进度之间的本地延迟（毫秒）。
 *
 * 为什么要有它：进度回调若在同一轮微任务里连发，ArkUI 只会渲染最后一帧，进度条等于没走。
 * 这里给一个**极短**的本地延迟（40ms × 2 步 ≈ 80ms），只为了让进度条真的动一下——
 * 不是网络仿真，mock 的提交不模拟任何真实耗时。
 */
const PROGRESS_STEP_MILLIS: number = 40;

/** 本地延迟（与 features/courses/SemesterSwitch 的同名帮手同一写法）。 */
function delayMillis(millis: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, millis);
  });
}

/**
 * 这一次提交要报多少"字节"。
 *
 * 有附件时用附件体积（`PickedAttachment.size`，picker 给不出时为 0）；否则用正文长度。
 * **下限取 1**：`withUploadProgress` 在 `total <= 0` 时进度恒为 0（参考实现同一分支），
 * 那样进度条就永远不动了。
 */
function progressTotal(plan: SubmissionPlan): number {
  const payload: number = plan.attachment === undefined ? plan.content.length : plan.attachment.size;
  return payload > 0 ? payload : 1;
}

export class MockAssignmentSubmitter extends AssignmentSubmitter {
  private readonly mockLogger: Logger;
  /** 与真实 `SubmitAssignment` **同一个端口类型**：picker 给的 URI → 字节。 */
  private readonly attachmentReader: AttachmentBytesSource;

  constructor(logger: Logger, attachmentReader: AttachmentBytesSource) {
    // 基类的执行器与请求端口在这里是"占位"：本类覆写 submit，它们不会被走到（见文件头）。
    // 附件读取器**不是**占位：它就是要用的那个端口，直接传给基类那套死代码，不另造替身
    // （设备侧传的是真实的 DeviceAttachmentReader，见 AssignmentSubmissionProvider）。
    super(new NeverUsedTaskExecutor(),
      new SubmitAssignment(new NeverUsedFetchPort(), attachmentReader, logger), logger);
    this.mockLogger = logger;
    this.attachmentReader = attachmentReader;
  }

  /**
   * 读这一次提交附件的**真实字节**；没有附件 / 读失败 / 读到 0 字节时返回 undefined（并 warn）。
   *
   * 返回值直接喂给 `recordSubmission`：undefined = 这一次**没有附件**（不是"附件是空的"）。
   */
  private async readAttachment(plan: SubmissionPlan): Promise<Uint8Array | undefined> {
    const picked = plan.attachment;
    if (picked === undefined) {
      return undefined;
    }
    let bytes: Uint8Array;
    try {
      bytes = await this.attachmentReader.read(picked.uri);
    } catch (error) {
      this.mockLogger.warn(LOG_DOMAIN
        + ' attachment read failed, recording the submission without an attachment:'
        + ' file=' + picked.name + ' uri=' + picked.uri
        + ' reason=' + (error as Error).message);
      return undefined;
    }
    if (bytes.length === 0) {
      this.mockLogger.warn(LOG_DOMAIN
        + ' attachment is empty, recording the submission without an attachment:'
        + ' file=' + picked.name + ' uri=' + picked.uri);
      return undefined;
    }
    this.mockLogger.info(LOG_DOMAIN + ' attachment bytes read for the local journal:'
      + ' file=' + picked.name + ' bytes=' + bytes.length.toString());
    return bytes;
  }

  /**
   * 一次本地样例提交：发几次进度 → 写台账 → 成功。
   *
   * 早退分支与真实实现同义：`plan === undefined`（无正文、无附件、不移除）⇒ 一行日志、
   * 不写台账（下一次读 `mockAssignments()` 仍是样例态）、返回 `noop`。
   */
  async submit(plan: SubmissionPlan | undefined, requestId: string,
    onProgress?: UploadProgressSink): Promise<SubmitOutcome> {
    if (plan === undefined) {
      this.mockLogger.info(LOG_DOMAIN + ' nothing to submit: no local sample submission recorded'
        + ' networkAttempts=' + networkAttemptCount().toString());
      return SubmitOutcome.noop('empty submission');
    }
    // 先读附件字节：读不到就"没有附件"，但这一次提交照样记下来（正文/时间）。
    const attachmentBytes: Uint8Array | undefined = await this.readAttachment(plan);
    const total: number = progressTotal(plan);
    const steps: number[] = [0, Math.round(total / 2), total];
    for (let i = 0; i < steps.length; i++) {
      if (onProgress !== undefined) {
        const progress: UploadProgress = { requestId: requestId, sent: steps[i], total: total };
        onProgress(progress);
      }
      if (i < steps.length - 1) {
        await delayMillis(PROGRESS_STEP_MILLIS);
      }
    }
    recordSubmission(plan, Date.now(), attachmentBytes);
    const attachmentName: string = plan.attachment === undefined ? '(none)' : plan.attachment.name;
    const diagnostic: string = 'local sample service (mock mode): xszyid=' + plan.studentHomeworkId
      + ' contentChars=' + plan.content.length.toString()
      + ' removeAttachment=' + plan.removeAttachment.toString()
      + ' file=' + attachmentName
      + ' attachmentBytes=' + (attachmentBytes === undefined ? '0' : attachmentBytes.length.toString())
      + ' networkAttempts=' + networkAttemptCount().toString();
    this.mockLogger.info(LOG_DOMAIN + ' local sample submission accepted (zero network): ' + diagnostic);
    return SubmitOutcome.success(200, diagnostic);
  }
}

/* ------------------------------------------------------------------ *
 * 永不被调用的替身（只为满足基类构造签名，见文件头）。
 * 它们的返回值都是**明确的失败**，而不是"假装成功"：一旦有人真的走到这里，
 * 应当立刻在日志/单测里暴露"mock 提交出口被改回了真实路径"，而不是静默成功。
 * ------------------------------------------------------------------ */

class NeverUsedTaskExecutor implements AuthedTaskExecutor {
  async run(task: SessionTask): Promise<AuthedRunResult> {
    // 刻意返回**降级**（而不是一个成功的空值）：真被走到时，基类 `submit` 会翻成
    // requiresEnrollment=true 的显式失败，界面立刻可见，而不是"提交了什么都没发生"。
    return AuthedRunResult.degraded(FailReason.NETWORK_UNREACHABLE, false,
      'mock submitter: task executor is never used');
  }
}

class NeverUsedFetchPort implements FetchPort {
  async postForm(session: Session, spec: PostFormSpec): Promise<FetchOutcome> {
    return { ok: false, status: 0, body: '', error: 'mock submitter: no network port' };
  }

  async get(session: Session, spec: GetSpec): Promise<FetchOutcome> {
    return { ok: false, status: 0, body: '', error: 'mock submitter: no network port' };
  }

  async upload(session: Session, spec: UploadSpec,
    onProgress?: UploadProgressSink): Promise<HttpOutcome> {
    return { ok: false, status: 0, body: '', error: 'mock submitter: no network port' };
  }
}
