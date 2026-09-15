/*
 * Mock 文件样例的 blob 目录（data/mock）。
 *
 * ## 它解决什么
 *
 * mock 模式下点开「文件」要**真的落盘出真文件**（预览 / 交给系统打开 / 分享 / 缓存命中
 * 全都要走通），而 mock 分支一行网络请求都不发。于是这些样例必须**打进包里**
 * （entry/src/main/resources/rawfile/mock-files/），本文件是"下载地址里的 mock=NNN
 * 到包内哪一份文件"的**唯一映射点**。
 *
 * ## 两套 mock id 空间（本文件同时认这两套）
 *
 *   1. **包内清单**（mock=101..106）：6 份打进包的样例，见下面的 MOCK_BLOBS；
 *   2. **提交附件**（submitted-<xszyid>.<ext>）：**没有**包内文件，字节在
 *      `MockSubmissionJournal` 的进程内台账里（用户这次提交真的选中的那份字节）。
 *      它的 rawfilePath 是一个**合成前缀**（MOCK_SUBMITTED_RAWFILE_PREFIX），
 *      保证与包内资产不可能撞车；读它的是 RawfileDownloadPort 里的组合 source。
 *
 * `mockBlobForUrl()` 对两套都返回一个 `MockFileBlob`，于是下载端口与真实的
 * FileDownloader 只看"地址 → 描述"，**不需要知道字节是包内资产还是台账**。
 *
 * ## 第二套 id 的拼法只此一份
 *
 * 提交附件的 id/URL 由 `buildMockSubmittedAttachmentId` / `buildMockSubmittedAttachmentUrl`
 * 构造，**MockData（拼"我的提交附件"的地址）与写台账的那一侧必须走同一个函数**。
 * 这里曾经有过一次真实的缺陷：MockData 自己拼了一串 `?mock=submitted-<xszyid>`（没有扩展名），
 * 本文件不认识它 ⇒ 用户刚提交的附件自己打不开（死链）。共用构造函数就是那次修复的产物。
 *
 * ## 与另外两处的一致性（改一处必须改三处）
 *
 *   1. data/mock/MockData.ets 的 mockFiles()：下载地址里的 mock=101..104 与 106；
 *      以及 mockNotices() 的附件地址（MOCK_NOTICE_ATTACHMENT_MOCK_ID = 105）；
 *   2. scripts/gen-mock-files.mjs：生成这 6 个文件名与内容；
 *   3. 本文件：mock id 到 { rawfilePath, contentType, fileName } 的映射。
 * scripts/check-mock-files.mjs 会在提交前 FAIL 掉"文件名对不上"的漂移。
 *
 * ## 为什么把"描述"与"读字节"分成两个东西
 *
 * 描述（MockFileBlob）是纯数据；读字节是平台能力（resourceManager / 台账）。
 * 端口只依赖 MockBlobSource 接口，于是设备实现（RawfileMockBlobSource）很薄，
 * host 单测注入内存替身即可，不需要设备、也不需要 rawfile 真的存在。
 *
 * ## 为什么解析查询串不用平台 URL
 *
 * 这里只要一个参数值，而 @ohos.url 的 URL 在 host 单测环境里不保证可用；手写解析是纯函数、
 * 可在 host 上直接断言。注意下载地址在下游会被 appendCsrfToken 追加 _csrf=，
 * 所以解析必须按 & 分段，而不是假设"只有一个参数"。
 */

import { formatSize } from '../../domain/files/FilePath';
import { CourseFile } from '../../domain/model/ContentItem';

/** rawfile 下的目录名（相对路径，无前导斜杠；与生成器的输出目录同名）。 */
export const MOCK_FILES_DIR: string = 'mock-files';

/** mock 下载地址里的查询参数名（MockData.mockFiles() 用的就是它）。 */
export const MOCK_BLOB_QUERY_KEY: string = 'mock';

/** 样例下载地址的站点路径（与 MockData 里各条样例地址同一个域名与路径）。 */
export const MOCK_DOWNLOAD_URL_BASE: string =
  'https://learn.tsinghua.edu.cn/b/wlxt/kc/wj_download';

