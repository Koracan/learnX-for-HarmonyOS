import React from 'react';
import {
  useColorScheme,
  AppState,
  type AppStateStatus,
  StatusBar,
  Platform,
} from 'react-native';
import { Immersive } from 'react-native-immersive';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import {
  NavigationContainer,
  DefaultTheme as NavigationDefaultTheme,
  DarkTheme as NavigationDarkTheme,
  type ParamListBase,
} from '@react-navigation/native';
import {
  createNativeStackNavigator,
  type NativeStackNavigationOptions,
  type NativeStackScreenProps,
} from '@react-navigation/native-stack';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import {
  Provider as PaperProvider,
  MD3DarkTheme,
  MD3LightTheme,
  useTheme,
  type MD3Theme,
} from 'react-native-paper';
import { Provider as StoreProvider } from 'react-redux';
import { PersistGate } from 'redux-persist/integration/react';
import MaterialIcons from 'react-native-vector-icons/MaterialIcons';
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
import HeaderTitle from 'components/HeaderTitle';
import { ToastProvider } from 'components/Toast';
import { persistor, store, useAppSelector, useAppDispatch } from 'data/store';
import { login } from 'data/actions/auth';
import { resetLoading } from 'data/actions/root';
import { getAllSemesters, getCurrentSemester } from 'data/actions/semesters';
import { getCoursesForSemester } from 'data/actions/courses';
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
import 'dayjs/locale/en';
import 'dayjs/locale/zh-cn';

dayjs.extend(relativeTime);
dayjs.locale(isLocaleChinese() ? 'zh-cn' : 'en');

const getScreenOptions = (theme: MD3Theme): NativeStackNavigationOptions => ({
  headerTitle: props => <HeaderTitle title={props.children} />,
  headerTitleAlign: 'center',
  headerShadowVisible: false,
  headerStyle: {
    backgroundColor: theme.colors.surface,
  },
});

const getDetailScreenOptions = (theme: MD3Theme) =>
  function ({
    route,
  }: NativeStackScreenProps<
    ParamListBase,
    string
  >): NativeStackNavigationOptions {
    const params = route.params as any;
    let title = '';
    let subtitle = '';

    if (route.name === 'CourseDetail') {
      title = params?.name || '';
      subtitle = params?.teacherName || '';
    } else if (route.name === 'FileDetail') {
      title = params?.title || '';
      subtitle = params?.courseName || '';
    } else {
      // NoticeDetail, AssignmentDetail
      title = params?.courseName || '';
      subtitle = params?.courseTeacherName || params?.publisher || '';
    }

    return {
      ...getScreenOptions(theme),
      headerTitle: () => <HeaderTitle title={title} subtitle={subtitle} />,
      headerTitleAlign: Platform.OS === 'android' ? 'left' : 'center',
    };
  };

const RootNavigator = createNativeStackNavigator<RootStackParams>();
const CourseStackNavigator = createNativeStackNavigator<CourseStackParams>();
const NoticeStackNavigator = createNativeStackNavigator<NoticeStackParams>();
const AssignmentStackNavigator =
  createNativeStackNavigator<AssignmentStackParams>();
const FileStackNavigator = createNativeStackNavigator<FileStackParams>();
const SettingsStackNavigator =
  createNativeStackNavigator<SettingsStackParams>();
const LoginNavigator = createNativeStackNavigator<LoginStackParams>();
const SearchNavigator = createNativeStackNavigator<SearchStackParams>();
const CourseXNavigator = createNativeStackNavigator<CourseXStackParams>();
const AssignmentSubmissionNavigator =
  createNativeStackNavigator<AssignmentSubmissionStackParams>();
const MainNavigator = createBottomTabNavigator<MainTabParams>();

/**
 * Login 子栈：登录与 SSO 导航容器。
 */
const LoginStack = () => {
  const theme = useTheme();
  return (
    <LoginNavigator.Navigator screenOptions={getScreenOptions(theme)}>
      <LoginNavigator.Screen
        name="Login"
        component={Login}
        options={{ headerShown: false }}
      />
      <LoginNavigator.Screen
        name="SSO"
        component={SSO}
        options={{ title: t('sso') }}
      />
    </LoginNavigator.Navigator>
  );
};

const CourseXStack = () => {
  const theme = useTheme();
  return (
    <CourseXNavigator.Navigator screenOptions={getScreenOptions(theme)}>
      <CourseXNavigator.Screen
        name="CourseX"
        component={Empty}
        options={{ title: t('courseX') }}
      />
    </CourseXNavigator.Navigator>
  );
};

