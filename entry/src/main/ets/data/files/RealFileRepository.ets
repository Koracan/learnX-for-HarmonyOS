/*
 * 真实文件仓储（data/files）：取数 + 下载都走 `AuthedTaskRunner`
 * （data/auth/SessionRestore：先确保有会话 + 会话失效时重登且**只重试一次** + 失败显式降级）。
 * 本文件**不自己造重登/重试/降级逻辑**（AGENTS.md 的硬约束）。
 *
 * ## 下载这条路上"会话失效"是怎么被识别的
 *
 * 1. 落盘前判定（`domain/files/FileDownloadPolicy`）在响应头到达时看 `Content-Type`：
 *    命中 `text/html`（平台自动跟随 302 后，登录页就是这个形态）⇒ **一个字节都不写**，
 *    并给出 `html-login-page` 这个明确原因；
 * 2. 本文件把这个原因翻成任务结果 `status=403`（`isNoLoginResponse` 的既有判据之一），
 *    于是 `SessionGate` 走它**既有的**"重登 + 只重试一次"分支——**不新增任何重试逻辑**；
 * 3. 重登后仍是登录页 ⇒ `requiresEnrollment=true` ⇒ 界面显示 `loh_session_expired`
 *    并**没有**留下文件。
 *
 * 非会话原因的失败（网络、写盘、非 200 且非 403）**不**触发重登：任务返回 200，
 * 由 `outcome.error` 驱动界面错误态（否则一次断网会白跑一次登录）。
 */

import { Logger } from '../../core/log/Logger';
import { isSessionLossReason } from '../../domain/files/FileDownloadPolicy';
import { TaskOutcome } from '../auth/ReAuth';
import { AuthedRunResult } from '../auth/SessionRestore';
import { Session } from '../remote/Requests';
import { AuthedTaskExecutor } from '../notices/RealNoticeRepository';
import {
  ClearCacheResult, DownloadProgressSink, FileDownloadOutcome, FileDownloadRequest, FileDownloader
} from './FileDownloader';
import { FileFetchResult, FileFetchSource } from './FileFetchSource';
import { FileDownloadReport, FileRepository, FileSnapshot } from './FileRepository';

/** 真实的文件数据源。 */
export class RealFileRepository implements FileRepository {
  private readonly executor: AuthedTaskExecutor;
  private readonly source: FileFetchSource;
  private readonly downloader: FileDownloader;
  private readonly logger: Logger;
  /**
   * 闭包带出来的取数结果（每次 refresh 重新赋值；不塞进 TaskOutcome 的字符串里）。
   *
   * 为什么是"哨兵值 + 布尔标记"而不是 `| null`：ArkTS 的流分析看不到闭包里的赋值，
   * 会把字段窄化成 `null`，随后 `result.files` 直接报
   * "Property 'files' does not exist on type 'never'"（实测）。
   */
  private fetched: FileFetchResult = emptyFetchResult();
  private fetchedSet: boolean = false;
  /** 闭包带出来的下载结果（同上；重试时会被第二次尝试覆盖）。 */
  private pending: FileDownloadOutcome = emptyDownloadOutcome();
  private pendingSet: boolean = false;

  constructor(executor: AuthedTaskExecutor, source: FileFetchSource, downloader: FileDownloader,
    logger: Logger) {
    this.executor = executor;
    this.source = source;
    this.downloader = downloader;
    this.logger = logger;
  }

  async refresh(): Promise<FileSnapshot> {
    const startedAt: number = Date.now();
    this.fetchedSet = false;
    const run: AuthedRunResult = await this.executor.run(
      async (session: Session): Promise<TaskOutcome> => {
        // 学期由取数源按**唯一的优先级实现**决定（覆盖 > 界面选择 > 站点当前）：这里显式
        // 传空串，让进程级的界面选择那条路径生效（此前这一行根本不带学期）。
        const result: FileFetchResult = await this.source.fetchWithSession(session, '');
        this.fetched = result;
        this.fetchedSet = true;
        // 0 条 = 失败信号：交给 SessionGate 的 '[]' 判据（与 RealNoticeRepository 同一口径）。
        return {
          status: 200,
          body: result.files.length === 0 ? '[]' : 'ok:' + result.files.length.toString(),
          responseUrl: ''
        };
      });
    if (!run.ok || run.requiresEnrollment) {
      throw new Error('file refresh degraded: requiresEnrollment=true reason=' + run.reason
        + ' reAuth=' + run.reAuthAttempted.toString() + ' diag=' + run.diagnostic);
    }
    if (!this.fetchedSet) {
      throw new Error('file refresh produced no result (source did not run)');
    }
    const result: FileFetchResult = this.fetched;
    const snapshot: FileSnapshot = {
      files: result.files,
      semesterId: result.semesterId,
      fetchedAtMillis: Date.now()
    };
    this.logger.info('files refresh done: items=' + snapshot.files.length.toString()
      + ' semester=' + snapshot.semesterId
      + ' elapsedMs=' + (Date.now() - startedAt).toString());
    return snapshot;
  }

  async download(request: FileDownloadRequest,
    onProgress?: DownloadProgressSink): Promise<FileDownloadReport> {
    this.pendingSet = false;
    const run: AuthedRunResult = await this.executor.run(
      async (session: Session): Promise<TaskOutcome> => {
        const outcome: FileDownloadOutcome = await this.downloader.download(session, request, onProgress);
        this.pending = outcome;
        this.pendingSet = true;
        if (!outcome.ok && isSessionLossReason(outcome.rejectedReason)) {
          // 借 noLogin 的既有判据（403）触发 SessionGate 的重登 + 只重试一次。
          return { status: 403, body: '', responseUrl: request.downloadUrl };
        }
        // 其余失败不触发重登：body 既不是 '[]' 也不含 login_timeout。
        return { status: 200, body: 'download-attempted', responseUrl: request.downloadUrl };
      });
    const outcome: FileDownloadOutcome = this.pendingSet ? this.pending : emptyDownloadOutcome();
    this.logger.info('file download report: ok=' + outcome.ok.toString()
      + ' bytes=' + outcome.bytes.toString()
      + ' fromCache=' + outcome.fromCache.toString()
      + ' rejected=' + outcome.rejectedReason
      + ' requiresEnrollment=' + run.requiresEnrollment.toString()
      + ' diag=' + run.diagnostic);
    return {
      outcome: outcome,
      requiresEnrollment: run.requiresEnrollment,
      diagnostic: run.diagnostic
    };
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

/** 取数结果的哨兵（"这次 source 没跑过"）。 */
function emptyFetchResult(): FileFetchResult {
  return { files: [], semesterId: '', siteCurrentSemesterId: '' };
}

/** 下载结果的哨兵（"这次下载器没跑过" ⇒ 明确失败）。 */
function emptyDownloadOutcome(): FileDownloadOutcome {
  return {
    ok: false, path: '', bytes: 0, fromCache: false, rejectedReason: '',
    error: 'download produced no result (source did not run)'
  };
}
