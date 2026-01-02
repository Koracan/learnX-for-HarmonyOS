import React, { useMemo } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { Text, useTheme, Caption, Divider, List } from 'react-native-paper';
import MaterialIcons from 'react-native-vector-icons/MaterialIcons';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { NoticeStackParams } from 'screens/types';
import AutoHeightWebView from 'components/AutoHeightWebView';
import { getWebViewTemplate } from 'helpers/html';
import dayjs from 'dayjs';
import { isLocaleChinese, t } from 'helpers/i18n';
import { stripExtension, getExtension } from 'helpers/fs';
import type { File } from 'data/types/state';
import Styles from 'constants/Styles';

type Props = NativeStackScreenProps<NoticeStackParams, 'NoticeDetail'>;
/**
 * 公告详情页：展示公告标题、课程与正文内容。
 */
const NoticeDetail: React.FC<Props> = ({ route, navigation }) => {
  const theme = useTheme();
  const notice = route.params;

  console.log(`[NoticeDetail] Rendering notice:`, {
    id: notice.id,
    hasContent: !!notice.content,
    contentLength: notice.content?.length,
    hasAttachment: !!notice.attachment,
  });

  const {
    id,
    courseName,
    courseTeacherName,
    title,
    publisher,
    publishTime,
    content,
    attachment,
  } = notice;

  const html = useMemo(
    () =>
      getWebViewTemplate(
        content || `<p>${t('noNoticeContent')}</p>`,
        theme.dark,
        theme.colors.surface,
      ),
    [content, theme],
  );

  const handleFileOpen = () => {
    if (attachment) {
      const data = {
        id,
        courseName,
        courseTeacherName,
        title: stripExtension(attachment.name),
        downloadUrl: attachment.downloadUrl,
        fileType: getExtension(attachment.name) ?? '',
      } as File;

      navigation.push('FileDetail', data);
    }
  };

  return (
    <ScrollView contentContainerStyle={styles.container}>
      <View style={styles.section}>
        <Text variant="headlineSmall" style={styles.title}>
          {title}
        </Text>
        <View style={Styles.flexRowCenter}>
          <Caption>{publisher}</Caption>
          <Caption style={styles.time}>
            {dayjs(publishTime).format(
              isLocaleChinese()
                ? 'YYYY 年 M 月 D 日 dddd HH:mm'
                : 'MMM D, YYYY HH:mm',
            )}
          </Caption>
        </View>
      </View>
      <Divider />
      {attachment && (
        <>
          <List.Item
            title={attachment.name}
            left={props => (
              <List.Icon
                {...props}
                icon={p => <MaterialIcons name="insert-drive-file" {...p} />}
              />
            )}
            onPress={handleFileOpen}
          />
          <Divider />
        </>
      )}
      <AutoHeightWebView source={{ html }} />
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  container: {
    paddingBottom: 32,
  },
  section: {
    padding: 16,
  },
  title: {
    marginBottom: 8,
  },
  time: {
    marginLeft: 8,
  },
  attachmentSection: {
    marginTop: 16,
  },
});

export default NoticeDetail;
