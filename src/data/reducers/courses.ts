import { createReducer } from 'typesafe-actions';
import {
  getCoursesForSemesterAction,
  setCourses,
  setHideCourse,
  setCourseOrder,
} from 'data/actions/courses';
import type { CoursesAction } from 'data/types/actions';
import type { CoursesState } from 'data/types/state';
import { sortByOrder } from 'helpers/reorder';

/**
 * 课程初始状态。
 */
const initialState: CoursesState = {
  items: [],
  names: {},
  hidden: [],
  order: [],
  fetching: false,
  error: null,
};

/**
 * 课程 reducer：处理课程列表加载与存储。
 */
export const courses = createReducer<CoursesState, CoursesAction>(initialState)
  .handleAction(getCoursesForSemesterAction.request, state => ({
    ...state,
    fetching: true,
    error: null,
  }))
  .handleAction(getCoursesForSemesterAction.success, (state, action) => {
    const courses = action.payload;
    const courseOrder = state.order;
    const orderedCourses = sortByOrder(courses, courseOrder);
    return {
      ...state,
      fetching: false,
      items: orderedCourses,
      names: orderedCourses.reduce<{
        [id: string]: { name: string; teacherName: string };
      }>(
        (prev, curr) => ({
          ...prev,
          [curr.id]: {
            name: curr.name,
            teacherName: curr.teacherName,
          },
        }),
        {},
      ),
      error: null,
    };
  })
  .handleAction(getCoursesForSemesterAction.failure, (state, action) => ({
    ...state,
    fetching: false,
    error: action.payload.reason,
  }))
  .handleAction(setCourses, (state, action) => ({
    ...state,
    items: action.payload.courses,
  }))
  .handleAction(setHideCourse, (state, action) => ({
    ...state,
    hidden: action.payload.flag
      ? [...state.hidden, action.payload.courseId]
      : state.hidden.filter(id => id !== action.payload.courseId),
  }))
  .handleAction(setCourseOrder, (state, action) => {
    const courses = state.items;
    const newOrder = action.payload;
    const orderedCourses = sortByOrder(courses, newOrder);
    return {
      ...state,
      order: newOrder,
      items: orderedCourses,
    };
  });
