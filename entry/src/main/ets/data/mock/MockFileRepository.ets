/*
 * Mock 文件数据源（data/mock）。
 *
 * ## 取数走样例；文件系统与**下载编排**都走真实实现
 *
 *   - refresh()：返回 mockFiles()，但把每条 size 换成**包内那份样例的真实字节数**
 *     （用 domain/files/FilePath.formatSize 格式化，与站点口径一致）。于是
 *     「列表上显示的大小 / 下载进度总量 / 落盘后的大小」三者一致，不会出现
 *     "写着 268.31KB、下载下来 3.71KB"这种自相矛盾。
 *   - download()：委托给一个**真实的 FileDownloader**（data/files），只是它的 DownloadPort
 *     是 RawfileDownloadPort（从包内资产喂字节）。于是缓存命中、落盘路径规则、设置
 *     （文档目录 / 省略课程名）、fileSize 收尾校验全部照旧复用 —— mock 里**没有**第二套
 *     下载逻辑（AGENTS.md 的硬约束：不要在 mock 里重写一遍）。
 *   - targetPath / cacheRoot / clearCache：继续委托真实仓储（它们本来就不发请求，
 *     而 mock 模式下"文件设置"子页仍要显示真实的落盘根目录）。
 *
 * ## 与前一版的差异（有意，且是本 ticket 的全部要点）
 *
 * 前一版 download() 直接返回一条显式失败（"mock mode: downloads are not performed"），
 * 于是详情页停在错误态 ⇒ 预览 / 交给系统打开 / 分享 / 清缓存**全都用不了**
 * （详情页是进页即自动下载）。现在改成"从包里喂字节"，**仍然一行网络请求都不发**：
 * RawfileDownloadPort 不碰 HttpClient 与 HttpDownloadPort，NetworkAudit 计数不变。
 *
 * ## 那个合成会话是哪来的
 *
 * FileDownloader 的签名要吃一个 Session（它要往地址上追加 _csrf）。mock 下没有真实会话，
 * 所以这里传一个**空会话**常量：_csrf= 会被追加到地址上，而 RawfileDownloadPort 只读
 * mock 参数，追加成什么值都不影响结果。这是"复用真实编排"的代价，也正是它值得的地方 ——
 * 缓存与落盘那几百行不必在 mock 里重写一遍。
 *
 * ## 为什么 downloader / blobs 是可为空的
 *
 * 拿不到宿主 Context 时（host 单测、极端失败态）既没有 rawfile 也没有落盘根目录。
 * 这时**不回落成"能下载"**：download() 返回显式失败、refresh() 保留站点给的 size 文本，
 * 与 features/files/repository/FileRepositoryProvider 的既有口径一致（Context 拿不到时
 * 该 provider 返回的也是一个"永远失败"的仓储）。
 */

import { Logger } from '../../core/log/Logger';
import { formatSize } from '../../domain/files/FilePath';
import { CourseFile } from '../../domain/model/ContentItem';
import { networkAttemptCount } from '../remote/NetworkAudit';
import { Session } from '../remote/Requests';
import {
  ClearCacheResult, DownloadProgressSink, FileDownloadOutcome, FileDownloadRequest, FileDownloader
} from '../files/FileDownloader';
import { FileDownloadReport, FileRepository, FileSnapshot } from '../files/FileRepository';
import { mockFiles } from './MockData';
import { MockBlobSource, MockFileBlob, mockBlobForUrl } from './MockFileBlobs';

const logger: Logger = new Logger('data.mock.files');

/** mock 下的合成会话（见文件头：只为满足真实编排的签名，不发任何请求）。 */
const MOCK_SESSION: Session = { cookie: '', csrfToken: '' };

export class MockFileRepository implements FileRepository {
  /** 真实实现只用来做"文件系统"那三件事（不取数、不发请求）。 */
  private readonly fileSystem: FileRepository;
  /** 真实的下载编排（端口是包内资产）；Context 不可用时为 null。 */
  private readonly downloader: FileDownloader | null;
  /** 读包内样例字节的端口（refresh 算真实体积、下载器喂字节，共用同一份）。 */
  private readonly blobs: MockBlobSource | null;

  constructor(fileSystem: FileRepository, downloader: FileDownloader | null,
    blobs: MockBlobSource | null) {
    this.fileSystem = fileSystem;
    this.downloader = downloader;
    this.blobs = blobs;
  }

  async refresh(): Promise<FileSnapshot> {
    const declared: CourseFile[] = mockFiles();
    const files: CourseFile[] = [];
    let sized: number = 0;
    for (let i = 0; i < declared.length; i++) {
      const file: CourseFile = declared[i];
      const bytes: number = this.blobLength(file.downloadUrl);
      if (bytes >= 0) {
        sized++;
      }
      files.push(copyWithSize(file, bytes >= 0 ? formatSize(bytes) : file.size));
    }
    const snapshot: FileSnapshot = {
      files: files,
      semesterId: 'mock',
      fetchedAtMillis: Date.now()
    };
    logger.info('mock file snapshot served: files=' + files.length.toString()
      + ' sizesFromBundledAssets=' + sized.toString()
      + ' unresolvedSizes=' + (files.length - sized).toString()
      + ' networkAttempts=' + networkAttemptCount().toString());
    return snapshot;
  }

  /** 包内样例的字节数；取不到（没有端口 / 没有该 id / 读失败）返回 -1 = 保留站点给的 size。 */
  private blobLength(url: string): number {
    const source: MockBlobSource | null = this.blobs;
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
      logger.warn('mock file size unresolved: asset=' + blob.rawfilePath
        + ' reason=' + (error as Error).message);
      return -1;
    }
  }

  async download(request: FileDownloadRequest,
    onProgress?: DownloadProgressSink): Promise<FileDownloadReport> {
    const downloader: FileDownloader | null = this.downloader;
    if (downloader === null) {
      logger.warn('mock download unavailable: bundled assets are not wired (no host context)');
      return {
        outcome: {
          ok: false, path: '', bytes: 0, fromCache: false, rejectedReason: '',
          error: 'mock mode: bundled sample files are unavailable (no host context)'
        },
        requiresEnrollment: false,
        diagnostic: 'mock mode: no bundled assets wired; nothing was written'
      };
    }
    const outcome: FileDownloadOutcome =
      await downloader.download(MOCK_SESSION, request, onProgress);
    logger.info('mock download via the real orchestration: ok=' + outcome.ok.toString()
      + ' bytes=' + outcome.bytes.toString()
      + ' fromCache=' + outcome.fromCache.toString()
      + ' path=' + outcome.path
      + ' rejected=' + outcome.rejectedReason
      + ' error=' + outcome.error
      + ' networkAttempts=' + networkAttemptCount().toString());
    return {
      outcome: outcome,
      requiresEnrollment: false,
      diagnostic: 'mock mode: download served from bundled rawfile assets (zero network)'
    };
  }

  targetPath(request: FileDownloadRequest): string {
    return this.fileSystem.targetPath(request);
  }

  cacheRoot(): string {
    return this.fileSystem.cacheRoot();
  }

  clearCache(): ClearCacheResult {
    return this.fileSystem.clearCache();
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
