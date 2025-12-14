import { createAction, createAsyncAction } from 'typesafe-actions';
import { ApiError, ContentType, CourseType, Language } from 'thu-learn-lib';
import dayjs from 'dayjs';
import { ThunkResult } from 'data/types/actions';
import {
  GET_ALL_NOTICES_FOR_COURSES_FAILURE,
  GET_ALL_NOTICES_FOR_COURSES_REQUEST,
  GET_ALL_NOTICES_FOR_COURSES_SUCCESS,
  SET_ARCHIVE_NOTICES,
  SET_FAV_NOTICE,
} from 'data/types/constants';
import { Notice } from 'data/types/state';
import { dataSource } from 'data/source';
import { setCourses } from 'data/actions/courses';
import { serializeError } from 'helpers/parse';

export const getAllNoticesForCoursesAction = createAsyncAction(
  GET_ALL_NOTICES_FOR_COURSES_REQUEST,
  GET_ALL_NOTICES_FOR_COURSES_SUCCESS,
  GET_ALL_NOTICES_FOR_COURSES_FAILURE,
)<undefined, Notice[], ApiError>();

export function getAllNoticesForCourses(): ThunkResult {
  return async (dispatch, getState) => {
    dispatch(getAllNoticesForCoursesAction.request());
    try {
      let courses = getState().courses.items;
      if (courses.length === 0) {
        const semesters = await dataSource.getSemesterIdList();
        const semesterId = semesters?.sort().reverse()[0];
        if (!semesterId) {
          throw new Error('No semesters available');
        }

        const fetched = await dataSource.getCourseList(
          semesterId,
          CourseType.STUDENT,
          Language.EN,
        );
        courses = fetched.map(c => ({
          id: c.id,
          name: c.name,
          teacherName: c.teacherName,
        }));
        dispatch(setCourses(courses));
      }

      const courseIds = courses.map(c => c.id);
      const results = await dataSource.getAllContents(
        courseIds,
        ContentType.NOTIFICATION,
      );

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
          }));
        })
        .sort(
          (a, b) =>
            dayjs(b.publishTime).unix() - dayjs(a.publishTime).unix() ||
            b.id.localeCompare(a.id),
        );

      dispatch(getAllNoticesForCoursesAction.success(notices));
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
