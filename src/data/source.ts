import CookieManager from '@react-native-cookies/cookies';
import { Learn2018Helper, addCSRFTokenToUrl } from 'thu-learn-lib';
import { store } from '../data/store';
import Urls from '../constants/Urls';
import { LearnOHDataProcessor } from 'react-native-learn-oh-data-processor';
import axios from 'axios';
import mime from 'mime-types';

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

/**
 * Wrapper for Native TurboModule requests to handle automatic re-authentication.
 * Similar to thu-learn-lib's withReAuth mechanism.
 */
const withNativeReAuth = async <T>(
  task: (cookieString: string, csrfToken: string) => Promise<T>,
): Promise<T> => {
  const getCredentials = async () => {
    const cookies = await CookieManager.get(Urls.learn);
    const cookieString = Object.keys(cookies)
      .map(key => `${key}=${cookies[key].value}`)
      .join('; ');
    const csrfToken = dataSource.getCSRFToken();
    return { cookieString, csrfToken };
  };

  const { cookieString, csrfToken } = await getCredentials();
  let result = await task(cookieString, csrfToken);

  // Detect noLogin:
  // 1. result is a string and contains login_timeout
  // 2. result is a string and starts with < (HTML login page)
  if (
    typeof result === 'string' &&
    (result.includes('login_timeout') || result.trim().startsWith('<'))
  ) {
    console.log(
      '[withNativeReAuth] Session expired detected, re-logging in...',
    );
    // This will use the provider to fetch credentials and login
    await dataSource.login();
    const creds = await getCredentials();
    console.log(
      '[withNativeReAuth] Re-login successful, retrying native task...',
    );
    result = await task(creds.cookieString, creds.csrfToken);
  }

  return result;
};

export const fetchAssignmentsWithReAuth = (courseIds: string[]) =>
  withNativeReAuth((cookie, token) =>
    LearnOHDataProcessor.fetchAssignments(courseIds, cookie, token),
  );

export const fetchNoticesWithReAuth = (courseIds: string[]) =>
  withNativeReAuth((cookie, token) =>
    LearnOHDataProcessor.fetchNotices(courseIds, cookie, token),
  );

export const fetchFilesWithReAuth = (courseIds: string[]) =>
  withNativeReAuth((cookie, token) =>
    LearnOHDataProcessor.fetchFiles(courseIds, cookie, token),
  );

const submitAssignmentUrl = `${Urls.learn}/b/wlxt/kczy/zy/student/tjzy`;

export const submitAssignment = async (
  studentHomeworkId: string,
  content?: string,
  attachment?: {
    uri: string;
    name: string;
  },
  onProgress?: (progress: number) => void,
  remove: boolean = false,
) => {
  if (!content && !attachment && !remove) {
    return;
  }

  const body = new FormData();
  body.append('xszyid', studentHomeworkId);
  body.append('zynr', content || '');
  body.append('isDeleted', remove ? '1' : '0');
  if (attachment) {
    body.append('fileupload', {
      uri: attachment.uri,
      name: attachment.name,
      type: mime.lookup(attachment.uri) || 'application/octet-stream',
    } as any);
  }

  try {
    await dataSource.login();
  } catch {
    throw new Error('Failed to submit the assignment: login failed');
  }

  const cookies = await CookieManager.get(Urls.learn);
  const cookieString = Object.keys(cookies)
    .map(key => `${key}=${cookies[key].value}`)
    .join('; ');

  const response = await axios.post(
    addCSRFTokenToUrl(submitAssignmentUrl, dataSource.getCSRFToken()),
    body,
    {
      headers: {
        'Content-Type': 'multipart/form-data',
        Cookie: cookieString,
      },
      onUploadProgress: progressEvent => {
        if (onProgress && progressEvent.total) {
          onProgress(progressEvent.loaded / progressEvent.total);
        }
      },
    },
  );

  if (response.data.result !== 'success') {
    throw new Error(response.data.msg || 'Failed to submit the assignment');
  }
};
