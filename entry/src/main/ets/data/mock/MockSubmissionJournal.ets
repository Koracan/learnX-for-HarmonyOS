/*
 * Mock 模式的**提交台账**（data/mock）：进程内、内存态。
 *
 * ## 为什么需要一份台账
 *
 * Mock 模式的数据源是 `MockData.mockAssignments()` 的**固定样例**：每次调用都返回
 * "作业 1/2 未提交、作业 3/4 已提交"的同一份快照。而提交链路的可观察结果是"这条作业变成
 * 已提交"——样例不改的话，用户点完提交、界面刷新（`AssignmentSubmissionPage.doSubmit`
 * 成功后调 `store.refresh()`）看到的仍是"未提交"，与"提交成功"的弹窗自相矛盾。
 *
 * 所以这里记一笔提交，由 `mockAssignments()` 在**生成样例之后**套用（覆盖层）：
 * 被提交过的作业翻成 `submitted: true` + 提交时间 + 提交正文/附件。样例数据本身一字不改。
 *
 * ## 为什么是内存态（**不落盘**）
 *
 * 与会话/凭据一致的运行期语义（ADR-0004：会话与凭据都不落盘，见 features/mock/MockMode.ets
 * 的"为什么不做成持久化的"）：mock 模式是"这次登录用样例数据"的一种**运行期**状态。
 * 因此台账随进程一起消失，重启后回到登录页、重新用 guest/guest 进入，作业回到样例初始态。
 *
 * 有意不为了"跨进程记住一次假提交"而在磁盘上发明第二份状态：那会让下一次登录看到一份
 * 谁也解释不清的"半提交"样例（参考实现的 mock store 同样只有一份内存态）。
 *
 * ## 与真实实现的关系
 *
 * 真实提交的结果由站点保存，客户端不存；本台账**只服务 Mock 模式**，
 * 真实路径（`AssignmentSubmissionProvider` 的 HTTP 分支）一行都不读它。
 */

import { Logger } from '../../core/log/Logger';
import { SubmissionPlan } from '../../domain/assignments/SubmissionState';

const logger: Logger = new Logger('data.mock.submitJournal');

/** 台账里记的附件：只留界面要展示的两格（文件名与体积字节数）。 */
export interface MockSubmittedAttachment {
  /** 文件名（已按自定义名规则拼回扩展名，与真实上传时的 multipart filename 同一份）。 */
  name: string;
  /** 字节数；picker 给不出时为 0（与 `PickedAttachment.size` 同义）。 */
  size: number;
}

/**
 * 台账里的一次提交（值形状）。
 *
 * `submittedAtMillis` 存**毫秒时间戳**而不是格式化后的串：格式化（`YYYY-MM-DD HH:mm`）
 * 是展示层的事，由 `MockData.formatDateTime` 在读台账时做，避免这里出现第二份时间格式实现。
 */
export interface MockSubmissionEntry {
  /** 提交的正文（「移除附件」时为**空串**，与真实提交的 `zynr` 同义）。 */
  content: string;
  /** 这一次提交是不是"移除已提交附件"（真实提交的 `isDeleted=1`）。 */
  removeAttachment: boolean;
  /** 这一次跟着上传的新附件；无附件时为 undefined。 */
  attachment?: MockSubmittedAttachment;
  /** 提交时刻（毫秒时间戳）。 */
  submittedAtMillis: number;
}

/**
 * 提交台账：key 是 `studentHomeworkId`（`xszyid`），值是一次提交。
 *
 * 同一个 `xszyid` **后一次提交覆盖前一次**——站点侧也是这个语义（一次作业一份提交状态），
 * 所以"先传附件、再移除附件"的最终态就是"没有附件"。
 */
const journal: Map<string, MockSubmissionEntry> = new Map<string, MockSubmissionEntry>();

/**
 * 记一次提交（覆盖同一 `xszyid` 的上一条）。
 *
 * `submittedAtMillis` 由调用方传入（`MockAssignmentSubmitter` 传 `Date.now()`），
 * 而不是在这里自己取时间：这样单测能钉死"时间来自提交那一刻"。
 */
export function recordSubmission(plan: SubmissionPlan, submittedAtMillis: number): void {
  const entry: MockSubmissionEntry = {
    content: plan.content,
    removeAttachment: plan.removeAttachment,
    submittedAtMillis: submittedAtMillis
  };
  // 「移除附件」这一支不带附件（`planSubmission` 也不会给）：不要顺手把上一条的附件留下来。
  if (!plan.removeAttachment && plan.attachment !== undefined) {
    entry.attachment = { name: plan.attachment.name, size: plan.attachment.size };
  }
  journal.set(plan.studentHomeworkId, entry);
  logger.info('mock submission journaled: xszyid=' + plan.studentHomeworkId
    + ' contentChars=' + entry.content.length.toString()
    + ' removeAttachment=' + entry.removeAttachment.toString()
    + ' attachment=' + (entry.attachment === undefined ? '(none)' : entry.attachment.name)
    + ' entries=' + journal.size.toString());
}

/** 读某条作业的提交记录；没提交过时为 undefined（样例态）。 */
export function submissionFor(studentHomeworkId: string): MockSubmissionEntry | undefined {
  return journal.get(studentHomeworkId);
}

/**
 * 清空台账（**只给单测做用例隔离用**；运行期没有调用者）。
 *
 * 运行期的"清空"就是进程重启（见文件头的"为什么是内存态"）。
 */
export function clearMockSubmissions(): void {
  const before: number = journal.size;
  journal.clear();
  if (before > 0) {
    logger.info('mock submissions cleared: entries=' + before.toString());
  }
}
