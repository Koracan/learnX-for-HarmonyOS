import React, { useMemo } from 'react';
import { StyleSheet, View, ScrollView } from 'react-native';
import {
  Caption,
  Divider,
  Title,
  useTheme,
  Text,
  List,
} from 'react-native-paper';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import dayjs from 'dayjs';
import MaterialCommunityIcons from 'react-native-vector-icons/MaterialCommunityIcons';
import AutoHeightWebView from 'components/AutoHeightWebView';
import Styles from 'constants/Styles';
import type { AssignmentStackParams } from 'screens/types';
import { getWebViewTemplate } from 'helpers/html';
import { t } from 'helpers/i18n';
import Colors from 'constants/Colors';

type Props = NativeStackScreenProps<AssignmentStackParams, 'AssignmentDetail'>;

const AssignmentDetail: React.FC<Props> = ({ route, navigation }) => {
  const theme = useTheme();
  const {
    courseName,
    title,
    deadline,
    description,
    attachment,
    submitted,
    submitTime,
    submittedAttachment,
    submittedContent,
    graded,
    graderName,
    gradeTime,
    grade,
    gradeContent,
  } = route.params;

  const html = useMemo(
    () =>
      getWebViewTemplate(
        description || `<p>${t('noAssignmentDescription')}</p>`,
        {
          isDark: theme.dark,
          backgroundColor: theme.colors.surface,
          textColor: theme.colors.onSurface,
        },
      ),
    [description, theme],
  );

  return (
    <ScrollView style={styles.container}>
      <View style={styles.header}>
        <Caption>{courseName}</Caption>
        <Title>{title}</Title>
        <View style={Styles.flexRow}>
          <MaterialCommunityIcons
            name="clock-outline"
            size={14}
            color={theme.colors.onSurfaceVariant}
          />
          <Caption style={styles.caption}>
            {t('deadline')}: {dayjs(deadline).format('YYYY-MM-DD HH:mm')}
          </Caption>
        </View>
      </View>

      <Divider />

      <View style={styles.section}>
        <Text variant="titleSmall" style={styles.sectionTitle}>
          {t('description')}
        </Text>
        <AutoHeightWebView source={{ html }} />
      </View>

      {attachment && (
        <>
          <Divider />
          <List.Item
            title={attachment.name}
            description={t('attachment')}
            left={props => <List.Icon {...props} icon="attachment" />}
            onPress={() => {
              // TODO: Implement file download/open
            }}
          />
        </>
      )}

      {(submitted || submittedContent || submittedAttachment) && (
        <>
          <Divider />
          <View style={styles.section}>
            <Text variant="titleSmall" style={styles.sectionTitle}>
              {t('submissionStatus')}
            </Text>
            <View style={Styles.flexRow}>
              <MaterialCommunityIcons
                name={submitted ? 'check-circle' : 'alert-circle'}
                size={16}
                color={submitted ? Colors.green500 : Colors.orange500}
              />
              <Text style={styles.statusText}>
                {submitted ? t('submitted') : t('unsubmitted')}
              </Text>
            </View>
            {submitTime && (
              <Caption>
                {t('submitTime')}: {dayjs(submitTime).format('YYYY-MM-DD HH:mm')}
              </Caption>
            )}
            {submittedContent && (
              <Text style={styles.submittedContent}>{submittedContent}</Text>
            )}
          </View>
        </>
      )}

      {graded && (
        <>
          <Divider />
          <View style={styles.section}>
            <Text variant="titleSmall" style={styles.sectionTitle}>
              {t('grade')}
            </Text>
            <Text variant="headlineSmall" style={styles.gradeText}>
              {grade}
            </Text>
            {graderName && (
              <Caption>
                {t('grader')}: {graderName}
              </Caption>
            )}
            {gradeTime && (
              <Caption>
                {t('gradeTime')}: {dayjs(gradeTime).format('YYYY-MM-DD HH:mm')}
              </Caption>
            )}
            {gradeContent && (
              <Text style={styles.gradeContent}>{gradeContent}</Text>
            )}
          </View>
        </>
      )}

      <View style={{ height: 40 }} />
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  header: {
    padding: 16,
  },
  caption: {
    marginLeft: 4,
  },
  section: {
    padding: 16,
  },
  sectionTitle: {
    marginBottom: 8,
    opacity: 0.6,
  },
  statusText: {
    marginLeft: 8,
  },
  submittedContent: {
    marginTop: 8,
    padding: 8,
    backgroundColor: 'rgba(0,0,0,0.05)',
    borderRadius: 4,
  },
  gradeText: {
    color: Colors.red500,
    fontWeight: 'bold',
  },
  gradeContent: {
    marginTop: 8,
    fontStyle: 'italic',
  },
});

export default AssignmentDetail;
