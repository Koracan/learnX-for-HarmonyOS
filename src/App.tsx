import React from 'react';
import { StatusBar, useColorScheme, AppState, type AppStateStatus } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import {
  NavigationContainer,
  DefaultTheme as NavigationDefaultTheme,
  DarkTheme as NavigationDarkTheme,
} from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import {
  Provider as PaperProvider, 
  MD3DarkTheme,
  MD3LightTheme,
} from 'react-native-paper';
import { Provider as StoreProvider } from 'react-redux';
import { PersistGate } from 'redux-persist/integration/react';
import Login from 'screens/Login';
import SSO from 'screens/SSO';
import Notices from 'screens/Notices';
import NoticeDetail from 'screens/NoticeDetail';
import Splash from 'components/Splash';
import { ToastProvider } from 'components/Toast';
import { persistor, store, useAppSelector, useAppDispatch } from 'data/store';
import { login } from 'data/actions/auth';
import useToast from 'hooks/useToast';
import type { NoticeStackParams, RootStackParams } from './screens/types';

const RootStack = createNativeStackNavigator<RootStackParams>();
const NoticeStack = createNativeStackNavigator<NoticeStackParams>();

/**
 * Notice 子栈：公告列表与公告详情导航容器。
 */
const NoticeStackScreens = () => (
  <NoticeStack.Navigator>
    <NoticeStack.Screen
      name="Notices"
      component={Notices}
      options={{ headerShown: false }}
    />
    <NoticeStack.Screen
      name="NoticeDetail"
      component={NoticeDetail as any}
      options={{ headerShown: true, title: '' }}
    />
  </NoticeStack.Navigator>
);

/**
 * 根栈：根据登录态切换登录流程或主功能栈，支持前后台切换自动重新登录。
 */
const RootStackScreens = () => {
  const auth = useAppSelector(state => state.auth);
  const dispatch = useAppDispatch();
  const hasCreds = !!auth.username && !!auth.password && !!auth.fingerPrint;
  const showMain = !auth.error && hasCreds && auth.loggedIn;
  const toast = useToast();
  const lastActiveTimeRef = React.useRef<number>(Date.now());
  const hasTriedAutoLoginRef = React.useRef<boolean>(false);

  console.log('[RootStackScreens] render', {
    hasCreds,
    loggedIn: auth.loggedIn,
    error: auth.error,
  });

  React.useEffect(() => {
    if (auth.error) {
      toast('Login failed', 'error', 8000);
    }
  }, [auth.error, toast]);

  // 自动重新登录逻辑：前后台切换或初始化时检查凭据
  const handleReLogin = React.useCallback(() => {
    const { username, password, fingerPrint, ssoInProgress, loggingIn, loggedIn } = auth;
    const idleTime = Date.now() - lastActiveTimeRef.current;

    if (!hasCreds) {
      return;
    }

    // 无论 loggedIn 与否，只要凭据存在且非登录中就尝试（初始或超时）
    if (!ssoInProgress && !loggingIn) {
      const shouldReLogin = idleTime > 10 * 60 * 1000 || !loggedIn; // 初次或超 10 分钟
      if (shouldReLogin) {
        console.log('[handleReLogin] Triggering auto-login, idle time:', idleTime, 'loggedIn:', loggedIn);
        toast('Re-authenticating...', 'success', 2000);
        dispatch(login({ reset: true }));
      }
    }
  }, [auth, dispatch, toast, hasCreds]);

  // AppState 监听：回到前台时触发重新登录
  React.useEffect(() => {
    const subscription = AppState.addEventListener('change', (nextAppState: AppStateStatus) => {
      if (nextAppState === 'active') {
        handleReLogin();
      }
      lastActiveTimeRef.current = Date.now();
    });

    return () => {
      subscription.remove();
    };
  }, [handleReLogin]);

  // 初始加载完成后尝试自动登录（仅一次）
  React.useEffect(() => {
    if (!hasTriedAutoLoginRef.current) {
      const timer = setTimeout(() => {
        hasTriedAutoLoginRef.current = true;
        handleReLogin();
      }, 800); // 延迟确保 rehydrate 完成
      return () => clearTimeout(timer);
    }
  }, [handleReLogin]);

  return (
    <RootStack.Navigator screenOptions={{ headerShown: false }}>
      {showMain ? (
        <RootStack.Screen name="NoticeStack" component={NoticeStackScreens} />
      ) : (
        <>
          <RootStack.Screen name="Login" component={Login} />
          <RootStack.Screen name="SSO" component={SSO} />
        </>
      )}
    </RootStack.Navigator>
  );
};

/**
 * 应用入口：主题、状态管理、导航与 Toast 提供者。
 */
const App = () => {
  const colorScheme = useColorScheme();
  const paperTheme = colorScheme === 'dark' ? MD3DarkTheme : MD3LightTheme;
  const navigationTheme =
    colorScheme === 'dark' ? NavigationDarkTheme : NavigationDefaultTheme;

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <PaperProvider theme={paperTheme}>
        <ToastProvider>
          <StoreProvider store={store}>
            <PersistGate loading={<Splash />} persistor={persistor}>
              <SafeAreaProvider>
                <NavigationContainer theme={navigationTheme}>
                  <RootStackScreens />
                </NavigationContainer>
              </SafeAreaProvider>
            </PersistGate>
          </StoreProvider>
        </ToastProvider>
        <StatusBar
          barStyle={colorScheme === 'dark' ? 'light-content' : 'dark-content'}
          backgroundColor={paperTheme.colors.surface}
          animated
        />
      </PaperProvider>
    </GestureHandlerRootView>
  );
};

export default App;
