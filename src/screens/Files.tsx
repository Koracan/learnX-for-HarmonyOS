import React, { useEffect, useCallback } from 'react';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { FileStackParams } from 'screens/types';
import { FlatList, RefreshControl, StyleSheet, View } from 'react-native';
import { Text } from 'react-native-paper';
import { useAppDispatch, useAppSelector } from 'data/store';
import { getAllFilesForCourses } from 'data/actions/files';
import { t } from 'helpers/i18n';
import type { File } from 'data/types/state';
import FileCard from 'components/FileCard';

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
  const { items, fetching } = useAppSelector(state => state.files);

  const handleRefresh = useCallback(() => {
    if (loggedIn && courseIds.length > 0) {
      console.log('[Files] Refreshing files for', courseIds.length, 'courses');
      dispatch(getAllFilesForCourses(courseIds));
    }
  }, [dispatch, loggedIn, courseIds]);

  const handlePress = useCallback(
    (item: File) => {
      navigation.push('FileDetail', item);
    },
    [navigation],
  );

  const renderItem = useCallback(
    ({ item }: { item: File }) => (
      <FileCard data={item} onPress={() => handlePress(item)} />
    ),
    [handlePress],
  );

  const keyExtractor = useCallback((item: File) => item.id, []);

  useEffect(() => {
    handleRefresh();
  }, [handleRefresh]);

  return (
    <View style={styles.container}>
      <FlatList
        data={items}
        keyExtractor={keyExtractor}
        renderItem={renderItem}
        contentContainerStyle={styles.list}
        initialNumToRender={10}
        windowSize={5}
        maxToRenderPerBatch={10}
        updateCellsBatchingPeriod={50}
        removeClippedSubviews
        refreshControl={
          <RefreshControl
            refreshing={fetching}
            onRefresh={handleRefresh}
          />
        }
        ListEmptyComponent={
          !fetching ? (
            <Text style={styles.empty}>{t('empty')}</Text>
          ) : null
        }
      />
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  list: {
    paddingVertical: 8,
  },
  empty: {
    textAlign: 'center',
    marginTop: 40,
    opacity: 0.5,
  },
});

export default Files;
