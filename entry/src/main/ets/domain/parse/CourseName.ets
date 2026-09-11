/*
 * 课程名 / 教师名的查表值——**零平台依赖**。
 *
 * 参考实现把 `courseNames[courseId] = { name, teacherName }` 放在 redux 的
 * `courses.names` 里；移植后它是解析器的一个纯输入，单独成文件避免
 * "解析器 A 为了拿这个类型去 import 解析器 B"的相互依赖。
 */

/** 课程名与教师名。 */
export interface CourseName {
  name: string;
  teacherName: string;
}

/** 课程名查不到时的占位（照参考实现）。 */
export const UNKNOWN_COURSE_NAME: string = 'Unknown Course';

/** 取课程名；查不到时返回 `Unknown Course`。 */
export function courseNameOf(courseNames: Record<string, CourseName>, courseId: string): string {
  const known: CourseName | undefined = courseNames[courseId];
  return known === undefined ? UNKNOWN_COURSE_NAME : known.name;
}

/** 取教师名；查不到时返回空串（照参考实现）。 */
export function teacherNameOf(courseNames: Record<string, CourseName>, courseId: string): string {
  const known: CourseName | undefined = courseNames[courseId];
  return known === undefined ? '' : known.teacherName;
}
