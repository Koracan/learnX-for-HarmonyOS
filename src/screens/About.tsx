import React from 'react';
import { Linking, StyleSheet } from 'react-native';
import { type NativeStackScreenProps } from '@react-navigation/native-stack';
import { Title, Text, useTheme } from 'react-native-paper';
import DeviceInfo from 'constants/DeviceInfo';
import SafeArea from 'components/SafeArea';
import ScrollView from 'components/ScrollView';
import { t } from 'helpers/i18n';
import { type SettingsStackParams } from './types';
const packageJson = require('../../package.json');

type Props = NativeStackScreenProps<SettingsStackParams, 'About'>;

const About: React.FC<Props> = () => {
  const theme = useTheme();

  return (
    <SafeArea>
      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollViewPaddings}
      >
        <Title>{t('versionInformation')}</Title>
        <Text style={styles.text}>
          {`v${packageJson.version} (build ${DeviceInfo.buildNo()})`}
        </Text>
        <Text style={styles.text}>© 2026 Han Wong</Text>
        <Text
          style={[styles.text, { color: theme.colors.primary }]}
          onPress={() => Linking.openURL('https://beian.miit.gov.cn/')}
        >
          京ICP备2026001019号-1A
        </Text>
        <Title style={styles.marginTop}>{t('maintainers')}</Title>
        <Text
          style={[styles.text, { color: theme.colors.primary }]}
          onPress={() => Linking.openURL('https://github.com/Koracan')}
        >
          Han Wong (Koracan)
        </Text>
        <Text style={styles.text}>
          {t('opensourceAt')}{' '}
          <Text
            style={{ color: theme.colors.primary }}
            onPress={() =>
              Linking.openURL('https://github.com/Koracan/learnX-for-HarmonyOS')
            }
          >
            Koracan/learnX-for-HarmonyOS
          </Text>
        </Text>
        <Title style={styles.marginTop}>{t('specialThanks')}</Title>
        
        <Text style={styles.text}>
          {'Rui Ying'}{' '}
          <Text
            style={{ color: theme.colors.primary }}
            onPress={() =>
              Linking.openURL('https://github.com/robertying/learnX')
            }
          >
            robertying/learnX
          </Text>
        </Text>

        <Text style={styles.text}>
          {t('harryChen')}{' '}
          <Text
            style={{ color: theme.colors.primary }}
            onPress={() =>
              Linking.openURL('https://github.com/Harry-Chen/thu-learn-lib')
            }
          >
            Harry-Chen/thu-learn-lib
          </Text>
        </Text>
        <Title style={styles.marginTop}>{t('opensourceDependencies')}</Title>
        {Object.keys(packageJson.dependencies).map(name => (
          <Text key={name} style={styles.text}>
            {name}
          </Text>
        ))}
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

export default About;
