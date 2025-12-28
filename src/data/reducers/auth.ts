import { createReducer } from 'typesafe-actions';
import { loginAction, setSSOInProgress } from 'data/actions/auth';
import type { AuthState } from 'data/types/state';

/**
 * 认证初始状态。
 */
const initialState: AuthState = {
  username: null,
  password: null,
  fingerPrint: null,
  fingerGenPrint: null,
  fingerGenPrint3: null,
  loggingIn: false,
  ssoInProgress: false,
  loggedIn: false,
  error: null,
};

/**
 * 认证 reducer：处理登录请求/成功/失败与 SSO 进度。
 */
export const auth = createReducer(initialState)
  .handleAction(loginAction.request, (state: AuthState) => ({
    ...state,
    loggingIn: true,
    error: null,
  }))
  .handleAction(loginAction.success, (state: AuthState, action: any) => {
    const payload = action.payload;
    if (payload) {
      return {
        ...state,
        loggingIn: false,
        loggedIn: true,
        username: payload.username,
        password: payload.password,
        fingerPrint: payload.fingerPrint,
        fingerGenPrint: payload.fingerGenPrint,
        fingerGenPrint3: payload.fingerGenPrint3,
        error: null,
      };
    } else {
      return {
        ...state,
        loggingIn: false,
        loggedIn: true,
        error: null,
      };
    }
  })
  .handleAction(loginAction.failure, (state: AuthState, action: any) => ({
    ...state,
    loggingIn: false,
    loggedIn: false,
    error: action.payload,
  }))
  .handleAction(setSSOInProgress, (state: AuthState, action: any) => ({
    ...state,
    ssoInProgress: action.payload.ssoInProgress,
  }));
