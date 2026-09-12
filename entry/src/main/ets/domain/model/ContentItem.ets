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

/**
 * **优秀作业**（参考实现 `HomeworkExcellent`，thu-learn-lib `index.js:906-927`）。
 *
 * 一条记录 = **某位同学对某次作业**的一次优秀提交；同一次作业可以有多条
 * （实测：2025-2026 春季 `…719` 课 18 条落在 12 个 `zyid` 上，其中 6 个 `zyid` 各 2 条）。
 * 因此它挂成 `Assignment.excellentHomeworkList`（数组），不是单值。
 *
 * 附件同源两枚：参考实现渲染时取 `gradeAttachment || submittedAttachment`
 * （AssignmentDetail.tsx:329-331），两者都来自优秀作业详情页 `viewYxzy?wlkcid=&xszyid=` 的
 * 四类附件块（复用 `parseAssignmentDetail`，块序不变）。
 */
export interface ExcellentHomework {
  /** `xszyid`：这一次优秀提交的标识（也是详情页地址的参数）。 */
  id: string;
  /** `zyid`：它属于哪一次作业（= `Assignment.baseId`，挂载的键）。 */
  baseId: string;
  title: string;
  /** 作者（`cy` 形如 "`<学号> <姓名>`"；匿名时两者都为空）。 */
  authorId: string;
  authorName: string;
  /** `sfzm === '是'`（thu-learn-lib `YES`）。 */
  anonymous: boolean;
  /** `zyfjid`：站点给出的优秀作业附件标识（诊断/兜底用，不直接当下载地址）。 */
  attachmentId?: string;
  /** 优秀作业详情页解析出的"批改附件"。 */
  gradeAttachment?: Attachment;
  /** 优秀作业详情页解析出的"已提交附件"。 */
  submittedAttachment?: Attachment;
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
  /** 站点下发的成绩（`cj` 的数值形态）；`undefined` = 未评分。 */
  grade?: number;
  /**
   * 成绩的**等级**形态（thu-learn-lib `GRADE_LEVEL_MAP.get(cj)` 的等价物）。
   *
   * `cj` 除了分数（如 88）还会下发**等级代码**（如 -100 = 已阅、-85 = 优秀、
   * -63 = 通过、-59 = 不通过、-50 = 缓考、-61/-65 = 免修/免课）。
   * 参考实现的详情页优先显示等级（`gradeLevel ? getAssignmentGradeLevelDescription(...) : grade`，
   * AssignmentDetail.tsx:263-269）；ticket 05 漏了这一格，ticket 10 按同一张表补上。
   * 取值为 thu-learn-lib `HomeworkGradeLevel` 的字符串（'checked' / 'distinction' / 'A+' …），
   * 表里没有的代码为 `undefined`（此时界面回退显示数字成绩）。
   */
  gradeLevel?: string;
  graderName?: string;
  /** 批改时间（`pysj`）；与 `deadline` 一样已规范化为 `YYYY-MM-DD HH:mm`（或原样字符串）。 */
  gradeTime?: string;
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
  /**
   * 本次作业的**优秀作业**（0..n 条）。参考实现的列表接口是**另一条**请求
   * （`/b/wlxt/kczy/zy/student/yxzylist`，每门课一次），按 `zyid` 归到作业上；
   * 列表成功但该作业没有优秀作业时为 `undefined`（不是空数组），界面据此决定是否显示 medal。
   */
  excellentHomeworkList?: ExcellentHomework[];
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
