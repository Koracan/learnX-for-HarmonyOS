/*
 * 文件落盘路径与展示文本的纯规则 —— **零平台依赖**（见 scripts/check-domain-purity.mjs）。
 *
 * 逐条移植参考实现 `reference/learnOH-old/src/helpers/fs.ts`：
 *
 * | 参考实现 | 出处 | 这里 |
 * | --- | --- | --- |
 * | `getLearnXFilesDir()` = `(fileUseDocumentDir ? DocumentDirectoryPath : CachesDirectoryPath) + '/learnX-files'` | fs.ts:26-33 | `learnXFilesRoot()`（两个根目录由调用方从 Context 取） |
 * | `dir = root + '/' + file.courseName + '/' + file.id` | fs.ts:54 | `fileDirectory()` |
 * | `fileOmitCourseName ? title : courseName + '-' + title`（再拼 `.${fileType}`） | fs.ts:59-63 | `localFileName()` |
 * | `formatSize(bytes)` | fs.ts:15-21 | `formatSize()`（逐字，含 `<= 0 → '0 B'` 与两位小数） |
 * | 卡片上的 `TYPE SIZE` 一行 | FileCard.tsx:70-75 | `fileMetaLine()` |
 *
 * ## 两条有意加固（**不是**参考实现的行为，逐条写清理由）
 *
 * 1. **目录名/缓存键兜底**：参考实现用 `file.id` 当目录名；真实数据里作业附件的
 *    `id` 可能是**空串**（下载地址是路径形态，没有 `fileId=`/`wjid=` 参数，
 *    见 ticket 10 的边界说明第 2 条）。空串当目录名会把不同文件全落进同一层
 *    `root/<课程名>/`，互相覆盖。`cacheKeyFor()` 因此兜底到 downloadUrl 的末段。
 * 2. **路径分隔符清洗**：标题里若含 `/` 会把路径切成两层（参考实现也会，但那是 bug
 *    而非契约）；清洗只动**文件系统保留字符**，中文与空格**原样保留**（验收第 4 条
 *    明确要求"含中文与空格的路径可用"，所以绝不能做"把非 ASCII 换掉"这类清洗）。
 */

/** 文件类型（预览能力的分档）。 */
export enum FileKind {
  PDF = 'pdf',
  IMAGE = 'image',
  OTHER = 'other'
}

/**
 * 参考实现 `canRenderInWebview`（helpers/html.ts:123-127）的同一组扩展名，
 * 加上它单独处理的 `pdf`（FileDetail.tsx:61-62 的 `canRender`）。
 */
const IMAGE_EXTENSIONS: string[] = ['jpg', 'jpeg', 'png', 'gif', 'svg', 'bmp', 'webp'];

/** 落盘根目录名（参考实现 `learnX-files`，逐字）。 */
export const LEARNX_FILES_DIR_NAME: string = 'learnX-files';

/** 兜底文件名：下载地址末段也取不到时用它（绝不产生空串路径）。 */
export const FALLBACK_FILE_NAME: string = 'file';

/** 扩展名 → 分档。 */
export function fileKindOf(fileType: string): FileKind {
  const type: string = fileType === undefined || fileType === null ? '' : fileType.toLowerCase().trim();
  if (type === 'pdf') {
    return FileKind.PDF;
  }
  if (IMAGE_EXTENSIONS.includes(type)) {
    return FileKind.IMAGE;
  }
  return FileKind.OTHER;
}

/**
 * 能否在应用内预览。
 *
 * 参考实现把 pdf 交给 react-native-pdf、
 * 把图片交给 WebView（都是应用内），但它的"打开"动作是 `FileViewer.open`（跳系统）。
 * 这里 pdf/图片一律在应用内渲染；"打开"（交给系统打开方式）是顶栏另一个按钮，与预览互不影响。
 */
export function canPreviewInApp(fileType: string): boolean {
  return fileKindOf(fileType) !== FileKind.OTHER;
}

/**
 * 清洗单个路径片段：只替换文件系统保留字符与控制字符。
 *
 * **中文、空格、点、括号、方括号一律保留** —— 验收第 4 条要求含中文与空格的路径可用，
 * 所以这里不做任何"安全化到 ASCII"的转换。
 */
export function sanitizePathSegment(text: string): string {
  const raw: string = text === undefined || text === null ? '' : text;
  let out: string = '';
  for (let i = 0; i < raw.length; i++) {
    const ch: string = raw.charAt(i);
    const code: number = raw.charCodeAt(i);
    if (code < 32 || ch === '/' || ch === '\\' || ch === ':' || ch === '*' || ch === '?'
      || ch === '"' || ch === '<' || ch === '>' || ch === '|') {
      out += '_';
      continue;
    }
    out += ch;
  }
  const trimmed: string = out.trim();
  return trimmed.length === 0 ? FALLBACK_FILE_NAME : trimmed;
}

