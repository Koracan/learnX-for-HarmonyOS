import React, { useMemo } from 'react';
import { ScrollView, StyleSheet } from 'react-native';
import { Text, useTheme } from 'react-native-paper';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { NoticeStackParams } from 'screens/types';
import AutoHeightWebView from 'components/AutoHeightWebView';
import { getWebViewTemplate } from 'helpers/html';

type Props = NativeStackScreenProps<NoticeStackParams, 'NoticeDetail'>;
/**
 * 公告详情页：展示公告标题、课程与正文内容。
 */
const NoticeDetail: React.FC<Props> = ({ route, navigation }) => {
  const theme = useTheme();
  const notice = route.params;

  const { surface, onSurface, primary } = theme.colors;

  const html = useMemo(
    () =>
      getWebViewTemplate(notice.content || '<p>No content.</p>', {
        backgroundColor: surface,
        textColor: onSurface,
        linkColor: primary,
        isDark: theme.dark,
      }),
    [notice.content, onSurface, primary, surface, theme.dark],
  );

  return (
    <ScrollView contentContainerStyle={styles.container}>
      <Text variant="headlineSmall" style={styles.title}>
        {notice.title}
      </Text>
      <Text variant="labelLarge" style={styles.subtitle}>
        {notice.courseName}
      </Text>
      <AutoHeightWebView source={{ html }} />
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  container: {
    padding: 16,
    gap: 8,
  },
  title: {
    marginBottom: 4,
  },
  subtitle: {
    marginBottom: 8,
  },
});

export default NoticeDetail;
