import React, {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
} from 'react';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import DocumentPicker from '@react-native-ohos/react-native-document-picker';
import { launchImageLibrary } from '@react-native-ohos/react-native-image-picker';
import {
  Alert,
  Keyboard,
  KeyboardAvoidingView,
  StyleSheet,
  TouchableWithoutFeedback,
  View,
} from 'react-native';
import {
  Button,
  Caption,
  Portal,
  ProgressBar,
  Snackbar,
  TextInput,
  useTheme,
} from 'react-native-paper';
import dayjs from 'dayjs';
import mimeTypes from 'mime-types';
import type { RemoteFile } from 'thu-learn-lib';
import SafeArea from 'components/SafeArea';
import TextButton from 'components/TextButton';
import ScrollView from 'components/ScrollView';
import Styles from 'constants/Styles';
import { getExtension, stripExtension } from 'helpers/fs';
import { removeTags } from 'helpers/html';
import { isLocaleChinese, t } from 'helpers/i18n';
import { useAppDispatch, useAppSelector } from 'data/store';
import type { File } from 'data/types/state';
import { submitAssignment } from 'data/source';
import {
  getAssignmentsForCourse,
  setPendingAssignmentData,
} from 'data/actions/assignments';
import useToast from 'hooks/useToast';
import type { AssignmentSubmissionStackParams } from './types';

type Props = NativeStackScreenProps<
  AssignmentSubmissionStackParams,
  'AssignmentSubmission'
>;

interface AttachmentResult {
  uri: string;
  type: string | null;
  name: string;
  size?: number | null;
}

