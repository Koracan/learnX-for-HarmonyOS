/*
 * 三域"抓取 → 解析 → 排序"整链单测（可测部分）。
 *
 * 端口（`FetchPort`）由脚本化假实现注入，响应体用夹具；
 * 因此这里验证的是：请求次数与顺序、响应 → 条目的映射、跨课程聚合、排序、
 * 失败容错，以及**每个域都打了带条目数与耗时的日志**（`data.* fetched ... items=.. elapsedMs=..`）。
 *
 * 真正的设备抓取（真实会话）另见「待账号验证」。
 */

import { describe, it, expect } from '@ohos/hypium';
import { Logger } from '../main/ets/core/log/Logger';
import { logBuffer } from '../main/ets/core/log/LogBuffer';
import { Assignment, CourseFile, Notice } from '../main/ets/domain/model/ContentItem';
import { CourseName } from '../main/ets/domain/parse/CourseName';
import { FetchOutcome, FetchPort, GetSpec, PostFormSpec, UploadSpec } from '../main/ets/data/remote/Port';
import { Session } from '../main/ets/data/remote/Requests';
import { NoticesFetcher, NOTICES_LOG_DOMAIN, extractNoticeRows } from '../main/ets/data/remote/NoticesFetcher';
import { AssignmentsFetcher, ASSIGNMENTS_LOG_DOMAIN, extractAssignmentRows, extractAssignmentDescription } from
  '../main/ets/data/remote/AssignmentsFetcher';
import { FilesFetcher, FILES_LOG_DOMAIN, extractCourseFileRows } from '../main/ets/data/remote/FilesFetcher';
import { strictPureBase64Decoder } from './TestHelpers';
import { isPastDeadline } from '../main/ets/features/assignments/AssignmentFilter';
import {
  NOTICE_LIST_RESPONSE_JSON, NOTICE_LIST_RESULTS_LIST_JSON, NOTICE_DETAIL_ML10_HTML,
  ASSIGNMENT_LIST_RESPONSE_JSON, ASSIGNMENT_DESCRIPTION_RESPONSE_JSON,
  ASSIGNMENT_DETAIL_FOUR_BLOCKS_HTML, FILE_LIST_RESPONSE_JSON, SESSION_EXPIRED_JSON
} from './fixtures/ContentItemFixtures';

const SESSION: Session = { cookie: 'JSESSIONID=fixture', csrfToken: 'csrf-fixture' };
const COURSES: Record<string, CourseName> = {
  'c1': { name: '通信与网络', teacherName: '周世东' },
  'c2': { name: '量子与统计', teacherName: '杜春光' }
};

/** 字符串 → 稳定整数（ArkTS 里用 Map 之外的简单键）。 */
function hashKey(text: string): number {
  let hash: number = 7;
  for (let i = 0; i < text.length; i++) {
    hash = (hash * 31 + text.charCodeAt(i)) % 2147483647;
  }
  return hash;
}

/** 脚本化假端口：按 URL 子串路由，记录每次调用。 */
class ScriptedFetchPort implements FetchPort {
  readonly postUrls: string[] = [];
  readonly getUrls: string[] = [];
  readonly uploads: string[] = [];
  private postRoutes: string[] = [];
  private postBodies: string[] = [];
  private getRoutes: string[] = [];
  private getBodies: string[] = [];
  private readonly cursors: Map<number, number> = new Map<number, number>();
  private failureUrlPart: string = '';

  routePost(urlPart: string, body: string): ScriptedFetchPort {
    this.postRoutes.push(urlPart);
    this.postBodies.push(body);
    return this;
  }

  /** 同一子串的多次 GET 按脚本顺序依次给出；用完后重复最后一条。 */
  routeGetSeq(urlPart: string, bodies: string[]): ScriptedFetchPort {
    for (let i = 0; i < bodies.length; i++) {
      this.getRoutes.push(urlPart);
      this.getBodies.push(bodies[i]);
    }
    return this;
  }

  failOn(urlPart: string): ScriptedFetchPort {
    this.failureUrlPart = urlPart;
    return this;
  }

