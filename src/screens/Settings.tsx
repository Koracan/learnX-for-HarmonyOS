import React from 'react';
import { Alert, Linking, StyleSheet } from 'react-native';
import type { StackScreenProps } from '@react-navigation/stack';
import SafeArea from 'components/SafeArea';
import TableCell from 'components/TableCell';
import ScrollView from 'components/ScrollView';
import { clearStore } from 'data/actions/root';
import { useAppDispatch, useAppSelector } from 'data/store';
import { clearLoginCookies, dataSource } from 'data/source';
import useDetailNavigator from 'hooks/useDetailNavigator';
import { t } from 'helpers/i18n';
import env from 'helpers/env';
import { type SettingsStackParams } from './types';

type Props = StackScreenProps<SettingsStackParams, 'Settings'>;

/**
 * 设置屏幕：显示用户设置和应用偏好。
 */
const Settings: React.FC<Props> = ({ navigation }) => {
  const detailNavigatorRef = useDetailNavigator();
  const dispatch = useAppDispatch();
  const userInfo = useAppSelector(state => state.user);
  const username = useAppSelector(state => state.auth.username);
  const isMockUser = username === env.DUMMY_USERNAME;

  const handlePush = (name: keyof SettingsStackParams) => {
    if (detailNavigatorRef?.current) {
      detailNavigatorRef.current.navigate(name as any, {
        disableAnimation: true,
      });
    } else {
      navigation.push(name, { disableAnimation: false } as any);
    }
  };

  const handleLogout = () => {
    Alert.alert(
      t('logout'),
      t('logoutConfirmation'),
      [
        {
          text: t('cancel'),
          style: 'cancel',
        },
        {
          text: t('ok'),
          onPress: () => {
            dataSource.logout();
            clearLoginCookies();
            dispatch(clearStore());
          },
        },
      ],
      { cancelable: true },
    );
  };

  return (
    <SafeArea>
      <ScrollView style={styles.flex1}>
        <TableCell
          imageAlt={userInfo.name ?? username ?? 'learnX'}
          primaryText={userInfo.name ?? username ?? 'learnX'}
          secondaryText={userInfo.department ?? undefined}
          type="none"
        />
        <TableCell
          iconName="person-remove"
          primaryText={t('logout')}
          type="none"
          onPress={handleLogout}
        />
        {!isMockUser ? (
          <TableCell
            style={styles.marginTop}
            iconName="fullscreen"
            primaryText={t('immersiveMode')}
            type="arrow"
            onPress={() => handlePush('ImmersiveSettings')}
          />
        ) : null}
        <TableCell
          style={styles.marginTop}
          iconName="loop"
          primaryText={t('semesterSelection')}
          type="arrow"
          onPress={() => handlePush('SemesterSelection')}
        />
        <TableCell
          iconName="rule-folder"
          primaryText={t('fileSettings')}
          type="arrow"
          onPress={() => handlePush('FileSettings')}
        />
        <TableCell
          style={styles.marginTop}
          iconName="policy"
          primaryText={t('privacyPolicy')}
          type="arrow"
          onPress={() =>
            Linking.openURL(
              'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=1864655084378428992',
            )
          }
        />
        <TableCell
          iconName="help"
          primaryText={t('helpAndFeedback')}
          type="arrow"
          onPress={() => handlePush('Help')}
        />
        <TableCell
          iconName="copyright"
          primaryText={t('about')}
          type="arrow"
          onPress={() => handlePush('About')}
        />
      </ScrollView>
    </SafeArea>
  );
};

const styles = StyleSheet.create({
  flex1: {
    flex: 1,
  },
  marginTop: {
    marginTop: 16,
  },
});

export default Settings;
