import React, { useCallback } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { Card, Text, Switch, Button } from 'react-native-paper';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { SettingsStackParams } from 'screens/types';
import { useAppDispatch, useAppSelector } from 'data/store';
import { setSetting } from 'data/actions/settings';

type Props = NativeStackScreenProps<SettingsStackParams, 'Settings'>;

/**
 * 设置屏幕：显示用户设置和应用偏好。
 */
const Settings: React.FC<Props> = ({ navigation }) => {
  const insets = useSafeAreaInsets();
  const dispatch = useAppDispatch();
  const auth = useAppSelector(state => state.auth);
  const settings = useAppSelector(state => state.settings);

  const handleStatusBarToggle = useCallback(
    (value: boolean) => {
      dispatch(setSetting('statusBarHidden', value));
    },
    [dispatch],
  );

  return (
    <View style={[styles.container, { paddingTop: insets.top }]}>
      <ScrollView contentContainerStyle={styles.scrollContent}>
        {/* 用户信息区域 */}
        <Card style={styles.card}>
          <Card.Content>
            <Text variant="titleMedium">{auth.username || 'User'}</Text>
            <Text variant="bodySmall" style={styles.secondaryText}>
              账户信息
            </Text>
          </Card.Content>
        </Card>

        {/* 显示/隐藏状态栏 - 可用功能 */}
        <Card style={styles.card}>
          <Card.Title title="显示/隐藏状态栏" />
          <Card.Content>
            <View style={styles.settingRow}>
              <Text variant="bodyMedium">隐藏状态栏</Text>
              <Switch
                value={settings.statusBarHidden}
                onValueChange={handleStatusBarToggle}
              />
            </View>
            <Text variant="bodySmall" style={styles.secondaryText}>
              {settings.statusBarHidden
                ? '状态栏已隐藏（沉浸式体验）'
                : '状态栏显示中'}
            </Text>
          </Card.Content>
        </Card>

        {/* 主题选择 - 占位 */}
        <Card style={styles.card}>
          <Card.Title title="主题" />
          <Card.Content>
            <Text variant="bodyMedium">跟随系统</Text>
            <Text variant="bodySmall" style={styles.secondaryText}>
              即将推出更多主题选项
            </Text>
          </Card.Content>
        </Card>

        {/* 关于 - 占位 */}
        <Card style={styles.card}>
          <Card.Title title="关于" />
          <Card.Content>
            <Button mode="text" onPress={() => {}}>
              查看更多信息
            </Button>
          </Card.Content>
        </Card>

        {/* 登出按钮 - 占位 */}
        <Card style={styles.card}>
          <Card.Content>
            <Button mode="contained" onPress={() => {}}>
              登出
            </Button>
          </Card.Content>
        </Card>

        {/* 底部间距 */}
        <View style={{ height: 40 }} />
      </ScrollView>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  scrollContent: {
    padding: 12,
    paddingBottom: 20,
    gap: 12,
  },
  card: {
    marginBottom: 0,
  },
  settingRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginVertical: 8,
  },
  secondaryText: {
    marginTop: 4,
    opacity: 0.7,
  },
});

export default Settings;
