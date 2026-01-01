import React, { useEffect, useCallback } from 'react';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { AssignmentStackParams } from 'screens/types';
import { useAppDispatch, useAppSelector } from 'data/store';
import { getAllAssignmentsForCourses } from 'data/actions/assignments';
import type { Assignment } from 'data/types/state';
import AssignmentCard from 'components/AssignmentCard';
import FilterList from 'components/FilterList';
import { selectFilteredAssignments } from 'data/selectors/filteredData';
import useDetailNavigator from 'hooks/useDetailNavigator';

type Props = NativeStackScreenProps<AssignmentStackParams, 'Assignments'>;

/**
 * 作业列表页：展示课程作业并支持下拉刷新。
 */
const Assignments: React.FC<Props> = ({ navigation }) => {
  const dispatch = useAppDispatch();
  const detailNavigator = useDetailNavigator();
  const loggedIn = useAppSelector(state => state.auth.loggedIn);
  const courseIds = useAppSelector(
    state => state.courses.items.map(i => i.id),
    (a, b) => JSON.stringify([...a].sort()) === JSON.stringify([...b].sort()),
  );
  const fetching = useAppSelector(state => state.assignments.fetching);
  const filteredData = useAppSelector(selectFilteredAssignments);

  const handleRefresh = useCallback(() => {
    if (loggedIn && courseIds.length > 0) {
      dispatch(getAllAssignmentsForCourses(courseIds));
    }
  }, [dispatch, loggedIn, courseIds]);

  const handlePress = useCallback(
    (item: Assignment) => {
      if (detailNavigator) {
        detailNavigator.navigate('AssignmentDetail', item);
      } else {
        navigation.push('AssignmentDetail', item);
      }
    },
    [navigation, detailNavigator],
  );

  useEffect(() => {
    handleRefresh();
  }, [handleRefresh]);

  return (
    <FilterList
      type="assignment"
      all={filteredData.all}
      unfinished={filteredData.unfinished}
      finished={filteredData.finished}
      fav={filteredData.fav}
      archived={filteredData.archived}
      hidden={filteredData.hidden}
      itemComponent={AssignmentCard}
      navigation={navigation}
      onItemPress={handlePress}
      refreshing={fetching}
      onRefresh={handleRefresh}
    />
  );
};

export default Assignments;
