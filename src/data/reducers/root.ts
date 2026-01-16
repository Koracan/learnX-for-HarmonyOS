import { combineReducers } from 'redux';
import { persistReducer, type PersistConfig } from 'redux-persist';
import SecureStorage from 'helpers/secureStorage';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { auth } from 'data/reducers/auth';
import { settings } from 'data/reducers/settings';
import { courses } from 'data/reducers/courses';
import { notices } from 'data/reducers/notices';
import assignments from 'data/reducers/assignments';
import files from 'data/reducers/files';
import { user } from 'data/reducers/user';
import { semestersReducer as semesters } from 'data/reducers/semesters';
import type {
  AppState,
  AuthState,
  SettingsState,
  SemestersState,
  AssignmentsState,
  FilesState,
  CoursesState,
} from 'data/types/state';
import type { AppActions } from 'data/types/actions';
import {
  RESET_LOADING,
  CLEAR_STORE,
  SET_MOCK_STORE,
  SET_FAV_NOTICE,
  SET_ARCHIVE_NOTICES,
  SET_FAV_FILE,
  SET_ARCHIVE_FILES,
  SET_FAV_ASSIGNMENT,
  SET_ARCHIVE_ASSIGNMENTS,
  SET_PENDING_ASSIGNMENT_DATA,
  SET_HIDE_COURSE,
  SET_COURSE_ORDER,
  SET_CURRENT_SEMESTER,
  SET_SETTING,
} from 'data/types/constants';
import type { NoticeState } from 'data/types/state';
import mockStore from 'data/mock';
import env from 'helpers/env';

/**
 * Auth 持久化配置：使用 secure storage 仅持久化敏感凭据。
 */
const authPersistConfig: PersistConfig<AuthState> = {
  key: 'auth',
  storage: SecureStorage,
  whitelist: [
    'username',
    'password',
    'fingerPrint',
    'fingerGenPrint',
    'fingerGenPrint3',
  ],
};

/**
 * Settings 持久化配置：使用 AsyncStorage 持久化用户设置。
 */
const settingsPersistConfig: PersistConfig<SettingsState> = {
  key: 'settings',
  storage: AsyncStorage,
  blacklist: ['newUpdate'],
};

/**
 * Semesters 持久化配置：使用 AsyncStorage 缓存学期数据。
 */
const semestersPersistConfig: PersistConfig<SemestersState> = {
  key: 'semesters',
  storage: AsyncStorage,
  whitelist: ['items', 'current'],
};

/**
 * Courses 持久化配置：持久化课程列表和顺序。
 */
const coursesPersistConfig: PersistConfig<CoursesState> = {
  key: 'courses',
  storage: AsyncStorage,
  whitelist: ['items', 'names', 'order', 'hidden'],
};

/**
 * User 持久化配置。
 */
const userPersistConfig: PersistConfig<any> = {
  key: 'user',
  storage: AsyncStorage,
};

/**
 * Assignments 持久化配置：持久化收藏与存档。
 */
const assignmentsPersistConfig: PersistConfig<AssignmentsState> = {
  key: 'assignments',
  storage: AsyncStorage,
  whitelist: ['favorites', 'archived', 'items'],
};

/**
 * Files 持久化配置：持久化收藏与存档。
 */
const filesPersistConfig: PersistConfig<FilesState> = {
  key: 'files',
  storage: AsyncStorage,
  whitelist: ['favorites', 'archived', 'items'],
};

/**
 * 公告持久化配置。
 */
const noticesPersistConfig: PersistConfig<NoticeState> = {
  key: 'notices',
  storage: AsyncStorage,
  whitelist: ['favorites', 'archived', 'items'],
};

const appReducer = combineReducers({
  auth: persistReducer(authPersistConfig, auth),
  settings: persistReducer(settingsPersistConfig, settings),
  courses: persistReducer(coursesPersistConfig, courses),
  notices: persistReducer(noticesPersistConfig, notices),
  assignments: persistReducer(assignmentsPersistConfig, assignments),
  files: persistReducer(filesPersistConfig, files),
  user: persistReducer(userPersistConfig, user),
  semesters: persistReducer(semestersPersistConfig, semesters),
}) as (state: AppState | undefined, action: AppActions) => AppState;

/**
 * 根 reducer：聚合各领域 reducer，并处理全局操作（如 RESET_LOADING）。
 */
export function rootReducer(
  state: AppState | undefined,
  action: AppActions,
): AppState {
  if (action.type === SET_MOCK_STORE) {
    return mockStore as unknown as AppState;
  } else if (action.type === CLEAR_STORE) {
    state = undefined;
  } else if (state && state.auth.username === env.DUMMY_USERNAME) {
    if (
      ![
        SET_FAV_NOTICE,
        SET_ARCHIVE_NOTICES,
        SET_FAV_FILE,
        SET_ARCHIVE_FILES,
        SET_FAV_ASSIGNMENT,
        SET_ARCHIVE_ASSIGNMENTS,
        SET_PENDING_ASSIGNMENT_DATA,
        SET_HIDE_COURSE,
        SET_COURSE_ORDER,
        SET_CURRENT_SEMESTER,
        SET_SETTING,
      ].includes(action.type)
    ) {
      return state;
    }
  }

  // 处理全局重置加载态
  if (state && action.type === RESET_LOADING) {
    return {
      ...state,
      auth: {
        ...state.auth,
        loggingIn: false,
      },
      semesters: {
        ...state.semesters,
        fetching: false,
        error: null,
      },
      courses: {
        ...state.courses,
        fetching: false,
        error: null,
      },
      notices: {
        ...state.notices,
        fetching: false,
        error: null,
      },
      files: {
        ...state.files,
        fetching: false,
        error: null,
      },
      assignments: {
        ...state.assignments,
        fetching: false,
        error: null,
      },
    };
  }

  // 处理登出时的全局状态清空
  if (action.type === CLEAR_STORE) {
    return appReducer(undefined, action as any);
  }

  return appReducer(state, action as any);
}
