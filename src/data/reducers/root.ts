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
} from 'data/types/state';
import type { AppActions } from 'data/types/actions';
import { RESET_LOADING } from 'data/types/constants';

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
  whitelist: ['graduate', 'immersiveMode'],
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
 * Assignments 持久化配置：持久化收藏与存档。
 */
const assignmentsPersistConfig: PersistConfig<AssignmentsState> = {
  key: 'assignments',
  storage: AsyncStorage,
  whitelist: ['favorites', 'archived'],
};

/**
 * Files 持久化配置：持久化收藏与存档。
 */
const filesPersistConfig: PersistConfig<FilesState> = {
  key: 'files',
  storage: AsyncStorage,
  whitelist: ['favorites', 'archived'],
};

const appReducer = combineReducers({
  auth: persistReducer(authPersistConfig, auth),
  settings: persistReducer(settingsPersistConfig, settings),
  courses,
  notices,
  assignments: persistReducer(assignmentsPersistConfig, assignments),
  files: persistReducer(filesPersistConfig, files),
  user,
  semesters: persistReducer(semestersPersistConfig, semesters),
}) as (state: AppState | undefined, action: AppActions) => AppState;

/**
 * 根 reducer：聚合各领域 reducer，并处理全局操作（如 RESET_LOADING）。
 */
export function rootReducer(
  state: AppState | undefined,
  action: AppActions,
): AppState {
  // 处理全局重置加载态
  if (action.type === RESET_LOADING) {
    return {
      ...state,
      auth: {
        ...state?.auth,
        loggingIn: false,
      },
      courses: {
        ...state?.courses,
        fetching: false,
      },
      notices: {
        ...state?.notices,
        fetching: false,
      },
      assignments: {
        ...state?.assignments,
        fetching: false,
      },
      files: {
        ...state?.files,
        fetching: false,
      },
      user: {
        ...state?.user,
        fetching: false,
      },
      semesters: {
        ...state?.semesters,
        fetching: false,
      },
    } as any;
  }

  return appReducer(state, action as any);
}