  async postForm(session: Session, spec: PostFormSpec): Promise<FetchOutcome> {
    this.postUrls.push(spec.url);
    if (this.failureUrlPart.length > 0 && spec.url.includes(this.failureUrlPart)) {
      return { ok: false, status: 403, body: '', error: 'HTTP 403' };
    }
    for (let i = 0; i < this.postRoutes.length; i++) {
      if (spec.url.includes(this.postRoutes[i])) {
        return { ok: true, status: 200, body: this.postBodies[i] };
      }
    }
    return { ok: false, status: 404, body: '', error: 'no scripted response for ' + spec.url };
  }

  async get(session: Session, spec: GetSpec): Promise<FetchOutcome> {
    this.getUrls.push(spec.url);
    for (let i = 0; i < this.getRoutes.length; i++) {
      if (spec.url.includes(this.getRoutes[i])) {
        const key: number = hashKey(this.getRoutes[i]);
        const seen: number | undefined = this.cursors.get(key);
        const index: number = seen === undefined ? 0 : seen;
        this.cursors.set(key, index + 1);
        const bounded: number = index < this.getBodies.length ? index : this.getBodies.length - 1;
        return { ok: true, status: 200, body: this.getBodies[bounded] };
      }
    }
    return { ok: false, status: 404, body: '', error: 'no scripted response for ' + spec.url };
  }

  async upload(session: Session, spec: UploadSpec): Promise<FetchOutcome> {
    this.uploads.push(spec.url);
    return { ok: true, status: 200, body: '{"result":"success"}' };
  }
}

/** 在日志环形缓冲里找最近一条含 needle 的记录，返回其 message。 */
function latestLog(tag: string, needle: string): string {
  const records = logBuffer.snapshot();
  for (let i = records.length - 1; i >= 0; i--) {
    if (records[i].tag === tag && records[i].message.includes(needle)) {
      return records[i].message;
    }
  }
  return '';
}

function assertHasItemsAndElapsed(message: string, expectedItems: number): void {
  expect(message.length > 0).assertTrue();
  expect(message.includes('items=' + expectedItems.toString())).assertTrue();
  const marker: string = 'elapsedMs=';
  const at: number = message.indexOf(marker);
  expect(at > 0).assertTrue();
  expect(Number.parseInt(message.substring(at + marker.length), 10) >= 0).assertTrue();
}

function noticeById(notices: Notice[], id: string): Notice {
  return notices.filter((item: Notice): boolean => item.id === id)[0];
}

