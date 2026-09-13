/*
 * 课程数据链路的单测：学期解析 / 课程列表逐字段解析 / 一次抓取聚合三域 /
 * 学期覆盖与选择的优先级 / 0 门课的判读 / AuthedTaskRunner 的显式降级。
 *
 * 全部注入式，无平台依赖（端口是脚本化假实现，响应体是本文件内的夹具）。
 * 真实站点数据的对照在设备取证里。
 */

import { describe, it, expect } from '@ohos/hypium';
import { Logger } from '../main/ets/core/log/Logger';
import { logBuffer } from '../main/ets/core/log/LogBuffer';
import { AuthedRunResult, SessionTask } from '../main/ets/data/auth/SessionRestore';
import { FailReason } from '../main/ets/data/auth/AuthTypes';
import { FetchOutcome, FetchPort, GetSpec, PostFormSpec, UploadSpec } from '../main/ets/data/remote/Port';
import { Session } from '../main/ets/data/remote/Requests';
import { AuthedTaskExecutor } from '../main/ets/data/notices/RealNoticeRepository';
import {
  CourseEntry, HttpCourseListSource, parseCourseEntries, parseCourseList
} from '../main/ets/data/courses/CourseListFetcher';
import {
  HttpSemesterSource, SemesterResolution, extractSemesterId, parseSemesterList
} from '../main/ets/data/courses/SemesterFetcher';
import { CourseRecord, CourseRepository, CourseSnapshot } from '../main/ets/data/courses/CourseRepository';
import { CourseFetchSource, HttpCourseFetchSource, buildCourseRecords } from '../main/ets/data/courses/CourseFetchSource';
import { RealCourseRepository } from '../main/ets/data/courses/RealCourseRepository';
import {
  clearRuntimeSemesterOverride, effectiveSemesterOverride, normalizeSemesterOverride,
  semesterOverrideSource, setRuntimeSemesterOverride
} from '../main/ets/data/courses/SemesterOverride';
import { CourseListStore } from '../main/ets/features/courses/CourseListStore';
import { strictPureBase64Decoder } from './TestHelpers';

const SESSION: Session = { cookie: 'JSESSIONID=fixture', csrfToken: 'csrf-fixture' };
const logger: Logger = new Logger('data.courses');

const CURRENT_SEMESTER_JSON: string =
  '{"result":{"xnxq":"2026-2027-1","xnxqmc":"2026-2027秋季学期"},"message":"success","resultList":[]}';

/** 学期集合：含 null（照参考实现的 filter(s => s != null)）且**非顺序**排列。 */
const SEMESTER_LIST_JSON: string =
  '["2024-2025-2","2026-2027-1","2025-2026-2",null]';

/** 课程列表：两门课，逐字段覆盖参考实现映射的每一个字段。 */
const COURSE_LIST_JSON: string = `{
  "result": {"xnxq": "2026-2027-1"},
  "message": "success",
  "resultList": [
    {
      "wlkcid": "2026-2027-1152226210",
      "kcm": "英语听说交流（A）",
      "zywkcm": "英语听说交流（A）",
      "ywkcm": "English Listening and Speaking (A)",
      "jsm": "张为民",
      "jsh": "2005001",
      "kch": "14201062",
      "kxh": "1"
    },
    {
      "wlkcid": "2026-2027-1152227978",
      "kcm": "形式语言与自动机",
      "zywkcm": "形式语言与自动机 &amp; 计算",
      "ywkcm": "Formal Languages and Automata",
      "jsm": "赵乙宁",
      "jsh": "2005002",
      "kch": "30240324",
      "kxh": "2"
    }
  ]
}`;

const EMPTY_COURSE_LIST_JSON: string = '{"message":"success","resultList":[]}';

const NOTICE_LIST_JSON: string = `{
  "result": "success",
  "object": {
    "aaData": [
      {"id": "gg1stu1", "ggid": "gg1", "bt": "欢迎", "fbrxm": "张为民", "fbsj": "2026-09-10 13:07", "sfqd": "0", "sfyd": "否", "fjmc": null, "ggnr": ""},
      {"id": "gg2stu1", "ggid": "gg2", "bt": "已读公告", "fbrxm": "张为民", "fbsj": "2026-09-09 10:00", "sfqd": "0", "sfyd": "是", "fjmc": null, "ggnr": ""}
    ]
  }
}`;

