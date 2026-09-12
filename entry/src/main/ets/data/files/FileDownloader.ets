/*
 * 下载编排（data/files）：把"路径规则 → 缓存命中 → 落盘前判定 → 写文件 → 收尾校验"
 * 串成一次调用。**所有平台能力都是注入的**（`DownloadPort` / `FileStore` / 设置来源），
 * 于是单测能在没有任何设备的情况下断言：
 *   - 命中 `text/html`（登录页）时 **`openSink` 一次都没被调用**（= 真的没落盘）；
 *   - 失败路径下目标路径**不存在**（= 不留下损坏文件）；
 *   - 中文与空格的路径按参考实现的形状拼出来。
 *
 * ## 与参考实现的差异（逐条，全部有理由）
 *
 * | 项 | 参考实现 `helpers/fs.ts:97-166` | 这里 |
 * | --- | --- | --- |
 * | 判定时机 | 先落盘，再 `stat` + 小文件含 `<html` 猜（台账第 1 条） | **响应头到达即判**，HTML/JSON 一个字节都不写 |
 * | 进度 | 平台库的 `progress` 回调（该库 `bytesWritten` 恒 0） | 平台 HTTP 层的 `dataReceive` 真实字节数 + `Content-Length` |
 * | 状态码 | 落盘后查 | 流结束后查（平台只在流结束给状态码，见 HttpDownloadPort 的说明） |
 * | 缓存键 | `file.id`（空串时会互相覆盖） | `cacheKeyFor(id, downloadUrl)` 兜底到地址末段（ticket 10 边界说明第 2 条） |
 */

import { Logger } from '../../core/log/Logger';
import {
  appendCsrfToken, evaluateDownloadContentType, evaluateDownloadStatus, redactCsrfToken,
  DownloadDecision
} from '../../domain/files/FileDownloadPolicy';
import {
  fileDirectory, learnXFilesRoot, localFilePath
} from '../../domain/files/FilePath';
import { DownloadHeaders, DownloadPort, DownloadSink, DownloadStreamResult } from '../remote/DownloadPort';
import { Session } from '../remote/Requests';
import { FileSettings, FileSettingsSource } from '../settings/FileSettings';
import { FileSink, FileStore } from './FileStorePort';

/** 一次下载请求（字段来自 FileDetail 路由参数；`cacheKey` 已按 cacheKeyFor 兜底）。 */
export interface FileDownloadRequest {
  downloadUrl: string;
  /** 缓存目录名 / 去重键。 */
  cacheKey: string;
  courseName: string;
  /** 展示用标题（参考实现的 `file.title`，已去扩展名）。 */
  title: string;
  /** 扩展名（参考实现的 `file.fileType`）；空串表示没有扩展名。 */
  fileType: string;
  /** true = 忽略已有缓存，强制重新下载（参考实现的 `handleDownload(true)`）。 */
  refresh: boolean;
}

/** 一次下载的结果。 */
export interface FileDownloadOutcome {
  ok: boolean;
  /** 目标路径（失败时也有值：便于日志判读"打算写到哪"）。 */
  path: string;
  /** 落盘后的真实字节数（失败/未落盘时为 0）。 */
  bytes: number;
  /** true = 命中已有缓存（没有发请求）。 */
  fromCache: boolean;
  /** '' = 没有拒绝；否则是落盘前判定给出的原因。 */
  rejectedReason: string;
  /** '' = 无错误；否则是失败说明。 */
  error: string;
}

/** 进度回调：已接收字节 + 总字节（`total < 0` = 服务端没给 Content-Length）。 */
export type DownloadProgressSink = (received: number, total: number) => void;

/** "清理缓存"的结果。 */
export interface ClearCacheResult {
  ok: boolean;
  /** 被清掉的根目录（进日志与界面）。 */
  root: string;
  error: string;
}

/** 下载落点的 sink：`onHeaders` 里做判定，**只有被接受才创建文件**。 */
class DownloadFileSink implements DownloadSink {
  private readonly store: FileStore;
  private readonly path: string;
  private readonly onProgress: DownloadProgressSink | undefined;
  private handle: FileSink | null = null;
  private rejectedReason: string = '';
  private failure: string = '';
  private received: number = 0;
  private total: number = -1;
  private accepted: boolean = false;

