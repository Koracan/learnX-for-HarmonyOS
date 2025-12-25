import { createAction, createAsyncAction } from 'typesafe-actions';
import { type ApiError, ContentType } from 'thu-learn-lib';
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
import { serializeError } from 'helpers/parse';
import { removeTags } from 'helpers/html';

/**
 * 获取全部课程公告的异步 action。
 */
export const getAllNoticesForCoursesAction = createAsyncAction(
  GET_ALL_NOTICES_FOR_COURSES_REQUEST,
  GET_ALL_NOTICES_FOR_COURSES_SUCCESS,
  GET_ALL_NOTICES_FOR_COURSES_FAILURE,
)<undefined, Notice[], ApiError>();

/**
 * 获取指定课程的公告列表，按时间排序后入 store。
 * @param courseIds 课程ID列表
 */
export function getAllNoticesForCourses(courseIds: string[]): ThunkResult {
  return async (dispatch, getState) => {
    console.log('[getAllNoticesForCourses] Starting fetch for', courseIds.length, 'courses');
    dispatch(getAllNoticesForCoursesAction.request());
    
    try {
      const results = await dataSource.getAllContents(
        courseIds,
        ContentType.NOTIFICATION,
      );
      
      const courses = getState().courses.items;
      const courseMap = courses.reduce<Record<string, string>>(
        (acc, c) => ({ ...acc, [c.id]: c.name }),
        {},
      );
      
      const notices = Object.keys(results)
        .flatMap(courseId => {
          const list = results[courseId];
          const courseName = courseMap[courseId] || '';
          return list.map<Notice>(n => ({
            ...n,
            courseId,
            courseName,
            plainText: n.content ? removeTags(n.content) : '',
          }));
        })
        .sort(
          (a, b) =>
            dayjs(b.publishTime).unix() - dayjs(a.publishTime).unix() ||
            b.id.localeCompare(a.id),
        );
      
      console.log('[getAllNoticesForCourses] Fetched', notices.length, 'notices');
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
