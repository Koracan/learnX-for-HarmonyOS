/*
 * 真实公告仓储与快照单测。
 *
 * 覆盖四条相关的行为：
 *   1. **抓取 → 映射 → 落快照**：`Notice`（domain）的字段逐项进 `NoticeRecord`，
 *      publishTime 走 parseNoticeTime（与卡片排序同一条路径）；
 *   2. **失败显式降级，绝不返回空列表**：AuthedTaskRunner 判定
 *      requiresEnrollment=true 时 refresh() 必须 reject；
 *   3. **快照先读**：解码成功 → fromSnapshot=true 且带抓取时间；版本不符/内容损坏 →
 *      返回 null 并**在日志里给出原因**；
 *   4. **序列化 round-trip**：encode(decode) 与 schemaVersion 判定；
 *   5. **已读随快照持久化**：markRead 落盘 → 冷启动读回并合并；站点仍报未读时保持已读；
 *      刷新会整份覆盖快照，因此刷新前也必须先把盘上的已读集合合并回来。
 *
 * 全部注入式，无平台依赖（不碰 prefs / 网络）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { Logger } from '../main/ets/core/log/Logger';
import { logBuffer } from '../main/ets/core/log/LogBuffer';
import { Notice } from '../main/ets/domain/model/ContentItem';
import { AuthedRunResult } from '../main/ets/data/auth/SessionRestore';
import {
  AuthedTaskExecutor, FORCE_NOTICE_UNREAD_FOR_EVIDENCE, NoticeFetchSource,
  RealNoticeRepository, noticeRecordOf
} from '../main/ets/data/notices/RealNoticeRepository';
import { SessionTask } from '../main/ets/data/auth/SessionRestore';
import {
  NOTICE_SNAPSHOT_SCHEMA_VERSION, NoticeRecord, NoticeSnapshot
} from '../main/ets/data/notices/NoticeRepository';
import {
  SnapshotDecodeResult, decodeNoticeSnapshot, encodeNoticeSnapshot, snapshotFromDecoded
} from '../main/ets/data/notices/NoticeSnapshotSerialization';
import { NoticeSnapshotPort, SnapshotLoadResult, SnapshotSaveResult } from '../main/ets/data/notices/NoticeSnapshotStore';
import { Session } from '../main/ets/data/remote/Requests';
import { FailReason } from '../main/ets/data/auth/AuthTypes';
import { NOTICE_SEED_RECORDS } from './fixtures/NoticeFixtures';

// 仓储的日志断言按 tag 检索（latestLog），所以这里必须用仓储自己的 tag。
const logger: Logger = new Logger('data.notices');

/** 与 SessionRestore.AuthedRunResult.success 同形的替身（真正构造要走它的私有构造器）。 */
function runOk(reAuth: boolean): AuthedRunResult {
  return AuthedRunResult.success('ok:1', reAuth, 'status=200');
}

function runDegraded(): AuthedRunResult {
  return AuthedRunResult.degraded(FailReason.NOT_LOGGED_IN, true,
    'still noLogin after reAuth status=403');
}

/** 执行器替身：直接调用任务一次（或直接返回降级结果）。 */
class FakeExecutor implements AuthedTaskExecutor {
  private readonly degraded: boolean;
  constructor(degraded: boolean) {
    this.degraded = degraded;
  }

  async run(task: SessionTask): Promise<AuthedRunResult> {
    if (this.degraded) {
      return runDegraded();
    }
    await task({ cookie: 'JSESSIONID=fixture', csrfToken: 'csrf' });
    return runOk(false);
  }
}

/** 抓取替身：返回固定集合，或抛出。 */
class FakeNoticeSource implements NoticeFetchSource {
  private readonly items: Notice[];
  private readonly error: string;
  constructor(items: Notice[], error: string = '') {
    this.items = items;
    this.error = error;
  }

  async fetchWithSession(session: Session): Promise<Notice[]> {
    if (this.error.length > 0) {
      throw new Error(this.error);
    }
    return this.items;
  }
}

/** 快照端口替身：内存里存一段字符串。 */
class FakeSnapshotPort implements NoticeSnapshotPort {
  payload: string = '';
  saved: string[] = [];
  loadResult: SnapshotLoadResult | null = null;

