import React, {
  useCallback,
  useDeferredValue,
  useLayoutEffect,
  useState,
} from 'react';
import { RefreshControl, View, StyleSheet } from 'react-native';
import { FlatList } from 'react-native-gesture-handler';
import type { StackNavigationProp } from '@react-navigation/stack';
import MaterialIcons from 'react-native-vector-icons/MaterialIcons';
import type { Assignment, Course, File, Notice } from 'data/types/state';
import { setSetting } from 'data/actions/settings';
import { setHideCourse } from 'data/actions/courses';
import { setArchiveNotices, setFavNotice } from 'data/actions/notices';
import {
  setArchiveAssignments,
  setFavAssignment,
} from 'data/actions/assignments';
import { setArchiveFiles, setFavFile } from 'data/actions/files';
import { useAppDispatch, useAppSelector } from 'data/store';
import useToast from 'hooks/useToast';
import type {
  AssignmentStackParams,
  CourseStackParams,
  FileStackParams,
  NoticeStackParams,
} from 'screens/types';
import { t } from 'helpers/i18n';
import Filter, { type FilterSelection } from './Filter';
import HeaderTitle from './HeaderTitle';
import Empty from './Empty';
import Skeleton from './Skeleton';
import type { CardWrapperProps } from './CardWrapper';
import IconButton from './IconButton';

export interface ItemComponentProps<T> extends CardWrapperProps {
  data: T;
}

export interface FilterListProps<T> {
  type: 'notice' | 'assignment' | 'file' | 'course';
  defaultSelected?: FilterSelection;
  defaultSubtitle?: string;
  unfinished?: T[];
  finished?: T[];
  all: T[];
  unread?: T[];
  fav?: T[];
  archived?: T[];
  hidden: T[];
  itemComponent: React.FC<React.PropsWithChildren<ItemComponentProps<T>>>;
  navigation:
    | StackNavigationProp<NoticeStackParams, 'Notices'>
    | StackNavigationProp<AssignmentStackParams, 'Assignments'>
    | StackNavigationProp<FileStackParams, 'Files'>
    | StackNavigationProp<CourseStackParams, 'Courses'>;
  onItemPress?: (item: T) => void;
  refreshing: boolean;
  onRefresh?: () => void;
}

