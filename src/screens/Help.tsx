import React from 'react';
import { Linking, StyleSheet } from 'react-native';
import { type NativeStackScreenProps } from '@react-navigation/native-stack';
import { Title, Text, useTheme } from 'react-native-paper';
import SafeArea from 'components/SafeArea';
import ScrollView from 'components/ScrollView';
import { t } from 'helpers/i18n';
import { type SettingsStackParams } from './types';

type Props = NativeStackScreenProps<SettingsStackParams, 'Help'>;

const Help: React.FC<Props> = () => {
  const theme = useTheme();

  return (
    <SafeArea>
      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollViewPaddings}
      >
        <Title>{t('githubRecommended')}</Title>
        <Text
          style={[styles.text, { color: theme.colors.primary }]}
          onPress={() =>
            Linking.openURL(
              'https://github.com/Koracan/learnX-for-HarmonyOS/issues/new/choose',
            )
          }
        >
          {t('createNewGitHubIssue')}
        </Text>
        <Title style={styles.marginTop}>{t('emailNotRecommended')}</Title>
        <Text
          style={[styles.text, { color: theme.colors.primary }]}
          onPress={() => Linking.openURL('mailto:koracan@163.com')}
        >
          koracan@163.com
        </Text>
        <Title style={styles.marginTop}>{t('issueTemplate')}</Title>
        <Text style={styles.text}>{t('issueTemplateDescription')}</Text>
        <Text style={styles.text}>{t('issueTemplateContent')}</Text>
      </ScrollView>
    </SafeArea>
  );
};

const styles = StyleSheet.create({
  marginTop: {
    marginTop: 24,
  },
  scrollView: {
    paddingHorizontal: 24,
  },
  scrollViewPaddings: {
    paddingVertical: 16,
  },
  text: {
    marginTop: 8,
  },
});

export default Help;
