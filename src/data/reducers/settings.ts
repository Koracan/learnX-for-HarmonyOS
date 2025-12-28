import type { SettingsAction } from 'data/types/actions';
import type { SettingsState } from 'data/types/state';
import {
  SET_SETTING,
  SET_EVENT_ID_FOR_ASSIGNMENT,
  REMOVE_EVENT_ID_FOR_ASSIGNMENT,
  CLEAR_EVENT_IDS,
} from 'data/types/constants';

/**
 * 设置初始状态。
 */
const initialState: SettingsState = {
  assignmentCalendarSync: false,
  assignmentReminderSync: false,
  syncedCalendarAssignments: {},
  syncedReminderAssignments: {},
  newUpdate: false,
  graduate: false,
  immersiveMode: false,
  fileUseDocumentDir: false,
  fileOmitCourseName: false,
  tabFilterSelections: {
    notice: 'all',
    assignment: 'unfinished',
    file: 'all',
    course: 'all',
  },
  alarms: {
    assignmentCalendarSecondAlarm: false,
    assignmentCalendarAlarm: false,
    assignmentCalendarNoAlarmIfComplete: false,
    assignmentReminderAlarm: false,
    courseAlarm: false,
  },
  courseInformationSharing: false,
  courseInformationSharingBadgeShown: false,
  lastShowChangelogVersion: null,
  openFileAfterDownload: false,
  courseEventOmitLocation: false,
};

/**
 * 设置 reducer：处理通用设置项更新。
 */
export function settings(
  state: SettingsState = initialState,
  action: SettingsAction,
): SettingsState {
  switch (action.type) {
    case SET_SETTING: {
      const oldValue = state[action.payload.key];
      const newValue = action.payload.value;
      if (
        typeof oldValue === 'object' &&
        typeof newValue === 'object' &&
        oldValue !== null &&
        newValue !== null
      ) {
        return {
          ...state,
          [action.payload.key]: {
            ...oldValue,
            ...newValue,
          },
        };
      } else {
        return {
          ...state,
          [action.payload.key]: newValue,
        };
      }
    }
    case SET_EVENT_ID_FOR_ASSIGNMENT:
      if (action.payload.type === 'calendar') {
        return {
          ...state,
          syncedCalendarAssignments: {
            ...state.syncedCalendarAssignments,
            [action.payload.assignmentId]: action.payload.eventId,
          },
        };
      } else {
        return {
          ...state,
          syncedReminderAssignments: {
            ...state.syncedReminderAssignments,
            [action.payload.assignmentId]: action.payload.eventId,
          },
        };
      }
    case REMOVE_EVENT_ID_FOR_ASSIGNMENT:
      if (action.payload.type === 'calendar') {
        const syncedCalendarAssignments = {
          ...state.syncedCalendarAssignments,
        };
        delete syncedCalendarAssignments[action.payload.assignmentId];
        return {
          ...state,
          syncedCalendarAssignments,
        };
      } else {
        const syncedReminderAssignments = {
          ...state.syncedReminderAssignments,
        };
        delete syncedReminderAssignments[action.payload.assignmentId];
        return {
          ...state,
          syncedReminderAssignments,
        };
      }
    case CLEAR_EVENT_IDS:
      if (action.payload.type === 'calendar') {
        return {
          ...state,
          syncedCalendarAssignments: {},
        };
      } else {
        return {
          ...state,
          syncedReminderAssignments: {},
        };
      }
    default:
      return state;
  }
}
