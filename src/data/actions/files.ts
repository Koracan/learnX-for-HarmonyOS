import { type ApiError } from 'thu-learn-lib';
import { createAction, createAsyncAction } from 'typesafe-actions';
import { InteractionManager } from 'react-native';
import dayjs from 'dayjs';
import { dataSource, fetchFilesWithReAuth } from 'data/source';
import type { ThunkResult } from 'data/types/actions';
import { LearnOHDataProcessor } from 'react-native-learn-oh-data-processor';
import {
  GET_ALL_FILES_FOR_COURSES_FAILURE,
  GET_ALL_FILES_FOR_COURSES_REQUEST,
  GET_ALL_FILES_FOR_COURSES_SUCCESS,
  GET_FILES_FOR_COURSE_FAILURE,
  GET_FILES_FOR_COURSE_REQUEST,
  GET_FILES_FOR_COURSE_SUCCESS,
  SET_FAV_FILE,
  SET_ARCHIVE_FILES,
} from 'data/types/constants';
import type { File } from 'data/types/state';
import { serializeError } from 'helpers/parse';

export const getFilesForCourseAction = createAsyncAction(
  GET_FILES_FOR_COURSE_REQUEST,
  GET_FILES_FOR_COURSE_SUCCESS,
  GET_FILES_FOR_COURSE_FAILURE,
)<
  undefined,
  {
    courseId: string;
    files: File[];
  },
  ApiError
>();

export function getFilesForCourse(courseId: string): ThunkResult {
  return async (dispatch, getState) => {
    dispatch(getFilesForCourseAction.request());

    try {
      const results = await dataSource.getFileList(courseId);
      const courseName = getState().courses.names[courseId];
      const files = results
        .map<File>(result => ({
          ...result,
          courseId,
          courseName: courseName.name,
          courseTeacherName: courseName.teacherName,
        }))
        .sort(
          (a, b) =>
            dayjs(b.uploadTime).unix() - dayjs(a.uploadTime).unix() ||
            b.id.localeCompare(a.id),
        );
      dispatch(
        getFilesForCourseAction.success({
          courseId,
          files,
        }),
      );
    } catch (err) {
      dispatch(getFilesForCourseAction.failure(serializeError(err)));
    }
  };
}

export const getAllFilesForCoursesAction = createAsyncAction(
  GET_ALL_FILES_FOR_COURSES_REQUEST,
  GET_ALL_FILES_FOR_COURSES_SUCCESS,
  GET_ALL_FILES_FOR_COURSES_FAILURE,
)<undefined, File[], ApiError>();

export function getAllFilesForCourses(courseIds: string[]): ThunkResult {
  return async (dispatch, getState) => {
    dispatch(getAllFilesForCoursesAction.request());

    try {
      let files: File[];
      const courseNames = getState().courses.names;

      const rawResultsJson = await fetchFilesWithReAuth(courseIds);

      const processedJson = await LearnOHDataProcessor.processFiles(
        rawResultsJson,
        JSON.stringify(courseNames),
      );
      files = JSON.parse(processedJson);

      InteractionManager.runAfterInteractions(() => {
        dispatch(getAllFilesForCoursesAction.success(files));
      });
    } catch (err) {
      dispatch(getAllFilesForCoursesAction.failure(serializeError(err)));
    }
  };
}

export const setFavFile = createAction(
  SET_FAV_FILE,
  (fileId: string, flag: boolean) => ({
    fileId,
    flag,
  }),
)();

export const setArchiveFiles = createAction(
  SET_ARCHIVE_FILES,
  (fileIds: string[], flag: boolean) => ({
    fileIds,
    flag,
  }),
)();
