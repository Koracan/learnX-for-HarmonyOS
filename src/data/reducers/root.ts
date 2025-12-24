import { combineReducers } from 'redux';
import { persistReducer, type PersistConfig } from 'redux-persist';
import SecureStorage from 'helpers/secureStorage';
import { auth } from 'data/reducers/auth';
import { settings } from 'data/reducers/settings';
import { courses } from 'data/reducers/courses';
import { notices } from 'data/reducers/notices';
import { user } from 'data/reducers/user';
import type { AppState, AuthState } from 'data/types/state';
import type { AppActions } from 'data/types/actions';

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

const appReducer = combineReducers({
  auth: persistReducer(authPersistConfig, auth),
  settings,
  courses,
  notices,
  user,
}) as (state: AppState | undefined, action: AppActions) => AppState;

/**
 * 根 reducer：聚合各领域 reducer。
 */
export function rootReducer(
  state: AppState | undefined,
  action: AppActions,
): AppState {
  return appReducer(state, action as any);
}