/** 一份包内样例文件的描述。 */
export interface MockFileBlob {
  /** 与 MockData.mockFiles() 的 downloadUrl 里 mock 参数的**值**对应。 */
  mockId: string;
  /** rawfile 下的相对路径（getRawFileContentSync 直接吃它）。 */
  rawfilePath: string;
  /** 下载响应的 Content-Type（落盘前判定按它走）。 */
  contentType: string;
  /** 包内文件名（诊断用；**落盘文件名由路径规则决定**，不是它）。 */
  fileName: string;
}

/** 四种 Content-Type（与 scripts/gen-mock-files.mjs 逐字一致）。 */
export const MOCK_PDF_CONTENT_TYPE: string = 'application/pdf';
export const MOCK_PPTX_CONTENT_TYPE: string =
  'application/vnd.openxmlformats-officedocument.presentationml.presentation';
export const MOCK_PNG_CONTENT_TYPE: string = 'image/png';
/** 扩展名未知时的 Content-Type（**不猜**类型）。 */
export const MOCK_BINARY_CONTENT_TYPE: string = 'application/octet-stream';

/** 读 rawfile 字节的端口（设备实现见 RawfileDownloadPort.RawfileMockBlobSource）。 */
export interface MockBlobSource {
  /** 读一份包内资产的字节；读不到时**抛**（怎么降级由调用方决定，端口不吞异常）。 */
  read(rawfilePath: string): Uint8Array;
}

/** 公告附件样例的 mock id（MockData.mockNotices() 的那条附件地址指向它）。 */
export const MOCK_NOTICE_ATTACHMENT_MOCK_ID: string = '105';

/** 公告附件样例的包内文件名（与生成器的输出逐字一致）。 */
export const MOCK_NOTICE_ATTACHMENT_FILE_NAME: string = 'mock-notice-attachment.pdf';

/**
 * 6 份样例的唯一清单。
 *
 * 顺序：前 4 条 = MockData.mockFiles() 的 mock=101..104，第 5 条（105）= mockNotices()
 * 的附件，第 6 条（106）= mockFiles() 里那张 PNG。
 */
const MOCK_BLOBS: MockFileBlob[] = [
  {
    mockId: '101',
    rawfilePath: MOCK_FILES_DIR + '/mock-course-syllabus.pdf',
    contentType: MOCK_PDF_CONTENT_TYPE,
    fileName: 'mock-course-syllabus.pdf'
  },
  {
    mockId: '102',
    rawfilePath: MOCK_FILES_DIR + '/mock-homework-1-answers.pdf',
    contentType: MOCK_PDF_CONTENT_TYPE,
    fileName: 'mock-homework-1-answers.pdf'
  },
  {
    mockId: '103',
    rawfilePath: MOCK_FILES_DIR + '/mock-physics-lab-manual.pdf',
    contentType: MOCK_PDF_CONTENT_TYPE,
    fileName: 'mock-physics-lab-manual.pdf'
  },
  {
    mockId: '104',
    rawfilePath: MOCK_FILES_DIR + '/mock-lecture-notes-3.pptx',
    contentType: MOCK_PPTX_CONTENT_TYPE,
    fileName: 'mock-lecture-notes-3.pptx'
  },
  {
    // 第 5 份专供**公告附件**：此前 mockNotices() 的附件写成 ?mock=1，本文件不认识 ⇒ 点开必失败。
    mockId: MOCK_NOTICE_ATTACHMENT_MOCK_ID,
    rawfilePath: MOCK_FILES_DIR + '/' + MOCK_NOTICE_ATTACHMENT_FILE_NAME,
    contentType: MOCK_PDF_CONTENT_TYPE,
    fileName: MOCK_NOTICE_ATTACHMENT_FILE_NAME
  },
  {
    // 第 6 份是**图片**：设备实测里 PDF 应用内预览依赖 HMS 的 pdfservice（模拟器没有），
    // 而图片预览走系统 image.createImageSource ⇒ 这一份才能证明"真的渲染出来了"。
    mockId: '106',
    rawfilePath: MOCK_FILES_DIR + '/mock-lab-schedule.png',
    contentType: MOCK_PNG_CONTENT_TYPE,
    fileName: 'mock-lab-schedule.png'
  }
];

