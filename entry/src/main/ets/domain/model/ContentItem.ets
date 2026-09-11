/*
 * 三种内容项（公告 / 作业 / 文件）的领域类型——**零平台依赖**（见 scripts/check-domain-purity.mjs）。
 *
 * 字段与语义照抄参考实现的解析产出（reference/learnOH-old/.../DataProcessorModule.ts）
 * 与状态类型（reference/learnOH-old/src/data/types/state.ts 的 Notice / Assignment / File），
 * 以保证移植后的下游（features/）拿到的是同一组字段。
 *
 * 「可选」一律用 `?: T | undefined` 显式写出，因为解析结果里"接口没给这个字段"
 * 与"接口给了空值"在下游要做不同处理（例如 `grade === undefined` 表示未评分）。
 */

/**
 * 附件 / 上传文件在领域里的统一形态。
 *
 * 参考实现里公告与作业的附件都只有 `name` + `downloadUrl`；`size` 与 `id`
 * 是参考实现的 HTML 里能取到但当时没取的两个字段（thu-learn-lib 的
 * `parseHomeworkFile` 取到了），这里补上并保持可选，避免解析器为取不到而撒谎。
 */
export interface Attachment {
  /** 下载地址；公告附件已展开为真实的 downloadFile 地址。 */
  downloadUrl: string;
  /** 展示用文件名（已做 HTML 实体解码）。 */
  name: string;
  /** 站点给出的附件标识（下载地址里的 `wjid` / `fileId`）。 */
  id?: string;
  /** 站点给出的体积文本，如 `139.54KB`。 */
  size?: string;
}

/** 内容项共有的课程归属字段（参考实现 `CourseExtraInfo`）。 */
export interface CourseOwned {
  courseId: string;
  /** 课程在 `courseNames` 里查不到时取 `Unknown Course`（照参考实现）。 */
  courseName: string;
  courseTeacherName: string;
}

/** 公告。正文为 HTML（已 Base64 解码 + 实体解码）。 */
export interface Notice extends CourseOwned {
  id: string;
  title: string;
  publisher: string;
  /** `YYYY-MM-DD HH:mm` 形式的发布时间。 */
  publishTime: string;
  expireTime?: string;
  markedImportant: boolean;
  hasRead: boolean;
  /** 公告详情页地址。 */
  url: string;
  /** 正文 HTML；解码失败或字段缺失时为空串（不抛异常）。 */
  content: string;
  attachment?: Attachment;
}

/** 作业。四类附件与三类正文对应参考实现的 `attachment` / `answerX` / `submittedX` / `gradeX`。 */
export interface Assignment extends CourseOwned {
  id: string;
  /** `xszyid`，学生-作业关系标识；未下发时为 undefined。 */
  studentHomeworkId?: string;
  /** `zyid`，作业本身标识。 */
  baseId: string;
  title: string;
  /** 作业详情页地址（`viewCj` 或 `viewZy`，取决于是否下发 `xszyid`）。 */
  url: string;
  deadline: string;
  lateSubmissionDeadline?: string;
  isLateSubmission: boolean;
  completionType: string;
  submissionType: string;
  /** 提交页地址。 */
  submitUrl: string;
  submitTime?: string;
  grade?: number;
  graderName?: string;
  /** 来自列表接口的 pynr 字段。 */
  gradeContent: string;
  submittedContent: string;
  answerContent: string;
  description: string;
  submitted: boolean;
  graded: boolean;
  attachment?: Attachment;
  submittedAttachment?: Attachment;
  gradeAttachment?: Attachment;
  answerAttachment?: Attachment;
}

/** 课程文件（对应参考实现的 `File`；类名避开 ArkTS 全局 `File`）。 */
export interface CourseFile extends CourseOwned {
  id: string;
  /** 下载地址里用的文件标识 `wjid`。 */
  fileId: string;
  title: string;
  description: string;
  /** 体积（站点原样给出，可能是数字或字符串）。 */
  size: string;
  uploadTime: string;
  fileType: string;
  isNew: boolean;
  downloadUrl: string;
}

/** 一次抓取的产物：条目 + 可观测的计数与耗时。 */
export interface FetchReport<T> {
  items: T[];
  /** 成功解析出的条目数（等于 `items.length`，显式留一个字段给日志）。 */
  itemCount: number;
  /** 抓取 + 解析耗时（毫秒）。 */
  elapsedMs: number;
}
