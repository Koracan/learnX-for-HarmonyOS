import { createAction } from 'typesafe-actions';
import { RESET_LOADING } from 'data/types/constants';

/**
 * 重置所有 fetching 状态。
 * 用于登出、错误恢复或其他需要清除所有加载态的场景。
 */
export const resetLoading = createAction(RESET_LOADING)();

