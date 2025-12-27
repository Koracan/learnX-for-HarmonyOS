import { type ApiError, ContentType } from 'thu-learn-lib';
import { createAction, createAsyncAction } from 'typesafe-actions';
import dayjs from 'dayjs';
import { dataSource } from 'data/source';
import type { ThunkResult } from 'data/types/actions';
import {
  GET_ALL_ASSIGNMENTS_FOR_COURSES_FAILURE,
  GET_ALL_ASSIGNMENTS_FOR_COURSES_REQUEST,
  GET_ALL_ASSIGNMENTS_FOR_COURSES_SUCCESS,
  SET_FAV_ASSIGNMENT,
  SET_ARCHIVE_ASSIGNMENTS,
} from 'data/types/constants';
import type { Assignment } from 'data/types/state';
import { serializeError } from 'helpers/parse';

export const getAllAssignmentsForCoursesAction = createAsyncAction(
  GET_ALL_ASSIGNMENTS_FOR_COURSES_REQUEST,
  GET_ALL_ASSIGNMENTS_FOR_COURSES_SUCCESS,
  GET_ALL_ASSIGNMENTS_FOR_COURSES_FAILURE,
)<undefined, Assignment[], ApiError>();

export function getAllAssignmentsForCourses(courseIds: string[]): ThunkResult {
  return async (dispatch, getState) => {
    dispatch(getAllAssignmentsForCoursesAction.request());

    try {
      const results = await dataSource.getAllContents(
        courseIds,
        ContentType.HOMEWORK,
      );
      const courses = getState().courses.items;
      const assignments = Object.keys(results)
        .map(courseId => {
          const assignmentsForCourse = results[courseId];
          const course = courses.find(c => c.id === courseId) ?? undefined;
    
          return assignmentsForCourse.map<Assignment>(assignment => ({
            ...assignment,
            courseId,
            courseName: course?.name ?? '',
            courseTeacherName: course?.teacherName ?? '',
          }));
        })
        .reduce((a, b) => a.concat(b), [])
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
      dispatch(getAllAssignmentsForCoursesAction.success(sorted));
    } catch (err) {
      dispatch(getAllAssignmentsForCoursesAction.failure(serializeError(err)));
    }
  };
}

export const setFavAssignment = createAction(
  SET_FAV_ASSIGNMENT,
)<{ id: string; fav: boolean }>();

export const setArchiveAssignments = createAction(
  SET_ARCHIVE_ASSIGNMENTS,
)<{ ids: string[]; archive: boolean }>();