const FilterList = <T extends Notice | Assignment | File | Course>({
  type,
  defaultSelected,
  all,
  unread,
  unfinished,
  finished,
  fav,
  archived,
  hidden,
  itemComponent: Component,
  navigation,
  onItemPress,
  defaultSubtitle,
  refreshing,
  onRefresh,
}: FilterListProps<T>) => {
  const dispatch = useAppDispatch();
  const toast = useToast();

  const tabFilterSelections = useAppSelector(
    state => state.settings.tabFilterSelections || {},
  );
  const filterSelected = useAppSelector(
    state =>
      (state.settings.tabFilterSelections &&
        state.settings.tabFilterSelections[type]) ??
      defaultSelected ??
      'all',
  );

  const [filterVisible, setFilterVisible] = useState(false);

  const isCourse = type === 'course';

  const data = (
    filterSelected === 'unfinished' && unfinished
      ? unfinished
      : filterSelected === 'finished' && finished
      ? finished
      : filterSelected === 'all'
      ? all
      : filterSelected === 'unread' && unread
      ? unread
      : filterSelected === 'fav'
      ? fav
      : filterSelected === 'archived'
      ? archived
      : hidden
  )!;

  const deferredData = useDeferredValue(data);

  const handleFilter = () => {
    setFilterVisible(v => !v);
  };

  const handleFav = (isFav: boolean, item: T) => {
    if (type === 'notice') {
      dispatch(setFavNotice(item.id, !isFav));
    } else if (type === 'assignment') {
      dispatch(setFavAssignment(item.id, !isFav));
    } else if (type === 'file') {
      dispatch(setFavFile(item.id, !isFav));
    }

    if (isFav) {
      toast(t('removeFromFav'), 'success', undefined, {
        label: t('undo'),
        onPress: () => handleFav(false, item),
      });
    } else {
      toast(t('addToFav'), 'success', undefined, {
        label: t('undo'),
        onPress: () => handleFav(true, item),
      });
    }
  };

  const handleArchive = (isArchived: boolean, item: T) => {
    if (type === 'notice') {
      dispatch(setArchiveNotices([item.id], !isArchived));
    } else if (type === 'assignment') {
      dispatch(setArchiveAssignments([item.id], !isArchived));
    } else if (type === 'file') {
      dispatch(setArchiveFiles([item.id], !isArchived));
    }

    if (isArchived) {
      toast(t('undoArchive'), 'success');
    } else {
      toast(t('archiveSucceeded'), 'success', undefined, {
        label: t('undo'),
        onPress: () => handleArchive(true, item),
      });
    }
  };

  const handleHide = (isHidden: boolean, id: string) => {
    dispatch(setHideCourse(id, !isHidden));

    if (isHidden) {
      toast(t('undoHide'), 'success');
    } else {
      toast(t('hideSucceeded'), 'success', undefined, {
        label: t('undo'),
        onPress: () => dispatch(setHideCourse(id, false)),
      });
    }
  };

  const handleFilterSelect = (selected: FilterSelection) => {
    dispatch(
      setSetting('tabFilterSelections', {
        ...tabFilterSelections,
        [type]: selected,
      }),
    );
    setFilterVisible(false);
  };

  useLayoutEffect(() => {
    navigation.setOptions({
      headerLeft: () => (
        <IconButton
          onPress={handleFilter}
          icon={props => <MaterialIcons {...props} name="filter-list" />}
        />
      ),
      headerTitle: props => (
        <HeaderTitle
          {...props}
          title={props.children!}
          subtitle={
            filterSelected === 'all'
              ? defaultSubtitle
              : t(filterSelected as any)
          }
        />
      ),
    });
  }, [navigation, filterSelected, defaultSubtitle]);

  const renderItem = useCallback(
    ({ item }: { item: T }) => (
      <Component
        data={item}
        onPress={() => onItemPress?.(item)}
        fav={fav?.some(f => f.id === item.id)}
        onFav={
          !isCourse
            ? () => handleFav(fav?.some(f => f.id === item.id) ?? false, item)
            : undefined
        }
        archived={archived?.some(a => a.id === item.id)}
        onArchive={
          !isCourse
            ? () =>
                handleArchive(
                  archived?.some(a => a.id === item.id) ?? false,
                  item,
                )
            : undefined
        }
        hidden={hidden.some(h => h.id === item.id)}
        onHide={
          isCourse
            ? () => handleHide(hidden.some(h => h.id === item.id), item.id)
            : undefined
        }
      />
    ),
    [Component, onItemPress, fav, archived, hidden, isCourse, handleFav, handleArchive, handleHide],
  );

  const skeletonData = Array.from({ length: 6 }).map((_, i) => ({ id: `skeleton-${i}` } as any));

  return (
    <View style={styles.container}>
      <Filter
        visible={filterVisible}
        selected={filterSelected}
        onSelectionChange={handleFilterSelect}
        allCount={all.length}
        unreadCount={unread?.length}
        favCount={fav?.length}
        archivedCount={archived?.length}
        hiddenCount={hidden.length}
        unfinishedCount={unfinished?.length}
      />
      <FlatList
        data={refreshing && deferredData.length === 0 ? skeletonData : deferredData}
        renderItem={refreshing && deferredData.length === 0 ? () => <Skeleton /> : renderItem}
        keyExtractor={item => item.id}
        contentContainerStyle={styles.list}
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={onRefresh} />
        }
        ListEmptyComponent={refreshing ? null : <Empty />}
        removeClippedSubviews={true}
        initialNumToRender={8}
        maxToRenderPerBatch={10}
        windowSize={5}
      />
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  list: {
    padding: 8,
  },
});

export default FilterList;
