/*
 * 提交页的状态机 —— **纯函数，零平台依赖**（见 scripts/check-domain-purity.mjs）。
 *
 * 为什么单独一层：工单验收第 3 条要求「失败有明确提示且**不丢失已填内容**」，而参考实现的
 * 这条语义藏在 React 组件的 `catch` 分支里（`AssignmentSubmission.tsx:233-237`：
 * 只 `setUploading(false)` / `setUploadError(true)` / `setProgress(0)`，**没有**动
 * `content` 与 `attachmentResult`）。把它落成纯状态函数之后，「失败不丢内容」这条
 * 断言可以在 host 单测里直接钉死，而不是靠人眼截图。
 *
 * 状态一律**不可变**（每个迁移返回新对象）：ArkUI 的 `@State` 在整对象替换时才重渲染，
 * 这也让单测可以逐字段比较「迁移前后哪些字段没变」。
 *
 * `SubmissionState` 是 **class 而不是 interface**：界面上它是 `@State` 变量，
 * class 是 ArkUI 状态变量的标准对象类型（interface 在部分版本上不被接受）。
 */

import { removeTags } from '../render/WebViewTemplate';
import {
  PickedAttachment, applyCustomAttachmentName, sanitizeCustomAttachmentName
} from './SubmissionForm';

/** 提交页的全部界面状态。 */
export class SubmissionState {
  /** 正文（多行输入，初值见 `initialSubmissionState`）。 */
  content: string;
  /** 自定义附件名输入框的值（已去掉 `.`）。 */
  customAttachmentName: string;
  /** 即将上传的新附件；`undefined` = 没选。 */
  attachment: PickedAttachment | undefined;
  /** 已提交附件的「移除」开关（可撤销；参考实现 :111-118）。 */
  removeAttachment: boolean;
  uploading: boolean;
  /** 0..1 的上传进度（参考实现把 `loaded/total` 四舍五入到两位）。 */
  progress: number;
  /** 上次提交是否失败（错误提示据此显示）。 */
  error: boolean;

  constructor(content: string, customAttachmentName: string, attachment: PickedAttachment | undefined,
    removeAttachment: boolean, uploading: boolean, progress: number, error: boolean) {
    this.content = content;
    this.customAttachmentName = customAttachmentName;
    this.attachment = attachment;
    this.removeAttachment = removeAttachment;
    this.uploading = uploading;
    this.progress = progress;
    this.error = error;
  }

  /** 逐字段复制（迁移函数的起点；不共享 attachment 对象本身，只共享它的引用）。 */
  copy(): SubmissionState {
    return new SubmissionState(this.content, this.customAttachmentName, this.attachment,
      this.removeAttachment, this.uploading, this.progress, this.error);
  }
}

/**
 * 正文初值（参考实现 :83-85）：
 * `(removeTags(submittedContent || '') ?? '').replace('-->', '')`。
 *
 * `replace` 的第一个参数是**字符串**，所以只替换**第一处** `-->`（不是全部）——
 * 逐字对齐，不要「顺手」改成全局替换。
 */
export function initialSubmissionContent(submittedContent: string | undefined): string {
  const plain: string = removeTags(submittedContent === undefined ? '' : submittedContent);
  return plain.replace('-->', '');
}

/** 初始状态。 */
export function initialSubmissionState(submittedContent: string | undefined): SubmissionState {
  return new SubmissionState(initialSubmissionContent(submittedContent), '', undefined,
    false, false, 0, false);
}

/** 改正文。 */
export function withContent(state: SubmissionState, content: string): SubmissionState {
  const next: SubmissionState = state.copy();
  next.content = content;
  return next;
}

/** 改自定义附件名（输入时去掉所有 `.`）。 */
export function withCustomAttachmentName(state: SubmissionState, text: string): SubmissionState {
  const next: SubmissionState = state.copy();
  next.customAttachmentName = sanitizeCustomAttachmentName(text);
  return next;
}

/** 选中一个新附件（覆盖上一个；参考实现的 `setAttachmentResult`）。 */
export function withAttachmentPicked(state: SubmissionState, picked: PickedAttachment): SubmissionState {
  const next: SubmissionState = state.copy();
  next.attachment = picked;
  next.error = false;
  return next;
}

/** 清空刚选中的附件（参考实现 `handlePickedAttachmentRemove`）。 */
export function withPickedAttachmentRemoved(state: SubmissionState): SubmissionState {
  const next: SubmissionState = state.copy();
  next.attachment = undefined;
  return next;
}

/** 已提交附件的「移除 / 撤销移除」开关。 */
export function withRemoveAttachmentToggled(state: SubmissionState): SubmissionState {
  const next: SubmissionState = state.copy();
  next.removeAttachment = !state.removeAttachment;
  return next;
}

/** 开始提交：`uploading=true`、清错误、进度清零（参考实现 :250-252）。 */
export function submitStarted(state: SubmissionState): SubmissionState {
  const next: SubmissionState = state.copy();
  next.uploading = true;
  next.error = false;
  next.progress = 0;
  return next;
}

