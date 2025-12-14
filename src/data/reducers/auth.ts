import { createReducer } from 'typesafe-actions';
import { loginAction, setSSOInProgress } from 'data/actions/auth';
import { AuthState } from 'data/types/state';

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

export const auth = createReducer(initialState)
  .handleAction(loginAction.request, (state: AuthState) => ({
    ...state,
    loggingIn: true,
    error: null,
  }))
  .handleAction(loginAction.success, (state: AuthState, action: any) => ({
    ...state,
    loggingIn: false,
    loggedIn: true,
    ...(action.payload || {}),
  }))
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