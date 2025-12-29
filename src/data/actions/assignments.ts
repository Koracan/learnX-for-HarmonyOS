import { type ApiError } from 'thu-learn-lib';
import { createAction, createAsyncAction } from 'typesafe-actions';
import { InteractionManager } from 'react-native';
import dayjs from 'dayjs';
import { dataSource, fetchAssignmentsWithReAuth } from 'data/source';
import type { ThunkResult } from 'data/types/actions';
import { LearnOHDataProcessor } from 'react-native-learn-oh-data-processor';
import {
  GET_ALL_ASSIGNMENTS_FOR_COURSES_FAILURE,
  GET_ALL_ASSIGNMENTS_FOR_COURSES_REQUEST,
  GET_ALL_ASSIGNMENTS_FOR_COURSES_SUCCESS,
  GET_ASSIGNMENTS_FOR_COURSE_FAILURE,
  GET_ASSIGNMENTS_FOR_COURSE_REQUEST,
  GET_ASSIGNMENTS_FOR_COURSE_SUCCESS,
  SET_FAV_ASSIGNMENT,
  SET_ARCHIVE_ASSIGNMENTS,
  SET_PENDING_ASSIGNMENT_DATA,
} from 'data/types/constants';
import type { Assignment, AssignmentsState } from 'data/types/state';
import { serializeError } from 'helpers/parse';

export const getAssignmentsForCourseAction = createAsyncAction(
  GET_ASSIGNMENTS_FOR_COURSE_REQUEST,
  GET_ASSIGNMENTS_FOR_COURSE_SUCCESS,
  GET_ASSIGNMENTS_FOR_COURSE_FAILURE,
)<
  undefined,
  {
    courseId: string;
    assignments: Assignment[];
  },
  ApiError
>();

export function getAssignmentsForCourse(courseId: string): ThunkResult {
  return async (dispatch, getState) => {
    dispatch(getAssignmentsForCourseAction.request());

    try {
      const results = await dataSource.getHomeworkList(courseId);
      const courseName = getState().courses.names[courseId];
      const assignments = results
        .map<Assignment>(result => ({
          ...result,
          courseId,
          courseName: courseName.name,
          courseTeacherName: courseName.teacherName,
        }))
        .sort(
          (a, b) =>
            dayjs(b.deadline).unix() - dayjs(a.deadline).unix() ||
            b.id.localeCompare(a.id),
        );
      const sorted = [
        ...assignments
          .filter(a => dayjs(a.deadline).isAfter(dayjs()))
          .reverse(),
        ...assignments.filter(a => !dayjs(a.deadline).isAfter(dayjs())),
      ];
      dispatch(
        getAssignmentsForCourseAction.success({
          courseId,
          assignments: sorted,
        }),
      );
    } catch (err) {
      dispatch(getAssignmentsForCourseAction.failure(serializeError(err)));
    }
  };
}

export const getAllAssignmentsForCoursesAction = createAsyncAction(
  GET_ALL_ASSIGNMENTS_FOR_COURSES_REQUEST,
  GET_ALL_ASSIGNMENTS_FOR_COURSES_SUCCESS,
  GET_ALL_ASSIGNMENTS_FOR_COURSES_FAILURE,
)<undefined, Assignment[], ApiError>();

export function getAllAssignmentsForCourses(courseIds: string[]): ThunkResult {
  return async (dispatch, getState) => {
    const startTime = Date.now();
    console.log('[Performance] Start fetching all assignments');
    dispatch(getAllAssignmentsForCoursesAction.request());

    try {
      let assignments: Assignment[];
      const courseNames = getState().courses.names;

      const fetchStartTime = Date.now();
      console.log(
        '[Performance] Using TurboModule for fetching and processing',
      );
      const rawResultsJson = await fetchAssignmentsWithReAuth(courseIds);
      console.log(
        `[Performance] Native fetching took ${Date.now() - fetchStartTime}ms`,
      );

      const processStartTime = Date.now();
      const processedJson = await LearnOHDataProcessor.processAssignments(
        rawResultsJson,
        JSON.stringify(courseNames),
      );
      assignments = JSON.parse(processedJson);
      console.log(`[JS] Assignments processed. Count: ${assignments.length}`);
      if (assignments.length > 0) {
        console.log(`[JS] First assignment sample:`, {
          id: assignments[0].id,
          hasDescription: !!assignments[0].description,
          hasAttachment: !!assignments[0].attachment,
        });
      }
      console.log(
        `[Performance] Native processing took ${
          Date.now() - processStartTime
        }ms`,
      );

      const sortStartTime = Date.now();
      const sorted = [
        ...assignments
          .filter(a => dayjs(a.deadline).isAfter(dayjs()))
          .reverse(),
        ...assignments.filter(a => !dayjs(a.deadline).isAfter(dayjs())),
      ];
      console.log(
        `[Performance] Final sorting took ${Date.now() - sortStartTime}ms`,
      );

      InteractionManager.runAfterInteractions(() => {
        const dispatchStartTime = Date.now();
        dispatch(getAllAssignmentsForCoursesAction.success(sorted));
        console.log(
          `[Performance] Dispatching success took ${
            Date.now() - dispatchStartTime
          }ms`,
        );
        console.log(
          `[Performance] Total assignment refresh took ${
            Date.now() - startTime
          }ms`,
        );
      });
    } catch (err) {
      dispatch(getAllAssignmentsForCoursesAction.failure(serializeError(err)));
    }
  };
}

export const setFavAssignment = createAction(
  SET_FAV_ASSIGNMENT,
  (assignmentId: string, flag: boolean) => ({
    assignmentId,
    flag,
  }),
)();

export const setArchiveAssignments = createAction(
  SET_ARCHIVE_ASSIGNMENTS,
  (assignmentIds: string[], flag: boolean) => ({
    assignmentIds,
    flag,
  }),
)();

export const setPendingAssignmentData = createAction(
  SET_PENDING_ASSIGNMENT_DATA,
  (data: AssignmentsState['pendingAssignmentData']) => data,
)();
