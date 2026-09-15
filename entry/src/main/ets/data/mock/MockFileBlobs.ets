/*
 * Mock 文件样例的 blob 目录（data/mock）。
 *
 * ## 它解决什么
 *
 * mock 模式下点开「文件」要**真的落盘出真文件**（预览 / 交给系统打开 / 分享 / 缓存命中
 * 全都要走通），而 mock 分支一行网络请求都不发。于是这 4 份样例必须**打进包里**
 * （entry/src/main/resources/rawfile/mock-files/），本文件是"下载地址里的 mock=NNN
 * 到包内哪一份文件"的**唯一映射点**。
 *
 * ## 与另外两处的一致性（改一处必须改三处）
 *
 *   1. data/mock/MockData.ets 的 mockFiles()：下载地址里的 mock=101..104；
 *   2. scripts/gen-mock-files.mjs：生成这 4 个文件名与内容；
 *   3. 本文件：mock id 到 { rawfilePath, contentType, fileName } 的映射。
 * scripts/check-mock-files.mjs 会在提交前 FAIL 掉"文件名对不上"的漂移。
 *
 * ## 为什么把"描述"与"读字节"分成两个东西
 *
 * 描述（MockFileBlob）是纯数据；读字节是平台能力（resourceManager）。端口只依赖
 * MockBlobSource 接口，于是设备实现（RawfileMockBlobSource）很薄，host 单测注入内存替身即可，
 * 不需要设备、也不需要 rawfile 真的存在。
 *
 * ## 为什么解析查询串不用平台 URL
 *
 * 这里只要一个参数值，而 @ohos.url 的 URL 在 host 单测环境里不保证可用；手写解析是纯函数、
 * 可在 host 上直接断言。注意下载地址在下游会被 appendCsrfToken 追加 _csrf=，
 * 所以解析必须按 & 分段，而不是假设"只有一个参数"。
 */

/** rawfile 下的目录名（相对路径，无前导斜杠；与生成器的输出目录同名）。 */
export const MOCK_FILES_DIR: string = 'mock-files';

/** mock 下载地址里的查询参数名（MockData.mockFiles() 用的就是它）。 */
export const MOCK_BLOB_QUERY_KEY: string = 'mock';

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

/** 两种 Content-Type（与 scripts/gen-mock-files.mjs 逐字一致）。 */
export const MOCK_PDF_CONTENT_TYPE: string = 'application/pdf';
export const MOCK_PPTX_CONTENT_TYPE: string =
  'application/vnd.openxmlformats-officedocument.presentationml.presentation';

/** 读 rawfile 字节的端口（设备实现见 RawfileDownloadPort.RawfileMockBlobSource）。 */
export interface MockBlobSource {
  /** 读一份包内资产的字节；读不到时**抛**（怎么降级由调用方决定，端口不吞异常）。 */
  read(rawfilePath: string): Uint8Array;
}

/** 4 份样例的唯一清单（顺序 = MockData.mockFiles() 的 mock=101..104 顺序）。 */
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
  }
];

/**
 * 全部样例。
 *
 * 为什么返回数组本身而不是副本：与 mockCourses() / mockNotices() 等样例函数同一口径 ——
 * 这 4 个描述对象是**不可变常量**（模块内没有别处赋值），调用方按只读使用。
 */
export function mockBlobCatalog(): MockFileBlob[] {
  return MOCK_BLOBS;
}

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

/** 下载地址到包内样例的映射；地址里没有**已知**的 mock id 时返回 null（不兜底到别的文件）。 */
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
  return null;
}