const AssignmentSubmission: React.FC<Props> = ({ navigation, route }) => {
  const theme = useTheme();
  const toast = useToast();

  const {
    id,
    courseId,
    courseName,
    studentHomeworkId,
    title,
    submitTime,
    submittedAttachment,
    submittedContent,
  } = route.params;

  const dispatch = useAppDispatch();

  const pendingAssignmentData = useAppSelector(
    state => state.assignments.pendingAssignmentData,
  );

  const [content, setContent] = useState(
    (removeTags(submittedContent || '') ?? '').replace('-->', ''),
  );
  const [customAttachmentName, setCustomAttachmentName] = useState('');
  const [attachmentResult, setAttachmentResult] =
    useState<AttachmentResult | null>(null);
  const [removeAttachment, setRemoveAttachment] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState(false);
  const [progress, setProgress] = useState(0);

  const inputRef = useRef<any>(null);

  const getDefaultAttachmentName = useCallback(
    (mimeType?: string | null) => {
      const ext =
        mimeTypes.extension(mimeType ?? 'application/octet-stream') || 'bin';
      return isLocaleChinese()
        ? `${title}-提交.${ext}`
        : `${title} Submission.${ext}`;
    },
    [title],
  );

  const handleCustomAttachmentNameChange = (text: string) => {
    setCustomAttachmentName(text.replaceAll('.', ''));
  };

  const handleUploadedAttachmentRemove = () => {
    setRemoveAttachment(!removeAttachment);
  };

  const handlePickedAttachmentRemove = () => {
    setAttachmentResult(null);
    dispatch(setPendingAssignmentData(null));
  };

  const handleDocumentPick = async () => {
    try {
      const result = await DocumentPicker.pick({
        type: [DocumentPicker.types.allFiles],
      });
      if (!result || result.length === 0) {
        return;
      }

      const file = result[0];
      setAttachmentResult({
        uri: file.uri,
        type: file.type ?? null,
        name: file.name ?? getDefaultAttachmentName(file.type),
        size: file.size,
      });
      dispatch(setPendingAssignmentData(null));
    } catch (err) {
      if (DocumentPicker.isCancel(err)) {
        return;
      }
      toast(t('filePickFailed'), 'error');
    }
  };

  const handlePhotoPick = async () => {
    try {
      const result = await launchImageLibrary({
        mediaType: 'mixed',
        selectionLimit: 1,
      });
      if (result.didCancel) {
        return;
      }
      const photos = result.assets;
      if (!photos || photos.length === 0) {
        throw new Error('No photo picked');
      }

      const photo = photos[0];
      setAttachmentResult({
        uri: photo.uri ?? '',
        type: photo.type ?? null,
        name: photo.fileName ?? getDefaultAttachmentName(photo.type),
        size: photo.fileSize,
      });
      dispatch(setPendingAssignmentData(null));
    } catch {
      toast(t('filePickFailed'), 'error');
    }
  };

  const handleFileOpen = (
    attachment?: RemoteFile & { type?: string | null },
  ) => {
    if (attachment) {
      navigation.push('FileDetail', {
        id,
        courseName,
        title: stripExtension(attachment.name),
        downloadUrl: attachment.downloadUrl,
        fileType:
          (attachment.type
            ? mimeTypes.extension(attachment.type)
            : getExtension(attachment.name)) ?? '',
      } as File);
    }
  };

  const handleSubmit = useCallback(async () => {
    setUploadError(false);
    setUploading(true);

    try {
      if (removeAttachment) {
        await submitAssignment(
          studentHomeworkId,
          '',
          undefined,
          setProgress,
          true,
        );
      } else if (content || attachmentResult) {
        const replaceName = (name: string) => {
          const customName = customAttachmentName.trim();
          if (!customName) {
            return name;
          }
          const ext = getExtension(name);
          return `${customName}.${ext}`;
        };

        await submitAssignment(
          studentHomeworkId,
          content,
          attachmentResult
            ? {
                uri: attachmentResult.uri,
                name: replaceName(attachmentResult.name),
              }
            : undefined,
          setProgress,
        );
      }

      setUploading(false);
      setProgress(0);

      dispatch(setPendingAssignmentData(null));
      dispatch(getAssignmentsForCourse(courseId));

      toast(t('assignmentSubmissionSucceeded'), 'success');
      navigation.goBack();
    } catch {
      setUploading(false);
      setUploadError(true);
      setProgress(0);
    }
  }, [
    attachmentResult,
    content,
    courseId,
    customAttachmentName,
    dispatch,
    navigation,
    removeAttachment,
    studentHomeworkId,
    toast,
  ]);

  const handleSubmitPress = useCallback(() => {
    Keyboard.dismiss();

    Alert.alert(
      t('submitAssignment'),
      t('submitAssignmentConfirmation'),
      [
        {
          text: t('cancel'),
          style: 'cancel',
        },
        {
          text: t('ok'),
          onPress: handleSubmit,
        },
      ],
      { cancelable: true },
    );
  }, [handleSubmit]);

  useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: () => (
        <TextButton
          disabled={
            uploading || (!removeAttachment && !content && !attachmentResult)
          }
          containerStyle={{ marginRight: 16 }}
          style={{ fontSize: 17, fontWeight: 'bold' }}
          onPress={handleSubmitPress}
        >
          {t('submit')}
        </TextButton>
      ),
    });
  }, [
    attachmentResult,
    content,
    handleSubmitPress,
    navigation,
    removeAttachment,
    uploading,
  ]);

  useEffect(() => {
    if (pendingAssignmentData) {
      setAttachmentResult({
        uri: pendingAssignmentData.data,
        type: pendingAssignmentData.mimeType,
        name: getDefaultAttachmentName(pendingAssignmentData.mimeType),
      });
    }
  }, [getDefaultAttachmentName, pendingAssignmentData]);

  return (
    <Portal.Host>
      <SafeArea>
        <KeyboardAvoidingView
          style={Styles.flex1}
          behavior={'padding'}
        >
          {progress ? <ProgressBar progress={progress} /> : null}
          <ScrollView
            contentContainerStyle={styles.scrollView}
            keyboardShouldPersistTaps="handled"
          >
            <TouchableWithoutFeedback onPress={() => inputRef.current?.focus()}>
              <View style={Styles.flex1}>
                <TextInput
                  ref={inputRef}
                  style={Styles.flex1}
                  contentStyle={Styles.flex1}
                  disabled={removeAttachment || uploading}
                  multiline
                  textAlignVertical="top"
                  placeholder={t('assignmentSubmissionContentPlaceholder')}
                  value={content}
                  onChangeText={setContent}
                />
              </View>
            </TouchableWithoutFeedback>
            {attachmentResult && (
              <TextInput
                disabled={removeAttachment || uploading}
                placeholder={t('assignmentSubmissionFilenamePlaceholder')}
                value={customAttachmentName}
                onChangeText={handleCustomAttachmentNameChange}
              />
            )}
          </ScrollView>
          <View style={styles.submissionDetail}>
            {submittedAttachment ? (
              <TextButton
                disabled={uploading}
                style={
                  attachmentResult || removeAttachment
                    ? {
                        textDecorationLine: 'line-through',
                        color: theme.colors.onSurfaceDisabled,
                      }
                    : undefined
                }
                containerStyle={[styles.attachmentButton, Styles.spacey1]}
                onPress={() => handleFileOpen(submittedAttachment)}
              >
                {submittedAttachment.name}
              </TextButton>
            ) : undefined}
            {!removeAttachment && attachmentResult ? (
              <TextButton
                containerStyle={[styles.attachmentButton, Styles.spacey1]}
                disabled={uploading}
                onPress={() =>
                  handleFileOpen({
                    id: '0000',
                    name: attachmentResult.name,
                    downloadUrl: attachmentResult.uri,
                    previewUrl: attachmentResult.uri,
                    size: attachmentResult.size
                      ? attachmentResult.size + 'B'
                      : '',
                    type: attachmentResult.type,
                  })
                }
              >
                {attachmentResult.name}{' '}
                {pendingAssignmentData
                  ? isLocaleChinese()
                    ? '（之前分享的）'
                    : '(previously shared)'
                  : ''}
              </TextButton>
            ) : undefined}
            <View style={styles.attachmentActionButtons}>
              {submittedAttachment ? (
                <Button
                  disabled={uploading}
                  mode="contained"
                  style={styles.submitButton}
                  onPress={handleUploadedAttachmentRemove}
                >
                  {removeAttachment
                    ? t('undoRemoveUploadedAttachment')
                    : t('removeUploadedAttachment')}
                </Button>
              ) : undefined}
              {attachmentResult && !removeAttachment ? (
                <Button
                  disabled={uploading}
                  mode="contained"
                  style={styles.submitButton}
                  onPress={handlePickedAttachmentRemove}
                >
                  {t('removePickedAttachment')}
                </Button>
              ) : undefined}
              {!removeAttachment ? (
                <>
                  <Button
                    style={styles.submitButton}
                    disabled={uploading}
                    mode="contained"
                    onPress={handleDocumentPick}
                  >
                    {t('documents')}
                  </Button>
                  <Button
                    style={styles.submitButton}
                    disabled={uploading}
                    mode="contained"
                    onPress={handlePhotoPick}
                  >
                    {t('photos')}
                  </Button>
                </>
              ) : undefined}
            </View>
            {submitTime && (
              <Caption style={Styles.spacey1}>
                {dayjs(submitTime).format(
                  isLocaleChinese()
                    ? '上次提交于 YYYY 年 M 月 D 日 dddd HH:mm'
                    : '[last submitted at] HH:mm, MMM D, YYYY',
                )}
              </Caption>
            )}
          </View>
        </KeyboardAvoidingView>
        <Snackbar
          visible={uploadError}
          duration={3000}
          onDismiss={() => setUploadError(false)}
        >
          {t('assignmentSubmissionFailed')}
        </Snackbar>
      </SafeArea>
    </Portal.Host>
  );
};

const styles = StyleSheet.create({
  scrollView: {
    flexGrow: 1,
  },
  submissionDetail: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    marginBottom: 96,
  },
  attachmentButton: {
    flex: 0,
  },
  submitButton: {
    alignSelf: 'flex-start',
    marginRight: 8,
  },
  attachmentActionButtons: {
    flexWrap: 'wrap',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginVertical: 8,
  },
});

export default AssignmentSubmission;
