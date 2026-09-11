/*
 * 三域"抓取 → 解析 → 排序"整链单测（ticket 05 验收项 1 的可测部分）。
 *
 * 端口（`FetchPort`）由脚本化假实现注入，响应体用夹具；
 * 因此这里验证的是：请求次数与顺序、响应 → 条目的映射、跨课程聚合、排序、
 * 失败容错，以及**每个域都打了带条目数与耗时的日志**（`data.* fetched ... items=.. elapsedMs=..`）。
 *
 * 真正的设备抓取（真实会话）另见 ticket 05 Comments 的"待账号验证"。
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
import { deviceBase64Decoder } from './TestHelpers';
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
      expect(extractAssignmentDescription(ASSIGNMENT_DESCRIPTION_RESPONSE_JSON))
        .assertEqual('<p>要求见课件&amp;讲义</p>');
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
        new Logger(NOTICES_LOG_DOMAIN), port, SESSION, COURSES, deviceBase64Decoder);
      const notices: Notice[] = await fetcher.fetch(['c1', 'c2']);
      expect(notices.length).assertEqual(4);
      expect(port.postUrls.length).assertEqual(4);
      expect(port.getUrls.length).assertEqual(2);
      expect(port.postUrls[0].includes('_csrf=csrf-fixture')).assertTrue();
      expect(port.postUrls[0].includes('pageListXsbyWgq')).assertTrue();
      expect(notices[0].publishTime).assertEqual('2020-09-25 07:21');
      expect(notices[3].publishTime).assertEqual('2020-08-17 17:50');
      const first: Notice = noticeById(notices, '26ef84e86d60f069016dadb09dd673b2');
      expect(first.courseId).assertEqual('c1');
      expect(first.courseName).assertEqual('通信与网络');
      expect(first.courseTeacherName).assertEqual('周世东');
      expect(first.hasRead).assertFalse();
      const second: Notice = noticeById(notices, 'aa11bb22cc33dd44');
      expect(second.courseName).assertEqual('量子与统计');
      expect(second.hasRead).assertTrue();
      const withAttachment: Notice[] = notices.filter((item: Notice): boolean => item.attachment !== undefined);
      expect(withAttachment.length).assertEqual(2);
      expect(withAttachment[0].attachment?.id).assertEqual('1998990181_GG_5f2c9a1b');
      assertHasItemsAndElapsed(latestLog(NOTICES_LOG_DOMAIN, 'fetched'), 4);
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
      // 列表 3 次；每条 2 次（描述 + 详情）→ post 3 + 2 = 5 次，get 2 × 2 = 4 次
      expect(port.postUrls.length).assertEqual(5);
      expect(port.getUrls.length).assertEqual(4);
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
        new Logger(NOTICES_LOG_DOMAIN), port, SESSION, COURSES, deviceBase64Decoder);
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
        new Logger(NOTICES_LOG_DOMAIN), port, SESSION, COURSES, deviceBase64Decoder).fetch(['c1']);
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
        new Logger(NOTICES_LOG_DOMAIN), port, SESSION, COURSES, deviceBase64Decoder).fetch([]);
      expect(notices.length).assertEqual(0);
      expect(port.postUrls.length).assertEqual(0);
      expect(port.getUrls.length).assertEqual(0);
      assertHasItemsAndElapsed(latestLog(NOTICES_LOG_DOMAIN, 'fetched'), 0);
    });
  });
}