  constructor(store: FileStore, path: string, onProgress: DownloadProgressSink | undefined) {
    this.store = store;
    this.path = path;
    this.onProgress = onProgress;
  }

  onHeaders(headers: DownloadHeaders): boolean {
    this.total = headers.contentLength;
    const decision: DownloadDecision = evaluateDownloadContentType(headers.contentType);
    if (!decision.accept) {
      this.rejectedReason = decision.reason;
      return false;
    }
    try {
      this.handle = this.store.openSink(this.path);
    } catch (error) {
      this.failure = 'open failed: ' + (error as Error).message;
      return false;
    }
    this.accepted = true;
    return true;
  }

  onChunk(chunk: ArrayBuffer): void {
    const handle: FileSink | null = this.handle;
    if (handle === null) {
      return;
    }
    handle.write(chunk);
    this.received += chunk.byteLength;
    if (this.onProgress !== undefined) {
      this.onProgress(this.received, this.total);
    }
  }

  close(): void {
    const handle: FileSink | null = this.handle;
    if (handle === null) {
      return;
    }
    this.handle = null;
    handle.close();
  }

  abort(): void {
    const handle: FileSink | null = this.handle;
    if (handle === null) {
      return;
    }
    this.handle = null;
    handle.abort();
  }

  isAccepted(): boolean {
    return this.accepted;
  }

  reason(): string {
    return this.rejectedReason;
  }

  error(): string {
    return this.failure;
  }

  bytesWritten(): number {
    return this.received;
  }
}

/** 下载编排器。 */
export class FileDownloader {
  private readonly port: DownloadPort;
  private readonly store: FileStore;
  private readonly settings: FileSettingsSource;
  private readonly logger: Logger;

  constructor(port: DownloadPort, store: FileStore, settings: FileSettingsSource, logger: Logger) {
    this.port = port;
    this.store = store;
    this.settings = settings;
    this.logger = logger;
  }

  /** 当前生效的落盘根目录（"清理缓存"要删的就是它）。 */
  cacheRoot(): string {
    const settings: FileSettings = this.settings.current();
    const roots = this.store.roots();
    return learnXFilesRoot(roots.filesDir, roots.cacheDir, settings.useDocumentDir);
  }

  /**
   * 清空文件缓存目录（参考实现 `removeFileDir()`，helpers/fs.ts:205-210）。
   *
   * 参考实现删的是**整个 `learnX-files` 目录**（不论它落在文档还是缓存下），这里照做：
   * 于是"使用文档目录"打开时也一并清掉（否则会出现"清了缓存但文件还在"）。
   * 返回删除是否真的生效（`exists` 复查），而不是"调用没抛异常"。
   */
  clearCache(): ClearCacheResult {
    const root: string = this.cacheRoot();
    this.store.removeTree(root);
    const stillThere: boolean = this.store.exists(root);
    this.logger.info('file cache cleared: root=' + root + ' removed=' + (!stillThere).toString());
    return { ok: !stillThere, root: root, error: stillThere ? 'directory still exists after removeTree' : '' };
  }

  /** 目标路径（界面用来显示"保存在哪"，也是缓存的键）。 */
  targetPath(request: FileDownloadRequest): string {
    const settings: FileSettings = this.settings.current();
    const roots = this.store.roots();
    const root: string = learnXFilesRoot(roots.filesDir, roots.cacheDir, settings.useDocumentDir);
    return localFilePath(root, request.courseName, request.cacheKey, request.title,
      request.fileType, settings.omitCourseName);
  }

