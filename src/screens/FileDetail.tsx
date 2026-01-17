import React, {
  useCallback,
  useContext,
  useEffect,
  useLayoutEffect,
  useState,
} from 'react';
import { StyleSheet, View, InteractionManager } from 'react-native';
import {
  useTheme,
  Text,
  ProgressBar,
  Title,
  Caption,
  Divider,
  Chip,
  ActivityIndicator,
} from 'react-native-paper';
import type { StackScreenProps } from '@react-navigation/stack';
import Icon from 'react-native-vector-icons/MaterialIcons';
import WebView from 'react-native-webview';
import Pdf from 'react-native-pdf';
import dayjs from 'dayjs';
import Styles from 'constants/Styles';
import { downloadFile, openFile, shareFile, formatSize } from 'helpers/fs';
import { isLocaleChinese, t } from 'helpers/i18n';
import { canRenderInWebview, needWhiteBackground } from 'helpers/html';
import useToast from 'hooks/useToast';
import useNavigationAnimation from 'hooks/useNavigationAnimation';
import type { FileStackParams } from 'screens/types';
import SafeArea from 'components/SafeArea';
import IconButton from 'components/IconButton';
import ScrollView from 'components/ScrollView';
import fs from 'react-native-fs';
import { SplitViewContext } from 'components/SplitView';
import { removeTags } from 'helpers/html';

type Props = StackScreenProps<FileStackParams, 'FileDetail'>;

