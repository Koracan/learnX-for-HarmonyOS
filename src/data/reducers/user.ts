import { createReducer, type ActionType } from 'typesafe-actions';
import { getUserInfoAction } from 'data/actions/user';
import type { UserState } from 'data/types/state';

/**
 * 用户初始状态。
 */
const initialState: UserState = {
  name: null,
  department: null,
} as UserState;

/**
 * 用户 reducer：处理用户信息加载与错误。
 */
export const user = createReducer<
  UserState,
  ActionType<typeof getUserInfoAction>
>(initialState).handleAction(getUserInfoAction.success, (state, action) => ({
  ...state,
  ...action.payload,
}));
