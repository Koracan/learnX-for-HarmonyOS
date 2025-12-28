import React, { useMemo } from 'react';
import { StyleSheet, View, ScrollView } from 'react-native';
import {
  Caption,
  Divider,
  Title,
  useTheme,
  Text,
  List,
  Chip,
} from 'react-native-paper';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import dayjs from 'dayjs';
import MaterialCommunityIcons from 'react-native-vector-icons/MaterialCommunityIcons';
import { HomeworkCompletionType, HomeworkSubmissionType } from 'thu-learn-lib';
import AutoHeightWebView from 'components/AutoHeightWebView';
import Styles from 'constants/Styles';
import type { AssignmentStackParams } from 'screens/types';
import { getWebViewTemplate, removeTags } from 'helpers/html';
import { isLocaleChinese, t } from 'helpers/i18n';
import Colors from 'constants/Colors';

type Props = NativeStackScreenProps<AssignmentStackParams, 'AssignmentDetail'>;

const AssignmentDetail: React.FC<Props> = ({ route, navigation }) => {
  const theme = useTheme();
  const {
    courseName,
    title,
    deadline,
    description,
    completionType,
    submissionType,
    attachment,
    submitted,
    isLateSubmission,
    submitTime,
    submittedAttachment,
    submittedContent,
    graded,
    graderName,
    gradeTime,
    grade,
    gradeLevel,
    gradeContent,
    gradeAttachment,
    answerContent,
    answerAttachment,
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
        <View style={Styles.flexRow}>
          <Chip compact mode="outlined" style={styles.chip}>
            {completionType === HomeworkCompletionType.GROUP
              ? t('assignmentGroupCompletion')
              : t('assignmentIndividualCompletion')}
          </Chip>
          <Chip compact mode="outlined" style={styles.chip}>
            {submissionType === HomeworkSubmissionType.OFFLINE
              ? t('assignmentOfflineSubmission')
              : t('assignmentOnlineSubmission')}
          </Chip>
        </View>
        <Title>{title}</Title>
        <View style={Styles.flexRowCenter}>
          <Caption>
            {isLocaleChinese()
              ? dayjs().isAfter(dayjs(deadline))
                ? dayjs().to(dayjs(deadline)) + '截止'
                : '还剩 ' + dayjs().to(dayjs(deadline), true)
              : dayjs().isAfter(dayjs(deadline))
              ? 'closed ' + dayjs().to(dayjs(deadline))
              : 'due in ' + dayjs().to(dayjs(deadline), true)}
          </Caption>
          <Caption style={styles.caption}>
            {dayjs(deadline).format(
              isLocaleChinese()
                ? 'YYYY 年 M 月 D 日 dddd HH:mm'
                : 'ddd, MMM D, YYYY HH:mm',
            )}
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
                {dayjs(submitTime).format(
                  isLocaleChinese()
                    ? isLateSubmission
                      ? 'YYYY 年 M 月 D 日 dddd HH:mm 补交'
                      : 'YYYY 年 M 月 D 日 dddd HH:mm 提交'
                    : isLateSubmission
                    ? '[submitted late at] HH:mm, MMM D, YYYY'
                    : '[submitted at] HH:mm, MMM D, YYYY',
                )}
              </Caption>
            )}
            {removeTags(submittedContent) ? (
              <Text style={styles.submittedContent}>
                {removeTags(submittedContent)}
              </Text>
            ) : null}
            {submittedAttachment && (
              <List.Item
                title={submittedAttachment.name}
                description={t('attachment')}
                left={props => <List.Icon {...props} icon="file-check" />}
                onPress={() => {
                  // TODO: Implement file download/open
                }}
              />
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
              {gradeLevel || grade}
            </Text>
            {removeTags(gradeContent) ? (
              <Text style={styles.gradeContent}>
                {removeTags(gradeContent)}
              </Text>
            ) : null}
            {gradeTime && (
              <Caption>
                {dayjs(gradeTime).format(
                  isLocaleChinese()
                    ? graderName
                      ? `YYYY 年 M 月 D 日 dddd HH:mm 由${graderName}批改`
                      : 'YYYY 年 M 月 D 日 dddd HH:mm 批改'
                    : graderName
                    ? `[graded by ${graderName} at] HH:mm, MMM D, YYYY`
                    : '[graded at] HH:mm, MMM D, YYYY',
                )}
              </Caption>
            )}
            {gradeAttachment && (
              <List.Item
                title={gradeAttachment.name}
                description={t('attachment')}
                left={props => <List.Icon {...props} icon="file-certificate" />}
                onPress={() => {
                  // TODO: Implement file download/open
                }}
              />
            )}
          </View>
        </>
      )}

      {(answerContent || answerAttachment) && (
        <>
          <Divider />
          <View style={styles.section}>
            {removeTags(answerContent) ? (
              <Text style={styles.answerContent}>
                {removeTags(answerContent)}
              </Text>
            ) : null}
            {answerAttachment && (
              <List.Item
                title={answerAttachment.name}
                description={t('attachment')}
                left={props => <List.Icon {...props} icon="key" />}
                onPress={() => {
                  // TODO: Implement file download/open
                }}
              />
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
  chip: {
    marginBottom: 8,
    marginRight: 8,
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
  answerContent: {
    marginTop: 8,
    color: Colors.blue500,
  },
});

export default AssignmentDetail;
