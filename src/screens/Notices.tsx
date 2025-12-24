import React, { useEffect, useCallback } from 'react';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { NoticeStackParams } from 'screens/types';
import { FlatList, RefreshControl, StyleSheet, View } from 'react-native';
import { Card, Text } from 'react-native-paper';
import { useAppDispatch, useAppSelector } from 'data/store';
import { getAllNoticesForCourses } from 'data/actions/notices';
import { t } from 'helpers/i18n';
import type { Notice } from 'data/types/state';
import { removeTags } from 'helpers/html';

const NoticeItem = React.memo(
  ({ item, onPressItem }: { item: Notice; onPressItem: (item: Notice) => void }) => {
    const handlePress = useCallback(() => onPressItem(item), [item, onPressItem]);

    return (
      <Card style={styles.card} onPress={handlePress}>
        <Card.Title title={item.title} subtitle={item.courseName} />
        {item.content ? (
          <Card.Content>
            <Text variant="bodyMedium" numberOfLines={3}>
              {removeTags(item.content)}
            </Text>
          </Card.Content>
        ) : null}
        <Card.Actions>
          <Text variant="labelSmall">{item.publishTime}</Text>
        </Card.Actions>
      </Card>
    );
  },
);
NoticeItem.displayName = 'NoticeItem';

type Props = NativeStackScreenProps<NoticeStackParams, 'Notices'>;
/**
 * 公告列表页：展示课程公告并支持下拉刷新。
 */
const Notices: React.FC<Props> = ({ navigation }) => {
  const dispatch = useAppDispatch();
  const auth = useAppSelector(state => state.auth);
  const courseIds = useAppSelector(
    state => state.courses.items.map(c => c.id),
    (a, b) => JSON.stringify(a) === JSON.stringify(b), // 避免数组引用变化导致无限循环
  );
  const { items, fetching } = useAppSelector(state => state.notices);

  const handleRefresh = useCallback(() => {
    if (auth.loggedIn && courseIds.length > 0) {
      console.log('[Notices] Refreshing notices for', courseIds.length, 'courses');
      dispatch(getAllNoticesForCourses(courseIds));
    }
  }, [dispatch, auth.loggedIn, courseIds]);

  const handlePress = useCallback(
    (item: Notice) => {
      navigation.push('NoticeDetail', item);
    },
    [navigation],
  );

  const renderItem = useCallback(
    ({ item }: { item: Notice }) => (
      <NoticeItem item={item} onPressItem={handlePress} />
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
