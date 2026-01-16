import fs from 'react-native-fs';
import FileViewer from 'react-native-file-viewer';
import Share from 'react-native-share';
import CookieManager from '@react-native-cookies/cookies';
import mime from 'mime-types';
import { store } from 'data/store';
import type { File } from 'data/types/state';
import { addCSRF, loginWithFingerPrint } from 'data/source';
import Urls from 'constants/Urls';

/**
 * 格式化文件大小。
 */
export const formatSize = (bytes: number): string => {
  if (bytes <= 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(2))} ${sizes[i]}`;
};

/**
 * 获取 LearnX 文件存储根目录。
 */
export const getLearnXFilesDir = () => {
  const settings = store.getState().settings;
  // HarmonyOS 下 DownloadDirectoryPath 不可用，优先使用 DocumentDirectoryPath 或 CachesDirectoryPath
  const baseDir = settings.fileUseDocumentDir
    ? fs.DocumentDirectoryPath
    : fs.CachesDirectoryPath;
  return `${baseDir}/learnX-files`;
};

/**
 * 下载文件。
 */
export const downloadFile = async (
  file: File,
  refresh?: boolean,
  onProgress?: (progress: number) => void,
) => {
  console.log(
    `[fs] Starting download for file: ${file.title} (ID: ${file.id})`,
  );

  let url = file.downloadUrl;
  if (url.startsWith('file://') || url.startsWith('content://')) {
    console.log(`[fs] File already local: ${url}`);
    return url;
  }

  const settings = store.getState().settings;
  const dir = `${getLearnXFilesDir()}/${file.courseName}/${file.id}`;

  console.log(`[fs] Target directory: ${dir}`);
  await fs.mkdir(dir);

  let path = settings.fileOmitCourseName
    ? `${dir}/${file.title}${file.fileType ? `.${file.fileType}` : ''}`
    : `${dir}/${file.courseName}-${file.title}${
        file.fileType ? `.${file.fileType}` : ''
      }`;

  if (!refresh && (await fs.exists(path))) {
    console.log(`[fs] downloadFile: File already exists at: ${path}`);
    return path;
  }

  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    console.error(`[fs] Invalid URL: ${url}`);
    throw new Error('Invalid file url');
  }

  if (refresh) {
    console.log(`[fs] Refreshing login...`);
    await loginWithFingerPrint();
  }
  url = addCSRF(url);

  // 获取 Cookie
  const cookies = await CookieManager.get(Urls.learn);
  const cookiesString = Object.values(cookies)
    .map(({ name, value }) => `${name}=${value}`)
    .join('; ');

  const downloadPromise = fs.downloadFile({
    fromUrl: url,
    toFile: path,
    headers: {
      Cookie: cookiesString,
      'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    },
    begin: res => {
      console.log(
        `[fs] Download started. JobID: ${res.jobId}, ContentLength: ${res.contentLength}`,
      );
    },
    progress: result => {
      if (result.contentLength > 0) {
        onProgress?.(
          parseFloat((result.bytesWritten / result.contentLength).toFixed(2)),
        );
      }
    },
  });

  try {
    const result = await downloadPromise.promise;
    console.log(
      `[fs] Download finished. Status: ${result.statusCode}, Bytes: ${result.bytesWritten}`,
    );

    // HarmonyOS 库缺陷：bytesWritten 始终返回 0，我们需要手动检查文件大小
    const stat = await fs.stat(path);
    console.log(`[fs] Actual file size on disk: ${stat.size} bytes`);

    // 错误处理
    if (result.statusCode !== 200 || stat.size === 0) {
      try {
        await fs.unlink(path);
      } catch {}

      console.error(
        `[fs] Download failed with status: ${result.statusCode}, file size: ${stat.size}`,
      );
      throw new Error('Download failed');
    }

    // 检查是否为 HTML 页面（通常意味着下载失败，返回了登录页或错误页）
    if (stat.size < 5000) {
      // 登录页通常比较小
      const content = await fs.readFile(path, 'utf8');
      if (
        content.includes('location.href') ||
        content.includes('<!DOCTYPE html') ||
        content.includes('<html')
      ) {
        console.error(
          `[fs] Downloaded file is an HTML page, deleting: ${path}`,
        );
        try {
          await fs.unlink(path);
        } catch {}
        throw new Error('Download failed: session expired or invalid');
      }
    }

    console.log(`[fs] File successfully downloaded to: ${path}`);
    return path;
  } catch (e) {
    console.error(`[fs] Download error:`, e);
    throw e;
  }
};

/**
 * 打开文件。
 */
export const openFile = async (path: string) => {
  try {
    console.log(`[fs] Opening file with FileViewer: ${path}`);
    await FileViewer.open(path, { showOpenWithDialog: true });
  } catch (e) {
    console.error(`[fs] Open file failed:`, e);
    throw new Error('Open file failed');
  }
};

/**
 * 分享文件。
 */
export const shareFile = async (file: File) => {
  const path = await downloadFile(file, false);

  try {
    await Share.open({
      url: `file://${path}`,
      type:
        (file.fileType && mime.lookup(file.fileType)) ||
        'application/octet-stream',
      title: '分享文件',
      showAppsToView: true,
      failOnCancel: false,
    });
  } catch (e) {
    console.error('[fs] Share error:', e);
  }
};

/**
 * 清除文件缓存目录。
 */
export const removeFileDir = async () => {
  const dir = getLearnXFilesDir();
  if (await fs.exists(dir)) {
    await fs.unlink(dir);
  }
};

/**
 * 获取文件扩展名。
 */
export const getExtension = (filename: string) => {
  const parts = filename.split('.');
  return parts.length > 1 ? parts.pop() : undefined;
};

/**
 * 移除文件扩展名。
 */
export const stripExtension = (filename: string) => {
  const parts = filename.split('.');
  return parts.length > 1 ? parts.slice(0, -1).join('.') : filename;
};
