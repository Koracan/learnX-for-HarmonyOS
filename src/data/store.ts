import {
  type TypedUseSelectorHook,
  useDispatch,
  useSelector,
} from 'react-redux';
import {
  persistStore,
  persistReducer,
  FLUSH,
  REHYDRATE,
  PAUSE,
  PERSIST,
  PURGE,
  REGISTER,
  type PersistConfig,
} from 'redux-persist';
import autoMergeLevel2 from 'redux-persist/lib/stateReconciler/autoMergeLevel2';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { configureStore } from '@reduxjs/toolkit';
import { rootReducer } from 'data/reducers/root';
import type { AppState, PersistAppState } from 'data/types/state';
import type { AppActions } from 'data/types/actions';

/**
 * redux-persist 配置：指定持久化键与合并策略。
 * 注意：auth/settings/semesters 已在 root reducer 中单独配置持久化，此处 blacklist 避免重复。
 */
const rootPersistConfig: PersistConfig<AppState> = {
  key: 'root',
  storage: AsyncStorage,
  stateReconciler: autoMergeLevel2,
  blacklist: [
    'auth',
    'settings',
    'semesters',
    'courses',
    'notices',
    'assignments',
    'files',
    'user',
  ],
};

/**
 * Redux store 实例，包含持久化与序列化检查配置。
 */
export const store = configureStore<PersistAppState, AppActions>({
  reducer: persistReducer(rootPersistConfig, rootReducer) as any,
  middleware: getDefaultMiddleware =>
    getDefaultMiddleware({
      serializableCheck: {
        ignoredActions: [FLUSH, REHYDRATE, PAUSE, PERSIST, PURGE, REGISTER],
      },
    }),
});

export const persistor = persistStore(store);

export type AppDispatch = typeof store.dispatch;
/**
 * 强类型 dispatch hook。
 */
export const useAppDispatch = () => useDispatch<AppDispatch>();
/**
 * 强类型 selector hook。
 */
export const useAppSelector: TypedUseSelectorHook<
  ReturnType<typeof store.getState>
> = useSelector;
