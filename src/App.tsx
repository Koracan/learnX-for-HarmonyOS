import React from 'react';
import {
  useColorScheme,
  AppState,
  type AppStateStatus,
  StatusBar,
  BackHandler,
} from 'react-native';
import { Immersive } from 'react-native-immersive';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import {
  NavigationContainer,
  useNavigation,
  type NavigationContainerRef,
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
import {
  useSafeAreaFrame,
  SafeAreaProvider,
} from 'react-native-safe-area-context';
import {
  Provider as PaperProvider,
  MD3DarkTheme,
  MD3LightTheme,
  useTheme,
  adaptNavigationTheme,
} from 'react-native-paper';
import { Provider as StoreProvider } from 'react-redux';
import { PersistGate } from 'redux-persist/integration/react';
import MaterialIcons from 'react-native-vector-icons/MaterialIcons';
import { LearnOHDataProcessor } from 'react-native-learn-oh-data-processor';
import Login from 'screens/Login';
import SSO from 'screens/SSO';
import Notices from 'screens/Notices';
import Search from 'screens/Search';
import NoticeDetail from 'screens/NoticeDetail';
import Assignments from 'screens/Assignments';
import AssignmentDetail from 'screens/AssignmentDetail';
import AssignmentSubmission from 'screens/AssignmentSubmission';
import Files from 'screens/Files';
import FileDetail from 'screens/FileDetail';
import Courses from 'screens/Courses';
import CourseDetail from 'screens/CourseDetail';
import Settings from 'screens/Settings';
import SemesterSelection from 'screens/SemesterSelection';
import FileSettings from 'screens/FileSettings';
import About from 'screens/About';
import Help from 'screens/Help';
import Splash from 'components/Splash';
import Empty from 'components/Empty';
import HeaderTitle from 'components/HeaderTitle';
import IconButton from 'components/IconButton';
import { SplitViewProvider } from 'components/SplitView';
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
  DetailStackParams,
} from 'screens/types';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
import 'dayjs/locale/en';
import 'dayjs/locale/zh-cn';

dayjs.extend(relativeTime);
dayjs.locale(isLocaleChinese() ? 'zh-cn' : 'en');

const BackButton = () => {
  const navigation = useNavigation();

  return (
    <IconButton
      onPress={() => navigation.goBack()}
      icon={props => <MaterialIcons {...props} name="close" />}
    />
  );
};

const getTitleOptions = (title: string, subtitle?: string) => {
  return {
    title,
    headerTitle: () => <HeaderTitle title={title} subtitle={subtitle} />,
  };
};

const getScreenOptions = <P extends ParamListBase, N extends keyof P>(
  title: string,
) =>
  function ({
    navigation,
  }: NativeStackScreenProps<P, N>): NativeStackNavigationOptions {
    return {
      ...getTitleOptions(title),
      headerTitleAlign: 'center',
      headerShadowVisible: false,
      headerRight: () => (
        <IconButton
          onPress={() => navigation.navigate('SearchStack' as any)}
          icon={props => <MaterialIcons {...props} name="search" />}
        />
      ),
    };
  };

