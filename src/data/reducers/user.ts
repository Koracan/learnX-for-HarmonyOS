import { createReducer } from 'typesafe-actions';
import { getUserInfoAction } from 'data/actions/user';
import type { UserState } from 'data/types/state';

/**
 * 用户初始状态。
 */
const initialState: UserState = {
  name: null,
  department: null,
  email: null,
  phone: null,
  id: null,
  gender: null,
  type: null,
  class: null,
};

/**
 * 用户 reducer：处理用户信息加载与错误。
 */
export const user = createReducer(initialState)
  .handleAction(getUserInfoAction.success, (state: UserState, action: any) => ({
    ...state,
    ...action.payload,
  }));