const EMPTY_NOTICE_LIST_JSON: string = '{"result":"success","object":{"aaData":[]}}';

/**
 * 每个课程一份作业（`xszyid` 不同）：`AssignmentsFetcher` 会按 `assignmentKey` 去重，
 * 两门课用同一条记录会被合并成一条，那样"每门课各 1 条未完成作业"就测不出来。
 * 截止时间取远未来，测试不依赖"今天几号"。
 */
function assignmentBody(id: string): string {
  return '{"result":"success","object":{"aaData":[{'
    + '"xszyid":"' + id + '","zyid":"zy-' + id + '","wlkcid":"x","bt":"大作业",'
    + '"jzsj":"2999-01-01 00:00","bjjzsj":null,"sfbj":"0","zywcfs":"个人","zytjfs":"网络学堂",'
    + '"scsj":null,"cj":null,"jsm":null,"pynr":""}]}}';
}

const EMPTY_ASSIGNMENT_LIST_JSON: string = '{"result":"success","object":{"aaData":[]}}';

const FILE_LIST_JSON: string = `{
  "result": "success",
  "object": [
    {"kjxxid": "kj1", "wjid": "wj1", "bt": "第1讲.pdf", "ms": "", "fileSize": "1.20MB",
     "scsj": "2026-09-10 13:07", "wjlx": "pdf", "isNew": true}
  ]
}`;

const EMPTY_FILE_LIST_JSON: string = '{"result":"success","object":[]}';

/** 脚本化假端口：按 URL 子串路由（先注册的优先）；未命中返回 404（三域对 404 容错）。 */
class ScriptedFetchPort implements FetchPort {
  readonly getUrls: string[] = [];
  readonly postUrls: string[] = [];
  private routeKeys: string[] = [];
  private routeBodies: string[][] = [];
  private cursors: Map<string, number> = new Map<string, number>();

  route(urlPart: string, body: string): ScriptedFetchPort {
    return this.routeSeq(urlPart, [body]);
  }

  /** 同一子串按脚本顺序依次给出；用完后重复最后一条（与 DataFetch.test 的假端口同法）。 */
  routeSeq(urlPart: string, bodies: string[]): ScriptedFetchPort {
    this.routeKeys.push(urlPart);
    this.routeBodies.push(bodies);
    return this;
  }

  private respond(url: string): FetchOutcome {
    for (let i = 0; i < this.routeKeys.length; i++) {
      const key: string = this.routeKeys[i];
      if (url.includes(key)) {
        const seen: number | undefined = this.cursors.get(key);
        const index: number = seen === undefined ? 0 : seen;
        this.cursors.set(key, index + 1);
        const list: string[] = this.routeBodies[i];
        const bounded: number = index < list.length ? index : list.length - 1;
        return { ok: true, status: 200, body: list[bounded] };
      }
    }
    return { ok: false, status: 404, body: '', error: 'no scripted response for ' + url };
  }

  async get(session: Session, spec: GetSpec): Promise<FetchOutcome> {
    this.getUrls.push(spec.url);
    return this.respond(spec.url);
  }

  async postForm(session: Session, spec: PostFormSpec): Promise<FetchOutcome> {
    this.postUrls.push(spec.url);
    return this.respond(spec.url);
  }

  async upload(session: Session, spec: UploadSpec): Promise<FetchOutcome> {
    return { ok: true, status: 200, body: '{"result":"success"}' };
  }
}

