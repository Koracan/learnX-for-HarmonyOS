import React, { useEffect, useCallback } from 'react';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { NoticeStackParams } from 'screens/types';
import { useMemo } from 'react';
import { FlatList, RefreshControl, StyleSheet, View } from 'react-native';
import { Card, Text } from 'react-native-paper';
import { useAppDispatch, useAppSelector } from 'data/store';
import { getAllNoticesForCourses } from 'data/actions/notices';
import { t } from 'helpers/i18n';
import type { Notice } from 'data/types/state';
// import removed: HTML 解析改在 actions 预计算

const NoticeItem = React.memo(
  ({ item, onPressItem }: { item: Notice; onPressItem: (item: Notice) => void }) => {
    const handlePress = useCallback(() => onPressItem(item), [item, onPressItem]);

    return (
      <Card style={styles.card} onPress={handlePress}>
        <Card.Title title={item.title} subtitle={item.courseName} />
        {item.plainText ? (
          <Card.Content>
            <Text variant="bodyMedium" numberOfLines={3}>
              {item.plainText}
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
  const currentSemester = useAppSelector(state => state.semesters.current);
  const coursesItems = useAppSelector(state => state.courses.items);
  const courseIds = useMemo(() => coursesItems.map(c => c.id), [coursesItems]);
  const { items, fetching } = useAppSelector(state => state.notices);

  const handleRefresh = useCallback(() => {
    if (auth.loggedIn && courseIds.length > 0) {
      console.log('[Notices] Refreshing notices for', courseIds.length, 'courses', 'semester=', currentSemester);
      dispatch(getAllNoticesForCourses(courseIds));
    }
  }, [dispatch, auth.loggedIn, courseIds, currentSemester]);

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
