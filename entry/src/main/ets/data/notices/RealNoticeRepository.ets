/*
 * 真实公告仓储（data/notices，ticket 09）：把三件事接起来——
 *   1. **取数**：走 `AuthedTaskRunner`（数据路径的统一入口），它负责"先确保有会话
 *      （冷启动就是那次纯 HTTP 重登）+ 会话失效时重登且只重试一次 + 失败显式降级"；
 *      本文件**不自己造重登/重试/降级逻辑**（AGENTS.md 的硬约束）。
 *   2. **映射**：domain/parse/NoticeParser 的 `Notice` → 界面用的 `NoticeRecord`。
 *   3. **快照**：抓取成功后落盘（抓取时间 + 结构版本），冷启动先读它。
 *
 * 两个"绝不"：
 *   - **绝不用空列表兜底**：取数失败一律 reject；`AuthedRunResult.requiresEnrollment`
 *     为真时抛错，并带 `requiresEnrollment=true` 的标记（界面据此回登录页）。
 *     spec 第 5 节与 ticket 03/08 的验收都要求"不把空列表交给界面"。
 *   - **绝不让快照损坏变成崩溃**：读/解码/写三处都不抛（见 NoticeSnapshotSerialization）。
 */

import { Logger } from '../../core/log/Logger';
import { Attachment, Notice } from '../../domain/model/ContentItem';
import { parseNoticeTime } from './NoticeTime';
import { AuthedRunResult, SessionTask } from '../auth/SessionRestore';
import { TaskOutcome } from '../auth/ReAuth';
import { Session } from '../remote/Requests';
import {
  NOTICE_SNAPSHOT_SCHEMA_VERSION, NoticeRecord, NoticeRepository, NoticeSnapshot
} from './NoticeRepository';
import {
  SnapshotDecodeResult, encodeNoticeSnapshot, snapshotFromDecoded
} from './NoticeSnapshotSerialization';
import { NoticeSnapshotPort, SnapshotLoadResult, SnapshotSaveResult } from './NoticeSnapshotStore';

/**
 * 任务执行器端口：设备侧就是 `AuthedTaskRunner`，测试里是替身。
 *
 * 签名**逐字**用 data/auth 的 `SessionTask` / `TaskOutcome`（而不是本地另立一套同形类型）：
 * ArkTS 不做结构类型（arkts-no-structural-typing），本地别名会让
 * `const e: AuthedTaskExecutor = authServices.runner` 直接编译失败（ticket 09 实测）。
 */
export interface AuthedTaskExecutor {
  run(task: SessionTask): Promise<AuthedRunResult>;
}

/** 公告抓取端口：设备侧是"课程列表 + NoticesFetcher"，测试里是替身。 */
export interface NoticeFetchSource {
  /** 在给定会话里抓取全部公告；失败时抛出（消息进日志）。 */
  fetchWithSession(session: Session): Promise<Notice[]>;
}

/** `Notice`（domain） → `NoticeRecord`（界面）。字段一一对应，不做额外加工。 */
export function noticeRecordOf(notice: Notice): NoticeRecord {
  const record: NoticeRecord = {
    id: notice.id,
    title: notice.title,
    content: notice.content,
    publisher: notice.publisher,
    courseId: notice.courseId,
    courseName: notice.courseName,
    courseTeacherName: notice.courseTeacherName,
    publishTimeMillis: parseNoticeTime(notice.publishTime),
    hasRead: notice.hasRead,
    markedImportant: notice.markedImportant,
    url: notice.url
  };
  const attachment: Attachment | undefined = notice.attachment;
  if (attachment !== undefined) {
    record.attachment = attachment;
  }
  return record;
}

/** 真实公告数据源。 */
export class RealNoticeRepository implements NoticeRepository {
  private readonly executor: AuthedTaskExecutor;
  private readonly source: NoticeFetchSource;
  private readonly snapshots: NoticeSnapshotPort;
  private readonly logger: Logger;
  /** 闭包带出来的抓取结果（每次 refresh 重新赋值；不放进 TaskOutcome 的字符串里）。 */
  private fetched: Notice[] = [];

