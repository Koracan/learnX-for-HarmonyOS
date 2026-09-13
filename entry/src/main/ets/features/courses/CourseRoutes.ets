/*
 * 课程 tab 的导航路由名与参数。
 *
 * 沿用既有选型：**每个 tab 一个自己的 NavPathStack**（见 features/shell/ShellTabs.ets
 * 的文件头）。课程 tab 的栈根是课程列表，压在上面的依次是：
 *   - 课程详情（三个标签页：公告 / 作业 / 文件）；
 *   - 学期切换；
 *   - 作业详情（真身）/ 文件详情（真身）；
 *     两者的占位页文件（`CourseDetailPlaceholder.ets`）已随真身落地删除。
 *
 * 参数类型用显式接口（ArkTS 无结构化类型，匿名对象字面量在 Navigation 参数上会编译失败）。
 */

/** 课程详情路由名。 */
export const ROUTE_COURSE_DETAIL: string = 'CourseDetail';

/** 学期切换路由名。 */
export const ROUTE_SEMESTER_SELECTION: string = 'SemesterSelection';

/*
 * 作业详情的路由名**已移到 `features/assignments/AssignmentRoutes.ets`**：
 * 这里曾定义 `ROUTE_ASSIGNMENT_DETAIL` 与一个扁平参数子集供占位页用，
 * 真身落地后路由名与参数（完整 `Assignment`）都收敛到作业那条线，课程详情页改从那里导入。
 * 这样"作业详情"只有一份路由常量与一个页面。
 */

/** 文件详情路由名（曾只交付"路由 + 占位页"，真身是文件详情页）。 */
export const ROUTE_COURSE_FILE_DETAIL: string = 'CourseFileDetail';

/**
 * 学期切换页参数。
 *
 * 为什么给一个空壳接口：`NavPathStack.pushPath` 的 `param` 是 `Object`，ArkTS 里原始值
 * （字符串等）不能当 `Object` 传；用显式接口让参数形状在类型上可见（ArkTS 也无结构化类型）。
 */
export interface SemesterSelectionRouteParams {
  /** 进入选择页时实际生效的学期（只用于日志/诊断）。 */
  activeSemesterId: string;
}

/** 课程详情参数：只带定位信息，内容由 CourseListStore 按 courseId 过滤后提供。 */
export interface CourseDetailRouteParams {
  courseId: string;
  courseName: string;
  courseTeacherName: string;
}

/** 文件详情参数（占位页逐项显示，便于 layout dump 核对"点进去的是这一条"）。 */
export interface CourseFileDetailRouteParams {
  id: string;
  fileId: string;
  title: string;
  courseId: string;
  courseName: string;
  courseTeacherName: string;
  size: string;
  uploadTime: string;
  fileType: string;
  downloadUrl: string;
}