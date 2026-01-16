import { createAction } from 'typesafe-actions';
import {
  RESET_LOADING,
  CLEAR_STORE,
  SET_MOCK_STORE,
} from 'data/types/constants';
import { persistor } from 'data/store';
import type { ThunkResult } from 'data/types/actions';

/**
 * 重置所有 fetching 状态。
 * 用于登出、错误恢复或其他需要清除所有加载态的场景。
 */
export const resetLoading = createAction(RESET_LOADING)();

export const clearStoreAction = createAction(CLEAR_STORE)();

/**
 * 清除整个 Redux Store。
 * 用于退出登录时重置用户数据。
 */
export function clearStore(): ThunkResult {
  return async dispatch => {
    dispatch(clearStoreAction());
    await persistor.purge();
    persistor.persist();
  };
}

export const setMockStore = createAction(SET_MOCK_STORE)();