  constructor(executor: AuthedTaskExecutor, source: NoticeFetchSource, snapshots: NoticeSnapshotPort,
    logger: Logger) {
    this.executor = executor;
    this.source = source;
    this.snapshots = snapshots;
    this.logger = logger;
  }

  /**
   * 读上次快照。首次运行 / 版本不符 / 内容损坏都返回 null，并落一行**带原因**的日志——
   * "没有快照"与"有快照但被丢弃"必须能区分（验收第 6 条要求能识别旧版本并丢弃重建）。
   */
  async loadSnapshot(): Promise<NoticeSnapshot | null> {
    const result: SnapshotLoadResult = await this.snapshots.load();
    if (!result.present) {
      this.logger.info('snapshot absent: cold start has nothing to show yet');
      return null;
    }
    const decoded: SnapshotDecodeResult = result.decoded;
    if (decoded.discardReason.length > 0) {
      this.logger.warn('snapshot discarded: reason=' + decoded.discardReason
        + ' onDiskVersion=' + decoded.onDiskVersion.toString()
        + ' currentVersion=' + NOTICE_SNAPSHOT_SCHEMA_VERSION.toString()
        + ' -> will rebuild from a fresh fetch');
      return null;
    }
    const snapshot: NoticeSnapshot = snapshotFromDecoded(decoded);
    this.logger.info('snapshot applied: items=' + snapshot.items.length.toString()
      + ' fetchedAt=' + snapshot.fetchedAtMillis.toString()
      + ' schemaVersion=' + snapshot.schemaVersion.toString());
    return snapshot;
  }

  /** 抓取 → 映射 → 落快照。失败一律 reject（**不返回空列表**）。 */
  async refresh(): Promise<NoticeSnapshot> {
    const startedAt: number = Date.now();
    this.fetched = [];
    const run: AuthedRunResult = await this.executor.run(async (session: Session): Promise<TaskOutcome> => {
      const notices: Notice[] = await this.source.fetchWithSession(session);
      this.fetched = notices;
      // 任务返回值的 body 只用于 SessionGate 的会话失效判定（恰好 '[]' / login_timeout）：
      // 真正抓到的条目经由闭包带出来，不塞进字符串（避免二次序列化）。
      return {
        status: 200,
        body: notices.length === 0 ? '[]' : 'ok:' + notices.length.toString(),
        responseUrl: ''
      };
    });
    if (!run.ok || run.requiresEnrollment) {
      // 显式降级：消息里带 requiresEnrollment=true，调用方（features）据此回登录页。
      throw new Error('notice refresh degraded: requiresEnrollment=true reason=' + run.reason
        + ' reAuth=' + run.reAuthAttempted.toString() + ' diag=' + run.diagnostic);
    }
    const items: NoticeRecord[] = this.mapFetched();
    const fetchedAtMillis: number = Date.now();
    const snapshot: NoticeSnapshot = {
      items: items,
      fetchedAtMillis: fetchedAtMillis,
      schemaVersion: NOTICE_SNAPSHOT_SCHEMA_VERSION,
      fromSnapshot: false
    };
    await this.persist(items, fetchedAtMillis);
    this.logger.info('notices refresh done: items=' + items.length.toString()
      + ' elapsedMs=' + (Date.now() - startedAt).toString()
      + ' fetchedAt=' + fetchedAtMillis.toString());
    return snapshot;
  }

  private mapFetched(): NoticeRecord[] {
    const records: NoticeRecord[] = [];
    for (let i = 0; i < this.fetched.length; i++) {
      records.push(noticeRecordOf(this.fetched[i]));
    }
    this.fetched = [];
    return records;
  }

  /** 落盘快照；失败只记日志（下一次刷新还会重写）。 */
  private async persist(items: NoticeRecord[], fetchedAtMillis: number): Promise<void> {
    const payload: string = encodeNoticeSnapshot(items, fetchedAtMillis);
    const result: SnapshotSaveResult = await this.snapshots.save(payload);
    if (!result.ok) {
      this.logger.warn('snapshot persist failed: ' + result.diagnostic);
    }
  }
}
