import {
  GET_ALL_SEMESTERS_REQUEST,
  GET_ALL_SEMESTERS_SUCCESS,
  GET_ALL_SEMESTERS_FAILURE,
  GET_CURRENT_SEMESTER_REQUEST,
  GET_CURRENT_SEMESTER_SUCCESS,
  GET_CURRENT_SEMESTER_FAILURE,
  SET_CURRENT_SEMESTER,
  RESET_LOADING,
} from 'data/types/constants';
import type { SemestersAction } from 'data/types/actions';
import type { SemestersState } from 'data/types/state';

const initialState: SemestersState = {
  fetchingAll: false,
  fetchingCurrent: false,
  items: [],
  current: null,
  error: null,
};

export const semestersReducer = (
  state: SemestersState = initialState,
  action: SemestersAction | { type: string; payload?: any },
): SemestersState => {
  switch (action.type) {
    case GET_ALL_SEMESTERS_REQUEST:
      return {
        ...state,
        fetchingAll: true,
        error: null,
      };
    case GET_ALL_SEMESTERS_SUCCESS:
      return {
        ...state,
        items: action.payload || [],
        fetchingAll: false,
        error: null,
      };
    case GET_ALL_SEMESTERS_FAILURE:
      return {
        ...state,
        fetchingAll: false,
        error: action.payload || 'Failed to fetch semesters',
      };
    case GET_CURRENT_SEMESTER_REQUEST:
      return {
        ...state,
        fetchingCurrent: true,
        error: null,
      };
    case GET_CURRENT_SEMESTER_SUCCESS:
      return {
        ...state,
        current: action.payload || null,
        fetchingCurrent: false,
        error: null,
      };
    case GET_CURRENT_SEMESTER_FAILURE:
      return {
        ...state,
        fetchingCurrent: false,
        error: action.payload || 'Failed to fetch current semester',
      };
    case SET_CURRENT_SEMESTER:
      return {
        ...state,
        current: action.payload || null,
      };
    case RESET_LOADING:
      return {
        ...state,
        fetchingAll: false,
        fetchingCurrent: false,
      };
    default:
      return state;
  }
};
