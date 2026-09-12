/*
 * 课程卡片上的三类计数 —— 领域纯逻辑，**零平台依赖**（见 scripts/check-domain-purity.mjs）。
 *
 * 逐条对齐参考实现 `data/selectors/filteredData.ts:24-49` 的 `selectCoursesWithCounts`：
 *
 * | 计数 | 参考实现条件 | 本实现 |
 * | --- | --- | --- |
 * | unreadNoticeCount | `notice.courseId === course.id && !notice.hasRead` | 同 |
 * | unfinishedAssignmentCount | `assignment.courseId === course.id && !assignment.submitted && dayjs(deadline).isAfter(now)` | 同（deadline 走 domain/parse/Text.parseTimestamp；dayjs 无效日期 ⇒ isAfter=false，这里 NaN ⇒ false，同效） |
 * | unreadFileCount | `file.courseId === course.id && file.isNew` | 同 |
 *
 * 注意"未完成"= **未提交且未截止**，不是"未提交"：已过期未交的作业不计入
 * （参考实现如此，别顺手改成"所有未交"）。
 */

import { Assignment, CourseFile, Notice } from '../model/ContentItem';
import { parseTimestamp } from '../parse/Text';

/** 一门课上的三类计数。 */
export interface CourseCounts {
  unreadNoticeCount: number;
  unfinishedAssignmentCount: number;
  unreadFileCount: number;
}

/**
 * 作业是否"未完成"（参考实现口径：未提交且截止时间在 now 之后）。
 *
 * `parseTimestamp` 解析失败返回 NaN ⇒ 不计入，与 dayjs 的
 * `dayjs(invalid).isAfter(now) === false` 一致。
 */
export function isUnfinishedAssignment(assignment: Assignment, nowMillis: number): boolean {
  if (assignment.submitted) {
    return false;
  }
  const deadlineMillis: number = parseTimestamp(assignment.deadline);
  return !Number.isNaN(deadlineMillis) && deadlineMillis > nowMillis;
}

/** 某门课的未读公告数。 */
export function countUnreadNoticesForCourse(notices: Notice[], courseId: string): number {
  let count: number = 0;
  for (const notice of notices) {
    if (notice.courseId === courseId && !notice.hasRead) {
      count++;
    }
  }
  return count;
}

/** 某门课的未完成作业数（未提交且未截止）。 */
export function countUnfinishedAssignmentsForCourse(assignments: Assignment[], courseId: string,
  nowMillis: number): number {
  let count: number = 0;
  for (const assignment of assignments) {
    if (assignment.courseId === courseId && isUnfinishedAssignment(assignment, nowMillis)) {
      count++;
    }
  }
  return count;
}

/** 某门课的新文件数（参考实现用 `isNew`）。 */
export function countNewFilesForCourse(files: CourseFile[], courseId: string): number {
  let count: number = 0;
  for (const file of files) {
    if (file.courseId === courseId && file.isNew) {
      count++;
    }
  }
  return count;
}

/** 一次性算出三类计数（课程卡片每行一次）。 */
export function countsForCourse(courseId: string, notices: Notice[], assignments: Assignment[],
  files: CourseFile[], nowMillis: number): CourseCounts {
  return {
    unreadNoticeCount: countUnreadNoticesForCourse(notices, courseId),
    unfinishedAssignmentCount: countUnfinishedAssignmentsForCourse(assignments, courseId, nowMillis),
    unreadFileCount: countNewFilesForCourse(files, courseId)
  };
}
