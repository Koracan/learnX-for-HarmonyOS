import type { AssignmentsAction } from 'data/types/actions';
import {
  GET_ALL_ASSIGNMENTS_FOR_COURSES_FAILURE,
  GET_ALL_ASSIGNMENTS_FOR_COURSES_REQUEST,
  GET_ALL_ASSIGNMENTS_FOR_COURSES_SUCCESS,
  SET_FAV_ASSIGNMENT,
  SET_ARCHIVE_ASSIGNMENTS,
} from 'data/types/constants';
import type { AssignmentsState } from 'data/types/state';

export default function assignments(
  state: AssignmentsState = {
    fetching: false,
    favorites: [],
    archived: [],
    items: [],
  },
  action: AssignmentsAction,
): AssignmentsState {
  switch (action.type) {
    case GET_ALL_ASSIGNMENTS_FOR_COURSES_REQUEST:
      return {
        ...state,
        fetching: true,
        error: null,
      };
    case GET_ALL_ASSIGNMENTS_FOR_COURSES_SUCCESS:
      return {
        ...state,
        fetching: false,
        items: action.payload,
        error: null,
      };
    case GET_ALL_ASSIGNMENTS_FOR_COURSES_FAILURE:
      return {
        ...state,
        fetching: false,
        error: action.payload.reason,
      };
    case SET_FAV_ASSIGNMENT:
      if (action.payload.fav) {
        return {
          ...state,
          favorites: [...state.favorites, action.payload.id],
        };
      } else {
        return {
          ...state,
          favorites: state.favorites.filter(item => item !== action.payload.id),
        };
      }
    case SET_ARCHIVE_ASSIGNMENTS:
      if (action.payload.archive) {
        return {
          ...state,
          archived: [...state.archived, ...action.payload.ids],
        };
      } else {
        return {
          ...state,
          archived: state.archived.filter(i => !action.payload.ids.includes(i)),
        };
      }
    default:
      return state;
  }
}