/**
 * 上传进度（参考实现 :172-180 的 `parseFloat((loaded/total).toFixed(2))`）。
 * `total <= 0` 时进度为 0（参考实现同一分支）。**不动其它字段**——上传中正文与附件必须留着。
 */
export function withUploadProgress(state: SubmissionState, sent: number, total: number): SubmissionState {
  const next: SubmissionState = state.copy();
  const ratio: number = total > 0 ? sent / total : 0;
  next.progress = Math.round(ratio * 100) / 100;
  return next;
}

/**
 * 提交失败（参考实现 :233-237）：`uploading=false`、`error=true`、进度清零，
 * **正文与已选附件一律保留**（这就是验收第 3 条的「不丢失已填内容」）。
 */
export function submitFailed(state: SubmissionState): SubmissionState {
  const next: SubmissionState = state.copy();
  next.uploading = false;
  next.error = true;
  next.progress = 0;
  return next;
}

/** 提交成功（参考实现 :225-232）：停止上传、清错误与进度；正文与附件由调用方丢弃整个状态。 */
export function submitSucceeded(state: SubmissionState): SubmissionState {
  const next: SubmissionState = state.copy();
  next.uploading = false;
  next.error = false;
  next.progress = 0;
  return next;
}

/** 提交按钮是否可用（参考实现 :274-276 的 `disabled` 取反）。 */
export function canSubmit(state: SubmissionState): boolean {
  if (state.uploading) {
    return false;
  }
  return state.removeAttachment || state.content.length > 0 || state.attachment !== undefined;
}

/** 这次提交是否要真的发请求（参考实现 source.ts:161-163：无正文、无附件、不移除 ⇒ 直接返回）。 */
export function shouldSendRequest(state: SubmissionState): boolean {
  return state.removeAttachment || state.content.length > 0 || state.attachment !== undefined;
}

/**
 * 提交入口走不了的原因。三种情形的**说法必须不同** —— 同一个"什么都不发生"会让用户
 * 分不清是自己没填东西、程序还在忙、还是这条作业根本不能交了。
 */
export type SubmitBlockReason = 'past_deadline' | 'uploading' | 'nothing_to_submit';

/**
 * 提交入口此刻能不能走：`undefined` = 可以；否则给出**原因**。
 *
 * `pastDeadline` 由调用方算好传进来，用的是**既有的那一份**截止判定
 * （`features/assignments/AssignmentFilter.isPastDeadline`，边界与 dayjs 的 `isAfter` 对齐）。
 * 领域层不自己再算一遍截止语义，避免同一条边界出现两种实现。
 *
 * `state` 传 `undefined` 表示调用点没有提交页的状态可看（作业详情页的入口只做一次跳转，
 * 它不构造提交请求）；那种调用点只能因为截止被拦下。
 *
 * 未截止时本函数的结论与 `canSubmit` **完全同义**（单测钉住这一等价），
 * 所以"能不能走"的判定没有被改宽或改窄，只是多了一个原因。
 *
 * 原因有先后：**截止是硬拦截**（任何状态下都不成立），其次才是"在飞 / 没内容"这两个
 * 用户自己可解的情形 —— 顺序写在这里，而不是留给调用方各猜一套。
 */
export function submitBlockReason(pastDeadline: boolean,
  state: SubmissionState | undefined): SubmitBlockReason | undefined {
  if (pastDeadline) {
    return 'past_deadline';
  }
  if (state === undefined) {
    return undefined;
  }
  if (state.uploading) {
    return 'uploading';
  }
  if (!shouldSendRequest(state)) {
    return 'nothing_to_submit';
  }
  return undefined;
}

/** 组装好的提交内容（数据层据此构造表单字段与文件部分）。 */
export interface SubmissionPlan {
  /** `xszyid`：学生作业 id。 */
  studentHomeworkId: string;
  /** `zynr`：正文（「移除附件」时为**空串**）。 */
  content: string;
  /** `isDeleted`：移除附件时为 true。 */
  removeAttachment: boolean;
  /** 要上传的新附件（文件名已按自定义名拼回扩展名）。移除态下为 undefined。 */
  attachment?: PickedAttachment;
}

/**
 * 把界面状态翻成「这一次提交要发什么」（参考实现 :250-273 的 `handleSubmit`）。
 *
 * `undefined` = 不发请求（参考实现 :161-163 的早退分支）。
 */
export function planSubmission(state: SubmissionState, studentHomeworkId: string): SubmissionPlan | undefined {
  if (!shouldSendRequest(state)) {
    return undefined;
  }
  if (state.removeAttachment) {
    // 移除态：正文不发、附件不带（参考实现 :180-188：content=''、无 attachment、remove=true）。
    return { studentHomeworkId: studentHomeworkId, content: '', removeAttachment: true };
  }
  const plan: SubmissionPlan = {
    studentHomeworkId: studentHomeworkId,
    content: state.content,
    removeAttachment: false
  };
  if (state.attachment !== undefined) {
    const picked: PickedAttachment = state.attachment;
    const name: string = applyCustomAttachmentName(picked.name, state.customAttachmentName);
    plan.attachment = {
      uri: picked.uri,
      name: name,
      mimeType: picked.mimeType,
      size: picked.size
    };
  }
  return plan;
}