const getDetailScreenOptions = <P extends ParamListBase, N extends keyof P>() =>
  function ({
    route,
  }: NativeStackScreenProps<P, N>): NativeStackNavigationOptions {
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
      ...getTitleOptions(title, subtitle),
      headerTitleAlign: 'center',
      headerShadowVisible: false,
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
const DetailNavigator = createNativeStackNavigator<DetailStackParams>();

const { LightTheme, DarkTheme } = adaptNavigationTheme({
  reactNavigationLight: NavigationDefaultTheme,
  reactNavigationDark: NavigationDarkTheme,
});

const lightThemeColors = {
  ...LightTheme.colors,
  primary: 'rgb(154, 37, 174)',
  onPrimary: 'rgb(255, 255, 255)',
  primaryContainer: 'rgb(255, 214, 254)',
  onPrimaryContainer: 'rgb(53, 0, 63)',
  secondary: 'rgb(107, 88, 107)',
  onSecondary: 'rgb(255, 255, 255)',
  secondaryContainer: 'rgb(244, 219, 241)',
  onSecondaryContainer: 'rgb(37, 22, 38)',
  tertiary: 'rgb(130, 82, 74)',
  onTertiary: 'rgb(255, 255, 255)',
  tertiaryContainer: 'rgb(255, 218, 212)',
  onTertiaryContainer: 'rgb(51, 17, 12)',
  error: 'rgb(186, 26, 26)',
  onError: 'rgb(255, 255, 255)',
  errorContainer: 'rgb(255, 218, 214)',
  onErrorContainer: 'rgb(65, 0, 2)',
  background: 'rgb(255, 251, 255)',
  onBackground: 'rgb(30, 26, 29)',
  surface: 'rgb(255, 251, 255)',
  onSurface: 'rgb(30, 26, 29)',
  surfaceVariant: 'rgb(236, 223, 232)',
  onSurfaceVariant: 'rgb(77, 68, 76)',
  outline: 'rgb(127, 116, 125)',
  outlineVariant: 'rgb(208, 195, 204)',
  shadow: 'rgb(0, 0, 0)',
  scrim: 'rgb(0, 0, 0)',
  inverseSurface: 'rgb(51, 47, 50)',
  inverseOnSurface: 'rgb(247, 238, 243)',
  inversePrimary: 'rgb(249, 171, 255)',
  elevation: {
    level0: 'transparent',
    level1: 'rgb(250, 240, 251)',
    level2: 'rgb(247, 234, 249)',
    level3: 'rgb(244, 228, 246)',
    level4: 'rgb(243, 225, 245)',
    level5: 'rgb(241, 221, 244)',
  },
  surfaceDisabled: 'rgba(30, 26, 29, 0.12)',
  onSurfaceDisabled: 'rgba(30, 26, 29, 0.38)',
  backdrop: 'rgba(54, 46, 53, 0.4)',
  card: 'rgb(255, 251, 255)',
};
const darkThemeColors = {
  ...DarkTheme.colors,
  primary: 'rgb(249, 171, 255)',
  onPrimary: 'rgb(87, 0, 102)',
  primaryContainer: 'rgb(123, 0, 143)',
  onPrimaryContainer: 'rgb(255, 214, 254)',
  secondary: 'rgb(215, 191, 213)',
  onSecondary: 'rgb(59, 43, 60)',
  secondaryContainer: 'rgb(83, 65, 83)',
  onSecondaryContainer: 'rgb(244, 219, 241)',
  tertiary: 'rgb(246, 184, 173)',
  onTertiary: 'rgb(76, 37, 31)',
  tertiaryContainer: 'rgb(103, 59, 52)',
  onTertiaryContainer: 'rgb(255, 218, 212)',
  error: 'rgb(255, 180, 171)',
  onError: 'rgb(105, 0, 5)',
  errorContainer: 'rgb(147, 0, 10)',
  onErrorContainer: 'rgb(255, 180, 171)',
  background: 'rgb(30, 26, 29)',
  onBackground: 'rgb(233, 224, 228)',
  surface: 'rgb(30, 26, 29)',
  onSurface: 'rgb(233, 224, 228)',
  surfaceVariant: 'rgb(77, 68, 76)',
  onSurfaceVariant: 'rgb(208, 195, 204)',
  outline: 'rgb(153, 141, 150)',
  outlineVariant: 'rgb(77, 68, 76)',
  shadow: 'rgb(0, 0, 0)',
  scrim: 'rgb(0, 0, 0)',
  inverseSurface: 'rgb(233, 224, 228)',
  inverseOnSurface: 'rgb(51, 47, 50)',
  inversePrimary: 'rgb(154, 37, 174)',
  elevation: {
    level0: 'transparent',
    level1: 'rgb(41, 33, 40)',
    level2: 'rgb(48, 38, 47)',
    level3: 'rgb(54, 42, 54)',
    level4: 'rgb(56, 43, 56)',
    level5: 'rgb(61, 46, 61)',
  },
  surfaceDisabled: 'rgba(233, 224, 228, 0.12)',
  onSurfaceDisabled: 'rgba(233, 224, 228, 0.38)',
  backdrop: 'rgba(54, 46, 53, 0.4)',
  card: 'rgb(30, 26, 29)',
};

const BrandLightPaperTheme = {
  ...MD3LightTheme,
  dark: false,
  colors: lightThemeColors,
  fonts: MD3LightTheme.fonts,
};
const BrandLightNavigationTheme = {
  ...NavigationDefaultTheme,
  colors: lightThemeColors,
};
const BrandDarkPaperTheme = {
  ...MD3DarkTheme,
  dark: true,
  colors: darkThemeColors,
  fonts: MD3DarkTheme.fonts,
};
const BrandDarkNavigationTheme = {
  ...NavigationDarkTheme,
  colors: darkThemeColors,
};

/**
 * Login 子栈：登录与 SSO 导航容器。
 */
const LoginStack = () => {
  return (
    <LoginNavigator.Navigator screenOptions={getScreenOptions(t('login'))}>
      <LoginNavigator.Screen
        name="Login"
        component={Login}
        options={{ headerShown: false }}
      />
      <LoginNavigator.Screen
        name="SSO"
        component={SSO}
        options={{
          headerLeft: () => <BackButton />,
          ...getTitleOptions(t('sso')),
        }}
      />
    </LoginNavigator.Navigator>
  );
};

const CourseXStack = () => {
  return (
    <CourseXNavigator.Navigator screenOptions={getScreenOptions(t('courseX'))}>
      <CourseXNavigator.Screen
        name="CourseX"
        component={Empty}
        options={{
          headerLeft: () => <BackButton />,
          ...getTitleOptions(t('courseX')),
        }}
      />
    </CourseXNavigator.Navigator>
  );
};

const SearchStack = () => {
  return (
    <SearchNavigator.Navigator screenOptions={getScreenOptions(t('search'))}>
      <SearchNavigator.Screen
        name="Search"
        component={Search}
        options={{
          headerLeft: () => <BackButton />,
          headerRight: () => null,
          ...getTitleOptions(t('search')),
        }}
      />
      <SearchNavigator.Screen
        name="NoticeDetail"
        component={NoticeDetail as any}
        options={getDetailScreenOptions()}
      />
      <SearchNavigator.Screen
        name="AssignmentDetail"
        component={AssignmentDetail as any}
        options={getDetailScreenOptions()}
      />
      <SearchNavigator.Screen
        name="FileDetail"
        component={FileDetail as any}
        options={getDetailScreenOptions()}
      />
    </SearchNavigator.Navigator>
  );
};

const AssignmentSubmissionStack = () => {
  return (
    <AssignmentSubmissionNavigator.Navigator
      screenOptions={getScreenOptions(t('assignmentSubmission'))}
    >
      <AssignmentSubmissionNavigator.Screen
        name="AssignmentSubmission"
        component={AssignmentSubmission}
        options={{
          headerLeft: () => <BackButton />,
          ...getTitleOptions(t('assignmentSubmission')),
        }}
      />
    </AssignmentSubmissionNavigator.Navigator>
  );
};

/**
 * Course 子栈：课程列表与课程详情导航容器。
 */
const CourseStack = () => {
  return (
    <CourseStackNavigator.Navigator
      screenOptions={getScreenOptions(t('courses'))}
    >
      <CourseStackNavigator.Screen
        name="Courses"
        component={Courses}
        options={getScreenOptions(t('courses'))}
      />
      <CourseStackNavigator.Screen
        name="CourseDetail"
        component={CourseDetail as any}
        options={getDetailScreenOptions()}
      />
      <CourseStackNavigator.Screen
        name="NoticeDetail"
        component={NoticeDetail as any}
        options={getDetailScreenOptions()}
      />
      <CourseStackNavigator.Screen
        name="AssignmentDetail"
        component={AssignmentDetail as any}
        options={getDetailScreenOptions()}
      />
      <CourseStackNavigator.Screen
        name="FileDetail"
        component={FileDetail as any}
        options={getDetailScreenOptions()}
      />
      <CourseStackNavigator.Screen
        name="AssignmentSubmission"
        component={AssignmentSubmission as any}
        options={getDetailScreenOptions()}
      />
    </CourseStackNavigator.Navigator>
  );
};

/**
 * Notice 子栈：公告列表与公告详情导航容器。
 */
const NoticeStack = () => {
  return (
    <NoticeStackNavigator.Navigator
      screenOptions={getScreenOptions(t('notices'))}
    >
      <NoticeStackNavigator.Screen
        name="Notices"
        component={Notices}
        options={getScreenOptions(t('notices'))}
      />
      <NoticeStackNavigator.Screen
        name="NoticeDetail"
        component={NoticeDetail as any}
        options={getDetailScreenOptions()}
      />
      <NoticeStackNavigator.Screen
        name="FileDetail"
        component={FileDetail as any}
        options={getDetailScreenOptions()}
      />
    </NoticeStackNavigator.Navigator>
  );
};

/**
 * Assignment 子栈：作业列表与作业详情导航容器。
 */
const AssignmentStack = () => {
  return (
    <AssignmentStackNavigator.Navigator
      screenOptions={getScreenOptions(t('assignments'))}
    >
      <AssignmentStackNavigator.Screen
        name="Assignments"
        component={Assignments}
        options={getScreenOptions(t('assignments'))}
      />
      <AssignmentStackNavigator.Screen
        name="AssignmentDetail"
        component={AssignmentDetail as any}
        options={getDetailScreenOptions()}
      />
      <AssignmentStackNavigator.Screen
        name="FileDetail"
        component={FileDetail as any}
        options={getDetailScreenOptions()}
      />
      <AssignmentStackNavigator.Screen
        name="AssignmentSubmission"
        component={AssignmentSubmission as any}
        options={getDetailScreenOptions()}
      />
    </AssignmentStackNavigator.Navigator>
  );
};

/**
 * File 子栈：文件列表与文件详情导航容器。
 */
const FileStack = () => {
  return (
    <FileStackNavigator.Navigator screenOptions={getScreenOptions(t('files'))}>
      <FileStackNavigator.Screen
        name="Files"
        component={Files}
        options={getScreenOptions(t('files'))}
      />
      <FileStackNavigator.Screen
        name="FileDetail"
        component={FileDetail as any}
        options={getDetailScreenOptions()}
      />
    </FileStackNavigator.Navigator>
  );
};

const SettingDetails = (
  <>
    <SettingsStackNavigator.Screen
      name="SemesterSelection"
      component={SemesterSelection}
      options={getTitleOptions(t('semesterSelection'))}
    />
    <SettingsStackNavigator.Screen
      name="FileSettings"
      component={FileSettings}
      options={getTitleOptions(t('fileSettings'))}
    />
    <SettingsStackNavigator.Screen
      name="About"
      component={About}
      options={getTitleOptions(t('about'))}
    />
    <SettingsStackNavigator.Screen
      name="Help"
      component={Help}
      options={getTitleOptions(t('helpAndFeedback'))}
    />
    <SettingsStackNavigator.Screen
      name="CalendarEvent"
      component={Empty}
      options={getTitleOptions(t('calendarsAndReminders'))}
    />
    <SettingsStackNavigator.Screen
      name="CourseInformationSharing"
      component={Empty}
      options={getTitleOptions(t('courseInformationSharing'))}
    />
  </>
);

/**
 * 设置子栈：设置页面导航容器。
 */
const SettingsStack = () => {
  return (
    <SettingsStackNavigator.Navigator
      screenOptions={getScreenOptions(t('settings'))}
    >
      <SettingsStackNavigator.Screen
        name="Settings"
        component={Settings}
        options={getTitleOptions(t('settings'))}
      />
      {SettingDetails}
    </SettingsStackNavigator.Navigator>
  );
};

const DetailStack = () => {
  return (
    <DetailNavigator.Navigator>
      <DetailNavigator.Screen
        name="EmptyDetail"
        component={Empty}
        options={{ headerShadowVisible: false, ...getTitleOptions('') }}
      />
      <DetailNavigator.Screen
        name="NoticeDetail"
        component={NoticeDetail as any}
        options={getDetailScreenOptions()}
      />
      <DetailNavigator.Screen
        name="AssignmentDetail"
        component={AssignmentDetail as any}
        options={getDetailScreenOptions()}
      />
      <DetailNavigator.Screen
        name="AssignmentSubmission"
        component={AssignmentSubmission as any}
        options={getDetailScreenOptions()}
      />
      <DetailNavigator.Screen
        name="FileDetail"
        component={FileDetail as any}
        options={getDetailScreenOptions()}
      />
      <DetailNavigator.Screen
        name="CourseDetail"
        component={CourseDetail as any}
        options={getDetailScreenOptions()}
      />
      {SettingDetails}
    </DetailNavigator.Navigator>
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
        tabBarActiveTintColor: theme.colors.primary,
        tabBarInactiveTintColor: 'gray',
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

const ImmersiveModeController = () => {
  const immersiveMode = useAppSelector(state => state.settings.immersiveMode);

  React.useEffect(() => {
    Immersive.setImmersive(immersiveMode);
  }, [immersiveMode]);

  return null;
};

/**
 * Container：应用主容器，负责导航、状态初始化、自动登录与生命周期管理。
 */
const Container = () => {
  const colorScheme = useColorScheme();
  const auth = useAppSelector(state => state.auth);
  const semesters = useAppSelector(state => state.semesters.items);
  const currentSemesterId = useAppSelector(state => state.semesters.current);
  const courses = useAppSelector(state => state.courses.items);
  const dispatch = useAppDispatch();
  const toast = useToast();
  const frame = useSafeAreaFrame();

  const mainNavigationContainerRef =
    React.useRef<NavigationContainerRef<{}>>(null);
  const detailNavigationContainerRef =
    React.useRef<NavigationContainerRef<{}>>(null);

  const lastActiveTimeRef = React.useRef<number>(Date.now());
  const hasTriedAutoLoginRef = React.useRef<boolean>(false);

  const showMain =
    !auth.error &&
    !!auth.username &&
    !!auth.password &&
    !!auth.fingerPrint &&
    auth.loggedIn;

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

  // 拦截根部侧滑返回，使其进入后台运行
  React.useEffect(() => {
    const onBackPress = () => {
      if (
        mainNavigationContainerRef.current &&
        !mainNavigationContainerRef.current.canGoBack()
      ) {
        LearnOHDataProcessor.moveToBackground();
        return true;
      }
      return false;
    };

    BackHandler.addEventListener('hardwareBackPress', onBackPress);
    return () =>
      BackHandler.removeEventListener('hardwareBackPress', onBackPress);
  }, []);

  const navigationContainerProps = {
    theme:
      colorScheme === 'dark'
        ? BrandDarkNavigationTheme
        : BrandLightNavigationTheme,
    fallback: <Splash />,
  };

  const showDetail = showMain && frame.width >= 750 && frame.width > frame.height;

  return (
    <NavigationContainer
      ref={mainNavigationContainerRef}
      {...navigationContainerProps}
    >
      <SplitViewProvider
        splitEnabled={showDetail}
        detailNavigationContainerRef={
          showDetail ? detailNavigationContainerRef : null
        }
        masterNavigationContainerRef={mainNavigationContainerRef}
        showDetail={showDetail}
      >
        <RootNavigator.Navigator
          screenOptions={{
            headerShown: false,
            presentation: 'fullScreenModal',
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
        <NavigationContainer
          independent={true}
          ref={detailNavigationContainerRef}
          {...navigationContainerProps}
        >
          <DetailStack />
        </NavigationContainer>
      </SplitViewProvider>
    </NavigationContainer>
  );
};

/**
 * 应用入口：主题、状态管理、导航与 Toast 提供者。
 */
const App = () => {
  const colorScheme = useColorScheme();

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <PaperProvider
        theme={
          colorScheme === 'dark' ? BrandDarkPaperTheme : BrandLightPaperTheme
        }
      >
        <ToastProvider>
          <StoreProvider store={store}>
            <PersistGate loading={<Splash />} persistor={persistor}>
              <SafeAreaProvider>
                <ImmersiveModeController />
                <Container />
              </SafeAreaProvider>
            </PersistGate>
          </StoreProvider>
        </ToastProvider>
        <StatusBar
          barStyle={colorScheme === 'dark' ? 'light-content' : 'dark-content'}
          backgroundColor={
            colorScheme === 'dark'
              ? BrandDarkPaperTheme.colors.surface
              : BrandLightPaperTheme.colors.surface
          }
          animated
        />
      </PaperProvider>
    </GestureHandlerRootView>
  );
};

export default App;
