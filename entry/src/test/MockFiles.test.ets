/*
 * Mock 文件样例的单测（host 侧 hypium，全部注入替身、不碰设备、不碰 rawfile）。
 *
 * ## 它钉住什么
 *
 * 这个 ticket 的要点是"mock 登录时文件要**真的落盘**"，而落盘要复用真实的下载编排
 * （data/files/FileDownloader）。所以这里断言的不是"某段 mock 代码被调用"，而是
 * **编排层的可观察后果**：
 *   (a) 写出的字节与包内资产**逐字节相同**，bytes 等于资产长度（不是"文件存在"就算过）；
 *   (b) refresh=false 的第二次调用命中缓存（fromCache=true）且**端口没有被再次调用**；
 *   (c) 进度回调收到的 total 等于真实字节数、received 单调递增到 total；
 *   (d) 地址里没有已知的 mock id ⇒ 显式失败，且目标路径**没有留下文件**；
 *   (e) refresh() 返回的每条 size 等于对应资产的真实长度（列表 / 进度 / 落盘三处一致）；
 *   (f) 上面全过程 networkAttemptCount() 不变 = **零网络**（mock 模式的硬要求）。
 *
 * 本轮收口补上的（三处自洽性缺口）：
 *   (g) **提交附件真的能打开**：提交一个可读附件之后，`mockAssignments()` 里那条
 *       `submittedAttachment.downloadUrl` 能被 `mockBlobForUrl` 解析，并且**真的走一遍**
 *       `MockFileRepository.download()`（组合 source + 假 FileStore）落盘出与选中附件
 *       **逐字节相同**的字节 —— 本套用例的决定性一条；
 *   (h) 合成前缀的 id 在台账里**没有**对应字节 ⇒ 端口显式失败、目标路径不残留文件；
 *   (i) `MockCourseRepository.refresh()` 的三个计数 == `countsForCourse(...)` 的返回值，
 *       且提交一条作业后该课程的 `unfinishedAssignmentCount` 减 1；
 *   (j) 课程快照里每条文件的 size == 包内真实长度的格式化文本（与「文件」tab 同一份）；
 *   (k) `mockNotices()` 那条附件的地址能被解析并下载出**非空**字节（此前是 `?mock=1` 死链）；
 *   (l) 以上全过程 networkAttemptCount() 不变。
 *
 * ## 替身为什么是"伪字节"而不是真的读那 6 个包内文件
 *
 * host 单测跑不到 rawfile（没有 resourceManager）。真实产物的结构由
 * scripts/check-mock-files.mjs 校验（PDF 的 xref/startxref/页对象、PPTX 的 ZIP 与部件），
 * 本文件校验的是**编排与映射**：真字节怎么进 sink、怎么命中缓存、怎么算体积。
 * 两者是互补的，不能互相替代。
 *
 * ## 假 FileStore 为什么要记内容
 *
 * 只记"文件存在 + 大小"就无法区分"写对了"与"写了别的 N 个字节"。这里按字节累积
 * （与 entry/src/test/FileDownload.test.ets 的假 store 同一路数，只是多留了内容），
 * 于是 (a) 的逐字节相同是可断言的。
 */

import { describe, it, expect } from '@ohos/hypium';
import { Logger } from '../main/ets/core/log/Logger';
import { CourseFile } from '../main/ets/domain/model/ContentItem';
import { formatSize } from '../main/ets/domain/files/FilePath';
import { networkAttemptCount, resetNetworkAudit } from '../main/ets/data/remote/NetworkAudit';
import {
  DownloadPort, DownloadSink, DownloadStreamResult
} from '../main/ets/data/remote/DownloadPort';
import { Session } from '../main/ets/data/remote/Requests';
import {
  ClearCacheResult, DownloadProgressSink, FileDownloadRequest, FileDownloader
} from '../main/ets/data/files/FileDownloader';
import {
  FileDownloadReport, FileRepository, FileSnapshot
} from '../main/ets/data/files/FileRepository';
import { FileRoots, FileSink, FileStore } from '../main/ets/data/files/FileStorePort';
import {
  applyFileSettingsOverride, clearRuntimeFileSettingsOverride, DEFAULT_FILE_SETTINGS,
  FileSettings, FileSettingsSource
} from '../main/ets/data/settings/FileSettings';
import {
  MOCK_NOTICE_ATTACHMENT_MOCK_ID, MockBlobSource, MockFileBlob, buildMockSubmittedAttachmentId,
  mockBlobCatalog, mockBlobForUrl, parseMockBlobId
} from '../main/ets/data/mock/MockFileBlobs';
import {
  CompositeMockBlobSource, RawfileDownloadPort
} from '../main/ets/data/mock/RawfileDownloadPort';
import { MockFileRepository } from '../main/ets/data/mock/MockFileRepository';
import {
  MockCourseRepository, noticesForCounts
} from '../main/ets/data/mock/MockCourseRepository';
import { MockAssignmentSubmitter } from '../main/ets/data/mock/MockAssignmentSubmitter';
import { clearMockSubmissions } from '../main/ets/data/mock/MockSubmissionJournal';
import {
  AttachmentBytesSource, SubmitOutcome
} from '../main/ets/data/assignments/SubmitAssignment';
import { SubmissionPlan } from '../main/ets/domain/assignments/SubmissionState';
import { CourseCounts, countsForCourse } from '../main/ets/domain/courses/CourseCounts';
import { CourseRecord, CourseSnapshot } from '../main/ets/data/courses/CourseRepository';
import { NoticeRecord } from '../main/ets/data/notices/NoticeRepository';
import { mockAssignments, mockFiles, mockNotices } from '../main/ets/data/mock/MockData';
import { Assignment, Attachment } from '../main/ets/domain/model/ContentItem';

