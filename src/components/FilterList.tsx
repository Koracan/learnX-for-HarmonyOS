import React, {
  useCallback,
  useDeferredValue,
  useLayoutEffect,
  useState,
} from 'react';
import { FlatList, RefreshControl, View, StyleSheet } from 'react-native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import MaterialIcons from 'react-native-vector-icons/MaterialIcons';
import type { Assignment, Course, File, Notice } from 'data/types/state';
import { setSetting } from 'data/actions/settings';
import { useAppDispatch, useAppSelector } from 'data/store';
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
    | NativeStackNavigationProp<NoticeStackParams, 'Notices'>
    | NativeStackNavigationProp<AssignmentStackParams, 'Assignments'>
    | NativeStackNavigationProp<FileStackParams, 'Files'>
    | NativeStackNavigationProp<CourseStackParams, 'Courses'>;
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

  const tabFilterSelections = useAppSelector(
    state => state.settings.tabFilterSelections || {},
  );
  const filterSelected = useAppSelector(
    state =>
      (state.settings.tabFilterSelections && state.settings.tabFilterSelections[type]) ?? defaultSelected ?? 'all',
  );

  const [filterVisible, setFilterVisible] = useState(false);

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
          title={t(type + 's' as any)}
          subtitle={
            filterSelected === 'all'
              ? defaultSubtitle
              : t(filterSelected as any)
          }
        />
      ),
    });
  }, [navigation, type, filterSelected, defaultSubtitle]);

  const renderItem = useCallback(
    ({ item }: { item: T }) => (
      <Component
        data={item}
        onPress={() => onItemPress?.(item)}
      />
    ),
    [Component, onItemPress],
  );

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
        data={deferredData}
        renderItem={renderItem}
        keyExtractor={item => item.id}
        contentContainerStyle={styles.list}
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={onRefresh} />
        }
        ListEmptyComponent={<Empty />}
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