  async load(): Promise<SnapshotLoadResult> {
    if (this.loadResult !== null) {
      return this.loadResult;
    }
    if (this.payload.length === 0) {
      return {
        present: false,
        decoded: {
          items: [], fetchedAtMillis: 0, readNoticeIds: [], discardReason: 'absent', onDiskVersion: -1
        }
      };
    }
    return { present: true, decoded: decodeNoticeSnapshot(this.payload) };
  }

  async save(payload: string): Promise<SnapshotSaveResult> {
    this.payload = payload;
    this.saved.push(payload);
    return { ok: true, diagnostic: 'chars=' + payload.length.toString() };
  }
}

/** 一条 domain 层的公告（用于映射断言）。 */
function domainNotice(id: string): Notice {
  return {
    id: id,
    title: '作业 <b>相关</b>说明 &amp; 提醒',
    content: '<p>正文</p>',
    publisher: '马赫',
    publishTime: '2020-08-30 09:49',
    markedImportant: true,
    hasRead: false,
    url: 'https://learn.tsinghua.edu.cn/f/wlxt/kcgg/wlkc_ggb/student/beforeViewXs?wlkcid=c1&id=' + id,
    courseId: 'c1',
    courseName: '通信与网络',
    courseTeacherName: '周世东',
    attachment: { name: 'a.pdf', downloadUrl: 'https://learn.tsinghua.edu.cn/b/x' }
  };
}

/** 与 noticeRecordOf 同一条路径：把 domain 公告写成界面记录（给"盘上已有快照"的用例当夹具）。 */
function domainRecord(id: string): NoticeRecord {
  return noticeRecordOf(domainNotice(id));
}

/** 在日志环形缓冲里找最近一条含 needle 的记录，返回其 message（空串=没有）。 */
function latestLog(tag: string, needle: string): string {
  const records = logBuffer.snapshot();
  for (let i = records.length - 1; i >= 0; i--) {
    if (records[i].tag === tag && records[i].message.includes(needle)) {
      return records[i].message;
    }
  }
  return '';
}

