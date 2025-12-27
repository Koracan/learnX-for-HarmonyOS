import { createReducer } from 'typesafe-actions';
import { getAllCoursesAction, setCourses } from 'data/actions/courses';
import type { CoursesAction } from 'data/types/actions';
import type { CoursesState } from 'data/types/state';

/**
 * 课程初始状态。
 */
const initialState: CoursesState = {
  items: [],
  names: {},
  hidden: [],
  fetching: false,
  error: null,
};

/**
 * 课程 reducer：处理课程列表加载与存储。
 */
export const courses = createReducer<CoursesState, CoursesAction>(initialState)
  .handleAction(getAllCoursesAction.request, state => ({
    ...state,
    fetching: true,
    error: null,
  }))
  .handleAction(getAllCoursesAction.success, (state, action) => ({
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
  }))
  .handleAction(getAllCoursesAction.failure, (state, action) => ({
    ...state,
    fetching: false,
    error: action.payload,
  }))
  .handleAction(setCourses, (state, action) => ({
    ...state,
    items: action.payload.courses,
  }));
