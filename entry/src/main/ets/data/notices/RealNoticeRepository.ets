/*
 * 真实公告仓储（data/notices）：把三件事接起来——
 *   1. **取数**：走 `AuthedTaskRunner`（数据路径的统一入口），它负责"先确保有会话
 *      （冷启动就是那次纯 HTTP 重登）+ 会话失效时重登且只重试一次 + 失败显式降级"；
 *      本文件**不自己造重登/重试/降级逻辑**（AGENTS.md 的硬约束）。
 *   2. **映射**：domain/parse/NoticeParser 的 `Notice` → 界面用的 `NoticeRecord`。
 *   3. **快照**：抓取成功后落盘（抓取时间 + 结构版本），冷启动先读它。
 *
 * 两个"绝不"：
 *   - **绝不用空列表兜底**：取数失败一律 reject；`AuthedRunResult.requiresEnrollment`
 *     为真时抛错，并带 `requiresEnrollment=true` 的标记（界面据此回登录页）。
 *     验收要求"不把空列表交给界面"。
 *   - **绝不让快照损坏变成崩溃**：读/解码/写三处都不抛（见 NoticeSnapshotSerialization）。
 */

import { Logger } from '../../core/log/Logger';
import { Attachment, Notice } from '../../domain/model/ContentItem';
import { parseNoticeTime } from './NoticeTime';
import { AuthedRunResult, SessionTask } from '../auth/SessionRestore';
import { TaskOutcome } from '../auth/ReAuth';
import { Session } from '../remote/Requests';
import {
  NOTICE_SNAPSHOT_SCHEMA_VERSION, NoticeRecord, NoticeRepository, NoticeSnapshot, mergeNoticeReadState
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
 * `const e: AuthedTaskExecutor = authServices.runner` 直接编译失败（实测）。
 */
export interface AuthedTaskExecutor {
  run(task: SessionTask): Promise<AuthedRunResult>;
}

/**
 * 取证开关：**在发起任何请求之前中止公告刷新**（提交态 `false`）。
 *
 * 用途只有一个：让**上一次成功刷新落盘的 `fetchedAtMillis`** 不被启动时那次刷新覆盖，
 * 从而能拍到页头的 `N 分钟前更新` 那一档。
 *
 * 实测的设备侧步骤（逐字命令与"注入值 → 画面文本"的对应见 `.scratch/icons/evidence/README.md` §7）：
 *   ① 用**提交态构建**启动一次 ⇒ 它成功刷新并落盘 `fetchedAtMillis = T0`
 *      （hilog `notices refresh done: … fetchedAt=T0`）；
 *   ② 换成**本开关为 true 的构建**装机；
 *   ③ 用**设备时钟**核对，等到 `设备now − T0 ≈ 90s` 时启动 —— 启动时刻由我们选、
 *      `hdc shell date +%s` 可读、差值可算，**不是赌手速**；
 *   ④ 启动后快照先生效、刷新被本开关中止 ⇒ 页头显示的就是 T0 对应的那一档（≈ `1 分钟前更新`）。
 *
 * **不要试图直接改写 preferences 里的快照**：本模拟器上 `shell` 域对该文件**没有写权限**
 * （实测 `/bin/sh: can't create …learnoh_notice_snapshot: Permission denied`，即使目录是 777），
 * `su` 也不可用；所以这里的"注入"= 固定启动时刻 + 掐掉覆盖它的那次刷新。
 *
 * 消费点自证：`refresh()` 每次都会把**实际生效值**打进 hilog（`notices refresh switch…`），
 * 所以"提交态已关"不靠源码行号、靠运行期那一行。其它任何数据路径都不读这个开关。
 */
export const NOTICES_REFRESH_FAILURE_FOR_EVIDENCE: boolean = false;

/**
 * 取证开关：把被选中的那一条公告按"站点说它没读过"处理（提交态 false）。
 *
 * 为什么需要它：站点自己的 sfyd 可能已经是已读，那样"打开后蓝点消失"就没有可观察的起点
 * —— 蓝点在打开之前就已经不在。本开关只改**这一次刷新的那一份内存副本**，不改站点数据、
 * 不动本地已读集合，于是设备上能拍齐"未读蓝点 → 点开 → 蓝点消失 → 重启后仍消失"四帧。
 *
 * 覆盖发生在**合并之前**（作用在抓取回来的记录上），所以"重启后仍消失"只可能由
 * **本地已读集合的持久化**解释：站点侧被本开关报成未读，合并之后却仍是已读 ⇒ 集合在盘上。
 *
 * 消费点自证：每次 refresh 都把实际生效值、被覆盖的 id、"有几条是本地集合把它从未读翻成
 * 已读"打进 hilog（notices refresh done 那一行）。
 */
export const FORCE_NOTICE_UNREAD_FOR_EVIDENCE: boolean = false;

/**
 * 覆盖哪一条：抓取结果**排序后的下标**。
 *
 * 取 1（第二条）而不是 0：这台设备上最新那条已经被本地已读集合记着，蓝点在打开前本来就不在，
 * 拿它当样本拍不出"打开前的蓝点"。
 *
 * 用**固定下标**、而不是"第一条本地集合没见过的"：冷启动那一帧要判别的正是"本地集合有没有
 * 持久化"，所以开关在写入之后必须**仍然**覆盖同一条；若按"没见过的"去挑，写完就无条可挑，
 * 那一帧会退化成"站点说已读"，失去判别性。
 */
export const EVIDENCE_UNREAD_INDEX: number = 1;

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
  /**
   * 本机已读集合（打开过的公告 id）：进程内是权威副本，落盘与它同处一份快照记录。
   * 只增不减——已读不因条目从站点列表里消失而失效；集合本身随快照一起被版本丢弃重建。
   */
  private readIds: string[] = [];
  /** 最近一次拿到内容项（读快照或抓取都算），markRead 重写快照时用它。 */
  private lastItems: NoticeRecord[] = [];
  private lastFetchedAtMillis: number = 0;
  /** 是否已经从磁盘读过一次已读集合（避免每次 refresh 都读盘）。 */
  private readStateLoaded: boolean = false;

  constructor(executor: AuthedTaskExecutor, source: NoticeFetchSource, snapshots: NoticeSnapshotPort,
    logger: Logger) {
    this.executor = executor;
    this.source = source;
    this.snapshots = snapshots;
    this.logger = logger;
  }

  /**
   * 读上次快照。首次运行 / 版本不符 / 内容损坏都返回 null，并落一行**带原因**的日志——
   * "没有快照"与"有快照但被丢弃"必须能区分（旧版本要能被识别并丢弃重建）。
   *
   * 读回时把盘上的已读集合与进程内的合并（并集）：任一侧记着的都算已读。
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
    this.readStateLoaded = true;
    this.absorbReadIds(decoded.readNoticeIds);
    const items: NoticeRecord[] = mergeNoticeReadState(decoded.items, this.readIds);
    this.lastItems = items;
    this.lastFetchedAtMillis = decoded.fetchedAtMillis;
    const snapshot: NoticeSnapshot = snapshotFromDecoded(decoded);
    snapshot.items = items;
    this.logger.info('snapshot applied: items=' + snapshot.items.length.toString()
      + ' fetchedAt=' + snapshot.fetchedAtMillis.toString()
      + ' schemaVersion=' + snapshot.schemaVersion.toString()
      + ' readIds=' + this.readIds.length.toString());
    return snapshot;
  }

  /** 读回集合与进程内集合的并集（盘上的顺序在前，保持稳定）。 */
  private absorbReadIds(onDisk: string[]): void {
    for (let i = 0; i < onDisk.length; i++) {
      const id: string = onDisk[i];
      if (id.length > 0 && !this.readIds.includes(id)) {
        this.readIds.push(id);
      }
    }
  }

  /**
   * 确保已读集合已经与磁盘对齐一次。refresh() 会**覆盖**整份快照，
   * 不先读回盘上的已读集合就会把上一次的已读状态抹掉。
   *
   * 只在**没有成功读到过磁盘**时才读：`loadSnapshot` 成功那一次已经把集合接进来了；
   * 那里读到的快照如果是"没有"或"被丢弃"，这里仍要再读一次（写盘可能刚刚才发生）。
   *
   * 顺便把盘上的内容项与抓取时间也接过来：markRead 在没有新数据时也要能重写一份完整快照。
   */
  private async ensureReadStateLoaded(): Promise<void> {
    if (this.readStateLoaded) {
      return;
    }
    this.readStateLoaded = true;
    const result: SnapshotLoadResult = await this.snapshots.load();
    if (!result.present || result.decoded.discardReason.length > 0) {
      return;
    }
    this.absorbReadIds(result.decoded.readNoticeIds);
    if (this.lastItems.length === 0 && result.decoded.items.length > 0) {
      this.lastItems = mergeNoticeReadState(result.decoded.items, this.readIds);
      this.lastFetchedAtMillis = result.decoded.fetchedAtMillis;
    }
  }

  /** 抓取 → 映射 → 合并已读 → 落快照。失败一律 reject（**不返回空列表**）。 */
  async refresh(): Promise<NoticeSnapshot> {
    // 消费点自证（AGENTS：开关必须把**实际生效值**打在谁读它的地方）：
    this.logger.info('notices refresh switch: NOTICES_REFRESH_FAILURE_FOR_EVIDENCE='
      + NOTICES_REFRESH_FAILURE_FOR_EVIDENCE.toString());
    if (NOTICES_REFRESH_FAILURE_FOR_EVIDENCE) {
      this.logger.error('notice refresh aborted before any request: NOTICES_REFRESH_FAILURE_FOR_EVIDENCE=true'
        + '（取证用：让注入的快照时间戳留在页头上）');
      throw new Error('notice refresh aborted by evidence switch');
    }
    // 落盘会整份覆盖：先把盘上的已读集合读回来，否则这次刷新会把已读状态抹掉。
    await this.ensureReadStateLoaded();
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
    // 取证覆盖必须作用在**抓取回来的记录**上、发生在合并**之前**：它就是"站点说这一条未读"的
    // 替身，随后交给本地已读集合去合并。顺序反了（先合并再覆盖）会盖掉本地集合的判定，
    // "冷启动后仍已读"就不再能归因于持久化的已读集合。
    const reportedUnread: NoticeRecord[] = this.applyEvidenceUnreadOverride(this.mapFetched());
    const flipped: number = this.countFlippedByLocalReadSet(reportedUnread);
    const items: NoticeRecord[] = mergeNoticeReadState(reportedUnread, this.readIds);
    const fetchedAtMillis: number = Date.now();
    this.lastItems = items;
    this.lastFetchedAtMillis = fetchedAtMillis;
    const snapshot: NoticeSnapshot = {
      items: items,
      fetchedAtMillis: fetchedAtMillis,
      schemaVersion: NOTICE_SNAPSHOT_SCHEMA_VERSION,
      fromSnapshot: false
    };
    await this.persist(items, fetchedAtMillis);
    this.logger.info('notices refresh done: items=' + items.length.toString()
      + ' elapsedMs=' + (Date.now() - startedAt).toString()
      + ' fetchedAt=' + fetchedAtMillis.toString()
      + ' readIds=' + this.readIds.length.toString()
      + ' localReadSetFlip=' + flipped.toString()
      + ' evidenceUnreadOverride=' + FORCE_NOTICE_UNREAD_FOR_EVIDENCE.toString());
    return snapshot;
  }

  /**
   * 打开详情时调用：把 id 记进本地已读集合，并把集合随同当前内容项**重写一次快照**。
   *
   * 为什么立刻落盘而不是等下次刷新：用户可能看完就杀进程，等刷新就等于没记住。
   * 抓取时间用**最近一次抓取的时间**、不改成"现在"——页头的"N 分钟前更新"说的是
   * 站点数据的新鲜度，与本地读没读过无关。
   */
  async markRead(noticeId: string): Promise<void> {
    if (noticeId.length === 0) {
      return;
    }
    if (this.readIds.includes(noticeId)) {
      // 已经记过：不必为同一个 id 反复重写磁盘。
      return;
    }
    this.readIds.push(noticeId);
    // 没有内容项可写时（首次刷新还没成功）只更新内存：下次刷新落盘时会带上。
    if (this.lastItems.length === 0) {
      this.logger.info('notice marked read (memory only): id=' + noticeId
        + ' readIds=' + this.readIds.length.toString());
      return;
    }
    const merged: NoticeRecord[] = mergeNoticeReadState(this.lastItems, this.readIds);
    this.lastItems = merged;
    await this.persist(merged, this.lastFetchedAtMillis);
    this.logger.info('notice marked read: id=' + noticeId
      + ' readIds=' + this.readIds.length.toString());
  }

  /**
   * 取证开关的落点：在**合并之前**把 EVIDENCE_UNREAD_INDEX 那一条抓取记录报成未读，
   * 等价于"站点说这一条没读过"。
   *
   * 提交态（开关为 false）原样返回，不做任何加工。返回值仍会过一遍
   * mergeNoticeReadState —— 于是"本地已读集合有没有持久化"直接决定冷启动后这条是已读还是未读。
   */
  private applyEvidenceUnreadOverride(items: NoticeRecord[]): NoticeRecord[] {
    if (!FORCE_NOTICE_UNREAD_FOR_EVIDENCE || items.length <= EVIDENCE_UNREAD_INDEX) {
      return items;
    }
    const target: NoticeRecord = items[EVIDENCE_UNREAD_INDEX];
    const unread: NoticeRecord = {
      id: target.id,
      title: target.title,
      content: target.content,
      publisher: target.publisher,
      courseId: target.courseId,
      courseName: target.courseName,
      courseTeacherName: target.courseTeacherName,
      publishTimeMillis: target.publishTimeMillis,
      hasRead: false,
      markedImportant: target.markedImportant,
      url: target.url
    };
    if (target.attachment !== undefined) {
      unread.attachment = target.attachment;
    }
    const out: NoticeRecord[] = [];
    for (let i = 0; i < items.length; i++) {
      out.push(i === EVIDENCE_UNREAD_INDEX ? unread : items[i]);
    }
    this.logger.warn('evidence unread override: index=' + EVIDENCE_UNREAD_INDEX.toString()
      + ' id=' + target.id + ' siteHasReadBefore=' + target.hasRead.toString()
      + ' reportedUnread=true');
    return out;
  }

  /**
   * 统计有多少条是"站点（或取证覆盖）说未读、但本地已读集合把它判成已读"的。
   *
   * 这是一个**消费点自证**数字：它非 0 就说明那一条的最终已读只可能来自本地集合，
   * 不可能来自站点数据。写进 refresh 的收尾日志，用于把两种来源区分开。
   */
  private countFlippedByLocalReadSet(items: NoticeRecord[]): number {
    let count: number = 0;
    for (let i = 0; i < items.length; i++) {
      const item: NoticeRecord = items[i];
      if (!item.hasRead && this.readIds.includes(item.id)) {
        count++;
      }
    }
    return count;
  }

  private mapFetched(): NoticeRecord[] {
    const records: NoticeRecord[] = [];
    for (let i = 0; i < this.fetched.length; i++) {
      records.push(noticeRecordOf(this.fetched[i]));
    }
    this.fetched = [];
    return records;
  }

  /** 落盘快照（含本地已读集合）；失败只记日志（下一次刷新还会重写）。 */
  private async persist(items: NoticeRecord[], fetchedAtMillis: number): Promise<void> {
    const payload: string = encodeNoticeSnapshot(items, fetchedAtMillis, this.readIds);
    const result: SnapshotSaveResult = await this.snapshots.save(payload);
    if (!result.ok) {
      this.logger.warn('snapshot persist failed: ' + result.diagnostic);
    }
  }
}
