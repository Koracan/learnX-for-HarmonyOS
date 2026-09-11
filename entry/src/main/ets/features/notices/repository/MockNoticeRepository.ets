/*
 * MockNoticeRepository —— ticket 03 的临时数据源，内容逐条取自参考实现
 * reference/learnOH-old/src/data/mock.ts 的 state.notices.items（7 条）。
 *
 * 两处刻意的处理：
 *  1. 时间保留参考实现的字符串形状（'2020-09-25 07:21'），由 NoticeOrder.parseNoticeTime
 *     换算成 epoch 毫秒 —— 与参考实现同一条解析路径，避免手抄时间戳出错；
 *  2. 字面量数组写成**非时间顺序**（见 MOCK_NOTICE_SEEDS）：界面上呈现的倒序只可能
 *     来自 NoticeOrder.sortNoticesDesc，而不是数据恰好有序。单测里有一条用例断言
 *     “原始数组不是排好序的”，守住这一点。
 *
 * 行为对齐接口契约（NoticeRepository）：loadSnapshot() 首次返回 null（还没有快照），
 * refresh() 造出带 fetchedAtMillis 的新快照并（内存里）存下来，且带一段人为延迟，
 * 让下拉刷新的动效可见。
 */
import { Logger } from '../../../core/log/Logger';
import { parseNoticeTime, sortNoticesDesc } from '../NoticeOrder';
import {
  NOTICE_SNAPSHOT_SCHEMA_VERSION, NoticeRecord, NoticeRepository, NoticeSnapshot
} from './NoticeRepository';

const logger: Logger = new Logger('features.notices.mock');

/** 参考实现里的公告形状（时间是原样的 'YYYY-MM-DD HH:mm' 字符串）。 */
interface MockNoticeSeed {
  id: string;
  title: string;
  content: string;
  publisher: string;
  courseId: string;
  courseName: string;
  courseTeacherName: string;
  publishTime: string;
  hasRead: boolean;
  markedImportant: boolean;
  url: string;
}

/** 参考实现 mock.ts 的 7 条公告，内容一字未改，**顺序被打乱**（见文件头注释）。 */
const MOCK_NOTICE_SEEDS: MockNoticeSeed[] = [
  {
    id: '26ef84e76d60efc1016d7fdd00382858',
    title: '作业相关说明',
    content: '\n \n \n  <p>统一作业为四个班都要求的作业，<strong>全部计入课程成绩</strong>；除了统一作业之外，其它是本班专属作业，建议尽量按时完成，期末根据整体完成情况，<strong>酌情加分</strong>。</p> \n \n',
    publisher: '马赫',
    courseId: '2019-2020-1139283221',
    courseName: '通信与网络',
    courseTeacherName: '周世东',
    publishTime: '2020-08-30 09:49',
    hasRead: false,
    markedImportant: false,
    url: 'https://www.example.com'
  },
  {
    id: '26ef84e86d60f069016dadb09dd673b2',
    title: '请按照助教的安排交作业（不要再放到原来的作业箱，以免丢失或延误）',
    content: '\n \n \n  <p>助教已安排好了交作业方式，请不要再交到理科楼的作业箱，以免造成丢失或延误批改。</p> \n \n',
    publisher: '杜春光',
    courseId: '2019-2020-1139282934',
    courseName: '量子与统计',
    courseTeacherName: '杜春光',
    publishTime: '2020-09-25 07:21',
    hasRead: true,
    markedImportant: false,
    url: 'https://www.example.com'
  },
  {
    id: '26ef84e76cc258ed016d3fa2f27d5f10',
    title: '课程讨论区里，发了一条关于第1讲作业的提示',
    content: '\n \n \n  <p>可跟贴讨论。</p> \n \n',
    publisher: '周世东',
    courseId: '2019-2020-1139283221',
    courseName: '通信与网络',
    courseTeacherName: '周世东',
    publishTime: '2020-08-17 22:30',
    hasRead: true,
    markedImportant: false,
    url: 'https://www.example.com'
  },
  {
    id: '26ef84e76d60efc1016daba2cc3451fc',
    title: '10月9日课程地点',
    content: '\n \n \n  <p>各位同学：</p> \n  <p>为方便同学们实验，10月9日课程地点改为<span style="color:#c0392b">中央主楼916机房</span>，时间还是原上课时间（13:30开始），请各位同学相互转告~</p> \n  <p>&nbsp;</p> \n  <p>祝 好！</p> \n \n',
    publisher: '孙文钰',
    courseId: '2019-2020-1139283217',
    courseName: '数字系统设计',
    courseTeacherName: '刘勇攀',
    publishTime: '2020-09-08 21:46',
    hasRead: true,
    markedImportant: false,
    url: 'https://www.example.com'
  },
  {
    id: '26ef84e76db3f55b016db4c4e8832da6',
    title: '第一次大作业',
    content: '\n \n \n  <p>第一次大作业已布置，请同学们仔细阅读作业说明文档，注意作业截止日期，合理安排时间。</p> \n \n',
    publisher: '薛有泽',
    courseId: '2019-2020-1139283216',
    courseName: '基于数字信号处理器的系统设计',
    courseTeacherName: '窦维蓓',
    publishTime: '2020-09-10 16:22',
    hasRead: true,
    markedImportant: false,
    url: 'https://www.example.com'
  },
  {
    id: '26ef84e76d60efc1016d71b8f4c63bc1',
    title: '调课提醒：9月29日（周日）8：00有课（改上周五课）',
    content: '\n \n \n  <p>根据学校放假调课安排，9月29日（周日）改上周五课，量子与统计课为早上8：00.</p> \n \n',
    publisher: '杜春光',
    courseId: '2019-2020-1139282934',
    courseName: '量子与统计',
    courseTeacherName: '杜春光',
    publishTime: '2020-09-22 15:52',
    hasRead: false,
    markedImportant: true,
    url: 'https://www.example.com'
  },
  {
    id: '26ef84e76cc258ed016d3ea25a95157d',
    title: '信源的信息度量课件第19页更正',
    content: '\n \n \n  <p>原：固定事件个数 M 的离散信源，均匀分布熵最大，为 1/M；更正为 log M。</p> \n \n',
    publisher: '周世东',
    courseId: '2019-2020-1139283221',
    courseName: '通信与网络',
    courseTeacherName: '周世东',
    publishTime: '2020-08-17 17:50',
    hasRead: true,
    markedImportant: false,
    url: 'https://www.example.com'
  }
];