/** 完整路由（课程 + 三域），用于"一次抓取聚合"的用例。 */
function fullPort(): ScriptedFetchPort {
  return new ScriptedFetchPort()
    .route('getCurrentAndNextSemester', CURRENT_SEMESTER_JSON)
    .route('queryxnxq', SEMESTER_LIST_JSON)
    .route('loadCourseBySemesterId', COURSE_LIST_JSON)
    .route('pageListXsbyWgq', NOTICE_LIST_JSON)
    .route('pageListXsbyYgq', EMPTY_NOTICE_LIST_JSON)
    .routeSeq('zyListWj', [assignmentBody('xs-c1'), assignmentBody('xs-c2')])
    .route('zyListYjwg', EMPTY_ASSIGNMENT_LIST_JSON)
    .route('zyListYpg', EMPTY_ASSIGNMENT_LIST_JSON)
    .route('kjxxbByWlkcidAndSizeForStudent', FILE_LIST_JSON);
}

function fetchSource(port: ScriptedFetchPort): HttpCourseFetchSource {
  const semesters: HttpSemesterSource = new HttpSemesterSource(logger, port);
  const courses: HttpCourseListSource = new HttpCourseListSource(logger, port, semesters);
  return new HttpCourseFetchSource(port, semesters, courses, strictPureBase64Decoder, logger);
}

/** 执行器替身：跑一次任务，或直接返回降级结果。 */
class FakeExecutor implements AuthedTaskExecutor {
  private readonly degraded: boolean;
  constructor(degraded: boolean) {
    this.degraded = degraded;
  }

  async run(task: SessionTask): Promise<AuthedRunResult> {
    if (this.degraded) {
      return AuthedRunResult.degraded(FailReason.NOT_LOGGED_IN, true, 'still noLogin after reAuth status=403');
    }
    await task(SESSION);
    return AuthedRunResult.success('ok:courses=2', false, 'status=200');
  }
}

/** 课程抓取替身。 */
class FakeCourseSource implements CourseFetchSource {
  private readonly snapshot: CourseSnapshot;
  constructor(snapshot: CourseSnapshot) {
    this.snapshot = snapshot;
  }

  async fetchWithSession(session: Session, selectedSemesterId: string): Promise<CourseSnapshot> {
    return this.snapshot;
  }
}

function emptySnapshot(): CourseSnapshot {
  return {
    courses: [], notices: [], assignments: [], files: [],
    semesterId: '2025-2026-2', siteCurrentSemesterId: '2026-2027-1', semesterSource: 'selection',
    semesters: ['2026-2027-1', '2025-2026-2'], semestersAvailable: true, fetchedAtMillis: 1
  };
}

/** 一门课的最小记录（本用例只关心 id / name）。 */
function courseRecord(id: string, name: string): CourseRecord {
  return {
    id: id,
    name: name,
    chineseName: name,
    englishName: '',
    teacherName: '',
    teacherNumber: '',
    courseNumber: '',
    courseIndex: 0,
    unreadNoticeCount: 0,
    unfinishedAssignmentCount: 0,
    unreadFileCount: 0
  };
}

/**
 * 记录被请求的学期、并按学期给出**不同课程集合**的假仓储。
 * "选择 → 生效"的判据必须能区分"换成了另一份数据"与"其实没换"，所以两个学期
 * 给不同的课程；`requests` 用来判"选择是否真的被传到了取数"。
 */
class FakeCourseRepository implements CourseRepository {
  readonly requests: string[] = [];
  private readonly failing: boolean;

  constructor(failing: boolean) {
    this.failing = failing;
  }

  async refresh(semesterId?: string): Promise<CourseSnapshot> {
    const asked: string = semesterId === undefined ? '' : semesterId;
    this.requests.push(asked);
    if (this.failing) {
      throw new Error('offline');
    }
    const picked: boolean = asked.length > 0;
    const courses: CourseRecord[] = asked === '2025-2026-2'
      ? [courseRecord('2025-2026-2-44100563', '形式语言与自动机')]
      : [courseRecord('2026-2027-1-14201092', '英语听说交流（A）'),
        courseRecord('2026-2027-1-30240324', '微积分')];
    return {
      courses: courses,
      notices: [],
      assignments: [],
      files: [],
      semesterId: picked ? asked : '2026-2027-1',
      siteCurrentSemesterId: '2026-2027-1',
      semesterSource: picked ? 'selection' : 'site-current',
      semesters: ['2026-2027-1', '2025-2026-2'],
      semestersAvailable: true,
      fetchedAtMillis: 123
    };
  }
}

