import {
  GET_ALL_SEMESTERS_REQUEST,
  GET_ALL_SEMESTERS_SUCCESS,
  GET_ALL_SEMESTERS_FAILURE,
  SET_CURRENT_SEMESTER,
  RESET_LOADING,
} from 'data/types/constants';
import type { SemestersAction } from 'data/types/actions';
import type { SemestersState } from 'data/types/state';

const initialState: SemestersState = {
  fetching: false,
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
        fetching: true,
        error: null,
      };
    case GET_ALL_SEMESTERS_SUCCESS:
      return {
        ...state,
        items: action.payload || [],
        current: (action.payload as string[])?.[0] || null,
        fetching: false,
        error: null,
      };
    case GET_ALL_SEMESTERS_FAILURE:
      return {
        ...state,
        fetching: false,
        error: action.payload || 'Failed to fetch semesters',
      };
    case SET_CURRENT_SEMESTER:
      return {
        ...state,
        current: action.payload || null,
      };
    case RESET_LOADING:
      return {
        ...state,
        fetching: false,
      };
    default:
      return state;
  }
};
