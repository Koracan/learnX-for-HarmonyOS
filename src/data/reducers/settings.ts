import { createReducer } from 'typesafe-actions';
import { setSetting } from 'data/actions/settings';
import type { SettingsAction } from 'data/types/actions';
import type { SettingsState } from 'data/types/state';

const initialState: SettingsState = {
  graduate: false,
};

export const settings = createReducer<SettingsState, SettingsAction>(
  initialState,
).handleAction(setSetting, (state, action) => ({
  ...state,
  [action.payload.key]: action.payload.value,
}));