export default function dataFetchTest() {
  describe('data.fetch', () => {
    it('extractorsTolerateEmptyAndMalformedBodies', 0, () => {
      expect(extractNoticeRows('').length).assertEqual(0);
      expect(extractNoticeRows('not json').length).assertEqual(0);
      expect(extractNoticeRows(SESSION_EXPIRED_JSON).length).assertEqual(0);
      expect(extractNoticeRows(NOTICE_LIST_RESPONSE_JSON).length).assertEqual(2);
      expect(extractNoticeRows(NOTICE_LIST_RESULTS_LIST_JSON).length).assertEqual(1);
      expect(extractAssignmentRows('').length).assertEqual(0);
      expect(extractAssignmentRows('}{').length).assertEqual(0);
      expect(extractAssignmentRows(SESSION_EXPIRED_JSON).length).assertEqual(0);
      expect(extractAssignmentRows(ASSIGNMENT_LIST_RESPONSE_JSON).length).assertEqual(2);
      expect(extractAssignmentDescription('').length).assertEqual(0);
      expect(extractAssignmentDescription('nope').length).assertEqual(0);
      // 描述接口的 msg 与参考实现一样做实体解码（decodeHTML(descJson.msg)）
      expect(extractAssignmentDescription(ASSIGNMENT_DESCRIPTION_RESPONSE_JSON))
        .assertEqual('<p>要求见课件&讲义</p>');
      expect(extractCourseFileRows('').length).assertEqual(0);
      expect(extractCourseFileRows('[]').length).assertEqual(0);
      expect(extractCourseFileRows(FILE_LIST_RESPONSE_JSON).length).assertEqual(2);
    });

    it('noticesFetchParsesAndLogsItemsAndElapsed', 0, async () => {
      const port: ScriptedFetchPort = new ScriptedFetchPort()
        .routePost('pageListXsbyWgq', NOTICE_LIST_RESPONSE_JSON)
        .routePost('pageListXsbyYgq', NOTICE_LIST_RESULTS_LIST_JSON)
        .routeGetSeq('beforeViewXs', [NOTICE_DETAIL_ML10_HTML]);
      const fetcher: NoticesFetcher = new NoticesFetcher(
        new Logger(NOTICES_LOG_DOMAIN), port, SESSION, COURSES, strictPureBase64Decoder);
      const notices: Notice[] = await fetcher.fetch(['c1', 'c2']);
      // 每个课程都拿到两份夹具：Wgq（2 条）+ Ygq（1 条）= 3 条 → 2 课程 = 6 条
      expect(notices.length).assertEqual(6);
      // 列表请求 = 2 课程 × 2 接口 = 4；详情请求 = 每课程 1 条带附件名的记录 = 2
      expect(port.postUrls.length).assertEqual(4);
      expect(port.getUrls.length).assertEqual(2);
      expect(port.postUrls[0].includes('_csrf=csrf-fixture')).assertTrue();
      expect(port.postUrls[0].includes('pageListXsbyWgq')).assertTrue();
      expect(notices[0].publishTime).assertEqual('2020-09-25 07:21');
      expect(notices[5].publishTime).assertEqual('2020-08-17 17:50');
      const first: Notice = noticeById(notices, '26ef84e86d60f069016dadb09dd673b2');
      expect(first.courseId).assertEqual('c1');
      expect(first.courseName).assertEqual('通信与网络');
      expect(first.courseTeacherName).assertEqual('周世东');
      // 这条记录的 sfyd 是 '已读'（夹具里三种写法各一：'0' / '已读' / 1）
      expect(first.hasRead).assertTrue();
      const unread: Notice = noticeById(notices, '26ef84e76cc258ed016d3ea25a95157d');
      expect(unread.hasRead).assertFalse();
      // Ygq 夹具的那条记录两个课程各一份：第一份属于 c1，且两份的课程名不同
      const second: Notice = noticeById(notices, 'aa11bb22cc33dd44');
      expect(second.courseId).assertEqual('c1');
      expect(second.courseName).assertEqual('通信与网络');
      expect(second.hasRead).assertTrue();
      const secondCopies: Notice[] = notices.filter((item: Notice): boolean => item.id === 'aa11bb22cc33dd44');
      expect(secondCopies.length).assertEqual(2);
      expect(secondCopies[0].courseName).assertEqual('通信与网络');
      expect(secondCopies[1].courseName).assertEqual('量子与统计');
      const withAttachment: Notice[] = notices.filter((item: Notice): boolean => item.attachment !== undefined);
      expect(withAttachment.length).assertEqual(2);
      expect(withAttachment[0].attachment?.id).assertEqual('1998990181_GG_5f2c9a1b');
      assertHasItemsAndElapsed(latestLog(NOTICES_LOG_DOMAIN, 'fetched'), 6);
    });

    it('assignmentsFetchParsesFourAttachmentsAndLogs', 0, async () => {
      const port: ScriptedFetchPort = new ScriptedFetchPort()
        .routePost('zyList', ASSIGNMENT_LIST_RESPONSE_JSON)
        .routePost('kczy/zy/student/detail', ASSIGNMENT_DESCRIPTION_RESPONSE_JSON)
        .routeGetSeq('zy/student/view', [ASSIGNMENT_DETAIL_FOUR_BLOCKS_HTML]);
      const fetcher: AssignmentsFetcher = new AssignmentsFetcher(
        new Logger(ASSIGNMENTS_LOG_DOMAIN), port, SESSION, COURSES);
      const assignments: Assignment[] = await fetcher.fetch(['c1']);
      expect(assignments.length).assertEqual(2);
      // 三个列表接口各返回同 2 条 → 3 次列表 post；每条记录都会先补详情再按 id 合并
      // （参考实现也是先去重后合并，所以是 2 条 × 3 来源 = 6 次补详情），
      // 每次补详情 = 1 次描述 post + 1 次详情 get：
      //   post = 3 + 6 = 9，get = 6
      // 补做：每门课再多一次优秀作业列表 post。本测试没有为 'yxzylist' 路由，
      // 于是那一次 404 被当成"这门课没有优秀作业"吞掉（顺带覆盖了失败容错）；
      // 列表为空 ⇒ 没有 viewYxzy get。
      //   post = 9 + 1 = 10，get = 6
      expect(port.postUrls.length).assertEqual(10);
      expect(port.getUrls.length).assertEqual(6);
      expect(assignments[0].excellentHomeworkList === undefined).assertTrue();
      const first: Assignment = assignments[0];
      expect(first.title).assertEqual('大作业1');
      expect(first.attachment?.name).assertEqual('作业要求.pdf');
      expect(first.answerAttachment?.name).assertEqual('参考答案.pdf');
      expect(first.submittedAttachment?.name).assertEqual('我的提交.pdf');
      expect(first.gradeAttachment?.name).assertEqual('批改结果.pdf');
      expect(first.description).assertEqual('<p>要求见课件&讲义</p>');
      expect(first.grade).assertEqual(88);
      expect(first.graded).assertTrue();
      expect(first.submitted).assertTrue();
      expect(first.courseName).assertEqual('通信与网络');
      assertHasItemsAndElapsed(latestLog(ASSIGNMENTS_LOG_DOMAIN, 'fetched'), 2);
    });

    /*
     * 优秀作业（补做）：每门课一次 `yxzylist` + 每条一次 `viewYxzy` 详情页，
     * 按 `zyid`（= Assignment.baseId）挂到作业上。
     * 夹具列表里"大作业1"的 zyid 是 26ef84e8937624450193ba443c9414aa。
     */
    it('assignmentsFetchAttachesExcellentHomeworkAndCountsRequests', 0, async () => {
      const excellent: string = '{"result":"success","object":{"aaData":['
        + '{"wlkcid":"c1","bt":"大作业1","xszyid":"exc-anon",'
        + '"zyid":"26ef84e8937624450193ba443c9414aa","zywcfs":"1","cy":"","sfzm":"是","zyfjid":"fj-anon"},'
        + '{"wlkcid":"c1","bt":"大作业1","xszyid":"exc-named",'
        + '"zyid":"26ef84e8937624450193ba443c9414aa","zywcfs":"1","cy":"2021000000 张三","sfzm":"否",'
        + '"zyfjid":"fj-named"}'
        + ']}}';
      const port: ScriptedFetchPort = new ScriptedFetchPort()
        .routePost('zyList', ASSIGNMENT_LIST_RESPONSE_JSON)
        .routePost('kczy/zy/student/detail', ASSIGNMENT_DESCRIPTION_RESPONSE_JSON)
        .routePost('yxzylist', excellent)
        .routeGetSeq('viewYxzy', [ASSIGNMENT_DETAIL_FOUR_BLOCKS_HTML])
        .routeGetSeq('zy/student/view', [ASSIGNMENT_DETAIL_FOUR_BLOCKS_HTML]);
      const assignments: Assignment[] = await new AssignmentsFetcher(
        new Logger(ASSIGNMENTS_LOG_DOMAIN), port, SESSION, COURSES).fetch(['c1']);
      expect(assignments.length).assertEqual(2);
      // post = 3 个列表 + 6 次补详情 + 1 次优秀作业列表 = 10；get = 6 次详情 + 2 次优秀作业页 = 8
      expect(port.postUrls.length).assertEqual(10);
      expect(port.getUrls.length).assertEqual(8);
      let withExcellent: Assignment | undefined = undefined;
      let withoutExcellent: Assignment | undefined = undefined;
      for (let i = 0; i < assignments.length; i++) {
        if (assignments[i].baseId === '26ef84e8937624450193ba443c9414aa') {
          withExcellent = assignments[i];
        } else {
          withoutExcellent = assignments[i];
        }
      }
      expect(withExcellent !== undefined).assertTrue();
      expect(withoutExcellent !== undefined).assertTrue();
      expect(withExcellent?.excellentHomeworkList?.length).assertEqual(2);
      expect(withExcellent?.excellentHomeworkList?.[0].anonymous).assertTrue();
      expect(withExcellent?.excellentHomeworkList?.[1].anonymous).assertFalse();
      expect(withExcellent?.excellentHomeworkList?.[1].authorName).assertEqual('张三');
      // 附件来自 `viewYxzy` 详情页的四类附件块（块序不变）
      expect(withExcellent?.excellentHomeworkList?.[0].gradeAttachment?.name).assertEqual('批改结果.pdf');
      expect(withExcellent?.excellentHomeworkList?.[0].submittedAttachment?.name).assertEqual('我的提交.pdf');
      // 没有优秀作业的那条保持 undefined（界面据此不显示 medal）
      expect(withoutExcellent?.excellentHomeworkList === undefined).assertTrue();
      // 消费点自证行 + 汇总行里的条数
      expect(latestLog(ASSIGNMENTS_LOG_DOMAIN, 'excellent: course=c1').includes('items=2')).assertTrue();
      expect(latestLog(ASSIGNMENTS_LOG_DOMAIN, 'excellent: course=c1').includes('anonymous=1')).assertTrue();
      expect(latestLog(ASSIGNMENTS_LOG_DOMAIN, 'excellent: course=c1').includes('named=1')).assertTrue();
      expect(latestLog(ASSIGNMENTS_LOG_DOMAIN, 'fetched').includes('excellent=2')).assertTrue();
    });


    /*
     * 真实数据缺陷回归（2026-09-12，模拟器 Pura 90，2025-2026 春季 57 条）：
     * 列表里前三条的截止时间是 05-31 / 06-20 / 04-30 —— **已过期段不是按时间排的**。
     * 根因：参考实现是两步（processor 先按截止时间倒序，JS 再切"未到期 / 已过期"），
     * 最初的移植只搬了第二步。这里钉住"两步都做完"：未到期在前且由近及远、已过期按时间倒序。
     */
    it('assignmentsFetchSortsByDeadlineBeforeSplittingUpcomingAndPast', 0, async () => {
      const pad: (n: number) => string = (n: number): string => (n < 10 ? '0' + n.toString() : n.toString());
      const future: Date = new Date(Date.now() + 400 * 24 * 3600 * 1000);
      const futureStamp: string = future.getFullYear().toString() + '-'
        + pad(future.getMonth() + 1) + '-' + pad(future.getDate()) + ' '
        + pad(future.getHours()) + ':' + pad(future.getMinutes());
      // 夹具顺序故意与截止时间顺序无关（旧 → 未到期 → 新）
      const body: string = '{"result":"success","object":{"aaData":['
        + '{"xszyid":"a-past-older","zyid":"a-past-older","bt":"旧","jzsj":"2020-09-05 23:59"},'
        + '{"xszyid":"a-future","zyid":"a-future","bt":"未到期","jzsj":"' + futureStamp + '"},'
        + '{"xszyid":"a-past-newer","zyid":"a-past-newer","bt":"新","jzsj":"2020-09-20 23:59"}'
        + ']}}';
      const port: ScriptedFetchPort = new ScriptedFetchPort()
        .routePost('zyList', body)
        .routePost('kczy/zy/student/detail', ASSIGNMENT_DESCRIPTION_RESPONSE_JSON)
        .routeGetSeq('zy/student/view', [ASSIGNMENT_DETAIL_FOUR_BLOCKS_HTML]);
      const assignments: Assignment[] = await new AssignmentsFetcher(
        new Logger(ASSIGNMENTS_LOG_DOMAIN), port, SESSION, COURSES).fetch(['c1']);
      expect(assignments.length).assertEqual(3);
      expect(assignments[0].id).assertEqual('a-future');
      expect(assignments[1].id).assertEqual('a-past-newer');
      expect(assignments[2].id).assertEqual('a-past-older');
      expect(isPastDeadline(assignments[0].deadline, Date.now())).assertFalse();
      expect(isPastDeadline(assignments[1].deadline, Date.now())).assertTrue();
    });

    it('filesFetchParsesAndLogs', 0, async () => {
      const port: ScriptedFetchPort = new ScriptedFetchPort()
        .routeGetSeq('kjxxbByWlkcidAndSizeForStudent', [FILE_LIST_RESPONSE_JSON]);
      const fetcher: FilesFetcher = new FilesFetcher(new Logger(FILES_LOG_DOMAIN), port, SESSION, COURSES);
      const files: CourseFile[] = await fetcher.fetch(['c1', 'c2']);
      expect(port.getUrls.length).assertEqual(2);
      expect(files.length).assertEqual(4);
      expect(files[0].title).assertEqual('第1讲 绪论.pdf');
      expect(files[0].size).assertEqual('1.20MB');
      expect(files[0].courseId === 'c1' || files[0].courseId === 'c2').assertTrue();
      expect(files[0].downloadUrl.includes('wjid=2016310500_KJ_157080064094130b5f1dcc2')).assertTrue();
      assertHasItemsAndElapsed(latestLog(FILES_LOG_DOMAIN, 'fetched'), 4);
    });

    it('survivesFailedRequestsWithoutLosingOthers', 0, async () => {
      const port: ScriptedFetchPort = new ScriptedFetchPort()
        .routePost('pageListXsbyWgq', NOTICE_LIST_RESPONSE_JSON)
        .routePost('pageListXsbyYgq', NOTICE_LIST_RESULTS_LIST_JSON)
        .routeGetSeq('beforeViewXs', [NOTICE_DETAIL_ML10_HTML])
        .failOn('pageListXsbyYgq');
      const fetcher: NoticesFetcher = new NoticesFetcher(
        new Logger(NOTICES_LOG_DOMAIN), port, SESSION, COURSES, strictPureBase64Decoder);
      const notices: Notice[] = await fetcher.fetch(['c1']);
      expect(notices.length).assertEqual(2);
      const message: string = latestLog(NOTICES_LOG_DOMAIN, 'fetched');
      expect(message.includes('failures=1')).assertTrue();
      expect(message.includes('items=2')).assertTrue();
      expect(latestLog(NOTICES_LOG_DOMAIN, 'request failed').length > 0).assertTrue();
    });

    it('treatsNonSuccessJsonAsNoItems', 0, async () => {
      const port: ScriptedFetchPort = new ScriptedFetchPort()
        .routePost('pageListXsbyWgq', SESSION_EXPIRED_JSON)
        .routePost('pageListXsbyYgq', SESSION_EXPIRED_JSON);
      const notices: Notice[] = await new NoticesFetcher(
        new Logger(NOTICES_LOG_DOMAIN), port, SESSION, COURSES, strictPureBase64Decoder).fetch(['c1']);
      expect(notices.length).assertEqual(0);
      assertHasItemsAndElapsed(latestLog(NOTICES_LOG_DOMAIN, 'fetched'), 0);
      const files: CourseFile[] = await new FilesFetcher(
        new Logger(FILES_LOG_DOMAIN), port, SESSION, COURSES).fetch(['c1']);
      expect(files.length).assertEqual(0);
      assertHasItemsAndElapsed(latestLog(FILES_LOG_DOMAIN, 'fetched'), 0);
      const assignments: Assignment[] = await new AssignmentsFetcher(
        new Logger(ASSIGNMENTS_LOG_DOMAIN), port, SESSION, COURSES).fetch(['c1']);
      expect(assignments.length).assertEqual(0);
      assertHasItemsAndElapsed(latestLog(ASSIGNMENTS_LOG_DOMAIN, 'fetched'), 0);
    });

    it('returnsEmptyImmediatelyForNoCourses', 0, async () => {
      const port: ScriptedFetchPort = new ScriptedFetchPort();
      const notices: Notice[] = await new NoticesFetcher(
        new Logger(NOTICES_LOG_DOMAIN), port, SESSION, COURSES, strictPureBase64Decoder).fetch([]);
      expect(notices.length).assertEqual(0);
      expect(port.postUrls.length).assertEqual(0);
      expect(port.getUrls.length).assertEqual(0);
      assertHasItemsAndElapsed(latestLog(NOTICES_LOG_DOMAIN, 'fetched'), 0);
    });
  });
}