import { createAction, createAsyncAction } from 'typesafe-actions';
import type { ApiError } from 'thu-learn-lib';
import { loginWithFingerPrint, resetDataSource } from 'data/source';
import type { ThunkResult } from 'data/types/actions';
import { getUserInfo } from 'data/actions/user';
import {
  LOGIN_FAILURE,
  LOGIN_REQUEST,
  LOGIN_SUCCESS,
  SET_SSO_IN_PROGRESS,
} from 'data/types/constants';
import type { Auth } from 'data/types/state';
import { serializeError } from 'helpers/parse';
import { retry } from 'helpers/retry';

/**
 * 登录异步 action：包含请求/成功/失败三个阶段。
 */
export const loginAction = createAsyncAction(
  LOGIN_REQUEST,
  LOGIN_SUCCESS,
  LOGIN_FAILURE,
)<{ clearCredential?: boolean }, Auth | undefined, ApiError>();

/**
 * 登录 thunk：支持 SSO 登录（可选 reset 重建数据源）。
 */
export function login({
  username,
  password,
  fingerPrint,
  fingerGenPrint = '',
  fingerGenPrint3 = '',
  reset = false,
}: {
  username?: string;
  password?: string;
  fingerPrint?: string;
  fingerGenPrint?: string;
  fingerGenPrint3?: string;
  reset?: boolean;
}): ThunkResult {
  return async (dispatch, getState) => {
    console.log('[login] Called with params:', {
      hasUsername: !!username,
      hasPassword: !!password,
      hasFingerprint: !!fingerPrint,
      reset,
    });

    if (!username || !password || !fingerPrint) {
      const { auth } = getState();
      console.log('[login] Reading from state:', {
        hasUsername: !!auth.username,
        hasPassword: !!auth.password,
        hasFingerprint: !!auth.fingerPrint,
        loggingIn: auth.loggingIn,
      });
      if (auth.loggingIn) {
        console.log('[login] Already logging in, return');
        return;
      }
    }

    dispatch(
      loginAction.request({
        clearCredential: !!username && !!password && !fingerPrint,
      }),
    );

    try {
      if (reset) {
        console.log('[login] Resetting dataSource');
        resetDataSource();
      }

      console.log('[login] Calling loginWithFingerPrint');
      await retry(async () => {
        await loginWithFingerPrint(
          username,
          password,
          fingerPrint,
          fingerGenPrint,
          fingerGenPrint3,
        );
      });

      console.log('[login] Login successful');
      if (username && password && fingerPrint) {
        dispatch(
          loginAction.success({
            username,
            password,
            fingerPrint,
            fingerGenPrint,
            fingerGenPrint3,
          }),
        );
      } else {
        dispatch(loginAction.success(undefined));
      }
      console.log('[login] Fetching user info');
      dispatch(getUserInfo());
    } catch (err) {
      console.error('[login] Failed:', err);
      dispatch(loginAction.failure(serializeError(err)));
    }
  };
}

/**
 * 离线登录：直接标记登录成功，不校验远端。
 */
export function loginWithOfflineMode(): ThunkResult {
  return dispatch => {
    dispatch(loginAction.success(undefined));
  };
}

/**
 * 设置 SSO 流程进度标记。
 */
export const setSSOInProgress = createAction(
  SET_SSO_IN_PROGRESS,
  (ssoInProgress: boolean) => ({
    ssoInProgress,
  }),
)();
