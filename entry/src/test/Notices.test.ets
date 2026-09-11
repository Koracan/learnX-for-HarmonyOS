/*
 * 公告域单测（ticket 03）：排序（倒序）、未读判定、空态分支、Mock 与接口的一致性。
 *
 * 覆盖面：
 *   1. NoticeOrder 的纯函数 —— 时间解析、发布时间倒序（含同一时间的 id 倒序、
 *      不改入参）、未读判定、空态判定；
 *   2. MockNoticeRepository 与一个"真实数据源替身"（FakeSnapshotNoticeRepository）
 *      实现同一个 NoticeRepository 接口，跑同一组契约断言 —— 这就是 ticket 09
 *      换实现不改界面的依据；
 *   3. NoticeListStore 的快照先行 + 后台刷新时序、失败保留旧数据、空集合空态。
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  NOTICE_SNAPSHOT_SCHEMA_VERSION, NoticeRecord, NoticeRepository, NoticeSnapshot
} from '../main/ets/features/notices/repository/NoticeRepository';
import {
  MockNoticeRepository, mockNoticeRecords, rawMockNoticeIds
} from '../main/ets/features/notices/repository/MockNoticeRepository';
import {
  compareNoticesDesc, countUnread, isNoticeListEmpty, isUnread, parseNoticeTime, sortNoticesDesc
} from '../main/ets/features/notices/NoticeOrder';
import { NoticeListStore, NoticeLoadPhase } from '../main/ets/features/notices/NoticeListStore';

/** 参考实现 mock.ts 的公告发布时间格式：'YYYY-MM-DD HH:mm'（本地时间）。 */
function record(id: string, publishTime: string, hasRead: boolean): NoticeRecord {
  return {
    id: id,
    title: 'title-' + id,
    content: '<p>body</p>',
    publisher: 'publisher',
    courseId: 'course-1',
    courseName: '课程一',
    courseTeacherName: '教师一',
    publishTimeMillis: parseNoticeTime(publishTime),
    hasRead: hasRead,
    markedImportant: false,
    url: 'https://www.example.com'
  };
}

function ids(items: NoticeRecord[]): string[] {
  const out: string[] = [];
  for (const item of items) {
    out.push(item.id);
  }
  return out;
}

function join(items: NoticeRecord[]): string {
  return ids(items).join(',');
}

/** 真实数据源替身（ticket 09 的形状）：能读快照、能把新抓取落成快照。 */
class FakeSnapshotNoticeRepository implements NoticeRepository {
  private stored: NoticeSnapshot | null = null;
  private readonly source: NoticeRecord[];

  constructor(source: NoticeRecord[]) {
    this.source = source;
  }

  async loadSnapshot(): Promise<NoticeSnapshot | null> {
    return this.stored;
  }

  async refresh(): Promise<NoticeSnapshot> {
    // 契约要求数据源给出的 items 已按发布时间倒序（参考实现也是在数据层排序）。
    const snapshot: NoticeSnapshot = {
      items: sortNoticesDesc(this.source),
      fetchedAtMillis: Date.now(),
      schemaVersion: NOTICE_SNAPSHOT_SCHEMA_VERSION,
      fromSnapshot: false
    };
    this.stored = snapshot;
    return snapshot;
  }
}

/** 先给旧快照、再抓取失败的数据源（验证失败时保留旧数据）。 */
class SnapshotThenFailRepository implements NoticeRepository {
  private readonly stored: NoticeSnapshot;

  constructor(stored: NoticeSnapshot) {
    this.stored = stored;
  }

  async loadSnapshot(): Promise<NoticeSnapshot | null> {
    return this.stored;
  }

  async refresh(): Promise<NoticeSnapshot> {
    throw new Error('offline');
  }
}

/**
 * 同一组契约断言，两个实现都要过。
 * 契约：refresh() 给倒序、非空 schemaVersion 与抓取时间；loadSnapshot() 在
 * refresh() 之前为 null、之后为最后一次抓取结果。
 */
async function assertRepositoryContract(repository: NoticeRepository, expectedCount: number): Promise<void> {
  const before: NoticeSnapshot | null = await repository.loadSnapshot();
  expect(before === null).assertTrue();
  const snapshot: NoticeSnapshot = await repository.refresh();
  expect(snapshot.items.length).assertEqual(expectedCount);
  expect(snapshot.schemaVersion).assertEqual(NOTICE_SNAPSHOT_SCHEMA_VERSION);
  expect(snapshot.fetchedAtMillis > 0).assertTrue();
  expect(snapshot.fromSnapshot).assertFalse();
  for (let i = 1; i < snapshot.items.length; i++) {
    expect(compareNoticesDesc(snapshot.items[i - 1], snapshot.items[i]) <= 0).assertTrue();
  }
  const after: NoticeSnapshot | null = await repository.loadSnapshot();
  expect(after !== null).assertTrue();
  if (after !== null) {
    expect(after.items.length).assertEqual(expectedCount);
  }
}

