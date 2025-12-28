import React, { memo, useMemo, useState } from 'react';
import { Dimensions } from 'react-native';
import { useTheme } from 'react-native-paper';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { useNavigation } from '@react-navigation/native';
import {
  TabBar,
  TabView,
  type SceneRendererProps,
  type NavigationState,
} from 'react-native-tab-view';
import { useAppDispatch, useAppSelector } from 'data/store';
import { getNoticesForCourse } from 'data/actions/notices';
import { getAssignmentsForCourse } from 'data/actions/assignments';
import { getFilesForCourse } from 'data/actions/files';
import NoticeCard from 'components/NoticeCard';
import AssignmentCard from 'components/AssignmentCard';
import FileCard from 'components/FileCard';
import Empty from 'components/Empty';
import FlatList from 'components/FlatList';
import { t } from 'helpers/i18n';
import type { CourseStackParams } from './types';
import type { Notice, Assignment, File } from 'data/types/state';

type Props = NativeStackScreenProps<CourseStackParams, 'CourseDetail'>;

const NoticesTab = memo(
  ({ courseId, data }: { courseId: string; data: Notice[] }) => {
    const navigation = useNavigation<any>();
    const dispatch = useAppDispatch();
    const loggedIn = useAppSelector(state => state.auth.loggedIn);
    const fetching = useAppSelector(state => state.notices.fetching);

    const handleRefresh = () => {
      if (loggedIn) {
        dispatch(getNoticesForCourse(courseId));
      }
    };

    return (
      <FlatList
        data={data}
        renderItem={({ item }) => (
          <NoticeCard
            data={item}
            hideCourseName
            onPress={() => navigation.push('NoticeDetail', item)}
          />
        )}
        keyExtractor={item => item.id}
        refreshing={fetching}
        onRefresh={handleRefresh}
        contentContainerStyle={[
          { flexGrow: 1 },
          data.length ? null : { justifyContent: 'center' },
        ]}
        ListEmptyComponent={<Empty />}
      />
    );
  },
);

const AssignmentsTab = memo(
  ({ courseId, data }: { courseId: string; data: Assignment[] }) => {
    const navigation = useNavigation<any>();
    const dispatch = useAppDispatch();
    const loggedIn = useAppSelector(state => state.auth.loggedIn);
    const fetching = useAppSelector(state => state.assignments.fetching);

    const handleRefresh = () => {
      if (loggedIn) {
        dispatch(getAssignmentsForCourse(courseId));
      }
    };

    return (
      <FlatList
        data={data}
        renderItem={({ item }) => (
          <AssignmentCard
            data={item}
            hideCourseName
            onPress={() => navigation.push('AssignmentDetail', item)}
          />
        )}
        keyExtractor={item => item.id}
        refreshing={fetching}
        onRefresh={handleRefresh}
        contentContainerStyle={[
          { flexGrow: 1 },
          data.length ? null : { justifyContent: 'center' },
        ]}
        ListEmptyComponent={<Empty />}
      />
    );
  },
);

const FilesTab = memo(
  ({ courseId, data }: { courseId: string; data: File[] }) => {
    const navigation = useNavigation<any>();
    const dispatch = useAppDispatch();
    const loggedIn = useAppSelector(state => state.auth.loggedIn);
    const fetching = useAppSelector(state => state.files.fetching);

    const handleRefresh = () => {
      if (loggedIn) {
        dispatch(getFilesForCourse(courseId));
      }
    };

    return (
      <FlatList
        data={data}
        renderItem={({ item }) => (
          <FileCard
            data={item}
            hideCourseName
            onPress={() => navigation.push('FileDetail', item)}
          />
        )}
        keyExtractor={item => item.id}
        refreshing={fetching}
        onRefresh={handleRefresh}
        contentContainerStyle={[
          { flexGrow: 1 },
          data.length ? null : { justifyContent: 'center' },
        ]}
        ListEmptyComponent={<Empty />}
      />
    );
  },
);

const CourseDetail: React.FC<Props> = ({ route, navigation }) => {
  const course = route.params;
  const theme = useTheme();

  const [index, setIndex] = useState(0);
  const [routes] = useState([
    { key: 'notices', title: t('notices') },
    { key: 'assignments', title: t('assignments') },
    { key: 'files', title: t('files') },
  ]);

  const allNotices = useAppSelector(state => state.notices.items);
  const allAssignments = useAppSelector(state => state.assignments.items);
  const allFiles = useAppSelector(state => state.files.items);

  const notices = useMemo(
    () => allNotices.filter(n => n.courseId === course.id),
    [allNotices, course.id],
  );
  const assignments = useMemo(
    () => allAssignments.filter(a => a.courseId === course.id),
    [allAssignments, course.id],
  );
  const files = useMemo(
    () => allFiles.filter(f => f.courseId === course.id),
    [allFiles, course.id],
  );

  const renderScene = ({ route: sceneRoute }: any) => {
    switch (sceneRoute.key) {
      case 'notices':
        return <NoticesTab courseId={course.id} data={notices} />;
      case 'assignments':
        return <AssignmentsTab courseId={course.id} data={assignments} />;
      case 'files':
        return <FilesTab courseId={course.id} data={files} />;
      default:
        return null;
    }
  };

  const renderTabBar = (
    props: SceneRendererProps & { navigationState: NavigationState<any> },
  ) => (
    <TabBar
      {...props}
      indicatorStyle={{ backgroundColor: theme.colors.primary }}
      style={{ backgroundColor: theme.colors.surface }}
      labelStyle={{ color: theme.colors.onSurface }}
    />
  );

  React.useLayoutEffect(() => {
    navigation.setOptions({ title: course.name });
  }, [navigation, course.name]);

  return (
    <TabView
      navigationState={{ index, routes }}
      renderScene={renderScene}
      renderTabBar={renderTabBar}
      onIndexChange={setIndex}
      initialLayout={{ width: Dimensions.get('window').width }}
    />
  );
};

export default CourseDetail;
