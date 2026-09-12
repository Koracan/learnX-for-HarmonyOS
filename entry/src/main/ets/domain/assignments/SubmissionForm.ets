/*
 * 作业提交的表单规则 —— **纯函数，零平台依赖**（见 scripts/check-domain-purity.mjs）。
 *
 * 逐条对齐参考实现 `reference/learnOH-old/src/screens/AssignmentSubmission.tsx`：
 *
 * | 规则 | 参考实现 | 出处 |
 * | --- | --- | --- |
 * | 默认附件名 | 中文 `<title>-提交.<ext>`、英文 `<title> Submission.<ext>`；ext 由 MIME 推，推不出用 `bin` | :96-105 |
 * | 自定义附件名 | 只在"即将上传的新附件"存在时出现；输入时去掉**所有** `.` | :107-109 |
 * | 上传时拼回扩展名 | `${customName}.${getExtension(原文件名)}` | :203-210 |
 * | 提交按钮可用性 | `disabled = uploading \|\| (!removeAttachment && !content && !attachment)` | :274-276 |
 * | 表单字段 | `xszyid` / `zynr` / `isDeleted` | src/data/source.ts:175-179 |
 * | 无正文且无附件且不移除 | **直接返回，不发请求** | src/data/source.ts:161-163 |
 * | 正文初值 | `removeTags(submittedContent)?.replace('-->','')` | :83-85 |
 *
 * 这一层只放**可 host 单测**的纯逻辑；取串、弹窗、picker、网络都在上层。
 */

/**
 * 一个"即将上传的新附件"（来自文件管理器或相册）。
 *
 * 参考实现是 `AttachmentResult`（:53-58，`uri/type/name/size`）。这里把 `type` 改名
 * `mimeType` 并**收紧为必填**：平台侧拿不到 MIME 时由上层按扩展名补齐，
 * 因为 multipart 的 `Content-Type` 必须有一个值（缺省 `application/octet-stream`）。
 */
export interface PickedAttachment {
  /** 平台给的本地 URI（picker 的返回值原样传下去）。 */
  uri: string;
  /** 展示名（用于默认文件名与 multipart 的 `filename`）。 */
  name: string;
  /** MIME 类型（multipart 文件部分的 `Content-Type`）。 */
  mimeType: string;
  /** 字节数（平台给不出时填 0；只用于展示，不参与组装）。 */
  size: number;
}

/** 扩展名 → MIME 的一对映射（顺序无关，查找是线性扫）。 */
interface MimeEntry {
  extension: string;
  mimeType: string;
}

/**
 * 扩展名 → MIME 表。
 *
 * 参考实现用 npm 的 `mime-types`（`mime.lookup(name)`）；ArkTS 侧没有这个包，
 * 故按本工程真正会遇到的文件类型列一张**闭集**，查不到一律
 * `application/octet-stream`（与参考实现的 `|| 'application/octet-stream'` 同一条兜底）。
 */
