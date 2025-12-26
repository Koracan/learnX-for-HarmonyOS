import React from 'react';
import {
  useColorScheme,
  AppState,
  type AppStateStatus,
  StatusBar,
} from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import {
  NavigationContainer,
  DefaultTheme as NavigationDefaultTheme,
  DarkTheme as NavigationDarkTheme,
} from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import {
  Provider as PaperProvider,
  MD3DarkTheme,
  MD3LightTheme,
  useTheme,
} from 'react-native-paper';
import { Provider as StoreProvider } from 'react-redux';
import { PersistGate } from 'redux-persist/integration/react';
import MaterialCommunityIcons from 'react-native-vector-icons/MaterialCommunityIcons';
import Login from 'screens/Login';
import SSO from 'screens/SSO';
import Notices from 'screens/Notices';
import NoticeDetail from 'screens/NoticeDetail';
import Settings from 'screens/Settings';
import Splash from 'components/Splash';
import { ToastProvider } from 'components/Toast';
import { persistor, store, useAppSelector, useAppDispatch } from 'data/store';
import { login } from 'data/actions/auth';
import { resetLoading } from 'data/actions/root';
import { getCoursesForSemester } from 'data/actions/courses';
import { getAllSemesters, getCurrentSemester } from 'data/actions/semesters';
import { t } from 'helpers/i18n';
import useToast from 'hooks/useToast';
import type { NoticeStackParams, SettingsStackParams, MainTabParams, RootStackParams } from 'screens/types';

const RootStack = createNativeStackNavigator<RootStackParams>();
const NoticeStack = createNativeStackNavigator<NoticeStackParams>();
const SettingsStack = createNativeStackNavigator<SettingsStackParams>();
const MainNavigator = createBottomTabNavigator<MainTabParams>();

/**
 * Notice 子栈：公告列表与公告详情导航容器。
 */
const NoticeStackScreens = () => {
  return (
    <NoticeStack.Navigator>
      <NoticeStack.Screen
        name="Notices"
        component={Notices}
        options={{ headerShown: true, title: t('notices') }}
      />
      <NoticeStack.Screen
        name="NoticeDetail"
        component={NoticeDetail as any}
        options={{ headerShown: true, title: '' }}
      />
    </NoticeStack.Navigator>
  );
};

/**
 * 状态栏控制器：根据用户设置显示/隐藏状态栏。
 */
const StatusBarController = () => {
  const statusBarHidden = useAppSelector(state => state.settings.statusBarHidden);

  return (
    <StatusBar
      hidden={statusBarHidden}
      animated={true}
      translucent={true}
      backgroundColor="transparent"
    />
  );
};

/**
 * 设置子栈：设置页面导航容器。
 */
const SettingsStackScreens = () => {
  return (
    <SettingsStack.Navigator>
      <SettingsStack.Screen
        name="Settings"
        component={Settings}
        options={{ headerShown: false }}
      />
    </SettingsStack.Navigator>
  );
};

/**
 * 主选项卡导航：通知和设置的选项卡切换。
 */
const MainTabScreens = () => {
  const theme = useTheme();

  return (
    <MainNavigator.Navigator
      screenOptions={({ route }) => ({
        tabBarIcon: ({ color, size }) => {
          const iconMap: Record<keyof MainTabParams, string> = {
            NoticeStack: 'bell',
            SettingsStack: 'cog',
          };
          return (
            <MaterialCommunityIcons
              name={iconMap[route.name]}
              size={size}
              color={color}
            />
          );
        },
        activeTintColor: theme.colors.primary,
        inactiveTintColor: 'gray',
        headerShown: false,
        tabBarLabel:
          route.name === 'NoticeStack'
            ? t('notices')
            : route.name === 'SettingsStack'
              ? '设置'
              : '',
      })}
    >
      <MainNavigator.Screen
        name="NoticeStack"
        component={NoticeStackScreens}
      />
      <MainNavigator.Screen
        name="SettingsStack"
        component={SettingsStackScreens}
      />
    </MainNavigator.Navigator>
  );
};