/* ------------------------------------------------------------------ *
 * 替身
 * ------------------------------------------------------------------ */

/** 内存文件 sink（把字节交给 store 累积）。 */
class MemoryFileSink implements FileSink {
  private readonly store: MemoryFileStore;
  private readonly path: string;

  constructor(store: MemoryFileStore, path: string) {
    this.store = store;
    this.path = path;
  }

  write(chunk: ArrayBuffer): void {
    this.store.append(this.path, chunk);
  }

  close(): void {
  }

  abort(): void {
  }
}

/** 内存文件系统（记内容，于是"逐字节相同"可断言）。 */
class MemoryFileStore implements FileStore {
  readonly contents: Map<string, number[]> = new Map<string, number[]>();
  readonly dirs: string[] = [];
  readonly removed: string[] = [];
  openCalls: number = 0;

  roots(): FileRoots {
    return { filesDir: '/mem/files', cacheDir: '/mem/cache' };
  }

  ensureDir(dir: string): void {
    this.dirs.push(dir);
  }

  exists(path: string): boolean {
    return this.contents.has(path);
  }

  openSink(path: string): FileSink {
    this.openCalls++;
    // 与 DeviceFileStore 的 OpenMode.TRUNC 同义：重下必须**截断**而不是追加。
    this.contents.set(path, []);
    return new MemoryFileSink(this, path);
  }

  remove(path: string): void {
    this.removed.push(path);
    this.contents.delete(path);
  }

  removeTree(path: string): void {
    const doomed: string[] = [];
    this.contents.forEach((value: number[], key: string): void => {
      if (key.startsWith(path)) {
        doomed.push(key);
      }
    });
    for (let i = 0; i < doomed.length; i++) {
      this.contents.delete(doomed[i]);
    }
  }

  fileSize(path: string): number {
    const value: number[] | undefined = this.contents.get(path);
    return value === undefined ? 0 : value.length;
  }

  append(path: string, chunk: ArrayBuffer): void {
    let bytes: number[] | undefined = this.contents.get(path);
    if (bytes === undefined) {
      bytes = [];
      this.contents.set(path, bytes);
    }
    const view: Uint8Array = new Uint8Array(chunk);
    for (let i = 0; i < view.length; i++) {
      bytes.push(view[i]);
    }
  }

  bytesOf(path: string): number[] {
    const value: number[] | undefined = this.contents.get(path);
    return value === undefined ? [] : value;
  }
}

/** 包内资产的替身：每个 rawfilePath 一份固定字节，并记录被读了几次。 */
class FakeBlobSource implements MockBlobSource {
  readonly assets: Map<string, Uint8Array> = new Map<string, Uint8Array>();
  reads: number = 0;

  read(rawfilePath: string): Uint8Array {
    this.reads++;
    const bytes: Uint8Array | undefined = this.assets.get(rawfilePath);
    if (bytes === undefined) {
      throw new Error('fake asset missing: ' + rawfilePath);
    }
    return bytes;
  }
}

/**
 * 统计端口被调用次数的装饰器。
 *
 * 为什么要它：(b) 的判据是"端口**没有被再次调用**"，而包内端口本身没有计数器
 * （它不该为了测试多一个字段）。装饰器让这件事在**端口边界**上可断言，
 * 与"blob 没被读"是两条不同的证据。
 */
class CountingDownloadPort implements DownloadPort {
  calls: number = 0;
  private readonly inner: DownloadPort;

  constructor(inner: DownloadPort) {
    this.inner = inner;
  }

  download(session: Session, url: string, sink: DownloadSink): Promise<DownloadStreamResult> {
    this.calls++;
    return this.inner.download(session, url, sink);
  }
}

/** 固定设置来源。 */
class FixedSettings implements FileSettingsSource {
  current(): FileSettings {
    return applyFileSettingsOverride(DEFAULT_FILE_SETTINGS);
  }
}

/** 真实仓储的替身（mock 只把"文件系统三件事"转发给它，这里直接转发给同一个下载器）。 */
class DelegatingFileSystem implements FileRepository {
  private readonly downloader: FileDownloader;

  constructor(downloader: FileDownloader) {
    this.downloader = downloader;
  }

  async refresh(): Promise<FileSnapshot> {
    throw new Error('delegating file system: refresh must not be called');
  }

  async download(request: FileDownloadRequest,
    onProgress?: DownloadProgressSink): Promise<FileDownloadReport> {
    throw new Error('delegating file system: download must not be called');
  }