export default function noticeRepositoryTest() {
  describe('data.notices.RealNoticeRepository', () => {
    it('mapsDomainFieldsAndPersistsASnapshotWithFetchTime', 0, async () => {
      const port: FakeSnapshotPort = new FakeSnapshotPort();
      const repository: RealNoticeRepository = new RealNoticeRepository(
        new FakeExecutor(false), new FakeNoticeSource([domainNotice('n1')]), port, logger);

      const snapshot: NoticeSnapshot = await repository.refresh();
      expect(snapshot.items.length).assertEqual(1);
      expect(snapshot.fromSnapshot).assertFalse();
      expect(snapshot.schemaVersion).assertEqual(NOTICE_SNAPSHOT_SCHEMA_VERSION);
      expect(snapshot.fetchedAtMillis > 0).assertTrue();

      const record: NoticeRecord = snapshot.items[0];
      expect(record.id).assertEqual('n1');
      expect(record.title).assertEqual('作业 <b>相关</b>说明 &amp; 提醒');
      expect(record.publisher).assertEqual('马赫');
      expect(record.courseName).assertEqual('通信与网络');
      expect(record.courseTeacherName).assertEqual('周世东');
      expect(record.markedImportant).assertTrue();
      expect(record.hasRead).assertFalse();
      expect(record.publishTimeMillis).assertEqual(parseTimeOf('2020-08-30 09:49'));
      expect(record.attachment !== undefined).assertTrue();
      if (record.attachment !== undefined) {
        expect(record.attachment.name).assertEqual('a.pdf');
      }
      // 落盘一次，且落盘内容能读回来。
      expect(port.saved.length).assertEqual(1);
      const reloaded = await repository.loadSnapshot();
      expect(reloaded !== null).assertTrue();
      if (reloaded !== null) {
        expect(reloaded.items.length).assertEqual(1);
        expect(reloaded.fromSnapshot).assertTrue();
        expect(reloaded.fetchedAtMillis).assertEqual(snapshot.fetchedAtMillis);
      }
    });

    it('rejectsAndNeverDegradesToAnEmptyList', 0, async () => {
      const port: FakeSnapshotPort = new FakeSnapshotPort();
      const repository: RealNoticeRepository = new RealNoticeRepository(
        new FakeExecutor(true), new FakeNoticeSource([domainNotice('n1')]), port, logger);
      let failed: boolean = false;
      try {
        await repository.refresh();
      } catch (error) {
        failed = true;
        expect((error as Error).message.includes('requiresEnrollment=true')).assertTrue();
      }
      expect(failed).assertTrue();
      // 降级路径不得落快照（否则会用"空/旧"覆盖真实内容）。
      expect(port.saved.length).assertEqual(0);
    });

    it('propagatesFetchFailureInsteadOfReturningAnEmptySnapshot', 0, async () => {
      const port: FakeSnapshotPort = new FakeSnapshotPort();
      const repository: RealNoticeRepository = new RealNoticeRepository(
        new FakeExecutor(false), new FakeNoticeSource([], 'course list request failed: status=403'),
        port, logger);
      let message: string = '';
      try {
        await repository.refresh();
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message.includes('course list request failed')).assertTrue();
    });

    it('discardsASnapshotWrittenByAnotherSchemaVersionAndLogsTheReason', 0, async () => {
      const port: FakeSnapshotPort = new FakeSnapshotPort();
      port.payload = '{"schemaVersion":99,"fetchedAtMillis":1,"items":[]}';
      const repository: RealNoticeRepository = new RealNoticeRepository(
        new FakeExecutor(false), new FakeNoticeSource([]), port, logger);
      const snapshot: NoticeSnapshot | null = await repository.loadSnapshot();
      expect(snapshot === null).assertTrue();
      const logged: string = latestLog('data.notices', 'snapshot discarded');
      expect(logged.includes('version_mismatch:99')).assertTrue();
      expect(logged.includes('currentVersion=' + NOTICE_SNAPSHOT_SCHEMA_VERSION.toString())).assertTrue();
    });

    it('discardsACorruptedSnapshotWithoutThrowing', 0, async () => {
      const port: FakeSnapshotPort = new FakeSnapshotPort();
      port.payload = '{"schemaVersion":2,"fetchedAtMillis":1,"readNoticeIds":[],"items":[{"id":"x"}]}';
      const repository: RealNoticeRepository = new RealNoticeRepository(
        new FakeExecutor(false), new FakeNoticeSource([]), port, logger);
      const snapshot: NoticeSnapshot | null = await repository.loadSnapshot();
      expect(snapshot === null).assertTrue();
      expect(latestLog('data.notices', 'discarded').includes('item_0_title')).assertTrue();
    });

    it('persistsARecordAsReadWithoutTouchingTheFetchTime', 0, async () => {
      const port: FakeSnapshotPort = new FakeSnapshotPort();
      const repository: RealNoticeRepository = new RealNoticeRepository(
        new FakeExecutor(false), new FakeNoticeSource([domainNotice('n1')]), port, logger);

      await repository.refresh();
      const fetchedAt: number = (await repository.loadSnapshot() as NoticeSnapshot).fetchedAtMillis;

      // 打开详情 → 已读；刷新被掐掉（页面失焦）时落盘的就是 markRead 这一次。
      await repository.markRead('n1');
      expect(port.saved.length).assertEqual(2);
      const persisted = JSON.parse(port.saved[1]) as Record<string, Object>;
      expect(JSON.stringify(persisted['readNoticeIds'])).assertEqual('["n1"]');
      expect(persisted['fetchedAtMillis'] as number).assertEqual(fetchedAt);
      expect(persisted['schemaVersion'] as number).assertEqual(NOTICE_SNAPSHOT_SCHEMA_VERSION);
      // 内容项与已读集合在同一份记录里（不新开一份存储）。
      expect((persisted['items'] as Object[]).length).assertEqual(1);

      // 冷启动读回：这一条仍然是已读。
      const reloaded: NoticeSnapshot | null = await repository.loadSnapshot();
      expect(reloaded !== null).assertTrue();
      if (reloaded !== null) {
        expect(reloaded.items[0].id).assertEqual('n1');
        expect(reloaded.items[0].hasRead).assertTrue();
      }
    });

    it('doesNotRewriteTheSnapshotWhenTheSameNoticeIsOpenedAgain', 0, async () => {
      const port: FakeSnapshotPort = new FakeSnapshotPort();
      const repository: RealNoticeRepository = new RealNoticeRepository(
        new FakeExecutor(false), new FakeNoticeSource([domainNotice('n1')]), port, logger);
      await repository.refresh();
      const afterRefresh: number = port.saved.length;
      await repository.markRead('n1');
      expect(port.saved.length).assertEqual(afterRefresh + 1);
      await repository.markRead('n1');
      expect(port.saved.length).assertEqual(afterRefresh + 1);
    });

    it('keepsTheReadStateAcrossARefreshThatStillReportsItUnread', 0, async () => {
      const port: FakeSnapshotPort = new FakeSnapshotPort();
      const repository: RealNoticeRepository = new RealNoticeRepository(
        new FakeExecutor(false), new FakeNoticeSource([domainNotice('n1')]), port, logger);
      await repository.refresh();
      await repository.markRead('n1');
      // 站点仍然说这一条没读过（sfyd 没变）：合并后界面必须仍是已读。
      const refreshed: NoticeSnapshot = await repository.refresh();
      expect(refreshed.items[0].hasRead).assertTrue();
      const reread: NoticeSnapshot | null = await repository.loadSnapshot();
      expect(reread !== null).assertTrue();
      if (reread !== null) {
        expect(reread.items[0].hasRead).assertTrue();
      }
    });

    it('mergesAPersistedReadSetBeforeRefreshingSoAReadStateSurvivesColdStart', 0, async () => {
      const port: FakeSnapshotPort = new FakeSnapshotPort();
      // 盘上是上一次运行留下的：内容项说未读，本地集合记着 n1 已读。
      port.payload = '{"schemaVersion":' + NOTICE_SNAPSHOT_SCHEMA_VERSION.toString()
        + ',"fetchedAtMillis":1,"readNoticeIds":["n1"],"items":['
        + JSON.stringify(domainRecord('n1')) + ']}';
      const repository: RealNoticeRepository = new RealNoticeRepository(
        new FakeExecutor(false), new FakeNoticeSource([domainNotice('n1')]), port, logger);
      // refresh() 会整份覆盖快照：不先合并盘上的已读集合，这次刷新就会把它抹掉。
      const refreshed: NoticeSnapshot = await repository.refresh();
      expect(refreshed.items[0].hasRead).assertTrue();
      const persisted = JSON.parse(port.saved[port.saved.length - 1]) as Record<string, Object>;
      expect(JSON.stringify(persisted['readNoticeIds'])).assertEqual('["n1"]');
    });

    it('evidenceUnreadOverrideIsOffAtCommit', 0, () => {
      // 提交前用 git show HEAD:<文件> 核对开关已复原，这里再加一道程序化断言：
      // 这个开关一旦被误提交成 true，用户会看到**假的未读蓝点**（站点本来报已读）。
      expect(FORCE_NOTICE_UNREAD_FOR_EVIDENCE).assertFalse();
    });

    it('mergesThePersistedReadSetIntoTheSnapshotItHandsBack', 0, async () => {
      const port: FakeSnapshotPort = new FakeSnapshotPort();
      port.payload = '{"schemaVersion":' + NOTICE_SNAPSHOT_SCHEMA_VERSION.toString()
        + ',"fetchedAtMillis":123,"readNoticeIds":["n1"],"items":['
        + JSON.stringify(domainRecord('n1')) + ',' + JSON.stringify(domainRecord('n2')) + ']}';
      const repository: RealNoticeRepository = new RealNoticeRepository(
        new FakeExecutor(false), new FakeNoticeSource([]), port, logger);
      const snapshot: NoticeSnapshot | null = await repository.loadSnapshot();
      expect(snapshot !== null).assertTrue();
      if (snapshot !== null) {
        expect(snapshot.items.length).assertEqual(2);
        expect(snapshot.items[0].hasRead).assertTrue();
        expect(snapshot.items[1].hasRead).assertFalse();
        expect(snapshot.fetchedAtMillis).assertEqual(123);
      }
    });
  });

  describe('data.notices.NoticeSnapshotSerialization', () => {
    it('roundTripsRecordsIncludingTheOptionalAttachment', 0, () => {
      const items: NoticeRecord[] = NOTICE_SEED_RECORDS.slice();
      const payload: string = encodeNoticeSnapshot(items, 1600000000000);
      const decoded: SnapshotDecodeResult = decodeNoticeSnapshot(payload);
      expect(decoded.discardReason).assertEqual('');
      expect(decoded.fetchedAtMillis).assertEqual(1600000000000);
      // 没有写入过已读时：集合是空数组，不是缺字段。
      expect(decoded.readNoticeIds.length).assertEqual(0);
      expect(decoded.items.length).assertEqual(items.length);
      for (let i = 0; i < items.length; i++) {
        expect(decoded.items[i].id).assertEqual(items[i].id);
        expect(decoded.items[i].title).assertEqual(items[i].title);
        expect(decoded.items[i].publishTimeMillis).assertEqual(items[i].publishTimeMillis);
        const hadAttachment: boolean = items[i].attachment !== undefined;
        expect(decoded.items[i].attachment !== undefined).assertEqual(hadAttachment);
      }
    });

    it('reportsADiscardReasonForEveryKindOfDamage', 0, () => {
      expect(decodeNoticeSnapshot('').discardReason).assertEqual('empty');
      expect(decodeNoticeSnapshot('{oops').discardReason).assertEqual('parse_failed');
      expect(decodeNoticeSnapshot('[]').discardReason).assertEqual('not_an_object');
      // 结构版本已经变过：这一条钉的是"版本对、但抓取时间坏掉"那一支。
      expect(decodeNoticeSnapshot('{"schemaVersion":2}').discardReason).assertEqual('fetched_at_invalid');
      expect(decodeNoticeSnapshot('{"fetchedAtMillis":1}').discardReason).assertEqual('version_missing');
      expect(decodeNoticeSnapshot('{"schemaVersion":2,"fetchedAtMillis":1,"items":"x"}').discardReason)
        .assertEqual('items_missing');
      // 版本不符时仍要报出磁盘上的版本号（"能识别旧版本"）。
      const stale: SnapshotDecodeResult = decodeNoticeSnapshot('{"schemaVersion":7,"fetchedAtMillis":1,"items":[]}');
      expect(stale.discardReason).assertEqual('version_mismatch:7');
      expect(stale.onDiskVersion).assertEqual(7);
      // 已读集合形状不对：整条丢弃并给出原因，不抛异常。
      expect(decodeNoticeSnapshot('{"schemaVersion":2,"fetchedAtMillis":1,"items":[],"readNoticeIds":"nope"}')
        .discardReason).assertEqual('read_ids_invalid');
      // 集合里混进非字符串成员：只丢那一项，其余照常读回（不因此丢弃内容）。
      const tolerant: SnapshotDecodeResult = decodeNoticeSnapshot(
        '{"schemaVersion":2,"fetchedAtMillis":1,"items":[],"readNoticeIds":["n1",7,"","n1","n2"]}');
      expect(tolerant.discardReason).assertEqual('');
      expect(tolerant.readNoticeIds.join(',')).assertEqual('n1,n2');
    });

    it('roundTripsTheLocalReadSet', 0, () => {
      const payload: string = encodeNoticeSnapshot(NOTICE_SEED_RECORDS, 42, ['n-2', 'n-1', 'n-2', '']);
      const decoded: SnapshotDecodeResult = decodeNoticeSnapshot(payload);
      expect(decoded.discardReason).assertEqual('');
      // 去重 + 丢空串，顺序保持写入序。
      expect(decoded.readNoticeIds.join(',')).assertEqual('n-2,n-1');
    });

    it('turnsADecodedPayloadIntoASnapshotThatIsMarkedAsFromSnapshot', 0, () => {
      const payload: string = encodeNoticeSnapshot(NOTICE_SEED_RECORDS, 42);
      const snapshot: NoticeSnapshot = snapshotFromDecoded(decodeNoticeSnapshot(payload));
      expect(snapshot.fromSnapshot).assertTrue();
      expect(snapshot.fetchedAtMillis).assertEqual(42);
      expect(snapshot.schemaVersion).assertEqual(NOTICE_SNAPSHOT_SCHEMA_VERSION);
    });

    it('mapsASingleDomainNoticeWithoutLosingTheOptionalFields', 0, () => {
      const record: NoticeRecord = noticeRecordOf(domainNotice('n9'));
      expect(record.id).assertEqual('n9');
      expect(record.attachment !== undefined).assertTrue();
      // 没有附件的公告：NoticeRecord 上不该出现 attachment 字段。
      // 不用 `delete`（ArkTS 禁 arkts-no-delete），改成构造一个不带该字段的同形对象。
      const bare: Notice = {
        id: 'n10', title: 't', content: '<p>c</p>', publisher: 'p', publishTime: '2020-01-01 00:00',
        markedImportant: false, hasRead: true, url: 'https://learn.tsinghua.edu.cn/x',
        courseId: 'c1', courseName: '通信与网络', courseTeacherName: '周世东'
      };
      const noAttachment: NoticeRecord = noticeRecordOf(bare);
      expect(noAttachment.attachment === undefined).assertTrue();
    });
  });
}

/** 与 NoticeTime.parseNoticeTime 同一条路径（这里只为了断言期望值）。 */
function parseTimeOf(text: string): number {
  return new Date(2020, 7, 30, 9, 49, 0, 0).getTime();
}
