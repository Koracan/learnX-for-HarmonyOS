import React, { useEffect, useRef, useState } from 'react';
import { Linking } from 'react-native';
import WebView from 'react-native-webview';
import type { WebViewProps } from 'react-native-webview';
import type {
  WebViewMessageEvent,
  WebViewNavigation,
  WebViewSource,
  WebViewSourceHtml,
} from 'react-native-webview/lib/WebViewTypes';
import CookieManager from '@react-native-cookies/cookies';
import Urls from 'constants/Urls';

/**
 * 自适应高度的 WebView：用于渲染公告 HTML 内容。
 */
const AutoHeightWebView: React.FC<
  React.PropsWithChildren<WebViewProps>
> = props => {
  const [height, setHeight] = useState(1);
  const [cookieString, setCookieString] = useState('');
  const webViewRef = useRef<WebView>(null);

  const injectedScript = `
    function waitForBridge() {
      if (!window.ReactNativeWebView?.postMessage) {
        setTimeout(waitForBridge, 50);
      } else {
        const h = Math.max(
          document.documentElement?.clientHeight || 0,
          document.documentElement?.scrollHeight || 0,
          document.body?.clientHeight || 0,
          document.body?.scrollHeight || 0,
        );
        window.ReactNativeWebView.postMessage(h.toString());
      }
    }
    window.addEventListener('load', waitForBridge);
    waitForBridge();
    true;
  `;

  const onMessage = (e: WebViewMessageEvent) => {
    const measured = parseInt(e.nativeEvent.data, 10);
    if (!Number.isNaN(measured) && measured > 0) {
      setHeight(measured);
    }
  };

  const onNavigationStateChange = (e: WebViewNavigation) => {
    if (e.navigationType === 'click') {
      webViewRef.current?.stopLoading();
      Linking.openURL(e.url);
    }
  };

  useEffect(() => {
    (async () => {
      const cookies = await CookieManager.get(Urls.learn);
      await Promise.all(
        Object.entries(cookies).map(([, value]) =>
          CookieManager.set(Urls.learn, value, true),
        ),
      );
      setCookieString(
        Object.entries(cookies)
          .map(([key, value]) => `${key}=${value.value}`)
          .join('; '),
      );
    })();
  }, []);

  return (
    <WebView
      ref={webViewRef}
      injectedJavaScriptBeforeContentLoaded={injectedScript}
      onMessage={onMessage}
      javaScriptEnabled
      showsHorizontalScrollIndicator={false}
      showsVerticalScrollIndicator={false}
      onNavigationStateChange={onNavigationStateChange}
      originWhitelist={['*']}
      sharedCookiesEnabled
      {...props}
      source={
        {
          baseUrl: (props.source as WebViewSourceHtml | undefined)?.html
            ? Urls.learn
            : undefined,
          headers: {
            Cookie: cookieString,
          },
          ...props.source,
        } as WebViewSource
      }
      style={[
        {
          height,
          backgroundColor: 'transparent',
          opacity: 1,
          minHeight: 1,
        },
        props.style,
      ]}
    />
  );
};

export default AutoHeightWebView;
