import React, { useEffect, useCallback } from 'react';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { NoticeStackParams } from 'screens/types';
import { useAppDispatch, useAppSelector } from 'data/store';
import { getAllNoticesForCourses } from 'data/actions/notices';
import type { Notice } from 'data/types/state';
import NoticeCard from 'components/NoticeCard';
import FilterList from 'components/FilterList';
import { selectFilteredNotices } from 'data/selectors/filteredData';
import useDetailNavigator from 'hooks/useDetailNavigator';

type Props = NativeStackScreenProps<NoticeStackParams, 'Notices'>;
/**
 * 公告列表页：展示课程公告并支持下拉刷新。
 */
const Notices: React.FC<Props> = ({ navigation }) => {
  const dispatch = useAppDispatch();
  const detailNavigator = useDetailNavigator();
  const loggedIn = useAppSelector(state => state.auth.loggedIn);
  const courseIds = useAppSelector(
    state => state.courses.items.map(i => i.id),
    (a, b) => JSON.stringify([...a].sort()) === JSON.stringify([...b].sort()),
  );
  const fetching = useAppSelector(state => state.notices.fetching);
  const filteredData = useAppSelector(selectFilteredNotices);

  const handleRefresh = useCallback(() => {
    if (loggedIn) {
      dispatch(getAllNoticesForCourses(courseIds));
    }
  }, [dispatch, loggedIn, courseIds]);

  const handlePress = useCallback(
    (item: Notice) => {
      if (detailNavigator) {
        detailNavigator.navigate('NoticeDetail', item);
      } else {
        navigation.push('NoticeDetail', item);
      }
    },
    [navigation, detailNavigator],
  );

  useEffect(() => {
    handleRefresh();
  }, [handleRefresh]);

  return (
    <FilterList
      type="notice"
      all={filteredData.all}
      unread={filteredData.unread}
      fav={filteredData.fav}
      archived={filteredData.archived}
      hidden={filteredData.hidden}
      itemComponent={NoticeCard}
      navigation={navigation}
      onItemPress={handlePress}
      refreshing={fetching}
      onRefresh={handleRefresh}
    />
  );
};

export default Notices;