/** 把种子逐条换成 NoticeRecord（时间走 parseNoticeTime，与参考实现同一条路径）。 */
export function mockNoticeRecords(): NoticeRecord[] {
  const records: NoticeRecord[] = [];
  for (const seed of MOCK_NOTICE_SEEDS) {
    const record: NoticeRecord = {
      id: seed.id,
      title: seed.title,
      content: seed.content,
      publisher: seed.publisher,
      courseId: seed.courseId,
      courseName: seed.courseName,
      courseTeacherName: seed.courseTeacherName,
      publishTimeMillis: parseNoticeTime(seed.publishTime),
      hasRead: seed.hasRead,
      markedImportant: seed.markedImportant,
      url: seed.url
    };
    records.push(record);
  }
  return records;
}

/** Mock 原始字面量顺序（乱序）——给单测用来证明排序确实发生。 */
export function rawMockNoticeIds(): string[] {
  const ids: string[] = [];
  for (const seed of MOCK_NOTICE_SEEDS) {
    ids.push(seed.id);
  }
  return ids;
}

/** 延时（官方 FAQ 的 sleep 写法：new Promise(resolve => setTimeout(resolve, ms))）。 */
function delay(millis: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, millis));
}

/** Mock 数据源：与真实实现同一个 NoticeRepository 接口。 */
export class MockNoticeRepository implements NoticeRepository {
  private readonly empty: boolean;
  private readonly latencyMillis: number;
  private stored: NoticeSnapshot | null = null;

  constructor(empty: boolean, latencyMillis: number) {
    this.empty = empty;
    this.latencyMillis = latencyMillis;
  }

  async loadSnapshot(): Promise<NoticeSnapshot | null> {
    return this.stored;
  }

  async refresh(): Promise<NoticeSnapshot> {
    await delay(this.latencyMillis);
    const items: NoticeRecord[] = this.empty ? [] : mockNoticeRecords();
    // 契约要求倒序；这里排一次，UI 侧 NoticeListStore 再排一次（防御性）。
    const snapshot: NoticeSnapshot = {
      items: sortNoticesDesc(items),
      fetchedAtMillis: Date.now(),
      schemaVersion: NOTICE_SNAPSHOT_SCHEMA_VERSION,
      fromSnapshot: false
    };
    this.stored = snapshot;
    logger.info('mock notices refreshed: count=' + snapshot.items.length.toString()
      + ' emptyMode=' + this.empty.toString());
    return snapshot;
  }
}
