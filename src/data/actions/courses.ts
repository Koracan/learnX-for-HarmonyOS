import { createAction, createAsyncAction } from 'typesafe-actions';
import { type ApiError, CourseType, Language } from 'thu-learn-lib';
import type { Course } from 'data/types/state';
import {
  SET_COURSES,
  GET_ALL_COURSES_REQUEST,
  GET_ALL_COURSES_SUCCESS,
  GET_ALL_COURSES_FAILURE,
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

/**
 * 获取课程列表的异步 action。
 */
export const getAllCoursesAction = createAsyncAction(
  GET_ALL_COURSES_REQUEST,
  GET_ALL_COURSES_SUCCESS,
  GET_ALL_COURSES_FAILURE,
)<undefined, Course[], ApiError>();

/**
 * 拉取指定学期课程列表并写入 store。
 */
export function getCoursesForSemester(semesterId: string): ThunkResult {
  return async dispatch => {
    dispatch(getAllCoursesAction.request());
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
        id: c.id,
        name: c.name,
        teacherName: c.teacherName,
      }));
      dispatch(setCourses(mapped));
      dispatch(getAllCoursesAction.success(mapped));
    } catch (err) {
      console.error('[getCoursesForSemester] Error:', err);
      dispatch(getAllCoursesAction.failure(serializeError(err)));
    }
  };
}
