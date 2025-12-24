import React, { useEffect } from 'react';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { NoticeStackParams } from 'screens/types';
import { FlatList, RefreshControl, StyleSheet, View } from 'react-native';
import { Card, Text } from 'react-native-paper';
import { useAppDispatch, useAppSelector } from 'data/store';
import { getAllNoticesForCourses } from 'data/actions/notices';
import type { Notice } from 'data/types/state';

const NoticeItem = ({ item }: { item: Notice }) => (
  <Card style={styles.card}>
    <Card.Title title={item.title} subtitle={item.courseName} />
    {item.content ? (
      <Card.Content>
        <Text variant="bodyMedium" numberOfLines={3}>
          {item.content}
        </Text>
      </Card.Content>
    ) : null}
    <Card.Actions>
      <Text variant="labelSmall">{item.publishTime}</Text>
    </Card.Actions>
  </Card>
);

type Props = NativeStackScreenProps<NoticeStackParams, 'Notices'>;
/**
 * 公告列表页：展示课程公告并支持下拉刷新。
 */
const Notices: React.FC<Partial<Props>> = () => {
  const dispatch = useAppDispatch();
  const auth = useAppSelector(state => state.auth);
  const { items, fetching } = useAppSelector(state => state.notices);

  useEffect(() => {
    if (auth.loggedIn) {
      console.log('[Notices] loggedIn, fetching notices');
      dispatch(getAllNoticesForCourses());
    } else {
      console.log('[Notices] skip fetch, not loggedIn');
    }
  }, [dispatch, auth.loggedIn]);

  return (
    <View style={styles.container}>
      <FlatList
        data={items}
        keyExtractor={item => item.id}
        renderItem={({ item }) => <NoticeItem item={item} />}
        contentContainerStyle={styles.list}
        refreshControl={
          <RefreshControl
            refreshing={fetching}
            onRefresh={() => dispatch(getAllNoticesForCourses())}
          />
        }
        ListEmptyComponent={
          !fetching ? (
            <Text style={styles.empty}>No notices yet.</Text>
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