/**
 * 全部样例。
 *
 * 为什么返回数组本身而不是副本：与 mockCourses() / mockNotices() 等样例函数同一口径 ——
 * 这些描述对象是**不可变常量**（模块内没有别处赋值），调用方按只读使用。
 */
export function mockBlobCatalog(): MockFileBlob[] {
  return MOCK_BLOBS;
}

/* ------------------------------------------------------------------ *
 * 第二套 id 空间：提交附件（submitted-<xszyid>.<ext>）
 * ------------------------------------------------------------------ */

/** 提交附件 mock id 的前缀（与包内 id 的数字形状不可能撞车）。 */
export const MOCK_SUBMITTED_ID_PREFIX: string = 'submitted-';

/**
 * 提交附件 rawfilePath 的**合成前缀**。
 *
 * 它不是一个真实目录（rawfile 下没有这个目录）：组合 source 只凭它把"读台账"与
 * "读包内资产"分开。取这个名字是为了**不可能与 MOCK_FILES_DIR 撞车**。
 */
export const MOCK_SUBMITTED_RAWFILE_PREFIX: string = 'mock-submitted/';

/** 一个提交附件的身份：谁的（xszyid）+ 什么扩展名。 */
export interface MockSubmittedBlobKey {
  /** 台账的键（studentHomeworkId / xszyid）。 */
  studentHomeworkId: string;
  /** 小写扩展名（不含点）；没有扩展名时是空串。 */
  extension: string;
}