const EXTENSION_TO_MIME: MimeEntry[] = [
  { extension: 'pdf', mimeType: 'application/pdf' },
  { extension: 'doc', mimeType: 'application/msword' },
  { extension: 'docx', mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' },
  { extension: 'xls', mimeType: 'application/vnd.ms-excel' },
  { extension: 'xlsx', mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' },
  { extension: 'ppt', mimeType: 'application/vnd.ms-powerpoint' },
  { extension: 'pptx', mimeType: 'application/vnd.openxmlformats-officedocument.presentationml.presentation' },
  { extension: 'txt', mimeType: 'text/plain' },
  { extension: 'md', mimeType: 'text/markdown' },
  { extension: 'csv', mimeType: 'text/csv' },
  { extension: 'json', mimeType: 'application/json' },
  { extension: 'xml', mimeType: 'application/xml' },
  { extension: 'html', mimeType: 'text/html' },
  { extension: 'zip', mimeType: 'application/zip' },
  { extension: 'rar', mimeType: 'application/vnd.rar' },
  { extension: '7z', mimeType: 'application/x-7z-compressed' },
  { extension: 'gz', mimeType: 'application/gzip' },
  { extension: 'tar', mimeType: 'application/x-tar' },
  { extension: 'png', mimeType: 'image/png' },
  { extension: 'jpg', mimeType: 'image/jpeg' },
  { extension: 'jpeg', mimeType: 'image/jpeg' },
  { extension: 'gif', mimeType: 'image/gif' },
  { extension: 'bmp', mimeType: 'image/bmp' },
  { extension: 'webp', mimeType: 'image/webp' },
  { extension: 'svg', mimeType: 'image/svg+xml' },
  { extension: 'heic', mimeType: 'image/heic' },
  { extension: 'mp3', mimeType: 'audio/mpeg' },
  { extension: 'wav', mimeType: 'audio/wav' },
  { extension: 'm4a', mimeType: 'audio/mp4' },
  { extension: 'mp4', mimeType: 'video/mp4' },
  { extension: 'mov', mimeType: 'video/quicktime' },
  { extension: 'avi', mimeType: 'video/x-msvideo' },
  { extension: 'mkv', mimeType: 'video/x-matroska' },
  { extension: 'apk', mimeType: 'application/vnd.android.package-archive' },
  { extension: 'bin', mimeType: 'application/octet-stream' }
];

/** 所有 MIME 的兜底值（参考实现同样用 `application/octet-stream` 兜底）。 */
export const OCTET_STREAM: string = 'application/octet-stream';

/** MIME → 扩展名（默认文件名用）。 */
interface ExtensionEntry {
  mimeType: string;
  extension: string;
}

/**
 * MIME → 扩展名表。
 *
 * 参考实现用 `mimeTypes.extension(mime)`（取自 mime-db，一个 MIME 可能对应多个扩展名，
 * 它返回**第一个**）。这里只列闭集里的一对一映射，顺序取 mime-db 的"第一个扩展名"
 * （例如 `image/jpeg` → `jpeg` 而不是 `jpg`，与参考实现一致）。
 * 查不到时返回 `'bin'` —— 参考实现的 `extension('application/octet-stream')` 正是 `'bin'`。
 *
 * 实践上本函数只作兜底：模拟器上两个 picker 都返回带扩展名的 URI，
 * 默认名走的是"URI 的 basename"那条路（见 features/assignments/AttachmentPickers.ets）。
 */
const MIME_TO_EXTENSION: ExtensionEntry[] = [
  { mimeType: 'application/pdf', extension: 'pdf' },
  { mimeType: 'application/msword', extension: 'doc' },
  { mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', extension: 'docx' },
  { mimeType: 'application/vnd.ms-excel', extension: 'xls' },
  { mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', extension: 'xlsx' },
  { mimeType: 'application/vnd.ms-powerpoint', extension: 'ppt' },
  { mimeType: 'application/vnd.openxmlformats-officedocument.presentationml.presentation', extension: 'pptx' },
  { mimeType: 'text/plain', extension: 'txt' },
  { mimeType: 'text/markdown', extension: 'md' },
  { mimeType: 'text/csv', extension: 'csv' },
  { mimeType: 'application/json', extension: 'json' },
  { mimeType: 'application/xml', extension: 'xml' },
  { mimeType: 'text/html', extension: 'html' },
  { mimeType: 'application/zip', extension: 'zip' },
  { mimeType: 'application/vnd.rar', extension: 'rar' },
  { mimeType: 'application/x-7z-compressed', extension: '7z' },
  { mimeType: 'application/gzip', extension: 'gz' },
  { mimeType: 'application/x-tar', extension: 'tar' },
  { mimeType: 'image/png', extension: 'png' },
  { mimeType: 'image/jpeg', extension: 'jpeg' },
  { mimeType: 'image/gif', extension: 'gif' },
  { mimeType: 'image/bmp', extension: 'bmp' },
  { mimeType: 'image/webp', extension: 'webp' },
  { mimeType: 'image/svg+xml', extension: 'svg' },
  { mimeType: 'image/heic', extension: 'heic' },
  { mimeType: 'audio/mpeg', extension: 'mp3' },
  { mimeType: 'audio/wav', extension: 'wav' },
  { mimeType: 'audio/mp4', extension: 'm4a' },
  { mimeType: 'video/mp4', extension: 'mp4' },
  { mimeType: 'video/quicktime', extension: 'mov' },
  { mimeType: 'video/x-msvideo', extension: 'avi' },
  { mimeType: 'video/x-matroska', extension: 'mkv' },
  { mimeType: OCTET_STREAM, extension: 'bin' }
];

/** 取扩展名（小写、不含点）；没有扩展名时空串。 */
export function lowerExtension(name: string): string {
  const dot: number = name.lastIndexOf('.');
  if (dot < 0 || dot === name.length - 1) {
    return '';
  }
  return name.substring(dot + 1).toLowerCase();
}

/** 文件名（或 URI 的末段）→ MIME；查不到一律 `application/octet-stream`。 */
export function mimeTypeForName(name: string): string {
  const extension: string = lowerExtension(name);
  if (extension.length === 0) {
    return OCTET_STREAM;
  }
  for (let i = 0; i < EXTENSION_TO_MIME.length; i++) {
    if (EXTENSION_TO_MIME[i].extension === extension) {
      return EXTENSION_TO_MIME[i].mimeType;
    }
  }
  return OCTET_STREAM;
}

/** MIME → 扩展名；查不到返回 `bin`（与参考实现的 `|| 'bin'` 一致）。 */
export function extensionForMime(mimeType: string): string {
  for (let i = 0; i < MIME_TO_EXTENSION.length; i++) {
    if (MIME_TO_EXTENSION[i].mimeType === mimeType) {
      return MIME_TO_EXTENSION[i].extension;
    }
  }
  return 'bin';
}

/**
 * 默认附件名（参考实现 :96-105）。
 *
 * 注意 `title` 用的是**原始标题**（含 HTML 标签），因为参考实现的 `route.params.title`
 * 就是列表项的原始 `title`，它没有先 `removeTags`。真实数据的标题是纯文本
 * （`bt` = "作业（12）"），所以这条差异在真实数据上不可见；这里保持逐字一致。
 */
export function defaultAttachmentName(title: string, mimeType: string, chinese: boolean): string {
  const extension: string = extensionForMime(mimeType);
  return chinese ? title + '-提交.' + extension : title + ' Submission.' + extension;
}

/** 自定义附件名的输入规则：去掉**所有** `.`（参考实现 :107-109 的 `replaceAll('.','')`）。 */
export function sanitizeCustomAttachmentName(text: string): string {
  return text.replace(/\./g, '');
}

/**
 * 上传时把扩展名拼回（参考实现 :203-210）。
 *
 * 逐字照抄 ````${customName}.${getExtension(name)}````：`getExtension` 在没有扩展名时
 * 返回 `undefined`，模板字符串会拼出字面量 `undefined`（`"名字.undefined"`）。
 * 这不是笔误，是参考实现的**当次行为**；照抄以免文件名与参考实现不同。
 */
export function applyCustomAttachmentName(originalName: string, customName: string): string {
  const trimmed: string = customName.trim();
  if (trimmed.length === 0) {
    return originalName;
  }
  const dot: number = originalName.lastIndexOf('.');
  if (dot < 0) {
    return trimmed + '.undefined';
  }
  return trimmed + '.' + originalName.substring(dot + 1);
}

/**
 * 从平台 URI 里取末段文件名（去掉 `?` / `#` 之后的部分；末尾没有 `/` 时整串当文件名）。
 *
 * 平台的两种 picker 都只给 URI：`file://docs/storage/Users/currentUser/Documents/报告 v2.pdf`、
 * `file://media/Photo/12/IMG_123/IMG_20240101_120000.jpg`（可能带 `?networkid=…`）。
 * 参考实现的 `file.name` / `photo.fileName` 在 RN 由 picker 直接给出；
 * HarmonyOS 侧只能自己从 URI 末段取 —— 这是平台替换，不改变「附件有名字」这个可观察量。
 */
export function fileNameFromUri(uri: string): string {
  let path: string = uri;
  const query: number = path.indexOf('?');
  if (query >= 0) {
    path = path.substring(0, query);
  }
  const fragment: number = path.indexOf('#');
  if (fragment >= 0) {
    path = path.substring(0, fragment);
  }
  const slash: number = path.lastIndexOf('/');
  return slash >= 0 ? path.substring(slash + 1) : path;
}

/**
 * 平台 URI → 附件。
 *
 * 文件名：URI 末段（非空时）；取不到时退回参考实现的默认名（:96-105）。
 * MIME：按**文件名的扩展名**查表（平台 picker 不返回 MIME）。
 * 体积：picker 不返回，这里填 0（界面不展示体积，只有 Content-Type 与文件名进 multipart）。
 */
export function pickedAttachmentFromUri(uri: string, title: string, chinese: boolean): PickedAttachment {
  const raw: string = fileNameFromUri(uri);
  const name: string = raw.length > 0 ? raw : defaultAttachmentName(title, OCTET_STREAM, chinese);
  return { uri: uri, name: name, mimeType: mimeTypeForName(name), size: 0 };
}

