import CookieManager from '@react-native-cookies/cookies';
import { Learn2018Helper, addCSRFTokenToUrl } from 'thu-learn-lib';
import { store } from 'data/store';
import Urls from 'constants/Urls';

export let dataSource: Learn2018Helper;

export const clearLoginCookies = async () => {
  try {
    // HarmonyOS cookies may persist unexpectedly; clear all for safety
    await CookieManager.clearAll(true);
  } catch (e) {
    console.warn('[clearLoginCookies] clearAll failed:', e);
  }
  try {
    await CookieManager.set(Urls.id, {
      httpOnly: true,
      name: 'JSESSIONID',
      path: '/',
      value: '',
    });
  } catch (e) {
    console.warn('[clearLoginCookies] set JSESSIONID failed:', e);
  }
};

export const loginWithFingerPrint = async (
  username?: string,
  password?: string,
  fingerPrint?: string,
  fingerGenPrint?: string,
  fingerGenPrint3?: string,
) => {
  await clearLoginCookies();

  console.log('[login debug] BigInt available:', typeof BigInt !== 'undefined');

  await dataSource.login(
    username,
    password,
    fingerPrint,
    fingerGenPrint,
    fingerGenPrint3,
  );
};

export const resetDataSource = () => {
  dataSource = new Learn2018Helper({
    fetch: async (url, options) => {
      const response = await fetch(url, {
        ...options,
        headers: {
          ...options?.headers,
          'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      });

      // 调试登录页面内容
      if (url.toString().includes('id.tsinghua.edu.cn/do/login')) {
        const clone = response.clone();
        const text = await clone.text();
        console.log(`[login debug] Page snippet: ${text.substring(0, 1000)}`);
        if (text.includes('sm2publicKey')) {
          console.log('[login debug] sm2publicKey found in page');
        } else {
          console.warn('[login debug] sm2publicKey NOT found in page!');
        }
      }

      return response;
    },
    provider: () => {
      const state = store.getState();
      const creds = {
        username: state.auth.username || undefined,
        password: state.auth.password || undefined,
        fingerPrint: state.auth.fingerPrint || '',
        fingerGenPrint: state.auth.fingerGenPrint || '',
        fingerGenPrint3: state.auth.fingerGenPrint3 || '',
      };
      console.log('[dataSource provider] Providing credentials:', {
        hasUsername: !!creds.username,
        hasPassword: !!creds.password,
        hasFingerprint: !!creds.fingerPrint,
      });
      return creds;
    },
  });
};

resetDataSource();

export const addCSRF = (url: string) => {
  if (new URL(url).hostname?.endsWith('tsinghua.edu.cn')) {
    console.log(`[fs] Adding CSRF token to URL: ${url}`);
    return addCSRFTokenToUrl(url, dataSource.getCSRFToken());
  }
  return url;
};
