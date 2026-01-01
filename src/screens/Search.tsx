import React, { useEffect, useRef, useState } from 'react';
import {
  KeyboardAvoidingView,
  SectionList,
  StyleSheet,
  TextInput,
  View,
} from 'react-native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { useIsFocused } from '@react-navigation/native';
import { Searchbar, Text, useTheme } from 'react-native-paper';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import useSearch from 'hooks/useSearch';
import Styles from 'constants/Styles';
import { useAppSelector } from 'data/store';
import type { Notice, Assignment, File } from 'data/types/state';
import NoticeCard from 'components/NoticeCard';
import AssignmentCard from 'components/AssignmentCard';
import FileCard from 'components/FileCard';
import Empty from 'components/Empty';
import SafeArea from 'components/SafeArea';
import { t } from 'helpers/i18n';
import type { SearchStackParams } from 'screens/types';
import useDetailNavigator from 'hooks/useDetailNavigator';

type Props = NativeStackScreenProps<SearchStackParams, 'Search'>;

const Search: React.FC<Props> = ({ navigation, route }) => {
  const theme = useTheme();
  const safeAreaInsets = useSafeAreaInsets();
  const detailNavigator = useDetailNavigator();
  const isFocused = useIsFocused();
  const searchRef = useRef<TextInput>(null);

  const notices = useAppSelector(state => state.notices.items);
  const assignments = useAppSelector(state => state.assignments.items);
  const files = useAppSelector(state => state.files.items);

  const [searchQuery, setSearchQuery] = useState(route.params?.query ?? '');

  useEffect(() => {
    if (isFocused && searchQuery === '') {
      searchRef.current?.focus();
    }
  }, [isFocused, searchQuery]);

  const [noticeResult, assignmentResult, fileResult] = useSearch(
    notices,
    assignments,
    files,
    searchQuery,
  );

  const handlePush = (name: any, item: any) => {
    if (detailNavigator) {
      detailNavigator.navigate(name, item);
    } else {
      navigation.push(name, item);
    }
  };

  return (
    <SafeArea>
      <View style={Styles.flex1}>
        <Searchbar
          ref={searchRef}
          style={[styles.searchBar, { backgroundColor: theme.colors.surface }]}
          elevation={0}
          placeholderTextColor={theme.colors.outline}
          placeholder={t('searchPlaceholder')}
          onChangeText={setSearchQuery}
          value={searchQuery}
        />
        {noticeResult.length === 0 &&
        assignmentResult.length === 0 &&
        fileResult.length === 0 ? (
          <KeyboardAvoidingView
            behavior={'padding'}
            style={Styles.flex1}
          >
            <Empty />
          </KeyboardAvoidingView>
        ) : (
          <SectionList<Notice | Assignment | File>
            contentContainerStyle={{ paddingBottom: safeAreaInsets.bottom }}
            sections={[
              { key: 'notice', title: t('notices'), data: noticeResult },
              {
                key: 'assignment',
                title: t('assignments'),
                data: assignmentResult,
              },
              { key: 'file', title: t('files'), data: fileResult },
            ]}
            keyExtractor={item => item.id}
            renderItem={({ item, section: { key } }) =>
              key === 'notice' ? (
                <NoticeCard
                  data={item as Notice}
                  onPress={() => handlePush('NoticeDetail', item as Notice)}
                />
              ) : key === 'assignment' ? (
                <AssignmentCard
                  data={item as Assignment}
                  onPress={() =>
                    handlePush('AssignmentDetail', item as Assignment)
                  }
                />
              ) : (
                <FileCard
                  data={item as File}
                  onPress={() => handlePush('FileDetail', item as File)}
                />
              )
            }
            renderSectionHeader={({ section: { title, data } }) =>
              data.length ? (
                <Text
                  variant="titleSmall"
                  style={[
                    styles.header,
                    {
                      color: theme.colors.outline,
                      backgroundColor: theme.dark
                        ? 'black'
                        : theme.colors.background,
                    },
                  ]}
                >
                  {title}
                </Text>
              ) : null
            }
            ItemSeparatorComponent={null}
          />
        )}
      </View>
    </SafeArea>
  );
};

const styles = StyleSheet.create({
  searchBar: {
    elevation: 0,
    borderRadius: 0,
  },
  header: {
    paddingHorizontal: 16,
    paddingVertical: 12,
    marginVertical: -1,
  },
});

export default Search;
