import { createAction } from 'typesafe-actions';
import { type SettingsState } from 'data/types/state';
import { SET_SETTING } from 'data/types/constants';

export const setSetting = createAction(
  SET_SETTING,
  <K extends keyof SettingsState>(key: K, value: SettingsState[K]) => ({
    key,
    value,
  }),
)();
