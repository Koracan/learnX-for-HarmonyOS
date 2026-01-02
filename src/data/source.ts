import CookieManager from '@react-native-cookies/cookies';
import { Learn2018Helper, addCSRFTokenToUrl } from 'thu-learn-lib';
import { store } from '../data/store';
import Urls from '../constants/Urls';
import { LearnOHDataProcessor } from 'react-native-learn-oh-data-processor';
import mime from 'mime-types';
import { DeviceEventEmitter } from 'react-native';

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
      return fetch(url, {
        ...options,
        headers: {
          ...options?.headers,
          'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      });
    },
    provider: () => {
      const state = store.getState();
      return {
        username: state.auth.username || undefined,
        password: state.auth.password || undefined,
        fingerPrint: state.auth.fingerPrint || '',
        fingerGenPrint: state.auth.fingerGenPrint || '',
        fingerGenPrint3: state.auth.fingerGenPrint3 || '',
      };
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
    // This will use the provider to fetch credentials and login
    await dataSource.login();
    const creds = await getCredentials();
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

  await loginWithFingerPrint();

  try {
    const url = addCSRF(submitAssignmentUrl);
    const cookies = await CookieManager.get(Urls.learn);
    const cookieString = Object.keys(cookies)
      .map(key => `${key.trim()}=${cookies[key].value}`)
      .join('; ');
    const csrfToken = dataSource.getCSRFToken();

    const params = {
      xszyid: studentHomeworkId,
      zynr: content || '',
      isDeleted: remove ? '1' : '0',
    };

    let filePath: string | undefined;
    if (attachment) {
      filePath = attachment.uri.replace('file://', '');
    }

    const requestId = `upload_${Date.now()}`;
    const subscription = DeviceEventEmitter.addListener(
      'LearnOHUploadProgress',
      e => {
        if (e.requestId === requestId && onProgress && e.total > 0) {
          onProgress?.(
            parseFloat((e.total ? e.loaded / e.total : 0).toFixed(2)),
          );
        }
      },
    );

    let resultStr: string;
    try {
      resultStr = await LearnOHDataProcessor.post(
        url,
        cookieString,
        csrfToken,
        JSON.stringify(params),
        filePath,
        attachment?.name,
        attachment
          ? mime.lookup(attachment.name) || 'application/octet-stream'
          : undefined,
        requestId,
      );
    } finally {
      subscription.remove();
    }

    let resData: any;
    try {
      resData = JSON.parse(resultStr);
    } catch (e) {
      if (!resultStr || resultStr.includes('error')) {
        throw new Error('Failed to submit the assignment: invalid response');
      }
      return;
    }

    if (resData?.result === 'error') {
      throw new Error('Failed to submit the assignment: ' + resData?.msg);
    }
  } catch (e: any) {
    console.error('[submitAssignment] error:', e.message);
    throw e;
  }
};
