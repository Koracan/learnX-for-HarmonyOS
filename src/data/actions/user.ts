import { createAsyncAction } from 'typesafe-actions';
import type { ThunkResult } from 'data/types/actions';
import { type ApiError, CourseType } from 'thu-learn-lib';
import { dataSource } from 'data/source';
import {
  GET_USER_INFO_FAILURE,
  GET_USER_INFO_REQUEST,
  GET_USER_INFO_SUCCESS,
} from 'data/types/constants';
import type { UserState } from 'data/types/state';

export const getUserInfoAction = createAsyncAction(
  /**
   * 获取用户信息的异步 action。
   */
  GET_USER_INFO_REQUEST,
  GET_USER_INFO_SUCCESS,
  GET_USER_INFO_FAILURE,
)<void, UserState, ApiError>();

export function getUserInfo(): ThunkResult {
  /**
   * 拉取用户信息并写入 store。
   */
  return async dispatch => {
    dispatch(getUserInfoAction.request());
    try {
      const userInfo = await dataSource.getUserInfo(CourseType.STUDENT);
      dispatch(getUserInfoAction.success(userInfo as UserState));
    } catch (err) {
      dispatch(getUserInfoAction.failure(err as ApiError));
    }
  };
}
