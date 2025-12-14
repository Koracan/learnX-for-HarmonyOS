import { createReducer } from 'typesafe-actions';
import { getAllCoursesAction, setCourses } from 'data/actions/courses';
import { CoursesAction } from 'data/types/actions';
import { CoursesState } from 'data/types/state';

const initialState: CoursesState = {
  items: [],
  hidden: [],
  fetching: false,
  error: null,
};

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
