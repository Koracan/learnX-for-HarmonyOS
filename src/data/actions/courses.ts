import { createAction, createAsyncAction } from 'typesafe-actions';
import { type ApiError, CourseType, Language } from 'thu-learn-lib';
import type { Course } from 'data/types/state';
import {
  SET_COURSES,
  SET_HIDE_COURSE,
  SET_COURSE_ORDER,
  GET_COURSES_FOR_SEMESTER_REQUEST,
  GET_COURSES_FOR_SEMESTER_SUCCESS,
  GET_COURSES_FOR_SEMESTER_FAILURE,
} from 'data/types/constants';
import type { ThunkResult } from 'data/types/actions';
import { dataSource } from 'data/source';
import { serializeError } from 'helpers/parse';
import { isLocaleChinese } from 'helpers/i18n';

/**
 * 设置课程列表。
 */
export const setCourses = createAction(SET_COURSES, (courses: Course[]) => ({
  courses,
}))();

export const setHideCourse = createAction(
  SET_HIDE_COURSE,
  (courseId: string, flag: boolean) => ({ courseId, flag }),
)();

export const setCourseOrder = createAction(
  SET_COURSE_ORDER,
  (courseIds: string[]) => courseIds,
)();

/**
 * 获取课程列表的异步 action。
 */
export const getCoursesForSemesterAction = createAsyncAction(
  GET_COURSES_FOR_SEMESTER_REQUEST,
  GET_COURSES_FOR_SEMESTER_SUCCESS,
  GET_COURSES_FOR_SEMESTER_FAILURE,
)<undefined, Course[], ApiError>();

/**
 * 拉取指定学期课程列表并写入 store。
 */
export function getCoursesForSemester(semesterId: string): ThunkResult {
  return async dispatch => {
    dispatch(getCoursesForSemesterAction.request());
    try {
      const lang = isLocaleChinese() ? Language.ZH : Language.EN;
      console.log('[getCoursesForSemester] semester=', semesterId, 'lang=', lang);

      const courses = await dataSource.getCourseList(
        semesterId,
        CourseType.STUDENT,
        lang,
      );
      console.log('[getCoursesForSemester] fetched courses=', courses.length);

      const mapped = courses.map<Course>(c => ({
        ...c,
        semesterId,
      }));
      dispatch(getCoursesForSemesterAction.success(mapped));
    } catch (err) {
      console.error('[getCoursesForSemester] Error:', err);
      dispatch(getCoursesForSemesterAction.failure(serializeError(err)));
    }
  };
}
