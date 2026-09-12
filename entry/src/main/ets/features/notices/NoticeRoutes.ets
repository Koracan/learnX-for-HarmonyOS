/*
 * 公告 tab 的导航路由名（ticket 04）。
 *
 * ticket 03 的导航选型（见 features/shell/ShellTabs.ets 文件头）：底栏用 Tabs，
 * **每个 tab 将来一个自己的 NavPathStack**。本 ticket 给公告 tab 装上第一个详情栈：
 * `NoticesPage` 里放一个 `Navigation`，列表是根内容，详情页是 `NavDestination`。
 * 这样切到别的 tab 时公告栈（含详情页）原样保留，与参考实现"每 tab 一个 stack"一致。
 *
 * 参数类型用 `NoticeRecord`（列表项就是它），详情页只读，不做二次取数 —— 与参考实现
 * `navigation.push('NoticeDetail', notice)` 把整个 Notice 对象带过去一致。
 */

/** 公告详情路由名。 */
export const ROUTE_NOTICE_DETAIL: string = 'NoticeDetail';

/**
 * 文件详情路由名。
 *
 * 【ticket 11 起】这条路由的**真身**是 `features/files/FileDetailPage`（下载 / 应用内预览 /
 * 分享）。ticket 04 的 `FileDetailPlaceholderPage` 已删除（被真身取代），
 * 路由名与参数形状（含本 ticket 追加的三个**可选**字段）保持兼容。
 *
 * 【ticket 10 复用它】作业详情里的附件点击**走同一条 `FileDetail` 路由**（照参考实现
 * AssignmentDetail.tsx:143 `navigation.push('FileDetail', data)`）。此时
 * `noticeId` 装的是**附件 id**（参考实现 AssignmentDetail.tsx:134 传的就是附件 id，
 * 与公告详情 NoticeDetail.tsx:64 传公告 id 不同）。这个字段的真身是"文件缓存目录名"
 * （参考实现 helpers/fs.ts:54 用它拼目录），所以两种来源都能用；字段名保留 `noticeId`
 * 是为了不动 ticket 04 已验收的导航契约 —— 见 ticket 11 的边界说明。
 */
export const ROUTE_FILE_DETAIL: string = 'FileDetail';

/** 附件跳转 FileDetail 的参数（对齐参考实现 NoticeDetail.tsx:63-71 / AssignmentDetail.tsx:132-145）。 */
export interface FileDetailRouteParams {
  /** 来源标识：公告详情传公告 id，作业详情传**附件 id**（两者都是"文件缓存目录名"）。 */
  noticeId: string;
  /** 课程名（参考实现原样透传，**详情页不显示它**，只作为附件跳转的参数）。 */
  courseName: string;
  courseTeacherName: string;
  /** `stripExtension(attachment.name)`。 */
  title: string;
  attachmentName: string;
  downloadUrl: string;
  /** `getExtension(attachment.name) ?? ''`。 */
  fileType: string;
  /*
   * 【ticket 11 追加：三个**可选**字段】
   *
   * 附件来源没有这三个量（`Attachment` 只有 name/downloadUrl/size），所以它们必须可选 ——
   * 公告详情与作业详情的构造点**一行都不用改**，ticket 04 已验收的导航契约（字段名与形状）
   * 也不变。加它们的理由：课程详情的文件标签页本来就有 size/uploadTime/description
   * （ticket 12 的 `CourseFileDetailRouteParams`），而文件详情真身落地后那条路由也走本页面，
   * 于是不需要第二套参数类型（见 ticket 11 的交付说明）。
   */
  /** 站点给出的体积文本（如 `139.54KB`）；附件通常没有。 */
  size?: string;
  /** 上传时间（`YYYY-MM-DD HH:mm`）；附件没有。 */
  uploadTime?: string;
  /** 描述（课程文件有，附件没有）。 */
  description?: string;
}
