import { createReducer } from 'typesafe-actions';
import { getUserInfoAction } from 'data/actions/user';

export interface UserState {
  fetching: boolean;
  info: any | null;
  error?: any | null;
}

/**
 * 用户初始状态。
 */
const initialState: UserState = {
  fetching: false,
  info: null,
  error: null,
};

/**
 * 用户 reducer：处理用户信息加载与错误。
 */
export const user = createReducer(initialState)
  .handleAction(getUserInfoAction.request, (state: UserState) => ({
    ...state,
    fetching: true,
    error: null,
  }))
  .handleAction(getUserInfoAction.success, (state: UserState, action: any) => ({
    ...state,
    fetching: false,
    info: action.payload,
  }))
  .handleAction(getUserInfoAction.failure, (state: UserState, action: any) => ({
    ...state,
    fetching: false,
    error: action.payload,
  }));