  targetPath(request: FileDownloadRequest): string {
    return this.downloader.targetPath(request);
  }

  cacheRoot(): string {
    return this.downloader.cacheRoot();
  }

  clearCache(): ClearCacheResult {
    return this.downloader.clearCache();
  }
}

/* ------------------------------------------------------------------ *
 * 夹具
 * ------------------------------------------------------------------ */

/** 伪字节（ASCII，于是长度 == 字符数，便于断言）。 */
function bytesOf(text: string): Uint8Array {
  const out: Uint8Array = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) {
    out[i] = text.charCodeAt(i) & 0xFF;
  }
  return out;
}

/**
 * 提交附件读取器的替身（与 MockSubmission.test.ets 的那只同形，但那只在别的文件里，
 * 这里需要一份独立的：两个测试文件不共享替身，避免"改一处影响两处"）。
 */
class FakeAttachmentReader implements AttachmentBytesSource {
  readonly files: Map<string, Uint8Array> = new Map<string, Uint8Array>();
  reads: number = 0;

  async read(uri: string): Promise<Uint8Array> {
    this.reads++;
    const bytes: Uint8Array | undefined = this.files.get(uri);
    if (bytes === undefined) {
      throw new Error('fake attachment reader has no bytes for: ' + uri);
    }
    return bytes;
  }
}

/** 提交附件的下载请求（与 FilesPage / 作业详情页的口径一致：cacheKey 用附件 id）。 */
function requestForAttachment(url: string, cacheKey: string, courseName: string,
  title: string): FileDownloadRequest {
  return {
    downloadUrl: url,
    cacheKey: cacheKey,
    courseName: courseName,
    title: title,
    fileType: 'pdf',
    refresh: false
  };
}

/** 从课程快照里按 id 取一门课（顺序断言会随样例顺序变，按 id 取更稳）。 */
function courseById(snapshot: CourseSnapshot, courseId: string): CourseRecord | undefined {
  for (let i = 0; i < snapshot.courses.length; i++) {
    if (snapshot.courses[i].id === courseId) {
      return snapshot.courses[i];
    }
  }
  return undefined;
}

/** 从作业样例里按 xszyid 取一条。 */
function assignmentByxszyid(xszyid: string): Assignment | undefined {
  const items: Assignment[] = mockAssignments();
  for (let i = 0; i < items.length; i++) {
    if (items[i].studentHomeworkId === xszyid) {
      return items[i];
    }
  }
  return undefined;
}

/** 把 MockFileRepository 与它的替身接起来。 */
class Harness {
  readonly store: MemoryFileStore = new MemoryFileStore();
  /** 包内资产的替身（"rawfile"那一侧）。 */
  readonly blobs: FakeBlobSource = new FakeBlobSource();
  /**
   * 与生产装配同一个组合 source（包内资产 + 提交台账）。
   *
   * 必须用它而不是直接用 `blobs`：否则"刚提交的附件能下载"这条根本没被走一遍
   * （合成前缀会被 FakeBlobSource 当成缺失资产）。
   * 台账是模块级单例，用例开头记得 `clearMockSubmissions()`。
   */
  readonly composite: CompositeMockBlobSource =
    new CompositeMockBlobSource(this.blobs, new Logger('test.mock.rawfile'));
  readonly port: CountingDownloadPort;
  readonly downloader: FileDownloader;
  readonly repository: MockFileRepository;

  constructor() {
    this.port = new CountingDownloadPort(
      new RawfileDownloadPort(this.composite, new Logger('test.mock.rawfile')));
    this.downloader = new FileDownloader(this.port, this.store, new FixedSettings(),
      new Logger('test.mock.downloader'));
    this.repository = new MockFileRepository(new DelegatingFileSystem(this.downloader),
      this.downloader, this.composite);
  }

  /** 给 4 份样例各塞一份**长度互不相同**的伪字节。 */
  seedAssets(): void {
    const catalog: MockFileBlob[] = mockBlobCatalog();
    for (let i = 0; i < catalog.length; i++) {
      let text: string = 'mock-' + catalog[i].mockId + '-fixture';
      for (let k = 0; k <= i; k++) {
        text += '!';
      }
      this.blobs.assets.set(catalog[i].rawfilePath, bytesOf(text));
    }
  }
}

/** 由真实样例记录造请求（缓存键口径与 FilesPage 一致：fileId 优先，id 兜底）。 */
function requestForFile(file: CourseFile, refresh: boolean): FileDownloadRequest {
  return {
    downloadUrl: file.downloadUrl,
    cacheKey: file.fileId.length > 0 ? file.fileId : file.id,
    courseName: file.courseName,
    title: file.title,
    fileType: file.fileType,
    refresh: refresh
  };
}

/** 地址里没有已知 mock id 的请求（(d) 用它）。 */
function requestForUnknownBlob(): FileDownloadRequest {
  return {
    downloadUrl: 'https://learn.tsinghua.edu.cn/b/wlxt/kc/wj_download?mock=999',
    cacheKey: 'mock-wjid-999',
    courseName: '数据结构',
    title: '不存在的样例',
    fileType: 'pdf',
    refresh: false
  };
}

