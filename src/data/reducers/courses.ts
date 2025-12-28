import { createReducer } from 'typesafe-actions';
import {
  getCoursesForSemesterAction,
  setCourses,
  setHideCourse,
  setCourseOrder,
} from 'data/actions/courses';
import type { CoursesAction } from 'data/types/actions';
import type { CoursesState } from 'data/types/state';

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
  .handleAction(getCoursesForSemesterAction.success, (state, action) => ({
    ...state,
    fetching: false,
    items: action.payload,
    names: action.payload.reduce(
      (prev, curr) => ({
        ...prev,
        [curr.id]: {
          name: curr.name,
          teacherName: curr.teacherName,
        },
      }),
      {},
    ),
    order:
      state.order.length === 0
        ? action.payload.map(c => c.id)
        : state.order.filter(id => action.payload.some(c => c.id === id)).concat(
            action.payload
              .filter(c => !state.order.includes(c.id))
              .map(c => c.id),
          ),
  }))
  .handleAction(getCoursesForSemesterAction.failure, (state, action) => ({
    ...state,
    fetching: false,
    error: action.payload,
  }))
  .handleAction(setCourses, (state, action) => ({
    ...state,
    items: action.payload.courses,
  }))
  .handleAction(setHideCourse, (state, action) => ({
    ...state,
    hidden: action.payload.flag
      ? [...new Set([...state.hidden, action.payload.courseId])]
      : state.hidden.filter(id => id !== action.payload.courseId),
  }))
  .handleAction(setCourseOrder, (state, action) => ({
    ...state,
    order: action.payload,
  }));
