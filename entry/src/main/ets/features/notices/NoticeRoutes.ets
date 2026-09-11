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

/** 文件详情路由名（本 ticket 只做占位页 + 导航参数，见 FileDetailPlaceholderPage）。 */
export const ROUTE_FILE_DETAIL: string = 'FileDetail';

/** 附件跳转 FileDetail 的参数（对齐参考实现 NoticeDetail.tsx:63-71）。 */
export interface FileDetailRouteParams {
  /** 公告 id（参考实现原样透传 `id`）。 */
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
}
