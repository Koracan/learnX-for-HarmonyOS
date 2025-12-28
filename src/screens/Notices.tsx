import React, { useEffect, useCallback } from 'react';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { NoticeStackParams } from 'screens/types';
import { FlatList, RefreshControl, StyleSheet, View } from 'react-native';
import { Text } from 'react-native-paper';
import { useAppDispatch, useAppSelector } from 'data/store';
import { getAllNoticesForCourses } from 'data/actions/notices';
import { t } from 'helpers/i18n';
import type { Notice } from 'data/types/state';
import NoticeCard from 'components/NoticeCard';

type Props = NativeStackScreenProps<NoticeStackParams, 'Notices'>;
/**
 * 公告列表页：展示课程公告并支持下拉刷新。
 */
const Notices: React.FC<Props> = ({ navigation }) => {
  const dispatch = useAppDispatch();
  const loggedIn = useAppSelector(state => state.auth.loggedIn);
  const courseIds = useAppSelector(
    state => state.courses.items.map(i => i.id),
    (a, b) => JSON.stringify([...a].sort()) === JSON.stringify([...b].sort()),
  );
  const { items, fetching } = useAppSelector(state => state.notices);

  const handleRefresh = useCallback(() => {
    if (loggedIn && courseIds.length > 0) {
      console.log('[Notices] Refreshing notices for', courseIds.length, 'courses');
      dispatch(getAllNoticesForCourses(courseIds));
    }
  }, [dispatch, loggedIn, courseIds]);

  const handlePress = useCallback(
    (item: Notice) => {
      navigation.push('NoticeDetail', item);
    },
    [navigation],
  );

  const renderItem = useCallback(
    ({ item }: { item: Notice }) => (
      <NoticeCard data={item} onPress={() => handlePress(item)} />
    ),
    [handlePress],
  );

  const keyExtractor = useCallback((item: Notice) => item.id, []);

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
    padding: 12,
    gap: 12,
  },
  card: {
    marginBottom: 8,
  },
  empty: {
    textAlign: 'center',
    marginTop: 32,
  },
});

export default Notices;