export default function noticesTest() {
  describe('features.notices.NoticeOrder', () => {
    it('parsesReferencePublishTimeFormat', 0, () => {
      expect(parseNoticeTime('2020-09-25 07:21')).assertEqual(new Date(2020, 8, 25, 7, 21, 0, 0).getTime());
      expect(parseNoticeTime('2020-09-25T07:21')).assertEqual(new Date(2020, 8, 25, 7, 21, 0, 0).getTime());
      expect(parseNoticeTime('')).assertEqual(0);
      expect(parseNoticeTime('not a time')).assertEqual(0);
      expect(parseNoticeTime('2020-13-01 00:00')).assertEqual(0);
    });

    it('sortsByPublishTimeDescending', 0, () => {
      const items: NoticeRecord[] = [
        record('b', '2020-08-30 09:49', true),
        record('d', '2020-09-25 07:21', true),
        record('a', '2020-08-17 22:30', true),
        record('c', '2020-09-10 16:22', true)
      ];
      expect(join(sortNoticesDesc(items))).assertEqual('d,c,b,a');
    });

    it('breaksTiesByIdDescending', 0, () => {
      const items: NoticeRecord[] = [
        record('a1', '2020-09-25 07:21', true),
        record('c3', '2020-09-25 07:21', true),
        record('b2', '2020-09-25 07:21', true)
      ];
      expect(join(sortNoticesDesc(items))).assertEqual('c3,b2,a1');
      // 同一时间的比较结果与参考实现 b.id.localeCompare(a.id) 同号。
      expect(compareNoticesDesc(items[0], items[1]) > 0).assertTrue();
    });

    it('doesNotMutateTheInputArray', 0, () => {
      const items: NoticeRecord[] = [
        record('a', '2020-08-17 22:30', true),
        record('b', '2020-09-25 07:21', true)
      ];
      const sorted: NoticeRecord[] = sortNoticesDesc(items);
      expect(join(items)).assertEqual('a,b');
      expect(join(sorted)).assertEqual('b,a');
    });

    it('treatsHasReadFalseAsUnread', 0, () => {
      expect(isUnread(record('a', '2020-09-25 07:21', false))).assertTrue();
      expect(isUnread(record('b', '2020-09-25 07:21', true))).assertFalse();
    });

    it('countsUnreadInTheMockSet', 0, () => {
      const items: NoticeRecord[] = mockNoticeRecords();
      expect(items.length).assertEqual(7);
      // 参考实现 mock.ts 里 hasRead=false 的两条：作业相关说明 / 调课提醒。
      expect(countUnread(items)).assertEqual(2);
    });

    it('mockLiteralOrderIsNotSorted', 0, () => {
      // 守住证据：界面上看到的倒序只能来自排序，不能是数据恰好有序。
      const raw: string[] = rawMockNoticeIds();
      const sorted: string[] = ids(sortNoticesDesc(mockNoticeRecords()));
      expect(raw.join(',') === sorted.join(',')).assertFalse();
      expect(sorted[0]).assertEqual('26ef84e86d60f069016dadb09dd673b2');
    });

    it('reportsEmptyOnlyWhenThereIsNoDataAndNoWorkInFlight', 0, () => {
      const empty: NoticeRecord[] = [];
      expect(isNoticeListEmpty(empty, false)).assertTrue();
      expect(isNoticeListEmpty(empty, true)).assertFalse();
      expect(isNoticeListEmpty([record('a', '2020-09-25 07:21', true)], false)).assertFalse();
    });
  });

  describe('features.notices.NoticeRepository', () => {
    it('mockRefreshesSevenSortedNoticesWithSnapshotMetadata', 0, async () => {
      const repository: NoticeRepository = new MockNoticeRepository(false, 1);
      await assertRepositoryContract(repository, 7);
      const snapshot: NoticeSnapshot = await repository.refresh();
      expect(join(snapshot.items)).assertEqual(
        '26ef84e86d60f069016dadb09dd673b2,26ef84e76d60efc1016d71b8f4c63bc1,'
        + '26ef84e76db3f55b016db4c4e8832da6,26ef84e76d60efc1016daba2cc3451fc,'
        + '26ef84e76d60efc1016d7fdd00382858,26ef84e76cc258ed016d3fa2f27d5f10,'
        + '26ef84e76cc258ed016d3ea25a95157d');
      expect(snapshot.items[1].markedImportant).assertTrue();
      expect(snapshot.items[1].hasRead).assertFalse();
      expect(snapshot.items[0].courseName).assertEqual('量子与统计');
    });

    it('mockEmptyModeReturnsAnEmptySnapshot', 0, async () => {
      const repository: NoticeRepository = new MockNoticeRepository(true, 1);
      const snapshot: NoticeSnapshot = await repository.refresh();
      expect(snapshot.items.length).assertEqual(0);
      expect(isNoticeListEmpty(snapshot.items, false)).assertTrue();
    });

    it('mockAndSnapshotImplementationsHonourTheSameContract', 0, async () => {
      const mock: NoticeRepository = new MockNoticeRepository(false, 1);
      const fake: NoticeRepository = new FakeSnapshotNoticeRepository(mockNoticeRecords());
      await assertRepositoryContract(mock, 7);
      await assertRepositoryContract(fake, 7);
    });
  });

  describe('features.notices.NoticeListStore', () => {
    it('rendersTheSnapshotFirstAndThenRefreshes', 0, async () => {
      const stale: NoticeSnapshot = {
        items: [record('old-1', '2020-08-30 09:49', false)],
        fetchedAtMillis: 1600000000000,
        schemaVersion: NOTICE_SNAPSHOT_SCHEMA_VERSION,
        fromSnapshot: true
      };
      const fresh: NoticeRecord[] = [
        record('new-1', '2020-09-25 07:21', false),
        record('new-2', '2020-09-10 16:22', true)
      ];
      const store: NoticeListStore = new NoticeListStore(
        new SnapshotWithFreshRepository(stale, fresh));
      await store.loadOnce();
      expect(store.phase).assertEqual(NoticeLoadPhase.READY);
      expect(store.items.length).assertEqual(2);
      expect(join(store.items)).assertEqual('new-1,new-2');
      expect(store.unreadCount()).assertEqual(1);
      expect(store.isEmpty()).assertFalse();
      expect(store.fetchedAtMillis > 1600000000000).assertTrue();
    });

    it('keepsTheSnapshotWhenRefreshFails', 0, async () => {
      const stale: NoticeSnapshot = {
        items: [record('old-1', '2020-08-30 09:49', true)],
        fetchedAtMillis: 1600000000000,
        schemaVersion: NOTICE_SNAPSHOT_SCHEMA_VERSION,
        fromSnapshot: true
      };
      const store: NoticeListStore = new NoticeListStore(new SnapshotThenFailRepository(stale));
      await store.loadOnce();
      expect(store.phase).assertEqual(NoticeLoadPhase.ERROR);
      expect(store.errorMessage).assertEqual('offline');
      expect(store.items.length).assertEqual(1);
    });

    it('reportsTheEmptyBranchForAnEmptySource', 0, async () => {
      const store: NoticeListStore = new NoticeListStore(new MockNoticeRepository(true, 1));
      await store.loadOnce();
      expect(store.items.length).assertEqual(0);
      expect(store.isEmpty()).assertTrue();
      expect(store.isBusy()).assertFalse();
    });

    it('sortsUnsortedSourceDataOnArrival', 0, async () => {
      const unsorted: NoticeRecord[] = [
        record('a', '2020-08-17 22:30', true),
        record('c', '2020-09-25 07:21', true),
        record('b', '2020-09-10 16:22', true)
      ];
      const store: NoticeListStore = new NoticeListStore(new FakeSnapshotNoticeRepository(unsorted));
      await store.loadOnce();
      expect(join(store.items)).assertEqual('c,b,a');
    });
  });
}

/** 旧快照 + 新抓取（两次结果不同）的数据源，用来验证"先快照后刷新"。 */
class SnapshotWithFreshRepository implements NoticeRepository {
  private readonly stale: NoticeSnapshot;
  private readonly fresh: NoticeRecord[];

  constructor(stale: NoticeSnapshot, fresh: NoticeRecord[]) {
    this.stale = stale;
    this.fresh = fresh;
  }

  async loadSnapshot(): Promise<NoticeSnapshot | null> {
    return this.stale;
  }

  async refresh(): Promise<NoticeSnapshot> {
    const snapshot: NoticeSnapshot = {
      items: this.fresh.slice(),
      fetchedAtMillis: Date.now(),
      schemaVersion: NOTICE_SNAPSHOT_SCHEMA_VERSION,
      fromSnapshot: false
    };
    return snapshot;
  }
}
