/*
 * 作业 tab 的导航路由名（ticket 10）。
 *
 * 选型沿用 ticket 03/04/12：**每个 tab 一个自己的 NavPathStack**（见 features/shell/ShellTabs.ets
 * 的文件头）。作业 tab 的栈根是作业列表，压在上面的依次是：
 *   - 作业详情（本 ticket 交付，替换 ticket 12 的占位页）；
 *   - 文件详情（附件点击的目标，**真身归 ticket 11**；路由与参数复用 ticket 04 的
 *     `ROUTE_FILE_DETAIL` / `FileDetailRouteParams`，见 AssignmentDetailPage 的说明）。
 *
 * 参数就是 `Assignment` 本身（与公告详情 `navigation.push('NoticeDetail', notice)` 同一做法）：
 * 详情页只读列表项携带的字段，不做二次取数 —— 参考实现 AssignmentDetail.tsx:37-80 也是
 * 从 `route.params` 里一次性取出全部字段。
 */

/**
 * 作业详情路由名。
 *
 * 【ticket 12 → ticket 10 的交接】ticket 12 在 `features/courses/CourseRoutes.ets` 里定义过同名常量
 * （值 `'CourseAssignmentDetail'`）与一个**扁平化的参数子集**（`AssignmentDetailRouteParams`），
 * 只为让课程详情的作业标签页"能进去且参数可见"。本 ticket 把它换成真身：
 * 路由名收敛到这里，参数改成完整 `Assignment`（详情页要显示描述/四类附件/成绩等级，
 * 扁平的 10 个字段不够）。课程详情页与本 tab 都推这一条路由、渲染同一个页面。
 */
export const ROUTE_ASSIGNMENT_DETAIL: string = 'AssignmentDetail';