function requireBlob(file: CourseFile): MockFileBlob {
  const blob: MockFileBlob | null = mockBlobForUrl(file.downloadUrl);
  if (blob === null) {
    throw new Error('fixture error: no bundled blob mapped for ' + file.downloadUrl);
  }
  return blob;
}

function requireAsset(source: FakeBlobSource, rawfilePath: string): Uint8Array {
  const bytes: Uint8Array | undefined = source.assets.get(rawfilePath);
  if (bytes === undefined) {
    throw new Error('fixture error: asset not seeded: ' + rawfilePath);
  }
  return bytes;
}

function sameBytes(written: number[], expected: Uint8Array): boolean {
  if (written.length !== expected.length) {
    return false;
  }
  for (let i = 0; i < expected.length; i++) {
    if (written[i] !== expected[i]) {
      return false;
    }
  }
  return true;
}

export default function mockFilesTest() {
  describe('data.mock.files', () => {
    it('parsesTheMockIdEvenAfterTheCsrfParameterIsAppended', 0, () => {
      // 真实编排会在地址上追加 _csrf=（见 MockFileRepository 的合成会话），
      // 所以解析必须按 & 分段，而不是假设"只有一个参数"。
      expect(parseMockBlobId('https://x/y?mock=101')).assertEqual('101');
      expect(parseMockBlobId('https://x/y?mock=101&_csrf=')).assertEqual('101');
      expect(parseMockBlobId('https://x/y?a=1&mock=104&b=2')).assertEqual('104');
      expect(parseMockBlobId('https://x/y?a=1')).assertEqual('');
      expect(parseMockBlobId('https://x/y')).assertEqual('');
      expect(parseMockBlobId('')).assertEqual('');
      // 未知 id 不兜底到别的文件（否则 (d) 永远失败不了）。
      expect(mockBlobForUrl('https://x/y?mock=999') === null).assertTrue();
      expect(mockBlobForUrl('https://x/y?a=1') === null).assertTrue();
      expect(mockBlobForUrl('https://x/y?mock=101&_csrf=') === null).assertFalse();
      // 文件样例的 mock id 与 MockData.mockFiles() 的地址一一对上；
      // 清单里另有第 5 条（公告附件 mock=105），它不在 mockFiles() 里。
      const declared: CourseFile[] = mockFiles();
      // 样例条数也钉死：5 条文件（101..104 + 106 那张 PNG）与清单 6 份（多出 105 公告附件）。
      expect(declared.length).assertEqual(5);
      expect(mockBlobCatalog().length).assertEqual(declared.length + 1);
      for (let i = 0; i < declared.length; i++) {
        const blob: MockFileBlob | null = mockBlobForUrl(declared[i].downloadUrl);
        expect(blob === null).assertFalse();
        // 文件列表里没有一条用的是公告附件那个 id（两套样例不重叠）。
        expect(parseMockBlobId(declared[i].downloadUrl) === MOCK_NOTICE_ATTACHMENT_MOCK_ID)
          .assertFalse();
      }
      // 公告附件那条自己认得出来。
      expect(mockBlobForUrl('https://x/y?mock=' + MOCK_NOTICE_ATTACHMENT_MOCK_ID) === null)
        .assertFalse();
      // 提交附件的 id 空间（submitted-<xszyid>.<ext>）也认得 —— 上一版这里返回 null，
      // 于是"我的提交附件"是一条谁都打不开的死链。
      const submittedId: string = buildMockSubmittedAttachmentId('mock-xszy-1', 'pdf');
      expect(mockBlobForUrl('https://x/y?mock=' + submittedId) === null).assertFalse();
      expect(mockBlobForUrl('https://x/y?mock=submitted-mock-xszy-1') === null).assertFalse();
      // 但"看起来像 submitted-、其实没有 xszyid"的形状仍然不兜底。
      expect(mockBlobForUrl('https://x/y?mock=submitted-') === null).assertTrue();
    });

    it('writesTheBundledAssetByteForByte', 0, async () => {
      clearRuntimeFileSettingsOverride();
      const harness: Harness = new Harness();
      harness.seedAssets();
      const file: CourseFile = mockFiles()[0];
      const expected: Uint8Array = requireAsset(harness.blobs, requireBlob(file).rawfilePath);
      const report: FileDownloadReport =
        await harness.repository.download(requestForFile(file, false));
      expect(report.outcome.ok).assertTrue();
      expect(report.outcome.bytes).assertEqual(expected.length);
      expect(report.outcome.fromCache).assertFalse();
      expect(report.outcome.error).assertEqual('');
      expect(harness.port.calls).assertEqual(1);
      // 逐字节相同（不是"大小对上了"）。
      expect(sameBytes(harness.store.bytesOf(report.outcome.path), expected)).assertTrue();
      // 落盘路径由真实路径规则算出（课程名 + 缓存键 + 课程名-标题.pdf）。
      expect(report.outcome.path.startsWith('/mem/cache/learnX-files/数据结构/mock-wjid-101/'))
        .assertTrue();
      expect(report.outcome.path.endsWith('.pdf')).assertTrue();
    });

    it('hitsTheCacheOnTheSecondCallWithoutTouchingThePort', 0, async () => {
      clearRuntimeFileSettingsOverride();
      const harness: Harness = new Harness();
      harness.seedAssets();
      const file: CourseFile = mockFiles()[0];
      const expected: Uint8Array = requireAsset(harness.blobs, requireBlob(file).rawfilePath);
      const first: FileDownloadReport =
        await harness.repository.download(requestForFile(file, false));
      expect(first.outcome.ok).assertTrue();
      expect(first.outcome.fromCache).assertFalse();
      expect(harness.port.calls).assertEqual(1);
      const readsAfterFirst: number = harness.blobs.reads;

      const second: FileDownloadReport =
        await harness.repository.download(requestForFile(file, false));
      expect(second.outcome.ok).assertTrue();
      expect(second.outcome.fromCache).assertTrue();
      expect(second.outcome.bytes).assertEqual(expected.length);
      // 端口与 blob 都没被第二次碰过（两条独立证据）。
      expect(harness.port.calls).assertEqual(1);
      expect(harness.blobs.reads).assertEqual(readsAfterFirst);

      // refresh=true 忽略缓存，重新从包里喂一遍。
      const third: FileDownloadReport =
        await harness.repository.download(requestForFile(file, true));
      expect(third.outcome.ok).assertTrue();
      expect(third.outcome.fromCache).assertFalse();
      expect(harness.port.calls).assertEqual(2);
      expect(sameBytes(harness.store.bytesOf(third.outcome.path), expected)).assertTrue();
    });

    it('reportsTheRealTotalAndMonotonicProgress', 0, async () => {
      clearRuntimeFileSettingsOverride();
      const harness: Harness = new Harness();
      harness.seedAssets();
      const file: CourseFile = mockFiles()[0];
      const expected: Uint8Array = requireAsset(harness.blobs, requireBlob(file).rawfilePath);
      const progress: number[][] = [];
      const report: FileDownloadReport = await harness.repository.download(
        requestForFile(file, false),
        (received: number, total: number): void => {
          progress.push([received, total]);
        });
      expect(report.outcome.ok).assertTrue();
      // 至少 2 块 ⇒ 进度条真的有中间态（一次交付 = 0 直接跳 100%）。
      expect(progress.length >= 2).assertTrue();
      for (let i = 0; i < progress.length; i++) {
        expect(progress[i][1]).assertEqual(expected.length);
        if (i > 0) {
          expect(progress[i][0] > progress[i - 1][0]).assertTrue();
        }
      }
      expect(progress[0][0] > 0).assertTrue();
      expect(progress[progress.length - 1][0]).assertEqual(expected.length);
    });

    it('failsExplicitlyAndLeavesNoFileWhenThereIsNoBundledBlob', 0, async () => {
      clearRuntimeFileSettingsOverride();
      const harness: Harness = new Harness();
      harness.seedAssets();
      const request: FileDownloadRequest = requestForUnknownBlob();
      const path: string = harness.repository.targetPath(request);
      const report: FileDownloadReport = await harness.repository.download(request);
      expect(report.outcome.ok).assertFalse();
      expect(report.outcome.bytes).assertEqual(0);
      expect(report.outcome.error.includes('no bundled sample blob')).assertTrue();
      // 明确失败 + 目标路径上什么都没有（**没有**留下 0 字节的半成品）。
      expect(harness.store.exists(path)).assertFalse();
      expect(harness.store.bytesOf(path).length).assertEqual(0);
      // 连文件都没被创建（端口在 onHeaders 之前就失败了）。
      expect(harness.store.openCalls).assertEqual(0);
      expect(report.requiresEnrollment).assertFalse();
      expect(harness.port.calls).assertEqual(1);
    });

    it('reportsBundledByteSizesInTheSnapshot', 0, async () => {
      clearRuntimeFileSettingsOverride();
      const harness: Harness = new Harness();
      harness.seedAssets();
      const declared: CourseFile[] = mockFiles();
      const snapshot: FileSnapshot = await harness.repository.refresh();
      expect(snapshot.files.length).assertEqual(declared.length);
      expect(snapshot.semesterId).assertEqual('mock');
      let changed: number = 0;
      for (let i = 0; i < declared.length; i++) {
        // 顺序与 id 都不变（界面上的列表顺序不受影响）。
        expect(snapshot.files[i].id).assertEqual(declared[i].id);
        const expected: Uint8Array = requireAsset(harness.blobs, requireBlob(declared[i]).rawfilePath);
        expect(snapshot.files[i].size).assertEqual(formatSize(expected.length));
        if (snapshot.files[i].size !== declared[i].size) {
          changed++;
        }
      }
      // 4 条**全都**换成了真实体积（不是"原样返回站点文本"）。
      expect(changed).assertEqual(declared.length);
    });

    it('keepsTheNetworkAuditCountAtZeroForTheWholeMockFlow', 0, async () => {
      // mock 模式的硬要求：一行请求都不发。NetworkAudit 的两个真实出口
      // （HttpClient / HttpDownloadPort）都没被碰过 ⇒ 计数全程为 0。
      resetNetworkAudit();
      clearRuntimeFileSettingsOverride();
      const harness: Harness = new Harness();
      harness.seedAssets();
      const file: CourseFile = mockFiles()[0];
      await harness.repository.refresh();
      const first: FileDownloadReport =
        await harness.repository.download(requestForFile(file, false));
      const second: FileDownloadReport =
        await harness.repository.download(requestForFile(file, false));
      const refreshed: FileDownloadReport =
        await harness.repository.download(requestForFile(file, true));
      const missing: FileDownloadReport =
        await harness.repository.download(requestForUnknownBlob());
      expect(first.outcome.ok).assertTrue();
      expect(second.outcome.fromCache).assertTrue();
      expect(refreshed.outcome.ok).assertTrue();
      expect(missing.outcome.ok).assertFalse();
      expect(networkAttemptCount()).assertEqual(0);
    });

    it('failsExplicitlyWhenNoBundledAssetsAreWired', 0, async () => {
      // 没有宿主 Context 的形态（与 Settings.test.ets 的构造点一致）：
      // 不回落成"能下载"，而是显式失败 + 保留站点给的 size 文本。
      clearRuntimeFileSettingsOverride();
      const repository: MockFileRepository =
        new MockFileRepository(new DelegatingFileSystem(new FileDownloader(
          new CountingDownloadPort(new RawfileDownloadPort(new FakeBlobSource(),
            new Logger('test.mock.rawfile'))), new MemoryFileStore(), new FixedSettings(),
          new Logger('test.mock.downloader'))), null, null);
      const snapshot: FileSnapshot = await repository.refresh();
      const declared: CourseFile[] = mockFiles();
      expect(snapshot.files.length).assertEqual(declared.length);
      expect(snapshot.files[0].size).assertEqual(declared[0].size);
      const report: FileDownloadReport =
        await repository.download(requestForFile(declared[0], false));
      expect(report.outcome.ok).assertFalse();
      expect(report.outcome.error.includes('unavailable')).assertTrue();
      expect(report.requiresEnrollment).assertFalse();
    });

    it('downloadsTheJournalledSubmissionAttachmentByteForByte', 0, async () => {
      // **本轮的决定性用例**：用户刚提交的附件必须真的能打开。
      // 提交（读真实字节进台账）→ 从 mockAssignments() 取地址 → 走真实下载编排落盘 → 逐字节相同。
      clearRuntimeFileSettingsOverride();
      clearMockSubmissions();
      const harness: Harness = new Harness();
      harness.seedAssets();
      const picked: Uint8Array = bytesOf('the-selected-attachment-bytes-42!');
      const uri: string = 'file://docs/pick/实验报告.pdf';
      const reader: FakeAttachmentReader = new FakeAttachmentReader();
      reader.files.set(uri, picked);
      const plan: SubmissionPlan = {
        studentHomeworkId: 'mock-xszy-1',
        content: '见附件',
        removeAttachment: false,
        attachment: {
          uri: uri, name: '实验报告.pdf', mimeType: 'application/pdf', size: picked.length
        }
      };
      const outcome: SubmitOutcome =
        await new MockAssignmentSubmitter(new Logger('test.mock.submit'), reader)
          .submit(plan, 'req-files-a');
      expect(outcome.ok).assertTrue();
      expect(reader.reads).assertEqual(1);

      const item: Assignment | undefined = assignmentByxszyid('mock-xszy-1');
      expect(item !== undefined).assertTrue();
      let url: string = '';
      if (item !== undefined && item.submittedAttachment !== undefined) {
        url = item.submittedAttachment.downloadUrl;
      }
      expect(url.length > 0).assertTrue();
      const blob: MockFileBlob | null = mockBlobForUrl(url);
      expect(blob !== null).assertTrue();
      if (blob !== null) {
        // 由 id 里带的扩展名决定，不是猜的。
        expect(blob.contentType).assertEqual('application/pdf');
        expect(blob.rawfilePath.startsWith('mock-submitted/')).assertTrue();
      }

      const report: FileDownloadReport = await harness.repository.download(
        requestForAttachment(url, 'mock-xszy-1', '数据结构', '实验报告.pdf'));
      expect(report.outcome.ok).assertTrue();
      expect(report.outcome.bytes).assertEqual(picked.length);
      expect(report.outcome.fromCache).assertFalse();
      expect(harness.port.calls).assertEqual(1);
      // 落盘的字节与用户选中的那份**逐字节相同**（不是"大小对上了"）。
      expect(sameBytes(harness.store.bytesOf(report.outcome.path), picked)).assertTrue();
      clearMockSubmissions();
    });

    it('failsExplicitlyWhenTheSubmittedIdHasNoJournalledBytes', 0, async () => {
      // 合成前缀的 id 在台账里没有字节 ⇒ 端口显式失败、目标路径不残留文件。
      // （注意与 (d) 的区别：那个是"id 根本不存在"，这个是"id 存在、字节不在"。）
      clearRuntimeFileSettingsOverride();
      clearMockSubmissions();
      const harness: Harness = new Harness();
      harness.seedAssets();
      const url: string = 'https://learn.tsinghua.edu.cn/b/wlxt/kc/wj_download?mock='
        + buildMockSubmittedAttachmentId('mock-xszy-9', 'pdf');
      // 描述是有的（id 合法），只有字节没有。
      expect(mockBlobForUrl(url) === null).assertFalse();
      const request: FileDownloadRequest =
        requestForAttachment(url, 'mock-xszy-9', '数据结构', '台账里没有的提交附件');
      const path: string = harness.repository.targetPath(request);
      const report: FileDownloadReport = await harness.repository.download(request);
      expect(report.outcome.ok).assertFalse();
      expect(report.outcome.bytes).assertEqual(0);
      expect(report.outcome.error.includes('no journalled attachment bytes')).assertTrue();
      // 目标路径上什么都没有（连文件都没被创建）。
      expect(harness.store.exists(path)).assertFalse();
      expect(harness.store.bytesOf(path).length).assertEqual(0);
      expect(harness.store.openCalls).assertEqual(0);
      expect(report.requiresEnrollment).assertFalse();
      expect(harness.port.calls).assertEqual(1);
    });

    it('derivesTheCourseCountsAndFollowsALocalSubmission', 0, async () => {
      // 课程卡片的三个计数由 countsForCourse 算出来（与真实路径同一份实现），
      // 不是 MockData 里写死的字段；提交一条作业后该课程的未完成数减 1。
      clearRuntimeFileSettingsOverride();
      clearMockSubmissions();
      const harness: Harness = new Harness();
      harness.seedAssets();
      const courses: MockCourseRepository = new MockCourseRepository(harness.blobs);
      const before: CourseSnapshot = await courses.refresh();
      const now: number = Date.now();
      for (let i = 0; i < before.courses.length; i++) {
        const course: CourseRecord = before.courses[i];
        // 用**与实现同一个**适配器（NoticeRecord → domain Notice），否则验的是另一个函数。
        const expected: CourseCounts = countsForCourse(course.id, noticesForCounts(before.notices),
          before.assignments, before.files, now);
        expect(course.unreadNoticeCount).assertEqual(expected.unreadNoticeCount);
        expect(course.unfinishedAssignmentCount).assertEqual(expected.unfinishedAssignmentCount);
        expect(course.unreadFileCount).assertEqual(expected.unreadFileCount);
      }
      // 样例文本里大学物理写 2 条未完成，样例里只有 1 条未提交（mock-xszy-2）
      // ⇒ 权威值是算出来的 1（off-by-one 修掉）。
      const physicsId: string = '2026-2027-1-100002';
      const physicsBefore: CourseRecord | undefined = courseById(before, physicsId);
      expect(physicsBefore !== undefined).assertTrue();
      if (physicsBefore !== undefined) {
        expect(physicsBefore.unfinishedAssignmentCount).assertEqual(1);
      }

      const submitter: MockAssignmentSubmitter =
        new MockAssignmentSubmitter(new Logger('test.mock.submit'), new FakeAttachmentReader());
      const plan: SubmissionPlan = {
        studentHomeworkId: 'mock-xszy-2', content: '交作业', removeAttachment: false
      };
      const outcome: SubmitOutcome = await submitter.submit(plan, 'req-course-count');
      expect(outcome.ok).assertTrue();

      const after: CourseSnapshot = await courses.refresh();
      const physicsAfter: CourseRecord | undefined = courseById(after, physicsId);
      expect(physicsAfter !== undefined).assertTrue();
      if (physicsAfter !== undefined && physicsBefore !== undefined) {
        expect(physicsAfter.unfinishedAssignmentCount)
          .assertEqual(physicsBefore.unfinishedAssignmentCount - 1);
        expect(physicsAfter.unfinishedAssignmentCount).assertEqual(0);
      }
      // 另一门课不受影响（数据结构那条未提交作业还在）。
      const dataStructures: CourseRecord | undefined =
        courseById(after, '2026-2027-1-100001');
      expect(dataStructures !== undefined).assertTrue();
      if (dataStructures !== undefined) {
        expect(dataStructures.unfinishedAssignmentCount).assertEqual(1);
      }
      clearMockSubmissions();
    });

    it('reportsTheSameBundledSizesInTheCourseSnapshot', 0, async () => {
      // 课程详情页「文件」标签页的体积 == 「文件」tab 的体积（同一个函数算的）。
      clearRuntimeFileSettingsOverride();
      clearMockSubmissions();
      const harness: Harness = new Harness();
      harness.seedAssets();
      const courses: MockCourseRepository = new MockCourseRepository(harness.blobs);
      const snapshot: CourseSnapshot = await courses.refresh();
      const declared: CourseFile[] = mockFiles();
      expect(snapshot.files.length).assertEqual(declared.length);
      let changed: number = 0;
      for (let i = 0; i < declared.length; i++) {
        expect(snapshot.files[i].id).assertEqual(declared[i].id);
        const expected: Uint8Array = requireAsset(harness.blobs, requireBlob(declared[i]).rawfilePath);
        expect(snapshot.files[i].size).assertEqual(formatSize(expected.length));
        if (snapshot.files[i].size !== declared[i].size) {
          changed++;
        }
      }
      // 全部换成了真实体积（不是原样返回站点文本）。
      expect(changed).assertEqual(declared.length);
      const filesTab: FileSnapshot = await harness.repository.refresh();
      expect(filesTab.files.length).assertEqual(snapshot.files.length);
      for (let i = 0; i < declared.length; i++) {
        expect(snapshot.files[i].size).assertEqual(filesTab.files[i].size);
      }
    });

    it('downloadsTheNoticeAttachmentSample', 0, async () => {
      // 公告附件此前是 ?mock=1（MockFileBlobs 不认识）⇒ 点开必失败；现在指向包内的
      // mock-notice-attachment.pdf（清单第 5 条，mock=105）。
      clearRuntimeFileSettingsOverride();
      clearMockSubmissions();
      const harness: Harness = new Harness();
      harness.seedAssets();
      const attached: NoticeRecord[] = mockNotices()
        .filter((notice: NoticeRecord): boolean => notice.attachment !== undefined);
      expect(attached.length > 0).assertTrue();
      if (attached.length === 0) {
        return;
      }
      const notice: NoticeRecord = attached[0];
      const attachment: Attachment | undefined = notice.attachment;
      expect(attachment !== undefined).assertTrue();
      if (attachment === undefined) {
        return;
      }
      const blob: MockFileBlob | null = mockBlobForUrl(attachment.downloadUrl);
      expect(blob !== null).assertTrue();
      if (blob !== null) {
        expect(blob.mockId).assertEqual(MOCK_NOTICE_ATTACHMENT_MOCK_ID);
        expect(blob.contentType).assertEqual('application/pdf');
      }
      const cacheKey: string = attachment.id === undefined ? 'mock-wjid-105' : attachment.id;
      const report: FileDownloadReport = await harness.repository.download(
        requestForAttachment(attachment.downloadUrl, cacheKey, notice.courseName, attachment.name));
      expect(report.outcome.ok).assertTrue();
      expect(report.outcome.bytes > 0).assertTrue();
      expect(harness.store.bytesOf(report.outcome.path).length).assertEqual(report.outcome.bytes);
    });

    it('keepsTheNetworkAuditCountAtZeroAcrossFilesSubmissionsAndNotices', 0, async () => {
      // 上面全过程（文件下载 / 本地提交 / 提交附件下载 / 公告附件下载 / 课程快照推导）
      // 一行请求都不发。只比"前后相等"，不 resetNetworkAudit()：那是别的用例也读的全局量。
      clearRuntimeFileSettingsOverride();
      clearMockSubmissions();
      const before: number = networkAttemptCount();
      const harness: Harness = new Harness();
      harness.seedAssets();

      const file: CourseFile = mockFiles()[0];
      const fileReport: FileDownloadReport =
        await harness.repository.download(requestForFile(file, false));
      expect(fileReport.outcome.ok).assertTrue();

      const picked: Uint8Array = bytesOf('zero-network-attachment-bytes');
      const uri: string = 'file://docs/pick/零网络.pdf';
      const reader: FakeAttachmentReader = new FakeAttachmentReader();
      reader.files.set(uri, picked);
      const submitter: MockAssignmentSubmitter =
        new MockAssignmentSubmitter(new Logger('test.mock.submit'), reader);
      const plan: SubmissionPlan = {
        studentHomeworkId: 'mock-xszy-1',
        content: '零网络',
        removeAttachment: false,
        attachment: {
          uri: uri, name: '零网络.pdf', mimeType: 'application/pdf', size: picked.length
        }
      };
      await submitter.submit(plan, 'req-zero-network');
      const item: Assignment | undefined = assignmentByxszyid('mock-xszy-1');
      expect(item !== undefined).assertTrue();
      if (item !== undefined && item.submittedAttachment !== undefined) {
        const submittedReport: FileDownloadReport = await harness.repository.download(
          requestForAttachment(item.submittedAttachment.downloadUrl, 'mock-xszy-1',
            '数据结构', item.submittedAttachment.name));
        expect(submittedReport.outcome.ok).assertTrue();
      } else {
        expect(false).assertTrue();
      }

      const attached: NoticeRecord[] = mockNotices()
        .filter((notice: NoticeRecord): boolean => notice.attachment !== undefined);
      for (let i = 0; i < attached.length; i++) {
        const noticeAttachment: Attachment | undefined = attached[i].attachment;
        if (noticeAttachment === undefined) {
          continue;
        }
        const cacheKey: string =
          noticeAttachment.id === undefined ? 'mock-wjid-105' : noticeAttachment.id;
        const noticeReport: FileDownloadReport = await harness.repository.download(
          requestForAttachment(noticeAttachment.downloadUrl, cacheKey, attached[i].courseName,
            noticeAttachment.name));
        expect(noticeReport.outcome.ok).assertTrue();
      }

      const snapshot: CourseSnapshot =
        await new MockCourseRepository(harness.blobs).refresh();
      expect(snapshot.courses.length > 0).assertTrue();

      const missing: FileDownloadReport =
        await harness.repository.download(requestForUnknownBlob());
      expect(missing.outcome.ok).assertFalse();
      expect(networkAttemptCount()).assertEqual(before);
      clearMockSubmissions();
    });
  });
}
