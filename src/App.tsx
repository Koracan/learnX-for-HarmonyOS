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
import Assignments from 'screens/Assignments';
import AssignmentDetail from 'screens/AssignmentDetail';
import Files from 'screens/Files';
import FileDetail from 'screens/FileDetail';
import Courses from 'screens/Courses';
import CourseDetail from 'screens/CourseDetail';
import Settings from 'screens/Settings';
import Splash from 'components/Splash';
import Empty from 'components/Empty';
import { ToastProvider } from 'components/Toast';
import { persistor, store, useAppSelector, useAppDispatch } from 'data/store';
import { login } from 'data/actions/auth';
import { resetLoading } from 'data/actions/root';
import { isLocaleChinese, t } from 'helpers/i18n';
import useToast from 'hooks/useToast';
import type {
  NoticeStackParams,
  AssignmentStackParams,
  FileStackParams,
  SettingsStackParams,
  MainTabParams,
  RootStackParams,
  CourseStackParams,
  LoginStackParams,
  CourseXStackParams,
  SearchStackParams,
  AssignmentSubmissionStackParams,
} from 'screens/types';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';

dayjs.extend(relativeTime);
dayjs.locale(isLocaleChinese() ? 'zh-cn' : 'en');

const RootStack = createNativeStackNavigator<RootStackParams>();
const LoginStack = createNativeStackNavigator<LoginStackParams>();
const CourseXStack = createNativeStackNavigator<CourseXStackParams>();
const SearchStack = createNativeStackNavigator<SearchStackParams>();
const AssignmentSubmissionStack = createNativeStackNavigator<AssignmentSubmissionStackParams>();
const CourseStack = createNativeStackNavigator<CourseStackParams>();
const NoticeStack = createNativeStackNavigator<NoticeStackParams>();
const AssignmentStack = createNativeStackNavigator<AssignmentStackParams>();
const FileStack = createNativeStackNavigator<FileStackParams>();
const SettingsStack = createNativeStackNavigator<SettingsStackParams>();
const MainNavigator = createBottomTabNavigator<MainTabParams>();

/**
 * Login 子栈：登录与 SSO 导航容器。
 */
const LoginStackScreens = () => {
  return (
    <LoginStack.Navigator>
      <LoginStack.Screen
        name="Login"
        component={Login}
        options={{ headerShown: false }}
      />
      <LoginStack.Screen
        name="SSO"
        component={SSO}
        options={{ title: t('sso') }}
      />
    </LoginStack.Navigator>
  );
};

const CourseXStackScreens = () => (
  <CourseXStack.Navigator>
    <CourseXStack.Screen
      name="CourseX"
      component={Empty}
      options={{ title: t('courseX') }}
    />
  </CourseXStack.Navigator>
);

const SearchStackScreens = () => (
  <SearchStack.Navigator>
    <SearchStack.Screen
      name="Search"
      component={Empty}
      options={{ title: t('search') }}
    />
  </SearchStack.Navigator>
);

const AssignmentSubmissionStackScreens = () => (
  <AssignmentSubmissionStack.Navigator>
    <AssignmentSubmissionStack.Screen
      name="AssignmentSubmission"
      component={Empty}
      options={{ title: t('assignmentSubmission') }}
    />
  </AssignmentSubmissionStack.Navigator>
);

/**
 * Course 子栈：课程列表与课程详情导航容器。
 */
const CourseStackScreens = () => {
  return (
    <CourseStack.Navigator>
      <CourseStack.Screen
        name="Courses"
        component={Courses}
        options={{ title: t('courses') }}
      />
      <CourseStack.Screen
        name="CourseDetail"
        component={CourseDetail as any}
        options={{ title: '' }}
      />
      <CourseStack.Screen
        name="NoticeDetail"
        component={NoticeDetail as any}
        options={{ title: '' }}
      />
      <CourseStack.Screen
        name="AssignmentDetail"
        component={AssignmentDetail as any}
        options={{ title: '' }}
      />
      <CourseStack.Screen
        name="FileDetail"
        component={FileDetail as any}
        options={{ title: '' }}
      />
    </CourseStack.Navigator>
  );
};

/**
 * Notice 子栈：公告列表与公告详情导航容器。
 */
