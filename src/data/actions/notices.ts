import { createAction, createAsyncAction } from 'typesafe-actions';
import { type ApiError, ContentType, CourseType, Language } from 'thu-learn-lib';
import dayjs from 'dayjs';
import type { ThunkResult } from 'data/types/actions';
import {
  GET_ALL_NOTICES_FOR_COURSES_FAILURE,
  GET_ALL_NOTICES_FOR_COURSES_REQUEST,
  GET_ALL_NOTICES_FOR_COURSES_SUCCESS,
  SET_ARCHIVE_NOTICES,
  SET_FAV_NOTICE,
} from 'data/types/constants';
import type { Notice } from 'data/types/state';
import { dataSource } from 'data/source';
import { setCourses } from 'data/actions/courses';
import { serializeError } from 'helpers/parse';

/**
 * 获取全部课程公告的异步 action。
 */
export const getAllNoticesForCoursesAction = createAsyncAction(
  GET_ALL_NOTICES_FOR_COURSES_REQUEST,
  GET_ALL_NOTICES_FOR_COURSES_SUCCESS,
  GET_ALL_NOTICES_FOR_COURSES_FAILURE,
)<undefined, Notice[], ApiError>();

/**
 * 拉取课程列表并获取公告列表，按时间排序后入 store。
 */
export function getAllNoticesForCourses(): ThunkResult {
  return async (dispatch, getState) => {
    console.log('[getAllNoticesForCourses] Starting fetch');
    dispatch(getAllNoticesForCoursesAction.request());
    try {
      let courses = getState().courses.items;
      console.log('[getAllNoticesForCourses] Existing courses:', courses.length);

      // 如果已有课程则直接用当前学期；否则按学期倒序尝试直到拿到公告或用尽。
      let notices: Notice[] = [];

      if (courses.length > 0) {
        const courseIds = courses.map(c => c.id);
        const results = await dataSource.getAllContents(
          courseIds,
          ContentType.NOTIFICATION,
        );
        const courseMap = courses.reduce<Record<string, string>>(
          (acc, c) => ({ ...acc, [c.id]: c.name }),
          {},
        );
        notices = Object.keys(results)
          .flatMap(courseId => {
            const list = results[courseId];
            const courseName = courseMap[courseId] || '';
            return list.map<Notice>(n => ({
              ...n,
              courseId,
              courseName,
            }));
          })
          .sort(
            (a, b) =>
              dayjs(b.publishTime).unix() - dayjs(a.publishTime).unix() ||
              b.id.localeCompare(a.id),
          );
        console.log('[getAllNoticesForCourses] Total notices (cached courses):', notices.length);
      } else {
        console.log('[getAllNoticesForCourses] Fetching semesters');
        const semesters = await dataSource.getSemesterIdList();
        console.log('[getAllNoticesForCourses] Semesters:', semesters);
        if (!semesters || semesters.length === 0) {
          throw new Error('No semesters available');
        }

        const sortedSemesters = semesters.sort().reverse();
        for (const semesterId of sortedSemesters) {
          console.log('[getAllNoticesForCourses] Try semester:', semesterId);
          const fetched = await dataSource.getCourseList(
            semesterId,
            CourseType.STUDENT,
            Language.EN,
          );
          console.log('[getAllNoticesForCourses] Fetched courses:', fetched.length);
          courses = fetched.map(c => ({
            id: c.id,
            name: c.name,
            teacherName: c.teacherName,
          }));
          dispatch(setCourses(courses));

          const courseIds = courses.map(c => c.id);
          const results = await dataSource.getAllContents(
            courseIds,
            ContentType.NOTIFICATION,
          );
          const courseMap = courses.reduce<Record<string, string>>(
            (acc, c) => ({ ...acc, [c.id]: c.name }),
            {},
          );
          notices = Object.keys(results)
            .flatMap(courseId => {
              const list = results[courseId];
              const courseName = courseMap[courseId] || '';
              return list.map<Notice>(n => ({
                ...n,
                courseId,
                courseName,
              }));
            })
            .sort(
              (a, b) =>
                dayjs(b.publishTime).unix() - dayjs(a.publishTime).unix() ||
                b.id.localeCompare(a.id),
            );
          console.log('[getAllNoticesForCourses] Notices for semester', semesterId, ':', notices.length);

          if (notices.length > 0) {
            break;
          }
        }
      }

      console.log('[getAllNoticesForCourses] Total notices (final):', notices.length);
      dispatch(getAllNoticesForCoursesAction.success(notices));
    } catch (err) {
      console.error('[getAllNoticesForCourses] Error:', err);
      dispatch(getAllNoticesForCoursesAction.failure(serializeError(err)));
    }
  };
}

/**
 * 设置公告收藏标记。
 */
export const setFavNotice = createAction(
  SET_FAV_NOTICE,
  (noticeId: string, flag: boolean) => ({
    noticeId,
    flag,
  }),
)();

/**
 * 批量设置公告归档标记。
 */
export const setArchiveNotices = createAction(
  SET_ARCHIVE_NOTICES,
  (noticeIds: string[], flag: boolean) => ({
    noticeIds,
    flag,
  }),
)();