/** 下载地址的文件名部分（去 query / fragment 后取最后一段，并解码百分号转义）。 */
export function downloadUrlFileName(url: string): string {
  if (url === undefined || url === null || url.length === 0) {
    return '';
  }
  let cut: string = url;
  const hash: number = cut.indexOf('#');
  if (hash >= 0) {
    cut = cut.substring(0, hash);
  }
  const query: number = cut.indexOf('?');
  if (query >= 0) {
    cut = cut.substring(0, query);
  }
  const slash: number = cut.lastIndexOf('/');
  const last: string = slash >= 0 ? cut.substring(slash + 1) : cut;
  if (last.length === 0) {
    return '';
  }
  try {
    return decodeURIComponent(last);
  } catch (error) {
    return last;
  }
}

/**
 * 缓存目录名 / 去重键：优先用站点给出的 id，**id 为空串时兜底到下载地址末段**
 * （ticket 10 边界说明第 2 条：作业附件的 id 可能是空串）。
 */
export function cacheKeyFor(id: string, downloadUrl: string): string {
  const trimmed: string = id === undefined || id === null ? '' : id.trim();
  if (trimmed.length > 0) {
    return sanitizePathSegment(trimmed);
  }
  const fromUrl: string = downloadUrlFileName(downloadUrl);
  return sanitizePathSegment(fromUrl.length > 0 ? fromUrl : FALLBACK_FILE_NAME);
}

/** 落盘根目录：`(使用文档目录 ? filesDir : cacheDir) + '/learnX-files'`（照参考实现）。 */
export function learnXFilesRoot(filesDir: string, cacheDir: string, useDocumentDir: boolean): string {
  const base: string = useDocumentDir ? filesDir : cacheDir;
  return stripTrailingSeparator(base) + '/' + LEARNX_FILES_DIR_NAME;
}

function stripTrailingSeparator(path: string): string {
  let out: string = path;
  while (out.length > 1 && (out.endsWith('/') || out.endsWith('\\'))) {
    out = out.substring(0, out.length - 1);
  }
  return out;
}

/** 单条文件的缓存目录：`root/<课程名>/<缓存键>`（照参考实现 fs.ts:54）。 */
export function fileDirectory(root: string, courseName: string, cacheKey: string): string {
  return stripTrailingSeparator(root) + '/' + sanitizePathSegment(courseName) + '/' + cacheKey;
}

/**
 * 文件名：`fileOmitCourseName ? title : courseName + '-' + title`，再拼 `.${fileType}`。
 * 没有扩展名时不拼点（照参考实现 `fileType ? `.${fileType}` : ''`）。
 */
export function localFileName(courseName: string, title: string, fileType: string, omitCourseName: boolean): string {
  const base: string = omitCourseName ? title : courseName + '-' + title;
  const extension: string = fileType === undefined || fileType === null ? '' : fileType.trim();
  const withExtension: string = extension.length > 0 ? base + '.' + extension : base;
  return sanitizePathSegment(withExtension);
}

/** 完整落盘路径。 */
export function localFilePath(root: string, courseName: string, cacheKey: string, title: string,
  fileType: string, omitCourseName: boolean): string {
  return fileDirectory(root, courseName, cacheKey) + '/'
    + localFileName(courseName, title, fileType, omitCourseName);
}

/**
 * 体积文本。逐字移植参考实现 helpers/fs.ts:15-21（含 `bytes <= 0 → '0 B'`
 * 与 `parseFloat(toFixed(2))` 去尾零）。
 */
export function formatSize(bytes: number): string {
  if (bytes <= 0) {
    return '0 B';
  }
  const k: number = 1024;
  const sizes: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
  const index: number = Math.floor(Math.log(bytes) / Math.log(k));
  return Number.parseFloat((bytes / Math.pow(k, index)).toFixed(2)).toString() + ' ' + sizes[index];
}

/**
 * 列表卡片上的一行元信息：`TYPE SIZE`（验收第 1 条"显示大小与类型"）。
 * 参考实现是 `[`${category}`, `${fileType.toUpperCase()}`, `${size}`].join(' ').trim()`；
 * 本工程没有 category，故只拼类型与体积，空的那一项不留下多余空格。
 */
export function fileMetaLine(fileType: string, size: string): string {
  const parts: string[] = [];
  const type: string = fileType === undefined || fileType === null ? '' : fileType.trim();
  const volume: string = size === undefined || size === null ? '' : size.trim();
  if (type.length > 0) {
    parts.push(type.toUpperCase());
  }
  if (volume.length > 0) {
    parts.push(volume);
  }
  return parts.join(' ');
}