const FileDetail: React.FC<Props> = ({ route, navigation }) => {
  useNavigationAnimation({ route, navigation } as any);
  const file = route.params;
  const theme = useTheme();
  const toast = useToast();
  const { showDetail, showMaster, toggleMaster } = useContext(SplitViewContext);

  const [path, setPath] = useState('');
  const [progress, setProgress] = useState(0);
  const [error, setError] = useState(false);
  const [fileSize, setFileSize] = useState(file.size);
  const [showInfo, setShowInfo] = useState(false);
  const [isReady, setIsReady] = useState(false);

  useEffect(() => {
    const task = InteractionManager.runAfterInteractions(() => {
      setIsReady(true);
    });
    return () => task.cancel();
  }, []);

  const canRender =
    path && (file.fileType === 'pdf' || canRenderInWebview(file.fileType));

  const handleDownload = useCallback(
    async (refresh: boolean) => {
      setPath('');
      setError(false);
      try {
        const downloadedPath = await downloadFile(file, refresh, setProgress);
        setPath(downloadedPath);
        setProgress(0);
        
        // Update file size after download
        const stat = await fs.stat(downloadedPath);
        setFileSize(formatSize(stat.size));
      } catch (e) {
        setError(true);
        toast(t('fileDownloadFailed'), 'error');
      }
    },
    [file, toast],
  );

  const handleOpen = useCallback(async () => {
    try {
      await openFile(path);
    } catch (e) {
      toast(t('openFileFailed'), 'error');
    }
  }, [path, toast]);

  const handleShare = useCallback(async () => {
    try {
      await shareFile(file);
    } catch (e) {
      console.error('[FileDetail] Share error:', e);
    }
  }, [file]);

  const handleToggleInfo = useCallback(() => {
    setShowInfo(prev => !prev);
  }, []);

  useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: () => (
        <View style={[Styles.flexRow, { justifyContent: 'flex-end' }]}>
          {showDetail && (
            <IconButton
              onPress={() => toggleMaster(!showMaster)}
              icon={showMaster ? 'fullscreen' : 'fullscreen-exit'}
            />
          )}
          <IconButton icon="refresh" onPress={() => handleDownload(true)} />
          <IconButton
            disabled={error || !path}
            onPress={handleShare}
            icon="share"
          />
          <IconButton
            disabled={error || !path}
            onPress={handleOpen}
            icon="open-in-new"
          />
          {canRender && (
            <IconButton
              disabled={error || !path}
              onPress={handleToggleInfo}
              icon={props => (
                <Icon {...props} name={showInfo ? 'preview' : 'info-outline'} />
              )}
            />
          )}
        </View>
      ),
    });
  }, [
    navigation,
    handleDownload,
    handleShare,
    handleOpen,
    handleToggleInfo,
    error,
    path,
    canRender,
    showInfo,
    showDetail,
    showMaster,
    toggleMaster,
  ]);

  useEffect(() => {
    handleDownload(false);
  }, [handleDownload]);

  return (
    <SafeArea>
      {error ? (
        <View style={styles.errorRoot}>
          <Icon name="error" color={theme.colors.outline} size={56} />
          <Text style={{ color: theme.colors.outline, marginTop: 8 }}>
            {t('fileDownloadFailed')}
          </Text>
        </View>
      ) : !path || !isReady ? (
        <View style={Styles.flexCenter}>
          <ActivityIndicator />
        </View>
      ) : !showInfo && canRender ? (
        file.fileType === 'pdf' ? (
          <Pdf
            style={Styles.flex1}
            source={{ uri: path }}
            fitPolicy={0}
          />
        ) : (
          <WebView
            style={{
              flex: 1,
              backgroundColor: needWhiteBackground(file.fileType)
                ? 'white'
                : 'transparent',
            }}
            source={{ uri: `file://${path}` }}
            originWhitelist={['*']}
            allowFileAccess={true}
          />
        )
      ) : (
        <>
          <ScrollView
            contentContainerStyle={{ paddingBottom: 100 }}
            style={{ backgroundColor: theme.colors.surface }}
          >
            <View style={styles.section}>
              <View style={Styles.flexRowCenter}>
                {file.category?.title && (
                  <Chip compact mode="outlined" style={styles.categoryChip}>
                    {file.category.title}
                  </Chip>
                )}
              </View>
              <Title>{removeTags(file.title)}</Title>
              <View style={Styles.flexRowCenter}>
                {file.uploadTime && (
                  <Caption>
                    {dayjs(file.uploadTime).format(
                      isLocaleChinese()
                        ? 'YYYY 年 M 月 D 日 dddd HH:mm'
                        : 'MMM D, YYYY HH:mm',
                    )}
                  </Caption>
                )}
              </View>
            </View>
            <Divider />
            <View style={[styles.section, styles.iconButton]}>
              <Icon
                style={styles.icon}
                name="insert-drive-file"
                color={theme.colors.primary}
                size={17}
              />
              <Text style={styles.textPaddingRight}>
                {file.fileType?.toUpperCase()}
              </Text>
            </View>
            <Divider />
            <View style={[styles.section, styles.iconButton]}>
              <Icon
                style={styles.icon}
                name="file-download"
                color={theme.colors.primary}
                size={17}
              />
              <Text style={styles.textPaddingRight}>
                {fileSize || t('noFileSize')}
              </Text>
            </View>
            <Divider />
            <Text style={styles.description}>
              {file.description || t('noFileDescription')}
            </Text>
          </ScrollView>
          <View
            style={[styles.actions, { backgroundColor: theme.colors.surface }]}
          >
            <View style={styles.colCenter}>
              <IconButton icon="share" size={48} onPress={handleShare} />
              <Text>{t('share')}</Text>
            </View>
            <View style={styles.colCenter}>
              <IconButton icon="open-in-new" size={48} onPress={handleOpen} />
              <Text>{t('open')}</Text>
            </View>
          </View>
        </>
      )}
      {progress > 0 ? (
        <ProgressBar
          style={styles.progressBar}
          progress={progress}
          color={theme.colors.primary}
        />
      ) : null}
    </SafeArea>
  );
};

const styles = StyleSheet.create({
  progressBar: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    zIndex: 99,
    height: 4,
  },
  skeletons: {
    flex: 1,
  },
  errorRoot: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  caption: {
    marginLeft: 8,
  },
  actions: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    paddingBottom: 16,
    opacity: 0.95,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: 'rgba(0,0,0,0.1)',
  },
  colCenter: {
    alignItems: 'center',
    marginHorizontal: 24,
  },
  section: {
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  textPaddingRight: {
    paddingRight: 16,
  },
  icon: {
    marginRight: 8,
  },
  iconButton: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  description: {
    padding: 16,
    fontSize: 16,
    lineHeight: 24,
  },
  categoryChip: {
    marginBottom: 8,
  },
});

export default FileDetail;
