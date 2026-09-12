/*
 * 课程列表抓取 —— **转发层**（data/notices）。
 *
 * 【ticket 12】课程这条线的完整实现在 `data/courses/CourseListFetcher.ets` 与
 * `data/courses/SemesterFetcher.ets`（ticket 12 要按学期取、要完整条目）。
 * ticket 09 的这份文件当时**只做了公告路径需要的那一小段**；本 ticket 把它改成转发，
 * 于是取数逻辑只有一份，而 ticket 09 的调用点（`NoticeFetchSource` /
 * `NoticeRepositoryProvider` / 单测）**一个导出名都不用改**。
 *
 * 行为边界（ticket 09 已验收）：`CourseListResult.names` 仍是
 * `courseId → { name: kcm, teacherName: jsm }`，`fetch(session)` 仍解析站点当前学期。
 * 新增的 `entries`（完整课程条目）与 `fetch(session, semesterId)` 不改变旧调用点的结果。
 */

export {
  COURSE_LIST_LOG_DOMAIN, COURSE_LIST_PATH_PREFIX, COURSE_LIST_LANGUAGE, RAW_PREVIEW_LIMIT,
  CourseEntry, CourseListResult, CourseListSource, HttpCourseListSource,
  parseCourseEntries, parseCourseList
} from '../courses/CourseListFetcher';

export {
  CURRENT_SEMESTER_PATH, SEMESTER_LIST_PATH, SemesterResolution, SemesterSource,
  HttpSemesterSource, extractSemesterId, parseSemesterList
} from '../courses/SemesterFetcher';