const SearchStack = () => {
  const theme = useTheme();
  return (
    <SearchNavigator.Navigator screenOptions={getScreenOptions(theme)}>
      <SearchNavigator.Screen
        name="Search"
        component={Empty}
        options={{ title: t('search') }}
      />
    </SearchNavigator.Navigator>
  );
};

const AssignmentSubmissionStack = () => {
  const theme = useTheme();
  return (
    <AssignmentSubmissionNavigator.Navigator
      screenOptions={getScreenOptions(theme)}
    >
      <AssignmentSubmissionNavigator.Screen
        name="AssignmentSubmission"
        component={Empty}
        options={{ title: t('assignmentSubmission') }}
      />
    </AssignmentSubmissionNavigator.Navigator>
  );
};

/**
 * Course 子栈：课程列表与课程详情导航容器。
 */
const CourseStack = () => {
  const theme = useTheme();
  return (
    <CourseStackNavigator.Navigator screenOptions={getScreenOptions(theme)}>
      <CourseStackNavigator.Screen
        name="Courses"
        component={Courses}
        options={{ title: t('courses') }}
      />
      <CourseStackNavigator.Screen
        name="CourseDetail"
        component={CourseDetail as any}
        options={getDetailScreenOptions(theme)}
      />
      <CourseStackNavigator.Screen
        name="NoticeDetail"
        component={NoticeDetail as any}
        options={getDetailScreenOptions(theme)}
      />
      <CourseStackNavigator.Screen
        name="AssignmentDetail"
        component={AssignmentDetail as any}
        options={getDetailScreenOptions(theme)}
      />
      <CourseStackNavigator.Screen
        name="FileDetail"
        component={FileDetail as any}
        options={getDetailScreenOptions(theme)}
      />
    </CourseStackNavigator.Navigator>
  );
};

/**
 * Notice 子栈：公告列表与公告详情导航容器。
 */
const NoticeStack = () => {
  const theme = useTheme();
  return (
    <NoticeStackNavigator.Navigator screenOptions={getScreenOptions(theme)}>
      <NoticeStackNavigator.Screen
        name="Notices"
        component={Notices}
        options={{ title: t('notices') }}
      />
      <NoticeStackNavigator.Screen
        name="NoticeDetail"
        component={NoticeDetail as any}
        options={getDetailScreenOptions(theme)}
      />
      <NoticeStackNavigator.Screen
        name="FileDetail"
        component={FileDetail as any}
        options={getDetailScreenOptions(theme)}
      />
    </NoticeStackNavigator.Navigator>
  );
};

/**
 * Assignment 子栈：作业列表与作业详情导航容器。
 */
const AssignmentStack = () => {
  const theme = useTheme();
  return (
    <AssignmentStackNavigator.Navigator screenOptions={getScreenOptions(theme)}>
      <AssignmentStackNavigator.Screen
        name="Assignments"
        component={Assignments}
        options={{ title: t('assignments') }}
      />
      <AssignmentStackNavigator.Screen
        name="AssignmentDetail"
        component={AssignmentDetail as any}
        options={getDetailScreenOptions(theme)}
      />
      <AssignmentStackNavigator.Screen
        name="FileDetail"
        component={FileDetail as any}
        options={getDetailScreenOptions(theme)}
      />
    </AssignmentStackNavigator.Navigator>
  );
};

/**
 * File 子栈：文件列表与文件详情导航容器。
 */
const FileStack = () => {
  const theme = useTheme();
  return (
    <FileStackNavigator.Navigator screenOptions={getScreenOptions(theme)}>
      <FileStackNavigator.Screen
        name="Files"
        component={Files}
        options={{ title: t('files') }}
      />
      <FileStackNavigator.Screen
        name="FileDetail"
        component={FileDetail as any}
        options={getDetailScreenOptions(theme)}
      />
    </FileStackNavigator.Navigator>
  );
};

/**
 * 沉浸式模式控制器：调用 react-native-immersive 统一控制系统栏。
 */
const ImmersiveModeController = () => {
  const immersiveMode = useAppSelector(state => state.settings.immersiveMode);

  React.useEffect(() => {
    Immersive.setImmersive(immersiveMode);
  }, [immersiveMode]);

  return null;
};

/**
 * 设置子栈：设置页面导航容器。
 */
