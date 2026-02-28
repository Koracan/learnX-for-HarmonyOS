import React from 'react';
import { StyleSheet } from 'react-native';
import { type StackScreenProps } from '@react-navigation/stack';
import { Text } from 'react-native-paper';
import SafeArea from 'components/SafeArea';
import TableCell from 'components/TableCell';
import ScrollView from 'components/ScrollView';
import { setSetting } from 'data/actions/settings';
import { useAppDispatch, useAppSelector } from 'data/store';
import { t } from 'helpers/i18n';
import useNavigationAnimation from 'hooks/useNavigationAnimation';
import { type SettingsStackParams } from './types';

type Props = StackScreenProps<SettingsStackParams, 'ImmersiveSettings'>;

const ImmersiveSettings: React.FC<Props> = props => {
  useNavigationAnimation(props as any);
  const dispatch = useAppDispatch();
  const immersiveMode = useAppSelector(state => state.settings.immersiveMode);
  const immersiveAvoidFrontCamera = useAppSelector(
    state => state.settings.immersiveAvoidFrontCamera,
  );

  const handleImmersiveToggle = (value: boolean) => {
    dispatch(setSetting('immersiveMode', value));
    if (!value && immersiveAvoidFrontCamera) {
      dispatch(setSetting('immersiveAvoidFrontCamera', false));
    }
  };

  return (
    <SafeArea>
      <ScrollView contentContainerStyle={styles.scrollViewPaddings}>
        <TableCell
          iconName="fullscreen"
          primaryText={t('immersiveMode')}
          type="switch"
          switchValue={immersiveMode}
          onSwitchValueChange={handleImmersiveToggle}
        />
        <Text style={styles.caption}>{t('immersiveModeDescription')}</Text>
        <TableCell
          style={styles.marginTop}
          iconName="center-focus-strong"
          primaryText={t('avoidFrontCamera')}
          type="switch"
          switchValue={immersiveMode && immersiveAvoidFrontCamera}
          switchDisabled={!immersiveMode}
          onSwitchValueChange={value =>
            dispatch(setSetting('immersiveAvoidFrontCamera', value))
          }
        />
        <Text style={styles.caption}>{t('avoidFrontCameraDescription')}</Text>
      </ScrollView>
    </SafeArea>
  );
};

const styles = StyleSheet.create({
  marginTop: {
    marginTop: 24,
  },
  scrollViewPaddings: {
    paddingVertical: 16,
  },
  caption: {
    fontSize: 12,
    marginTop: 4,
    marginHorizontal: 16,
    opacity: 0.6,
  },
});

export default ImmersiveSettings;
