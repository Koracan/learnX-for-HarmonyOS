import React from 'react';
import { ScrollView, StyleSheet } from 'react-native';
import { Text } from 'react-native-paper';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { NoticeStackParams } from 'screens/types';

type Props = NativeStackScreenProps<NoticeStackParams, 'NoticeDetail'>;
const NoticeDetail: React.FC<Props> = ({ route, navigation }) => {
  const notice = route.params;

  return (
    <ScrollView contentContainerStyle={styles.container}>
      <Text variant="headlineSmall" style={styles.title}>
        {notice.title}
      </Text>
      <Text variant="labelLarge" style={styles.subtitle}>
        {notice.courseName}
      </Text>
      <Text variant="bodyMedium">{notice.content ?? 'No content.'}</Text>
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