const NoticeStackScreens = () => {
  return (
    <NoticeStack.Navigator>
      <NoticeStack.Screen
        name="Notices"
        component={Notices}
        options={{ title: t('notices') }}
      />
      <NoticeStack.Screen
        name="NoticeDetail"
        component={NoticeDetail as any}
        options={{ title: '' }}
      />
    </NoticeStack.Navigator>
  );
};

/**
 * Assignment 子栈：作业列表与作业详情导航容器。
 */
const AssignmentStackScreens = () => {
  return (
    <AssignmentStack.Navigator>
      <AssignmentStack.Screen
        name="Assignments"
        component={Assignments}
        options={{ title: t('assignments') }}
      />
      <AssignmentStack.Screen
        name="AssignmentDetail"
        component={AssignmentDetail as any}
        options={{ title: '' }}
      />
    </AssignmentStack.Navigator>
  );
};

/**
 * File 子栈：文件列表与文件详情导航容器。
 */
const FileStackScreens = () => {
  return (
    <FileStack.Navigator>
      <FileStack.Screen
        name="Files"
        component={Files}
        options={{ title: t('files') }}
      />
      <FileStack.Screen
        name="FileDetail"
        component={FileDetail as any}
        options={{ title: '' }}
      />
    </FileStack.Navigator>
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
        options={{ title: t('settings') }}
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
            CourseStack: 'book-open-variant',
            NoticeStack: 'bell',
            AssignmentStack: 'clipboard-text',
            FileStack: 'file-document',
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
          route.name === 'CourseStack'
            ? t('courses')
            : route.name === 'NoticeStack'
              ? t('notices')
              : route.name === 'AssignmentStack'
                ? t('assignments')
                : route.name === 'FileStack'
                  ? t('files')
                  : route.name === 'SettingsStack'
                    ? t('settings')
                    : '',
      })}
    >
      <MainNavigator.Screen
        name="NoticeStack"
        component={NoticeStackScreens}
      />
      <MainNavigator.Screen
        name="AssignmentStack"
        component={AssignmentStackScreens}
      />
      <MainNavigator.Screen
        name="FileStack"
        component={FileStackScreens}
      />
      <MainNavigator.Screen
        name="CourseStack"
        component={CourseStackScreens}
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
  const dispatch = useAppDispatch();
  const toast = useToast();
  const lastActiveTimeRef = React.useRef<number>(Date.now());
  const hasTriedAutoLoginRef = React.useRef<boolean>(false);

  const showMain =
    !auth.error && !!auth.username && !!auth.password && !!auth.fingerPrint;

  console.log('[RootStackScreens] render', {
    showMain,
    error: auth.error,
  });

  React.useEffect(() => {
    if (auth.error && auth.username && auth.password && auth.fingerPrint) {
      toast(t('loginFailed'), 'error', 8000);
    }
  }, [auth.error, auth.username, auth.password, auth.fingerPrint, toast]);

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
      return;
    }

    // SSO 或登录正在进行，避免冲突
    if (ssoInProgress || loggingIn) {
      return;
    }

    // 初次登录或超过 10 分钟未活跃
    const shouldReLogin = idleTime > 10 * 60 * 1000 || !loggedIn;
    if (shouldReLogin) {
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
          dispatch(resetLoading());
          handleReLogin();
        } else if (
          nextAppState === 'inactive' ||
          nextAppState === 'background'
        ) {
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
    <RootStack.Navigator
      screenOptions={{
        headerShown: false,
      }}
    >
      {showMain ? (
        <>
          <RootStack.Screen name="MainTab" component={MainTabScreens} />
          <RootStack.Screen
            name="CourseXStack"
            component={CourseXStackScreens}
            options={{ gestureEnabled: false }}
          />
          <RootStack.Screen
            name="SearchStack"
            component={SearchStackScreens}
            options={{ gestureEnabled: false }}
          />
          <RootStack.Screen
            name="AssignmentSubmissionStack"
            component={AssignmentSubmissionStackScreens}
            options={{ gestureEnabled: false }}
          />
        </>
      ) : (
        <RootStack.Screen name="LoginStack" component={LoginStackScreens} />
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
