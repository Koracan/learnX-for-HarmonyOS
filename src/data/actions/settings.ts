import { createAction } from 'typesafe-actions';
import { type SettingsState } from 'data/types/state';
import {
  SET_SETTING,
  SET_EVENT_ID_FOR_ASSIGNMENT,
  REMOVE_EVENT_ID_FOR_ASSIGNMENT,
  CLEAR_EVENT_IDS,
} from 'data/types/constants';

export const setSetting = createAction(
  /**
   * 设置单个设置项。
   */
  SET_SETTING,
  <K extends keyof SettingsState>(key: K, value: SettingsState[K]) => ({
    key,
    value,
  }),
)();

export const setEventIdForAssignment = createAction(
  SET_EVENT_ID_FOR_ASSIGNMENT,
  (type: 'calendar' | 'reminder', assignmentId: string, eventId: string) => ({
    type,
    assignmentId,
    eventId,
  }),
)();

export const removeEventIdForAssignment = createAction(
  REMOVE_EVENT_ID_FOR_ASSIGNMENT,
  (type: 'calendar' | 'reminder', assignmentId: string) => ({
    type,
    assignmentId,
  }),
)();

export const clearEventIds = createAction(
  CLEAR_EVENT_IDS,
  (type: 'calendar' | 'reminder') => ({ type }),
)();