/** 扩展名 → Content-Type 的表（构建一次；未知扩展名不在这里）。 */
function buildContentTypeTable(): Map<string, string> {
  const table: Map<string, string> = new Map<string, string>();
  table.set('pdf', MOCK_PDF_CONTENT_TYPE);
  table.set('pptx', MOCK_PPTX_CONTENT_TYPE);
  table.set('ppt', 'application/vnd.ms-powerpoint');
  table.set('docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
  table.set('doc', 'application/msword');
  table.set('xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  table.set('xls', 'application/vnd.ms-excel');
  table.set('zip', 'application/zip');
  table.set('txt', 'text/plain');
  table.set('md', 'text/markdown');
  table.set('png', 'image/png');
  table.set('jpg', 'image/jpeg');
  table.set('jpeg', 'image/jpeg');
  table.set('gif', 'image/gif');
  return table;
}

const EXTENSION_CONTENT_TYPES: Map<string, string> = buildContentTypeTable();

/**
 * 扩展名（可带点、可大小写混杂）→ Content-Type；未知 / 没有扩展名 ⇒ application/octet-stream。
 *
 * 为什么不"看内容猜类型"：mock 的字节就是用户选中的那份，Content-Type 只能来自
 * 文件名这个已知事实；猜错会让落盘前判定（拒绝 HTML/JSON）误伤或漏放。
 */
export function mockContentTypeForExtension(extension: string): string {
  const key: string = extension.trim().toLowerCase().replace('.', '');
  const known: string | undefined = EXTENSION_CONTENT_TYPES.get(key);
  return known === undefined ? MOCK_BINARY_CONTENT_TYPE : known;
}

/** 文件名 → 小写扩展名（不含点）；没有扩展名（或文件名以点结尾）时空串。 */
export function extensionOfFileName(fileName: string): string {
  const dot: number = fileName.lastIndexOf('.');
  if (dot < 0 || dot === fileName.length - 1) {
    return '';
  }
  return fileName.substring(dot + 1).trim().toLowerCase();
}

/** 下载地址：`<站点路径>?mock=<id>`（两套 id 空间共用同一个形状）。 */
export function mockBlobUrl(mockId: string): string {
  return MOCK_DOWNLOAD_URL_BASE + '?' + MOCK_BLOB_QUERY_KEY + '=' + mockId;
}

/** 提交附件的 mock id：`submitted-<xszyid>.<ext>`（无扩展名时不留点）。 */
export function buildMockSubmittedAttachmentId(studentHomeworkId: string,
  extension: string): string {
  const ext: string = extension.trim().toLowerCase().replace('.', '');
  return MOCK_SUBMITTED_ID_PREFIX + studentHomeworkId + (ext.length > 0 ? '.' + ext : '');
}

/**
 * 提交附件的下载地址（**唯一**的构造函数）。
 *
 * MockData（生成"我的提交附件"）与 MockAssignmentSubmitter（写台账）都调它；
 * 不许各自拼一份 —— 这正是上一版的缺陷来源（见文件头）。
 */
export function buildMockSubmittedAttachmentUrl(studentHomeworkId: string,
  extension: string): string {
  return mockBlobUrl(encodeURIComponent(
    buildMockSubmittedAttachmentId(studentHomeworkId, extension)));
}

/** `submitted-` 前缀去掉之后的尾巴 → 身份；解析不出时 null（不兜底）。 */
function parseSubmittedKeyTail(tail: string): MockSubmittedBlobKey | null {
  if (tail.length === 0) {
    return null;
  }
  const dot: number = tail.lastIndexOf('.');
  if (dot < 0) {
    return { studentHomeworkId: tail, extension: '' };
  }
  const id: string = tail.substring(0, dot);
  if (id.length === 0) {
    return null;
  }
  return { studentHomeworkId: id, extension: tail.substring(dot + 1).toLowerCase() };
}

/** mock id → 提交附件身份；不是 `submitted-` 形状时 null。 */
export function parseMockSubmittedAttachmentId(mockId: string): MockSubmittedBlobKey | null {
  if (!mockId.startsWith(MOCK_SUBMITTED_ID_PREFIX)) {
    return null;
  }
  return parseSubmittedKeyTail(mockId.substring(MOCK_SUBMITTED_ID_PREFIX.length));
}

/** 提交附件的合成 rawfilePath。 */
export function submittedRawfilePath(key: MockSubmittedBlobKey): string {
  return MOCK_SUBMITTED_RAWFILE_PREFIX + key.studentHomeworkId
    + (key.extension.length > 0 ? '.' + key.extension : '');
}

/** 合成 rawfilePath → 提交附件身份；不是合成前缀时 null（组合 source 据此分流）。 */
export function parseSubmittedRawfilePath(rawfilePath: string): MockSubmittedBlobKey | null {
  if (!rawfilePath.startsWith(MOCK_SUBMITTED_RAWFILE_PREFIX)) {
    return null;
  }
  return parseSubmittedKeyTail(rawfilePath.substring(MOCK_SUBMITTED_RAWFILE_PREFIX.length));
}

/** 提交附件的描述（rawfilePath 是合成前缀；contentType 由 id 里带的扩展名决定）。 */
function submittedBlobForId(mockId: string): MockFileBlob | null {
  const key: MockSubmittedBlobKey | null = parseMockSubmittedAttachmentId(mockId);
  if (key === null) {
    return null;
  }
  return {
    mockId: mockId,
    rawfilePath: submittedRawfilePath(key),
    contentType: mockContentTypeForExtension(key.extension),
    fileName: key.studentHomeworkId + (key.extension.length > 0 ? '.' + key.extension : '')
  };
}

/* ------------------------------------------------------------------ *
 * 解析
 * ------------------------------------------------------------------ */

/** 从下载地址里取 mock 参数的值；取不到返回空串（**不猜**）。 */
export function parseMockBlobId(url: string): string {
  const text: string = url === undefined || url === null ? '' : url;
  const query: number = text.indexOf('?');
  if (query < 0) {
    return '';
  }
  let cut: string = text.substring(query + 1);
  const hash: number = cut.indexOf('#');
  if (hash >= 0) {
    cut = cut.substring(0, hash);
  }
  const parts: string[] = cut.split('&');
  for (let i = 0; i < parts.length; i++) {
    const part: string = parts[i];
    const eq: number = part.indexOf('=');
    if (eq < 0) {
      continue;
    }
    if (part.substring(0, eq) === MOCK_BLOB_QUERY_KEY) {
      return decodeURIComponent(part.substring(eq + 1)).trim();
    }
  }
  return '';
}

/**
 * 下载地址到描述（包内样例或提交附件）的映射；
 * 地址里没有**已知**的 mock id 时返回 null（不兜底到别的文件）。
 */
export function mockBlobForUrl(url: string): MockFileBlob | null {
  const id: string = parseMockBlobId(url);
  if (id.length === 0) {
    return null;
  }
  for (let i = 0; i < MOCK_BLOBS.length; i++) {
    if (MOCK_BLOBS[i].mockId === id) {
      return MOCK_BLOBS[i];
    }
  }
  return submittedBlobForId(id);
}

/* ------------------------------------------------------------------ *
 * 体积：把"站点给的体积文本"换成"包里那份字节的真实体积"
 * ------------------------------------------------------------------ */

/** 一份文件体积的重算结果。 */
export interface BundledSizeResult {
  /** 换过体积的副本（顺序与 id 不变）。 */
  files: CourseFile[];
  /** 真的从字节算出来的条数（其余保留站点给的文本）。 */
  resolvedCount: number;
}

/**
 * 包内样例（或台账字节）的真实长度；取不到（没有端口 / 未知 id / 读失败）返回 -1。
 *
 * 为什么失败返回 -1 而不是 0：0 会让界面显示"0 B"，而真实含义是"这条我们算不出来"；
 * 调用方据此保留站点给的体积文本。
 */
export function bundledSizeFor(url: string, source: MockBlobSource | null): number {
  if (source === null) {
    return -1;
  }
  const blob: MockFileBlob | null = mockBlobForUrl(url);
  if (blob === null) {
    return -1;
  }
  try {
    return source.read(blob.rawfilePath).length;
  } catch (error) {
    return -1;
  }
}

/**
 * 只换 size 的副本。
 *
 * 为什么不用对象展开（...file）：ArkTS 对 interface 的展开支持不保证，而且
 * **这里是三处口径（MockData 的字段名 / 域类型 / 本文件）之间唯一的接缝**——
 * 显式列出每个字段，将来域类型加字段时会在这里编译失败，而不是静默丢字段。
 */
function copyWithSize(file: CourseFile, size: string): CourseFile {
  return {
    id: file.id,
    fileId: file.fileId,
    title: file.title,
    description: file.description,
    size: size,
    uploadTime: file.uploadTime,
    fileType: file.fileType,
    isNew: file.isNew,
    downloadUrl: file.downloadUrl,
    courseId: file.courseId,
    courseName: file.courseName,
    courseTeacherName: file.courseTeacherName
  };
}

/**
 * 把每条文件的 size 换成**包内那份样例的真实字节数**（formatSize 格式化，与站点口径一致）。
 *
 * MockFileRepository（「文件」tab）与 MockCourseRepository（课程详情页「文件」标签页）
 * **必须调同一个函数**：否则同一个文件在两个页面上写着两个体积（这就是本函数存在的理由）。
 * 解析不出来的那条保留原来的文本（不编、不显示 0 B）。
 */
export function applyBundledSizes(files: CourseFile[], source: MockBlobSource | null):
  BundledSizeResult {
  const out: CourseFile[] = [];
  let resolved: number = 0;
  for (let i = 0; i < files.length; i++) {
    const file: CourseFile = files[i];
    const bytes: number = bundledSizeFor(file.downloadUrl, source);
    if (bytes >= 0) {
      resolved++;
    }
    out.push(copyWithSize(file, bytes >= 0 ? formatSize(bytes) : file.size));
  }
  return { files: out, resolvedCount: resolved };
}