/**
 * 根栈：根据登录态切换登录流程或主功能栈，支持前后台切换自动重新登录。
 */
const RootStackScreens = () => {
  const auth = useAppSelector(state => state.auth);
  const semesters = useAppSelector(state => state.semesters);
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
      toast(t('loginFailed'), 'error', 8000);
    }
  }, [auth.error, toast]);

  // 登录成功后初始化学期列表
  React.useEffect(() => {
    if (!auth.loggedIn) return;
    if (semesters.items.length === 0 && !semesters.fetchingAll) {
      console.log('[RootStackScreens] Logged in, fetching semesters');
      dispatch(getAllSemesters());
    }
  }, [auth.loggedIn, semesters.items.length, semesters.fetchingAll, dispatch]);

  // 登录后拉取当前学期（可与学期列表并行），避免重复请求依赖 fetchingCurrent
  React.useEffect(() => {
    if (!auth.loggedIn) return;
    if (semesters.current) return;
    if (semesters.fetchingCurrent) return;
    console.log('[RootStackScreens] Fetching current semester');
    dispatch(getCurrentSemester());
  }, [auth.loggedIn, semesters.current, semesters.fetchingCurrent, dispatch]);

  // 根据当前学期加载课程（无 ref、防止 fetching 抖动引起循环）
  React.useEffect(() => {
    if (!auth.loggedIn) return;
    if (!semesters.current) return;
    dispatch(getCoursesForSemester(semesters.current));
  }, [auth.loggedIn, semesters.current, dispatch]);

  // 自动重新登录逻辑：检查凭据完整性、SSO 状态、登录超时
  const handleReLogin = React.useCallback(() => {
    const {
      username,
      password,
      fingerPrint,
      ssoInProgress,
      loggingIn,
      loggedIn,
    } = auth;
    const idleTime = Date.now() - lastActiveTimeRef.current;

    // 凭据不完整，无法重新登录
    if (!username || !password || !fingerPrint) {
      console.log(
        '[handleReLogin] Credentials incomplete, skipping auto-login',
      );
      return;
    }

    // SSO 或登录正在进行，避免冲突
    if (ssoInProgress || loggingIn) {
      console.log(
        '[handleReLogin] SSO or login in progress, skipping auto-login',
        {
          ssoInProgress,
          loggingIn,
        },
      );
      return;
    }

    // 初次登录或超过 10 分钟未活跃
    const shouldReLogin = idleTime > 10 * 60 * 1000 || !loggedIn;
    if (shouldReLogin) {
      console.log('[handleReLogin] Triggering auto-login', {
        idleTime,
        loggedIn,
        reason: idleTime > 10 * 60 * 1000 ? 'idle-timeout' : 'not-logged-in',
      });
      toast(t('loggingIn'), 'success', 1000);
      dispatch(login({ reset: true }));
    }
  }, [auth, dispatch, toast]);

  // AppState 监听：区分后台/前台状态，前台时重新认证，后台时记录时间
  React.useEffect(() => {
    const subscription = AppState.addEventListener(
      'change',
      (nextAppState: AppStateStatus) => {
        if (nextAppState === 'active') {
          // 返回前台：清除加载态、尝试重新登录
          console.log(
            '[AppState] Returning to foreground, reset loading and attempt re-login',
          );
          dispatch(resetLoading());
          handleReLogin();
        } else if (
          nextAppState === 'inactive' ||
          nextAppState === 'background'
        ) {
          // 进入后台/非活跃：记录当前时间
          console.log(
            '[AppState] Entering background/inactive, recording idle time start',
          );
          lastActiveTimeRef.current = Date.now();
        }
      },
    );

    return () => {
      subscription.remove();
    };
  }, [handleReLogin, dispatch]);

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
        <RootStack.Screen name="MainTab" component={MainTabScreens} />
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
                <StatusBarController />
                <NavigationContainer theme={navigationTheme}>
                  <RootStackScreens />
                </NavigationContainer>
              </SafeAreaProvider>
            </PersistGate>
          </StoreProvider>
        </ToastProvider>
      </PaperProvider>
    </GestureHandlerRootView>
  );
};

export default App;