export default function courseDataTest() {
  describe('data.courses.parsing', () => {
    it('extracts the current semester id from the site response', 0, () => {
      expect(extractSemesterId(CURRENT_SEMESTER_JSON)).assertEqual('2026-2027-1');
      expect(extractSemesterId('not json')).assertEqual('');
      expect(extractSemesterId('{"result":{}}')).assertEqual('');
    });

    it('parses the semester list and drops nulls like the reference implementation', 0, () => {
      const parsed: string[] | undefined = parseSemesterList(SEMESTER_LIST_JSON);
      expect(parsed !== undefined).assertTrue();
      if (parsed !== undefined) {
        expect(parsed.length).assertEqual(3);
      }
      expect(parseSemesterList('{"a":1}') === undefined).assertTrue();
      expect(parseSemesterList('nope') === undefined).assertTrue();
    });

    it('maps every course field the reference implementation maps', 0, () => {
      const entries: CourseEntry[] | undefined = parseCourseEntries(COURSE_LIST_JSON);
      expect(entries !== undefined).assertTrue();
      if (entries === undefined) {
        return;
      }
      expect(entries.length).assertEqual(2);
      expect(entries[0].id).assertEqual('2026-2027-1152226210');
      expect(entries[0].name).assertEqual('英语听说交流（A）');
      expect(entries[0].chineseName).assertEqual('英语听说交流（A）');
      expect(entries[0].englishName).assertEqual('English Listening and Speaking (A)');
      expect(entries[0].teacherName).assertEqual('张为民');
      expect(entries[0].teacherNumber).assertEqual('2005001');
      expect(entries[0].courseNumber).assertEqual('14201062');
      expect(entries[0].courseIndex).assertEqual(1);
      // zywkcm 走 decodeHTML（参考实现口径），kcm 也解码。
      expect(entries[1].name).assertEqual('形式语言与自动机 & 计算');
      expect(entries[1].chineseName).assertEqual('形式语言与自动机');
      expect(entries[1].teacherName).assertEqual('赵乙宁');
      // 非 JSON / message 非 success / resultList 缺失都必须是显式失败信号。
      expect(parseCourseEntries('nope') === undefined).assertTrue();
      expect(parseCourseEntries('{"message":"fail","resultList":[]}') === undefined).assertTrue();
      expect(parseCourseEntries('{"message":"success"}') === undefined).assertTrue();
    });

    it('keeps the ticket 09 name table (kcm, undecoded) for the notice path', 0, () => {
      const names = parseCourseList(COURSE_LIST_JSON);
      expect(names !== undefined).assertTrue();
      if (names === undefined) {
        return;
      }
      // 既有口径：name = kcm 原样（**不**解码、**不**取 zywkcm）。
      expect(names['2026-2027-1152227978'].name).assertEqual('形式语言与自动机');
      expect(names['2026-2027-1152227978'].teacherName).assertEqual('赵乙宁');
    });
  });

  describe('data.courses.SemesterOverride', () => {
    it('accepts only well-formed semester ids and gives runtime priority', 0, () => {
      clearRuntimeSemesterOverride();
      expect(normalizeSemesterOverride('  2025-2026-2 ')).assertEqual('2025-2026-2');
      expect(normalizeSemesterOverride('2025-2026')).assertEqual('');
      expect(normalizeSemesterOverride('junk')).assertEqual('');
      expect(effectiveSemesterOverride()).assertEqual('');
      expect(semesterOverrideSource()).assertEqual('none');

      expect(setRuntimeSemesterOverride('junk')).assertFalse();
      expect(effectiveSemesterOverride()).assertEqual('');
      expect(setRuntimeSemesterOverride('2025-2026-2')).assertTrue();
      expect(effectiveSemesterOverride()).assertEqual('2025-2026-2');
      expect(semesterOverrideSource()).assertEqual('runtime-want-param');
      clearRuntimeSemesterOverride();
      expect(effectiveSemesterOverride()).assertEqual('');
    });
  });

  describe('data.courses.HttpSemesterSource', () => {
    it('resolves the current semester and sorts the picker list newest first', 0, async () => {
      const port: ScriptedFetchPort = fullPort();
      const source: HttpSemesterSource = new HttpSemesterSource(logger, port);
      const resolution: SemesterResolution = await source.resolve(SESSION);
      expect(resolution.currentSemesterId).assertEqual('2026-2027-1');
      expect(resolution.listOk).assertTrue();
      expect(resolution.semesters.length).assertEqual(3);
      expect(resolution.semesters[0]).assertEqual('2026-2027-1');
      expect(resolution.semesters[1]).assertEqual('2025-2026-2');
      expect(resolution.semesters[2]).assertEqual('2024-2025-2');
    });

    it('degrades the semester list without failing the whole refresh', 0, async () => {
      const port: ScriptedFetchPort = new ScriptedFetchPort()
        .route('getCurrentAndNextSemester', CURRENT_SEMESTER_JSON);
      const source: HttpSemesterSource = new HttpSemesterSource(logger, port);
      const resolution: SemesterResolution = await source.resolve(SESSION);
      expect(resolution.currentSemesterId).assertEqual('2026-2027-1');
      expect(resolution.listOk).assertFalse();
      expect(resolution.semesters.length).assertEqual(0);
    });

    it('throws when the current semester request fails', 0, async () => {
      const port: ScriptedFetchPort = new ScriptedFetchPort();
      const source: HttpSemesterSource = new HttpSemesterSource(logger, port);
      let message: string = '';
      try {
        await source.resolve(SESSION);
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message.includes('current semester request failed')).assertTrue();
    });
  });

  describe('data.courses.HttpCourseFetchSource', () => {
    it('aggregates courses, three domains and counts in one session', 0, async () => {
      clearRuntimeSemesterOverride();
      const port: ScriptedFetchPort = fullPort();
      const snapshot: CourseSnapshot = await fetchSource(port).fetchWithSession(SESSION, '');
      expect(snapshot.courses.length).assertEqual(2);
      expect(snapshot.semesterId).assertEqual('2026-2027-1');
      expect(snapshot.semesterSource).assertEqual('site-current');
      expect(snapshot.siteCurrentSemesterId).assertEqual('2026-2027-1');
      expect(snapshot.semestersAvailable).assertTrue();
      expect(snapshot.semesters[0]).assertEqual('2026-2027-1');
      // 先断言三域条数（失败时能立刻区分"没取到"与"计数算错"）。
      expect(snapshot.notices.length).assertEqual(4);
      expect(snapshot.assignments.length).assertEqual(2);
      expect(snapshot.files.length).assertEqual(2);
      // 两门课，每个域各一条可用记录（公告一读一未读 → 1；作业未交未截止 → 1；文件 isNew → 1）。
      for (let i = 0; i < snapshot.courses.length; i++) {
        expect(snapshot.courses[i].unreadNoticeCount).assertEqual(1);
        expect(snapshot.courses[i].unfinishedAssignmentCount).assertEqual(1);
        expect(snapshot.courses[i].unreadFileCount).assertEqual(1);
      }
      expect(snapshot.fetchedAtMillis > 0).assertTrue();
      // 课程名表与条目都来自同一次响应。
      expect(snapshot.courses[0].id).assertEqual('2026-2027-1152226210');
    });

    it('lets the runtime override win over the UI selection', 0, async () => {
      const port: ScriptedFetchPort = fullPort();
      setRuntimeSemesterOverride('2025-2026-2');
      const snapshot: CourseSnapshot = await fetchSource(port).fetchWithSession(SESSION, '2024-2025-2');
      clearRuntimeSemesterOverride();
      expect(snapshot.semesterId).assertEqual('2025-2026-2');
      expect(snapshot.semesterSource).assertEqual('override');
      // 课程列表请求确实带上了覆盖后的学期段。
      let semesterInUrl: boolean = false;
      for (const url of port.getUrls) {
        if (url.includes('loadCourseBySemesterId/2025-2026-2/')) {
          semesterInUrl = true;
        }
      }
      expect(semesterInUrl).assertTrue();
    });

    it('uses the UI selection when no override is active', 0, async () => {
      clearRuntimeSemesterOverride();
      const port: ScriptedFetchPort = fullPort();
      const snapshot: CourseSnapshot = await fetchSource(port).fetchWithSession(SESSION, '2025-2026-2');
      expect(snapshot.semesterId).assertEqual('2025-2026-2');
      expect(snapshot.semesterSource).assertEqual('selection');
      expect(snapshot.siteCurrentSemesterId).assertEqual('2026-2027-1');
    });

    it('fails loudly when the site current semester has no courses', 0, async () => {
      clearRuntimeSemesterOverride();
      const port: ScriptedFetchPort = new ScriptedFetchPort()
        .route('getCurrentAndNextSemester', CURRENT_SEMESTER_JSON)
        .route('queryxnxq', SEMESTER_LIST_JSON)
        .route('loadCourseBySemesterId', EMPTY_COURSE_LIST_JSON);
      let message: string = '';
      try {
        await fetchSource(port).fetchWithSession(SESSION, '');
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message.includes('EMPTY for the site current semester')).assertTrue();
    });

    it('renders the empty state when a non-current semester genuinely has no courses', 0, async () => {
      clearRuntimeSemesterOverride();
      const port: ScriptedFetchPort = new ScriptedFetchPort()
        .route('getCurrentAndNextSemester', CURRENT_SEMESTER_JSON)
        .route('queryxnxq', SEMESTER_LIST_JSON)
        .route('loadCourseBySemesterId', EMPTY_COURSE_LIST_JSON);
      const snapshot: CourseSnapshot = await fetchSource(port).fetchWithSession(SESSION, '2025-2026-2');
      expect(snapshot.courses.length).assertEqual(0);
      expect(snapshot.semesterId).assertEqual('2025-2026-2');
      expect(snapshot.semesterSource).assertEqual('selection');
      expect(snapshot.notices.length).assertEqual(0);
    });

    it('falls back to current + active semester when the semester list is unavailable', 0, async () => {
      clearRuntimeSemesterOverride();
      const port: ScriptedFetchPort = new ScriptedFetchPort()
        .route('getCurrentAndNextSemester', CURRENT_SEMESTER_JSON)
        .route('loadCourseBySemesterId', COURSE_LIST_JSON)
        .route('pageListXsbyWgq', EMPTY_NOTICE_LIST_JSON)
        .route('pageListXsbyYgq', EMPTY_NOTICE_LIST_JSON)
        .route('zyListWj', EMPTY_ASSIGNMENT_LIST_JSON)
        .route('zyListYjwg', EMPTY_ASSIGNMENT_LIST_JSON)
        .route('zyListYpg', EMPTY_ASSIGNMENT_LIST_JSON)
        .route('kjxxbByWlkcidAndSizeForStudent', EMPTY_FILE_LIST_JSON);
      const snapshot: CourseSnapshot = await fetchSource(port).fetchWithSession(SESSION, '2025-2026-2');
      expect(snapshot.semestersAvailable).assertFalse();
      expect(snapshot.semesters.length).assertEqual(2);
      expect(snapshot.semesters[0]).assertEqual('2026-2027-1');
      expect(snapshot.semesters[1]).assertEqual('2025-2026-2');
    });
  });

  describe('data.courses.buildCourseRecords', () => {
    it('carries the parsed fields through and starts from zero counts', 0, () => {
      const entries: CourseEntry[] | undefined = parseCourseEntries(COURSE_LIST_JSON);
      expect(entries !== undefined).assertTrue();
      if (entries === undefined) {
        return;
      }
      const records = buildCourseRecords(entries, [], [], [], Date.now());
      expect(records.length).assertEqual(2);
      expect(records[0].id).assertEqual('2026-2027-1152226210');
      expect(records[0].name).assertEqual('英语听说交流（A）');
      expect(records[0].teacherName).assertEqual('张为民');
      expect(records[0].courseNumber).assertEqual('14201062');
      expect(records[0].courseIndex).assertEqual(1);
      expect(records[0].unreadNoticeCount).assertEqual(0);
      expect(records[0].unfinishedAssignmentCount).assertEqual(0);
      expect(records[0].unreadFileCount).assertEqual(0);
    });
  });

  describe('data.courses.RealCourseRepository', () => {
    it('returns the snapshot produced inside the runner', 0, async () => {
      const repository: RealCourseRepository = new RealCourseRepository(
        new FakeExecutor(false), new FakeCourseSource(emptySnapshot()), logger);
      const snapshot: CourseSnapshot = await repository.refresh('2025-2026-2');
      expect(snapshot.semesterId).assertEqual('2025-2026-2');
      expect(snapshot.courses.length).assertEqual(0);
    });

    it('rejects with requiresEnrollment when the runner degrades', 0, async () => {
      const repository: RealCourseRepository = new RealCourseRepository(
        new FakeExecutor(true), new FakeCourseSource(emptySnapshot()), logger);
      let message: string = '';
      try {
        await repository.refresh();
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message.includes('requiresEnrollment=true')).assertTrue();
    });
  });

  describe('data.courses.CourseListStore', () => {
    it('records the pick synchronously and applies the picked semester and course set', 0, async () => {
      const repository: FakeCourseRepository = new FakeCourseRepository(false);
      const store: CourseListStore = new CourseListStore(repository);
      // 点击那一刻选择就必须已经可读（勾选标记据此同步移动），而不是等取数回来才动。
      const pending: Promise<boolean> = store.selectSemester('2025-2026-2');
      expect(store.selectedSemesterId).assertEqual('2025-2026-2');
      expect(store.pendingSemesterId).assertEqual('2025-2026-2');
      await pending;
      // 选择真的被传给了取数（否则"生效"可能只是巧合）。
      expect(repository.requests.length).assertEqual(1);
      expect(repository.requests[0]).assertEqual('2025-2026-2');
      // 生效结果：生效学期 + 课程集合都来自被选的那个学期。
      expect(store.semesterId).assertEqual('2025-2026-2');
      expect(store.semesterSource).assertEqual('selection');
      expect(store.courses.length).assertEqual(1);
      expect(store.courses[0].name).assertEqual('形式语言与自动机');
      // 站点当前学期没有被误当成选择。
      expect(store.siteCurrentSemesterId).assertEqual('2026-2027-1');
      // 取数结束后不再算"在途"。
      expect(store.pendingSemesterId).assertEqual('');
    });

    it('keeps following the pick on later refreshes instead of the site current semester', 0, async () => {
      const repository: FakeCourseRepository = new FakeCourseRepository(false);
      const store: CourseListStore = new CourseListStore(repository);
      await store.loadOnce();
      expect(store.semesterSource).assertEqual('site-current');
      expect(store.courses.length).assertEqual(2);
      await store.selectSemester('2025-2026-2');
      expect(store.courses.length).assertEqual(1);
      expect(store.courses[0].id).assertEqual('2025-2026-2-44100563');
      // 选择留在 store 上：下一次刷新（下拉 / 提交后重取）仍按它取数。
      await store.refresh();
      expect(store.semesterId).assertEqual('2025-2026-2');
      expect(repository.requests.length).assertEqual(3);
      expect(repository.requests[2]).assertEqual('2025-2026-2');
    });

    it('reports the failure and clears the in-flight pick when the picked semester fails', 0, async () => {
      const store: CourseListStore = new CourseListStore(new FakeCourseRepository(true));
      await store.selectSemester('2025-2026-2');
      expect(store.hasError()).assertTrue();
      expect(store.errorMessage).assertEqual('offline');
      // 失败后不能留着"在途"标记，否则勾选标记会一直指向一个没有生效的学期。
      expect(store.pendingSemesterId).assertEqual('');
      expect(store.semesterId).assertEqual('');
    });
  });
}