/*
 * Mock 文件数据源（data/mock，ticket 17）。
 *
 * **只有取数走样例**；文件系统那三件事（`targetPath` / `cacheRoot` / `clearCache`）**委托给真实实现** ——
 * 它们本来就不发请求，而在 mock 模式下"文件设置"子页仍要显示真实的落盘根目录。
 *
 * `download()` **不委托**：它**不做任何网络动作**，直接返回一条显式失败并把原因写清楚
 * （参考实现的 mock 文件本来也没有可下载的真地址；ticket 17 的验收要求"不发起真实网络请求"）。
 */

import { Logger } from '../../core/log/Logger';
import { networkAttemptCount } from '../remote/NetworkAudit';
import {
  ClearCacheResult, DownloadProgressSink, FileDownloadRequest
} from '../files/FileDownloader';
import { FileDownloadReport, FileRepository, FileSnapshot } from '../files/FileRepository';
import { mockFiles } from './MockData';

const logger: Logger = new Logger('data.mock.files');

export class MockFileRepository implements FileRepository {
  /** 真实实现只用来做"文件系统"那三件事（不取数、不发请求）。 */
  private readonly fileSystem: FileRepository;

  constructor(fileSystem: FileRepository) {
    this.fileSystem = fileSystem;
  }

  async refresh(): Promise<FileSnapshot> {
    const files = mockFiles();
    const snapshot: FileSnapshot = {
      files: files,
      semesterId: 'mock',
      fetchedAtMillis: Date.now()
    };
    logger.info('mock file snapshot served: files=' + files.length.toString()
      + ' networkAttempts=' + networkAttemptCount().toString());
    return snapshot;
  }

  async download(request: FileDownloadRequest,
    onProgress?: DownloadProgressSink): Promise<FileDownloadReport> {
    logger.info('mock download refused (no network in mock mode): url=' + request.downloadUrl
      + ' networkAttempts=' + networkAttemptCount().toString());
    return {
      outcome: {
        ok: false,
        path: '',
        bytes: 0,
        fromCache: false,
        rejectedReason: '',
        error: 'mock mode: downloads are not performed'
      },
      requiresEnrollment: false,
      diagnostic: 'mock mode: download short-circuited before any network call'
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
