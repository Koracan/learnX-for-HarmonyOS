import React from 'react';
import { Alert, StyleSheet } from 'react-native';
import { StackActions } from '@react-navigation/native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import SafeArea from 'components/SafeArea';
import TableCell from 'components/TableCell';
import ScrollView from 'components/ScrollView';
import { setSetting } from 'data/actions/settings';
import { clearStore } from 'data/actions/root';
import { useAppDispatch, useAppSelector } from 'data/store';
import { clearLoginCookies, dataSource } from 'data/source';
import useDetailNavigator from 'hooks/useDetailNavigator';
import { t } from 'helpers/i18n';
import { type SettingsStackParams } from './types';

type Props = NativeStackScreenProps<SettingsStackParams, 'Settings'>;

/**
 * 设置屏幕：显示用户设置和应用偏好。
 */
const Settings: React.FC<Props> = ({ navigation }) => {
  const detailNavigator = useDetailNavigator();
  const dispatch = useAppDispatch();
  const userInfo = useAppSelector(state => state.user);
  const username = useAppSelector(state => state.auth.username);
  const settings = useAppSelector(state => state.settings);

  const handlePush = (name: keyof SettingsStackParams) => {
    if (detailNavigator) {
      detailNavigator.dispatch(
        StackActions.replace(name, {
          disableAnimation: true,
        }),
      );
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

  const handleImmersiveToggle = (value: boolean) => {
    dispatch(setSetting('immersiveMode', value));
    Alert.alert(
      t('restartRequired'),
      t('pleaseRestartAppToApplyImmersive'),
      [{ text: t('ok') }],
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
        <TableCell
          style={styles.marginTop}
          iconName="fullscreen"
          primaryText={t('immersiveMode')}
          type="switch"
          switchValue={settings.immersiveMode}
          onSwitchValueChange={handleImmersiveToggle}
        />
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