  async download(session: Session, request: FileDownloadRequest,
    onProgress?: DownloadProgressSink): Promise<FileDownloadOutcome> {
    const settings: FileSettings = this.settings.current();
    const roots = this.store.roots();
    const root: string = learnXFilesRoot(roots.filesDir, roots.cacheDir, settings.useDocumentDir);
    const dir: string = fileDirectory(root, request.courseName, request.cacheKey);
    const path: string = localFilePath(root, request.courseName, request.cacheKey, request.title,
      request.fileType, settings.omitCourseName);

    // 消费点自证（AGENTS.md：开关必须打在谁读它、谁用它）：这一行同时钉住"根目录"
    // 与"文件名形状"两件事，于是"设置是否生效"在 hilog 里是可判读的。
    this.logger.info('file download plan: ' + describePlan(settings, root, dir, path)
      + ' refresh=' + request.refresh.toString());

    if (!request.refresh && this.store.exists(path)) {
      const cachedBytes: number = this.store.fileSize(path);
      this.logger.info('file download: cache hit bytes=' + cachedBytes.toString() + ' path=' + path);
      return {
        ok: cachedBytes > 0, path: path, bytes: cachedBytes, fromCache: true,
        rejectedReason: '', error: cachedBytes > 0 ? '' : 'cached file is empty'
      };
    }

    const url: string = appendCsrfToken(request.downloadUrl, session.csrfToken);
    this.logger.info('file download: GET ' + redactCsrfToken(url));
    const sink: DownloadFileSink = new DownloadFileSink(this.store, path, onProgress);
    let stream: DownloadStreamResult;
    try {
      this.store.ensureDir(dir);
      stream = await this.port.download(session, url, sink);
    } catch (error) {
      sink.abort();
      this.store.remove(path);
      const message: string = (error as Error).message;
      this.logger.warn('file download failed (transport threw): ' + message);
      return { ok: false, path: path, bytes: 0, fromCache: false, rejectedReason: '', error: message };
    }

    if (stream.rejected) {
      sink.abort();
      this.store.remove(path);
      const reason: string = sink.reason().length > 0 ? sink.reason() : 'rejected-by-policy';
      this.logger.warn('file download rejected before writing: reason=' + reason
        + ' status=' + stream.status.toString() + ' contentType="' + stream.contentType + '"');
      return {
        ok: false, path: path, bytes: 0, fromCache: false,
        rejectedReason: reason, error: sink.error()
      };
    }

    if (stream.error !== undefined) {
      sink.abort();
      this.store.remove(path);
      this.logger.warn('file download failed (stream error): ' + stream.error);
      return {
        ok: false, path: path, bytes: 0, fromCache: false, rejectedReason: '', error: stream.error
      };
    }

    sink.close();

    // 状态码：平台只在流结束后给（见 HttpDownloadPort 文件头），所以这一步是"事后删除"，
    // 而不是"事前拦截"。真正要拦的会话失效形态（200 + text/html）已在 onHeaders 拦下。
    const statusDecision: DownloadDecision = evaluateDownloadStatus(stream.status);
    if (!statusDecision.accept) {
      this.store.remove(path);
      this.logger.warn('file download rejected after stream: reason=' + statusDecision.reason
        + ' bytes=' + sink.bytesWritten().toString());
      return {
        ok: false, path: path, bytes: 0, fromCache: false,
        rejectedReason: statusDecision.reason, error: ''
      };
    }

    const bytes: number = this.store.fileSize(path);
    if (bytes <= 0) {
      this.store.remove(path);
      this.logger.warn('file download produced an empty file: status=' + stream.status.toString()
        + ' received=' + stream.receivedBytes.toString());
      return {
        ok: false, path: path, bytes: 0, fromCache: false, rejectedReason: '', error: 'empty file'
      };
    }

    this.logger.info('file download done: bytes=' + bytes.toString()
      + ' expected=' + stream.contentLength.toString()
      + ' contentType="' + stream.contentType + '" path=' + path);
    return { ok: true, path: path, bytes: bytes, fromCache: false, rejectedReason: '', error: '' };
  }
}

/** 消费点自证串（根目录 + 文件名形状 + 两个设置的生效值）。 */
function describePlan(settings: FileSettings, root: string, dir: string, path: string): string {
  return 'useDocumentDir=' + settings.useDocumentDir.toString()
    + ' omitCourseName=' + settings.omitCourseName.toString()
    + ' root=' + root
    + ' dir=' + dir
    + ' path=' + path;
}
