import React, { useEffect, useCallback } from 'react';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { FileStackParams } from 'screens/types';
import { useAppDispatch, useAppSelector } from 'data/store';
import { getAllFilesForCourses } from 'data/actions/files';
import type { File } from 'data/types/state';
import FileCard from 'components/FileCard';
import FilterList from 'components/FilterList';
import useFilteredData from 'hooks/useFilteredData';

type Props = NativeStackScreenProps<FileStackParams, 'Files'>;

/**
 * 文件列表页：展示课程文件并支持下拉刷新。
 */
const Files: React.FC<Props> = ({ navigation }) => {
  const dispatch = useAppDispatch();
  const loggedIn = useAppSelector(state => state.auth.loggedIn);
  const courseIds = useAppSelector(
    state => state.courses.items.map(i => i.id),
    (a, b) => JSON.stringify([...a].sort()) === JSON.stringify([...b].sort()),
  );
  const items = useAppSelector(
    state => state.files.items,
    (a, b) => JSON.stringify(a) === JSON.stringify(b),
  );
  const fetching = useAppSelector(state => state.files.fetching);
  const fav = useAppSelector(state => state.files.favorites);
  const archived = useAppSelector(state => state.files.archived);
  const hidden = useAppSelector(state => state.courses.hidden);

  const filteredData = useFilteredData({
    data: items,
    fav,
    archived,
    hidden,
  });

  const handleRefresh = useCallback(() => {
    if (loggedIn && courseIds.length > 0) {
      dispatch(getAllFilesForCourses(courseIds));
    }
  }, [dispatch, loggedIn, courseIds]);

  const handlePress = useCallback(
    (item: File) => {
      navigation.push('FileDetail', item);
    },
    [navigation],
  );

  useEffect(() => {
    handleRefresh();
  }, [handleRefresh]);

  return (
    <FilterList
      type="file"
      all={filteredData.all}
      unread={filteredData.unread}
      fav={filteredData.fav}
      archived={filteredData.archived}
      hidden={filteredData.hidden}
      itemComponent={FileCard}
      navigation={navigation}
      onItemPress={handlePress}
      refreshing={fetching}
      onRefresh={handleRefresh}
    />
  );
};

export default Files;
