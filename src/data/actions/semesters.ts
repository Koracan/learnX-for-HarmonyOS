import { createAction, createAsyncAction } from 'typesafe-actions';
import { dataSource } from 'data/source';
import type { ThunkResult } from 'data/types/actions';
import {
  GET_ALL_SEMESTERS_FAILURE,
  GET_ALL_SEMESTERS_REQUEST,
  GET_ALL_SEMESTERS_SUCCESS,
  GET_CURRENT_SEMESTER_REQUEST,
  GET_CURRENT_SEMESTER_SUCCESS,
  GET_CURRENT_SEMESTER_FAILURE,
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
      const sorted = semesters?.sort().reverse();
      console.log(
        '[getAllSemesters] Success length=',
        sorted?.length,
        'first=',
        sorted?.[0],
      );
      dispatch(getAllSemestersAction.success(sorted));
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

export const getCurrentSemesterAction = createAsyncAction(
  GET_CURRENT_SEMESTER_REQUEST,
  GET_CURRENT_SEMESTER_SUCCESS,
  GET_CURRENT_SEMESTER_FAILURE,
)<undefined, string, Error>();

export function getCurrentSemester(): ThunkResult {
  return async (dispatch, getState) => {
    dispatch(getCurrentSemesterAction.request());
    try {
      const semester = await dataSource.getCurrentSemester();
      console.log('[getCurrentSemester] Backend returned:', semester?.id);
      dispatch(getCurrentSemesterAction.success(semester?.id));

      if (semester?.id && !getState().semesters.current) {
        dispatch(setCurrentSemester(semester.id));
      }
    } catch (err) {
      console.warn('[getCurrentSemester] Failed:', err);
      const e =
        err instanceof Error
          ? err
          : new Error(
              typeof err === 'string' ? err : JSON.stringify(err ?? {}),
            );
      dispatch(getCurrentSemesterAction.failure(e));
    }
  };
}

export const setCurrentSemester = createAction(
  SET_CURRENT_SEMESTER,
  (semesterId: string) => semesterId,
)();
