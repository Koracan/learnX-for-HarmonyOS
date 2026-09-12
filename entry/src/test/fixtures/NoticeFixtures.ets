/*
 * 公告测试夹具（entry/src/test/fixtures）：参考实现 mock.ts 的 7 条公告，逐字保留。
 *
 * 【ticket 09 迁移】这个数组原来长在 features/notices/repository/MockNoticeRepository.ets
 * 里（ticket 03 的过渡位置）。本 ticket 把 Mock 从主源码树删掉（组装点已切真实数据源），
 * 但**测试仍然需要一份确定性的公告集合**，所以把它搬到测试夹具：
 *   - 时间保留参考实现的字符串形状（'YYYY-MM-DD HH:mm'），由 parseNoticeTime 换算成
 *     epoch 毫秒——与参考实现同一条解析路径，避免手抄时间戳出错；
 *   - 字面量数组写成**非时间顺序**：界面上呈现的倒序只可能来自 sortNoticesDesc，
 *     而不是数据恰好有序。单测里有一条用例断言"原始数组不是排好序的"，守住这一点。
 *
 * 【与 ticket 17 的边界】ticket 17（设置 + 正式 Mock 模式）要求"guest/guest 登录进入
 * Mock 模式"，届时会有一个**主源码树里的** Mock 数据源；本文件不是它的替代品，
 * ticket 17 可以复用这 7 条种子（或直接搬过去）。此处只服务单测。
 */
import { Attachment } from '../../main/ets/domain/model/ContentItem';
import { NoticeRecord } from '../../main/ets/data/notices/NoticeRepository';
import { parseNoticeTime } from '../../main/ets/data/notices/NoticeTime';

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
  attachment?: Attachment;
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
    url: 'https://www.example.com',
    // 逐字取自参考实现 mock.ts:290-296（含 downloadUrl / previewUrl 两个地址）。
    attachment: {
      id: '1998990181_ZY_1604316692859411626215e-c233-4663-a567-a932bf4d4962',
      name: '附件附件附件附件附件附件附件附件附件附件附件附件附件附件附件附件.pdf',
      downloadUrl: 'https://www.apple.com/environment/pdf/Apple_Environmental_Responsibility_Report_2018.pdf'
    }
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
      url: seed.url,
      // 显式写成"有则赋值、无则保持 undefined"，避免把 undefined 塞进可选字段。
      attachment: seed.attachment
    };
    records.push(record);
  }
  return records;
}

/** 一次性构造好的 7 条记录（多处断言用它，避免每次重算时间戳）。 */
export const NOTICE_SEED_RECORDS: NoticeRecord[] = mockNoticeRecords();

/** Mock 原始字面量顺序（乱序）——给单测用来证明排序确实发生。 */
export function rawMockNoticeIds(): string[] {
  const ids: string[] = [];
  for (const seed of MOCK_NOTICE_SEEDS) {
    ids.push(seed.id);
  }
  return ids;
}
