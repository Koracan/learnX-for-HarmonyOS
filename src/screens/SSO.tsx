import React, { useRef, useState } from 'react';
import { Platform, StyleSheet } from 'react-native';
import { ProgressBar } from 'react-native-paper';
import WebView, { WebViewMessageEvent } from 'react-native-webview';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { OnShouldStartLoadWithRequest } from 'react-native-webview/lib/WebViewTypes';
import { useAppDispatch } from 'data/store';
import { login, setSSOInProgress } from 'data/actions/auth';
import useToast from 'hooks/useToast';
import type { RootStackParams } from './types';

const SSO_LOGIN_URL =
  'https://id.tsinghua.edu.cn/do/off/ui/auth/login/form/bb5df85216504820be7bba2b0ae1535b/0';
const LEARN_ROAMING_URL =
  'https://learn.tsinghua.edu.cn/f/j_spring_security_thauth_roaming_entry';

type Props = NativeStackScreenProps<RootStackParams, 'SSO'>;

const SSO: React.FC<Props> = ({ route, navigation }) => {
  const dispatch = useAppDispatch();
  const toast = useToast();
  const username = route.params.username;
  const password = route.params.password;

  const [progress, setProgress] = useState(0);
  const fingerPrint = useRef(
    'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
      const r = Math.random() * 16 | 0;
      const v = c === 'x' ? r : (r & 0x3 | 0x8);
      return v.toString(16);
    })
  );
  const formData = useRef<{
    username: string;
    password: string;
    fingerPrint: string;
    fingerGenPrint: string;
    fingerGenPrint3: string;
  } | null>(null);

  const injectedJs = `
    (function () {
      'use strict';

      const sendToReactNative = (type, data) => {
        window?.ReactNativeWebView?.postMessage?.(JSON.stringify({ type, data }));
      };

      // Intercept XMLHttpRequest to inject fingerprint/deviceName when server saves finger
      const origOpen = XMLHttpRequest.prototype.open;
      const origSend = XMLHttpRequest.prototype.send;

      XMLHttpRequest.prototype.open = function (method, url, ...rest) {
        this._url = url;
        this._method = method;
        return origOpen.apply(this, [method, url, ...rest]);
      };

      XMLHttpRequest.prototype.send = function (body) {
        if (
          this._url === '/b/doubleAuth/personal/saveFinger' &&
          typeof body === 'string'
        ) {
          const params = new URLSearchParams(body);
          params.set('fingerprint', '${fingerPrint.current}');
          params.set('deviceName', 'HarmonyOS,learnX/harmony');
          params.set('radioVal', '是');
          body = params.toString();
        }

        this._body = body;
        this.addEventListener('load', () => {
          // sendToReactNative('XHR_RESPONSE', { method: this._method, url: this._url, status: this.status, requestBody: this._body, response: this.responseText });
        });

        return origSend.apply(this, [body]);
      };

      const setupLoginPage = () => {
        const usernameInput = document.querySelector('input#i_user');
        const passwordInput = document.querySelector('input#i_pass');

        if (!usernameInput || !passwordInput) {
          return false;
        }

        usernameInput.value = '${username}';
        usernameInput.readOnly = true;

        passwordInput.value = ${JSON.stringify(password)};
        passwordInput.readOnly = true;

        return true;
      };

      const overrideJQuerySubmit = () => {
        if (window.jQuery && !window.jQuery.fn.submit.isOverridden) {
          const originalSubmit = window.jQuery.fn.submit;

          window.jQuery.fn.submit = function () {
            const formElement = this[0];

            const fingerPrintField = formElement.querySelector('[name="fingerPrint"]');
            if (fingerPrintField) {
              fingerPrintField.value = '${fingerPrint.current}';
            }

            const singleLoginField = formElement.querySelector('[name="singleLogin"]');
            if (singleLoginField && !singleLoginField.checked) {
              singleLoginField.click();
            }

            const formData = new FormData(formElement);
            const requestBody = Object.fromEntries(formData.entries());

            sendToReactNative('JQUERY_SUBMIT', {
              formId: formElement.id,
              requestBody: requestBody,
            });

            return originalSubmit.apply(this, arguments);
          };

          window.jQuery.fn.submit.isOverridden = true;
        }
      };

      const jqueryChecker = setInterval(() => {
        if (window.jQuery) {
          clearInterval(jqueryChecker);
          overrideJQuerySubmit();
        }
      }, 100);

      const runAllTasks = () => {
        setupLoginPage();
      };

      const observer = new MutationObserver(() => {
        observer.disconnect();
        runAllTasks();
        observer.observe(document.documentElement, {
          childList: true,
          subtree: true,
        });
      });
      observer.observe(document.documentElement, {
        childList: true,
        subtree: true,
      });

      runAllTasks();

      return true;
    })();
  `;

  const handleShouldStartLoadWithRequest: OnShouldStartLoadWithRequest = (e) => {
    if (!e.url.startsWith(LEARN_ROAMING_URL)) return true;

     console.log('[SSO] Intercepted LEARN_ROAMING_URL, formData:', formData.current);

    if (!formData.current) {
      // Something went wrong
       console.log('[SSO] No form data, showing error toast');
      toast('SSO login failed', 'error');
    } else {
       console.log('[SSO] Dispatching login action with:', {
         username: formData.current.username,
         fingerPrint: formData.current.fingerPrint,
       });
      dispatch(login({ ...formData.current, reset: true }));
    }

    dispatch(setSSOInProgress(false));
    navigation.goBack();

    return false;
  };

  const handleMessage = (event: WebViewMessageEvent) => {
    try {
      const { type, data } = JSON.parse(event.nativeEvent.data);
       console.log('[SSO] Received message:', type, data);
      if (type === 'JQUERY_SUBMIT' && data.formId === 'theform') {
        formData.current = {
          username,
          password,
          fingerPrint: data.requestBody.fingerPrint,
          fingerGenPrint: data.requestBody.fingerGenPrint,
          fingerGenPrint3: data.requestBody.fingerGenPrint3,
        };
         console.log('[SSO] Form data captured:', formData.current);
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
        onLoadProgress={({ nativeEvent }) => setProgress(parseFloat(nativeEvent.progress.toFixed(2)))}
        onShouldStartLoadWithRequest={handleShouldStartLoadWithRequest}
        injectedJavaScript={injectedJs}
        onMessage={handleMessage}
      />
    </>
  );
};

const styles = StyleSheet.create({ webview: { backgroundColor: 'transparent' } });

export default SSO;
