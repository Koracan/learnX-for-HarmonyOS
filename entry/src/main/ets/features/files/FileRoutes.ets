/*
 * 文件 tab 自己的路由。
 *
 * 沿用既有选型：**每个 tab 一个自己的 NavPathStack**。
 *   - `ROUTE_FILE_DETAIL`（定义在 features/notices/NoticeRoutes.ets）：
 *     文件详情真身，公告/作业/课程三条来源都推它；
 *   - `ROUTE_FILE_SETTINGS`：文件设置页（值/语义在 data/settings，**全局设置页的入口归全局设置**）。
 */

import { CourseFileDetailRouteParams } from '../courses/CourseRoutes';
import { FileDetailRouteParams } from '../notices/NoticeRoutes';

/** 文件设置页路由名。 */
export const ROUTE_FILE_SETTINGS: string = 'FileSettings';

/**
 * 课程详情的"文件"标签页参数 → 文件详情参数。
 *
 * 为占位页定义了 `CourseFileDetailRouteParams`（带 size/uploadTime/description），
 * 真身落地后**不新造第二套参数类型**：由本函数转成既有的 `FileDetailRouteParams`
 * （后来给它加了三个**可选**字段，于是这里能带上这三个量）。
 * `noticeId` 装的是"缓存目录名"，取 `fileId` 并以 `id` 兜底（`kjxxid` 必定非空）。
 */
export function fileDetailParamsFromCourseFile(params: CourseFileDetailRouteParams): FileDetailRouteParams {
  return {
    noticeId: params.fileId.length > 0 ? params.fileId : params.id,
    courseName: params.courseName,
    courseTeacherName: params.courseTeacherName,
    title: params.title,
    attachmentName: params.title + (params.fileType.length > 0 ? '.' + params.fileType : ''),
    downloadUrl: params.downloadUrl,
    fileType: params.fileType,
    size: params.size,
    uploadTime: params.uploadTime,
    description: ''
  };
}

/**
 * 文件设置页参数。
 *
 * 为什么给一个空壳接口：`NavPathStack.pushPath` 的 `param` 是 `Object`，
 * ArkTS 里原始值不能当 `Object` 传（SemesterSelectionRouteParams 同一处置）。
 */
export interface FileSettingsRouteParams {
  /** 进入设置页时实际生效的落盘根目录（只用于日志/诊断）。 */
  activeRoot: string;
}
