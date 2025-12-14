import { createAction, createAsyncAction } from 'typesafe-actions';
import { ApiError, CourseType, Language } from 'thu-learn-lib';
import { Course } from 'data/types/state';
import {
  SET_COURSES,
  GET_ALL_COURSES_REQUEST,
  GET_ALL_COURSES_SUCCESS,
  GET_ALL_COURSES_FAILURE,
} from 'data/types/constants';
import { ThunkResult } from 'data/types/actions';
import { dataSource } from 'data/source';
import { serializeError } from 'helpers/parse';

export const setCourses = createAction(SET_COURSES, (courses: Course[]) => ({
  courses,
}))();

export const getAllCoursesAction = createAsyncAction(
  GET_ALL_COURSES_REQUEST,
  GET_ALL_COURSES_SUCCESS,
  GET_ALL_COURSES_FAILURE,
)<undefined, Course[], ApiError>();

export function getAllCourses(): ThunkResult {
  return async dispatch => {
    dispatch(getAllCoursesAction.request());
    try {
      const semesters = await dataSource.getSemesterIdList();
      const semesterId = semesters?.sort().reverse()[0];
      if (!semesterId) {
        throw new Error('No semesters available');
      }

      const courses = await dataSource.getCourseList(
        semesterId,
        CourseType.STUDENT,
        Language.EN,
      );
      const mapped = courses.map<Course>(c => ({
        id: c.id,
        name: c.name,
        teacherName: c.teacherName,
      }));
      dispatch(setCourses(mapped));
      dispatch(getAllCoursesAction.success(mapped));
    } catch (err) {
      dispatch(getAllCoursesAction.failure(serializeError(err)));
    }
  };
}
