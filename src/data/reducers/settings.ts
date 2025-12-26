import { createReducer } from 'typesafe-actions';
import { setSetting } from 'data/actions/settings';
import type { SettingsAction } from 'data/types/actions';
import type { SettingsState } from 'data/types/state';

/**
 * 设置初始状态。
 */
const initialState: SettingsState = {
  graduate: false,
  immersiveMode: false,
};

/**
 * 设置 reducer：处理通用设置项更新。
 */
export const settings = createReducer<SettingsState, SettingsAction>(
  initialState,
).handleAction(setSetting, (state, action) => ({
  ...state,
  [action.payload.key]: action.payload.value,
}));
