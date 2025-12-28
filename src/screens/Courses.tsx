import React, { useCallback, useEffect, useMemo } from 'react';
import { FlatList, RefreshControl, StyleSheet } from 'react-native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import dayjs from 'dayjs';
import CourseCard from 'components/CourseCard';
import { useAppDispatch, useAppSelector } from 'data/store';
import { getCoursesForSemester } from 'data/actions/courses';
import { getAllSemesters, getCurrentSemester } from 'data/actions/semesters';
import type { Course } from 'data/types/state';
import type { CourseStackParams } from './types';

type Props = NativeStackScreenProps<CourseStackParams, 'Courses'>;

const Courses: React.FC<Props> = ({ navigation }) => {
  const dispatch = useAppDispatch();
  const loggedIn = useAppSelector(state => state.auth.loggedIn);
  const currentSemesterId = useAppSelector(state => state.semesters.current);
  const courses = useAppSelector(state => state.courses.items);
  const fetching = useAppSelector(state => state.courses.fetching);

  const notices = useAppSelector(state => state.notices.items);
  const assignments = useAppSelector(state => state.assignments.items);
  const files = useAppSelector(state => state.files.items);

  const coursesWithCounts = useMemo(() => {
    return courses.map(course => ({
      ...course,
      unreadNoticeCount: notices.filter(
        notice => notice.courseId === course.id && !notice.hasRead,
      ).length,
      unfinishedAssignmentCount: assignments.filter(
        assignment =>
          assignment.courseId === course.id &&
          !assignment.submitted &&
          dayjs(assignment.deadline).isAfter(dayjs()),
      ).length,
      unreadFileCount: files.filter(
        file => file.courseId === course.id && file.isNew,
      ).length,
    }));
  }, [assignments, courses, files, notices]);

  const handleRefresh = useCallback(() => {
    if (loggedIn) {
      if (currentSemesterId) {
        dispatch(getCoursesForSemester(currentSemesterId));
      } else {
        dispatch(getCurrentSemester());
      }
    }
  }, [currentSemesterId, dispatch, loggedIn]);

  useEffect(() => {
    if (loggedIn && !currentSemesterId) {
      dispatch(getAllSemesters());
      dispatch(getCurrentSemester());
    }
  }, [dispatch, loggedIn, currentSemesterId]);

  useEffect(() => {
    if (loggedIn && currentSemesterId) {
      dispatch(getCoursesForSemester(currentSemesterId));
    }
  }, [currentSemesterId, dispatch, loggedIn]);

  const renderItem = ({ item }: { item: (typeof coursesWithCounts)[0] }) => (
    <CourseCard
      data={item}
      onPress={() => navigation.navigate('CourseDetail', item as Course)}
    />
  );

  return (
    <FlatList
      data={coursesWithCounts}
      renderItem={renderItem}
      keyExtractor={item => item.id}
      contentContainerStyle={styles.list}
      refreshControl={
        <RefreshControl refreshing={fetching} onRefresh={handleRefresh} />
      }
    />
  );
};

const styles = StyleSheet.create({
  list: {
    padding: 8,
  },
});

export default Courses;