const SettingsStack = () => {
  const theme = useTheme();
  return (
    <SettingsStackNavigator.Navigator screenOptions={getScreenOptions(theme)}>
      <SettingsStackNavigator.Screen
        name="Settings"
        component={Settings}
        options={{ title: t('settings') }}
      />
    </SettingsStackNavigator.Navigator>
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
            NoticeStack: 'notifications',
            AssignmentStack: 'event',
            FileStack: 'folder',
            CourseStack: 'apps',
            SettingsStack: 'settings',
          };
          return (
            <MaterialIcons
              name={iconMap[route.name as keyof typeof iconMap]}
              size={size}
              color={color}
            />
          );
        },
        activeTintColor: theme.colors.primary,
        inactiveTintColor: 'gray',
        tabBarStyle: {
          borderTopColor: theme.colors.outlineVariant,
        },
        tabBarLabelPosition: 'below-icon',
        tabBarLabelStyle: {
          marginBottom: 2,
        },
        headerShown: false,
      })}
    >
      <MainNavigator.Screen
        name="NoticeStack"
        component={NoticeStack}
        options={{ title: t('notices') }}
      />
      <MainNavigator.Screen
        name="AssignmentStack"
        component={AssignmentStack}
        options={{ title: t('assignments') }}
      />
      <MainNavigator.Screen
        name="FileStack"
        component={FileStack}
        options={{ title: t('files') }}
      />
      <MainNavigator.Screen
        name="CourseStack"
        component={CourseStack}
        options={{ title: t('courses') }}
      />
      <MainNavigator.Screen
        name="SettingsStack"
        component={SettingsStack}
        options={{
          title: t('settings'),

          tabBarBadgeStyle: {
            backgroundColor: 'red',
            maxWidth: 10,
            maxHeight: 10,
          },
        }}
      />
    </MainNavigator.Navigator>
  );
};

/**
 * Container：应用主容器，负责导航、状态初始化、自动登录与生命周期管理。
 */
const Container = () => {
  const colorScheme = useColorScheme();
  const navigationTheme =
    colorScheme === 'dark' ? NavigationDarkTheme : NavigationDefaultTheme;

  const auth = useAppSelector(state => state.auth);
  const semesters = useAppSelector(state => state.semesters.items);
  const currentSemesterId = useAppSelector(state => state.semesters.current);
  const courses = useAppSelector(state => state.courses.items);
  const dispatch = useAppDispatch();
  const toast = useToast();
  const lastActiveTimeRef = React.useRef<number>(Date.now());
  const hasTriedAutoLoginRef = React.useRef<boolean>(false);

  const showMain =
    !auth.error &&
    !!auth.username &&
    !!auth.password &&
    !!auth.fingerPrint &&
    auth.loggedIn;

  console.log('[Container] render', {
    showMain,
    error: auth.error,
  });

  // 全局数据初始化逻辑
  React.useEffect(() => {
    if (!auth.loggedIn) {
      return;
    }

    if (semesters.length === 0) {
      dispatch(getAllSemesters());
    }
    if (!currentSemesterId) {
      dispatch(getCurrentSemester());
    }
  }, [dispatch, currentSemesterId, auth.loggedIn, semesters.length]);

  React.useEffect(() => {
    if (auth.loggedIn && currentSemesterId && courses.length === 0) {
      dispatch(getCoursesForSemester(currentSemesterId));
    }
  }, [dispatch, currentSemesterId, auth.loggedIn, courses.length]);

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
    <SafeAreaProvider>
      <NavigationContainer theme={navigationTheme}>
        <ImmersiveModeController />
        <RootNavigator.Navigator
          screenOptions={{
            headerShown: false,
          }}
        >
          {showMain ? (
            <>
              <RootNavigator.Screen name="MainTab" component={MainTabScreens} />
              <RootNavigator.Screen
                name="CourseXStack"
                component={CourseXStack}
                options={{ gestureEnabled: false }}
              />
              <RootNavigator.Screen
                name="SearchStack"
                component={SearchStack}
                options={{ gestureEnabled: false }}
              />
              <RootNavigator.Screen
                name="AssignmentSubmissionStack"
                component={AssignmentSubmissionStack}
                options={{ gestureEnabled: false }}
              />
            </>
          ) : (
            <RootNavigator.Screen name="LoginStack" component={LoginStack} />
          )}
        </RootNavigator.Navigator>
      </NavigationContainer>
    </SafeAreaProvider>
  );
};

/**
 * 应用入口：主题、状态管理、导航与 Toast 提供者。
 */
const App = () => {
  const colorScheme = useColorScheme();
  const paperTheme = colorScheme === 'dark' ? MD3DarkTheme : MD3LightTheme;

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <PaperProvider theme={paperTheme}>
        <ToastProvider>
          <StoreProvider store={store}>
            <PersistGate loading={<Splash />} persistor={persistor}>
              <Container />
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
