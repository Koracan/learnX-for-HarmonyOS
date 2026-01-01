import React, { useEffect, useCallback } from 'react';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { FileStackParams } from 'screens/types';
import { useAppDispatch, useAppSelector } from 'data/store';
import { getAllFilesForCourses } from 'data/actions/files';
import type { File } from 'data/types/state';
import FileCard from 'components/FileCard';
import FilterList from 'components/FilterList';
import { selectFilteredFiles } from 'data/selectors/filteredData';
import useDetailNavigator from 'hooks/useDetailNavigator';

type Props = NativeStackScreenProps<FileStackParams, 'Files'>;

/**
 * 文件列表页：展示课程文件并支持下拉刷新。
 */
const Files: React.FC<Props> = ({ navigation }) => {
  const dispatch = useAppDispatch();
  const detailNavigator = useDetailNavigator();
  const loggedIn = useAppSelector(state => state.auth.loggedIn);
  const courseIds = useAppSelector(
    state => state.courses.items.map(i => i.id),
    (a, b) => JSON.stringify([...a].sort()) === JSON.stringify([...b].sort()),
  );
  const fetching = useAppSelector(state => state.files.fetching);
  const filteredData = useAppSelector(selectFilteredFiles);

  const handleRefresh = useCallback(() => {
    if (loggedIn && courseIds.length > 0) {
      dispatch(getAllFilesForCourses(courseIds));
    }
  }, [dispatch, loggedIn, courseIds]);

  const handlePress = useCallback(
    (item: File) => {
      if (detailNavigator) {
        detailNavigator.navigate('FileDetail', item);
      } else {
        navigation.push('FileDetail', item);
      }
    },
    [navigation, detailNavigator],
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
