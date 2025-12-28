import React, { useCallback, useEffect, useMemo } from 'react';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import dayjs from 'dayjs';
import CourseCard from 'components/CourseCard';
import { useAppDispatch, useAppSelector } from 'data/store';
import { getCoursesForSemester } from 'data/actions/courses';
import { getAllSemesters, getCurrentSemester } from 'data/actions/semesters';
import type { Course } from 'data/types/state';
import type { CourseStackParams } from './types';
import FilterList from 'components/FilterList';
import { getSemesterTextFromId } from 'helpers/parse';

type Props = NativeStackScreenProps<CourseStackParams, 'Courses'>;

const Courses: React.FC<Props> = ({ navigation }) => {
  const dispatch = useAppDispatch();
  const loggedIn = useAppSelector(state => state.auth.loggedIn);
  const currentSemesterId = useAppSelector(state => state.semesters.current);
  const courses = useAppSelector(
    state => state.courses.items,
    (a, b) => JSON.stringify(a) === JSON.stringify(b),
  );
  const hiddenIds = useAppSelector(state => state.courses.hidden);
  const fetching = useAppSelector(state => state.courses.fetching);

  const notices = useAppSelector(
    state => state.notices.items,
    (a, b) => JSON.stringify(a) === JSON.stringify(b),
  );
  const assignments = useAppSelector(
    state => state.assignments.items,
    (a, b) => JSON.stringify(a) === JSON.stringify(b),
  );
  const files = useAppSelector(
    state => state.files.items,
    (a, b) => JSON.stringify(a) === JSON.stringify(b),
  );

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

  const all = coursesWithCounts.filter(i => !hiddenIds.includes(i.id));
  const hidden = coursesWithCounts.filter(i => hiddenIds.includes(i.id));

  const handleRefresh = useCallback(() => {
    if (loggedIn) {
      if (currentSemesterId) {
        dispatch(getCoursesForSemester(currentSemesterId));
      } else {
        dispatch(getCurrentSemester());
      }
    }
  }, [currentSemesterId, dispatch, loggedIn]);

  const handlePress = (item: Course) => {
    navigation.push('CourseDetail', item);
  };

  return (
    <FilterList
      type="course"
      defaultSubtitle={
        currentSemesterId
          ? getSemesterTextFromId(currentSemesterId)
          : undefined
      }
      all={all as any}
      hidden={hidden as any}
      itemComponent={CourseCard as any}
      navigation={navigation}
      onItemPress={handlePress as any}
      refreshing={fetching}
      onRefresh={handleRefresh}
    />
  );
};

export default Courses;
