import React, { useRef, useState } from 'react';
import { Platform, StyleSheet } from 'react-native';
import { ProgressBar } from 'react-native-paper';
import WebView, { type WebViewMessageEvent } from 'react-native-webview';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { OnShouldStartLoadWithRequest } from 'react-native-webview/lib/WebViewTypes';
import { useAppDispatch } from 'data/store';
import { login, setSSOInProgress } from 'data/actions/auth';
import useToast from 'hooks/useToast';
import type { RootStackParams } from './types';
import packageJson from '../../package.json';

const ssoCustomScript = require('../helpers/preval/sso.preval.js');

const SSO_LOGIN_URL =
  'https://id.tsinghua.edu.cn/do/off/ui/auth/login/form/bb5df85216504820be7bba2b0ae1535b/0';
const LEARN_ROAMING_URL =
  'https://learn.tsinghua.edu.cn/f/j_spring_security_thauth_roaming_entry';

type Props = NativeStackScreenProps<RootStackParams, 'SSO'>;

/**
 * SSO 页面：加载统一认证 WebView，拦截指纹提交后回调登录。
 */
const SSO: React.FC<Props> = ({ route, navigation }) => {
  const dispatch = useAppDispatch();
  const toast = useToast();
  const username = route.params.username;
  const password = route.params.password;

  const [progress, setProgress] = useState(0);
  const fingerPrint = useRef(
    'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
      const r = (Math.random() * 16) | 0;
      const v = c === 'x' ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    }),
  );
  const formData = useRef<{
    username: string;
    password: string;
    fingerPrint: string;
    fingerGenPrint: string;
    fingerGenPrint3: string;
  } | null>(null);

  const injectedJs = ssoCustomScript
    .replaceAll('${username}', username)
    .replaceAll("'${password}'", JSON.stringify(password))
    .replaceAll('${fingerPrint}', fingerPrint.current)
    .replaceAll('${deviceName}', `HarmonyOS,learnX/${packageJson.version}`);

  const handleShouldStartLoadWithRequest: OnShouldStartLoadWithRequest = e => {
    if (!e.url.startsWith(LEARN_ROAMING_URL)) return true;

    if (!formData.current) {
      toast('SSO login failed', 'error');
    } else {
      dispatch(login({ ...formData.current, reset: true }));
    }

    dispatch(setSSOInProgress(false));
    navigation.goBack();

    return false;
  };

  const handleMessage = (event: WebViewMessageEvent) => {
    try {
      const { type, data } = JSON.parse(event.nativeEvent.data);
      if (type === 'JQUERY_SUBMIT' && data.formId === 'theform') {
        formData.current = {
          username,
          password,
          fingerPrint: data.requestBody.fingerPrint,
          fingerGenPrint: data.requestBody.fingerGenPrint,
          fingerGenPrint3: data.requestBody.fingerGenPrint3,
        };
      }
    } catch (e) {
      console.error('Failed to parse WebView message:', e);
    }
  };

  return (
    <>
      {progress && progress !== 1 ? <ProgressBar progress={progress} /> : null}
      <WebView
        style={styles.webview}
        source={{ uri: SSO_LOGIN_URL, headers: { Cookie: '' } }}
        decelerationRate={Platform.OS === 'ios' ? 'normal' : undefined}
        onLoadProgress={({ nativeEvent }) =>
          setProgress(parseFloat(nativeEvent.progress.toFixed(2)))
        }
        onShouldStartLoadWithRequest={handleShouldStartLoadWithRequest}
        injectedJavaScript={injectedJs}
        onMessage={handleMessage}
      />
    </>
  );
};

const styles = StyleSheet.create({
  webview: { backgroundColor: 'transparent' },
});

export default SSO;
