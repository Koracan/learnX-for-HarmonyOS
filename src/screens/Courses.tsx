import React, { useCallback, useEffect } from 'react';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import CourseCard from 'components/CourseCard';
import { useAppDispatch, useAppSelector } from 'data/store';
import { getCoursesForSemester } from 'data/actions/courses';
import { getCurrentSemester } from 'data/actions/semesters';
import type { Course } from 'data/types/state';
import type { CourseStackParams } from './types';
import FilterList from 'components/FilterList';
import { getSemesterTextFromId } from 'helpers/parse';
import { selectFilteredCourses } from 'data/selectors/filteredData';
import useDetailNavigator from 'hooks/useDetailNavigator';

type Props = NativeStackScreenProps<CourseStackParams, 'Courses'>;

const Courses: React.FC<Props> = ({ navigation }) => {
  const dispatch = useAppDispatch();
  const detailNavigator = useDetailNavigator();
  const loggedIn = useAppSelector(state => state.auth.loggedIn);
  const currentSemesterId = useAppSelector(state => state.semesters.current);
  const fetching = useAppSelector(state => state.courses.fetching);
  const filteredData = useAppSelector(selectFilteredCourses);

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
    if (detailNavigator) {
      detailNavigator.navigate('CourseDetail', item);
    } else {
      navigation.push('CourseDetail', item);
    }
  };

  useEffect(() => {
    handleRefresh();
  }, [handleRefresh]);

  return (
    <FilterList
      type="course"
      defaultSubtitle={
        currentSemesterId ? getSemesterTextFromId(currentSemesterId) : undefined
      }
      all={filteredData.all as any}
      hidden={filteredData.hidden as any}
      itemComponent={CourseCard as any}
      navigation={navigation}
      onItemPress={handlePress as any}
      refreshing={fetching}
      onRefresh={handleRefresh}
    />
  );
};

export default Courses;
