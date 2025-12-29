import { createAction, createAsyncAction } from 'typesafe-actions';
import { type ApiError } from 'thu-learn-lib';
import { InteractionManager } from 'react-native';
import dayjs from 'dayjs';
import type { ThunkResult } from 'data/types/actions';
import {
  GET_ALL_NOTICES_FOR_COURSES_FAILURE,
  GET_ALL_NOTICES_FOR_COURSES_REQUEST,
  GET_ALL_NOTICES_FOR_COURSES_SUCCESS,
  GET_NOTICES_FOR_COURSE_FAILURE,
  GET_NOTICES_FOR_COURSE_REQUEST,
  GET_NOTICES_FOR_COURSE_SUCCESS,
  SET_ARCHIVE_NOTICES,
  SET_FAV_NOTICE,
} from 'data/types/constants';
import type { Notice } from 'data/types/state';
import { dataSource, fetchNoticesWithReAuth } from 'data/source';
import { serializeError } from 'helpers/parse';
import { LearnOHDataProcessor } from 'react-native-learn-oh-data-processor';

export const getNoticesForCourseAction = createAsyncAction(
  GET_NOTICES_FOR_COURSE_REQUEST,
  GET_NOTICES_FOR_COURSE_SUCCESS,
  GET_NOTICES_FOR_COURSE_FAILURE,
)<undefined, { courseId: string; notices: Notice[] }, ApiError>();

export function getNoticesForCourse(courseId: string): ThunkResult {
  return async (dispatch, getState) => {
    dispatch(getNoticesForCourseAction.request());

    try {
      const results = await dataSource.getNotificationList(courseId);
      const courseName = getState().courses.names[courseId];
      const notices = results
        .map<Notice>(result => ({
          ...result,
          courseId,
          courseName: courseName.name,
          courseTeacherName: courseName.teacherName,
        }))
        .sort(
          (a, b) =>
            dayjs(b.publishTime).unix() - dayjs(a.publishTime).unix() ||
            b.id.localeCompare(a.id),
        );
      dispatch(getNoticesForCourseAction.success({ notices, courseId }));
    } catch (err) {
      dispatch(getNoticesForCourseAction.failure(serializeError(err)));
    }
  };
}

export const getAllNoticesForCoursesAction = createAsyncAction(
  GET_ALL_NOTICES_FOR_COURSES_REQUEST,
  GET_ALL_NOTICES_FOR_COURSES_SUCCESS,
  GET_ALL_NOTICES_FOR_COURSES_FAILURE,
)<undefined, Notice[], ApiError>();

export function getAllNoticesForCourses(courseIds: string[]): ThunkResult {
  return async (dispatch, getState) => {
    dispatch(getAllNoticesForCoursesAction.request());

    try {
      let notices: Notice[];
      const courseNames = getState().courses.names;

      const rawResultsJson = await fetchNoticesWithReAuth(courseIds);

      const processedJson = await LearnOHDataProcessor.processNotices(
        rawResultsJson,
        JSON.stringify(courseNames),
      );
      notices = JSON.parse(processedJson);
      console.log(`[JS] Notices processed. Count: ${notices.length}`);
      if (notices.length > 0) {
        console.log(`[JS] First notice sample:`, {
          id: notices[0].id,
          hasContent: !!notices[0].content,
          hasAttachment: !!notices[0].attachment,
        });
      }

      InteractionManager.runAfterInteractions(() => {
        dispatch(getAllNoticesForCoursesAction.success(notices));
      });
    } catch (err) {
      dispatch(getAllNoticesForCoursesAction.failure(serializeError(err)));
    }
  };
}

export const setFavNotice = createAction(
  SET_FAV_NOTICE,
  (noticeId: string, flag: boolean) => ({
    noticeId,
    flag,
  }),
)();

export const setArchiveNotices = createAction(
  SET_ARCHIVE_NOTICES,
  (noticeIds: string[], flag: boolean) => ({
    noticeIds,
    flag,
  }),
)();
