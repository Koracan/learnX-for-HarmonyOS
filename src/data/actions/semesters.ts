import { createAction, createAsyncAction } from 'typesafe-actions';
import { dataSource } from 'data/source';
import type { ThunkResult } from 'data/types/actions';
import {
  GET_ALL_SEMESTERS_FAILURE,
  GET_ALL_SEMESTERS_REQUEST,
  GET_ALL_SEMESTERS_SUCCESS,
  SET_CURRENT_SEMESTER,
} from 'data/types/constants';

export const getAllSemestersAction = createAsyncAction(
  GET_ALL_SEMESTERS_REQUEST,
  GET_ALL_SEMESTERS_SUCCESS,
  GET_ALL_SEMESTERS_FAILURE,
)<undefined, string[], Error>();

export function getAllSemesters(): ThunkResult {
  return async dispatch => {
    dispatch(getAllSemestersAction.request());

    try {
      console.log('[getAllSemesters] Fetching semesters...');
      const semesters = await dataSource.getSemesterIdList();
      console.log('[getAllSemesters] Success:', semesters);
      dispatch(getAllSemestersAction.success(semesters));
    } catch (err) {
      console.error('[getAllSemesters] Error:', err);
      dispatch(
        getAllSemestersAction.failure(
          err instanceof Error ? err : new Error('Unknown error'),
        ),
      );
    }
  };
}

export const setCurrentSemester = createAction(
  SET_CURRENT_SEMESTER,
  (semesterId: string) => semesterId,
)();
