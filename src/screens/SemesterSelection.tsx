import React, { useCallback, useEffect, useState } from 'react';
import { StyleSheet } from 'react-native';
import { type StackScreenProps } from '@react-navigation/stack';
import TableCell from 'components/TableCell';
import SafeArea from 'components/SafeArea';
import FlatList from 'components/FlatList';
import { dataSource } from 'data/source';
import { useAppDispatch, useAppSelector } from 'data/store';
import {
  getAllSemesters,
  getCurrentSemester,
  setCurrentSemester,
} from 'data/actions/semesters';
import { getSemesterTextFromId } from 'helpers/parse';
import useNavigationAnimation from 'hooks/useNavigationAnimation';
import { type SettingsStackParams } from './types';

type Props = StackScreenProps<SettingsStackParams, 'SemesterSelection'>;

const SemesterSelection: React.FC<Props> = (props) => {
  useNavigationAnimation(props as any);
  const dispatch = useAppDispatch();
  const semesters = useAppSelector(state => state.semesters.items);
  const fetching = useAppSelector(state => state.semesters.fetching);
  const currentSemesterId = useAppSelector(state => state.semesters.current);

  const [latestSemester, setLatestSemester] = useState<string | null>(null);

  const getLatestSemester = async () => {
    try {
      const { id } = await dataSource.getCurrentSemester();
      setLatestSemester(id);
    } catch (e) {
      console.error('Failed to get current semester', e);
    }
  };

  const handleSelect = (id: string) => {
    dispatch(setCurrentSemester(id));
  };

  const handleRefresh = useCallback(() => {
    getLatestSemester();
    dispatch(getCurrentSemester());
    dispatch(getAllSemesters());
  }, [dispatch]);

  useEffect(() => {
    handleRefresh();
  }, [handleRefresh]);

  return (
    <SafeArea>
      <FlatList
        contentContainerStyle={styles.padding}
        data={semesters}
        ListHeaderComponent={
          latestSemester && !semesters.includes(latestSemester) ? (
            <TableCell
              iconName={currentSemesterId === latestSemester ? 'check' : undefined}
              primaryText={getSemesterTextFromId(latestSemester)}
              type="none"
              onPress={() => handleSelect(latestSemester)}
            />
          ) : null
        }
        renderItem={({ item }) => (
          <TableCell
            iconName={currentSemesterId === item ? 'check' : undefined}
            primaryText={item ? getSemesterTextFromId(item) : ''}
            type="none"
            onPress={() => handleSelect(item)}
          />
        )}
        keyExtractor={item => item}
        refreshing={fetching}
        onRefresh={handleRefresh}
      />
    </SafeArea>
  );
};

const styles = StyleSheet.create({
  padding: {
    paddingVertical: 16,
  },
});

export default SemesterSelection;
