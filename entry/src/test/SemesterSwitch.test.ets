/*
 * 学期切换的整链单测：**唯一**的有效学期优先级函数 + 界面选择进入进程级状态后
 * 四条取数路径都读到它 + 切换编排的结果分类与提示选择。
 *
 * 全部注入式，无平台依赖（端口是脚本化假实现，仓储是替身）。
 *
 * **进程级全局状态会在用例之间串味**：所以每个用例开始前都 `clearSelectedSemesterId()`
 * （与既有用例对 `clearRuntimeSemesterOverride()` 的处理同一口径）。
 */

import { describe, it, expect, beforeEach } from '@ohos/hypium';
import { Logger } from '../main/ets/core/log/Logger';
import { FetchOutcome, FetchPort, GetSpec, PostFormSpec, UploadSpec } from '../main/ets/data/remote/Port';
import { Session } from '../main/ets/data/remote/Requests';
import { Notice } from '../main/ets/domain/model/ContentItem';
import {
  COURSE_LIST_PATH_PREFIX, HttpCourseListSource
} from '../main/ets/data/courses/CourseListFetcher';
import { HttpSemesterSource } from '../main/ets/data/courses/SemesterFetcher';
import { HttpCourseFetchSource } from '../main/ets/data/courses/CourseFetchSource';
import { HttpNoticeFetchSource } from '../main/ets/data/notices/NoticeFetchSource';
import { HttpFileFetchSource } from '../main/ets/data/files/FileFetchSource';
import { CourseRecord, CourseRepository, CourseSnapshot } from '../main/ets/data/courses/CourseRepository';
import { CourseListStore } from '../main/ets/features/courses/CourseListStore';
import {
  EffectiveSemester, clearRuntimeSemesterOverride, clearSelectedSemesterId, resolveEffectiveSemester,
  selectedSemesterForFetch, setRuntimeSemesterOverride, setSelectedSemesterId
} from '../main/ets/data/courses/SemesterOverride';
import {
  DomainOutcome, SWITCH_DOMAIN_COURSES, SWITCH_DOMAIN_FILES, SWITCH_DOMAIN_NOTICES,
  SWITCH_RESULT_FAILED, SWITCH_RESULT_PARTIAL, SWITCH_RESULT_SUCCESS, buildDomainOutcome,
  classifySwitchResult, summarizeReason
} from '../main/ets/features/courses/SemesterSwitch';
import {
  SEMESTER_SWITCH_TOAST_MILLIS_FOR_EVIDENCE, TOAST_MILLIS_FOR_EVIDENCE, resolveToastMillis
} from '../main/ets/ui/components/Toast';
import { strictPureBase64Decoder } from './TestHelpers';

const SESSION: Session = { cookie: 'JSESSIONID=fixture', csrfToken: 'csrf-fixture' };
const logger: Logger = new Logger('data.courses');

/** 站点当前学期 = 2026-2027-1（秋季）；被选的学期 = 2025-2026-2（春季，数据不同）。 */
const SITE_CURRENT: string = '2026-2027-1';
const PICKED: string = '2025-2026-2';

const CURRENT_SEMESTER_JSON: string =
  '{"result":{"xnxq":"' + SITE_CURRENT + '","xnxqmc":"2026-2027秋季学期"},"message":"success","resultList":[]}';
const SEMESTER_LIST_JSON: string = '["' + SITE_CURRENT + '","' + PICKED + '","2024-2025-2"]';

/** 课程列表：两门课（公告路径要非空课程才有公告）。 */
const COURSE_LIST_JSON: string = '{"message":"success","resultList":['
  + '{"wlkcid":"' + SITE_CURRENT + '-c1","kcm":"课程一","zywkcm":"课程一","ywkcm":"C1","jsm":"张老师",'
  + '"jsh":"2005001","kch":"14201062","kxh":"1"},'
  + '{"wlkcid":"' + SITE_CURRENT + '-c2","kcm":"课程二","zywkcm":"课程二","ywkcm":"C2","jsm":"李老师",'
  + '"jsh":"2005002","kch":"30240324","kxh":"2"}]}';

const NOTICE_LIST_JSON: string = '{"result":"success","object":{"aaData":['
  + '{"id":"gg1stu1","ggid":"gg1","bt":"欢迎","fbrxm":"张老师","fbsj":"2026-09-10 13:07",'
  + '"sfqd":"0","sfyd":"否","fjmc":null,"ggnr":""}]}}';
const EMPTY_NOTICE_LIST_JSON: string = '{"result":"success","object":{"aaData":[]}}';

const FILE_LIST_JSON: string = '{"result":"success","object":['
  + '{"kjxxid":"kj1","wjid":"wj1","bt":"第1讲.pdf","ms":"","fileSize":"1.20MB",'
  + '"scsj":"2026-09-10 13:07","wjlx":"pdf","isNew":true}]}';

/** 脚本化假端口：按 URL 子串路由，记录每次 GET 的 URL；未命中 404。 */
class ScriptedFetchPort implements FetchPort {
  readonly getUrls: string[] = [];
  private routeKeys: string[] = [];
  private routeBodies: string[] = [];

  route(urlPart: string, body: string): ScriptedFetchPort {
    this.routeKeys.push(urlPart);
    this.routeBodies.push(body);
    return this;
  }

  async get(session: Session, spec: GetSpec): Promise<FetchOutcome> {
    this.getUrls.push(spec.url);
    for (let i = 0; i < this.routeKeys.length; i++) {
      if (spec.url.includes(this.routeKeys[i])) {
        return { ok: true, status: 200, body: this.routeBodies[i] };
      }
    }
    return { ok: false, status: 404, body: '', error: 'no scripted response for ' + spec.url };
  }

  async postForm(session: Session, spec: PostFormSpec): Promise<FetchOutcome> {
    return { ok: true, status: 200, body: NOTICE_LIST_JSON };
  }

  async upload(session: Session, spec: UploadSpec): Promise<FetchOutcome> {
    return { ok: true, status: 200, body: '{"result":"success"}' };
  }
}

function fullPort(): ScriptedFetchPort {
  return new ScriptedFetchPort()
    .route('getCurrentAndNextSemester', CURRENT_SEMESTER_JSON)
    .route('queryxnxq', SEMESTER_LIST_JSON)
    .route('loadCourseBySemesterId', COURSE_LIST_JSON)
    .route('pageListXsbyWgq', NOTICE_LIST_JSON)
    .route('pageListXsbyYgq', EMPTY_NOTICE_LIST_JSON)
    .route('kjxxbByWlkcidAndSizeForStudent', FILE_LIST_JSON);
}

/** 课程列表请求 URL 里的学期段（`…/loadCourseBySemesterId/<xnxq>/<lang>`）。 */
function semesterInCourseUrl(url: string): string {
  const prefix: string = '/loadCourseBySemesterId/';
  const at: number = url.indexOf(prefix);
  if (at < 0) {
    return '';
  }
  const rest: string = url.substring(at + prefix.length);
  const slash: number = rest.indexOf('/');
  return slash < 0 ? rest : rest.substring(0, slash);
}

function askedSemesters(port: ScriptedFetchPort): string[] {
  const out: string[] = [];
  for (let i = 0; i < port.getUrls.length; i++) {
    const value: string = semesterInCourseUrl(port.getUrls[i]);
    if (value.length > 0) {
      out.push(value);
    }
  }
  return out;
}

/** 课程仓储替身：记录被问到的学期，并按学期给**不同**的课程集合。 */
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
    const courses: CourseRecord[] = asked === PICKED
      ? [courseRecord(PICKED + '-44100563', '形式语言与自动机')]
      : [courseRecord(SITE_CURRENT + '-14201092', '英语听说交流（A）')];
    return {
      courses: courses,
      notices: [], assignments: [], files: [],
      semesterId: picked ? asked : SITE_CURRENT,
      siteCurrentSemesterId: SITE_CURRENT,
      semesterSource: picked ? 'selection' : 'site-current',
      semesters: [SITE_CURRENT, PICKED],
      semestersAvailable: true,
      fetchedAtMillis: 123
    };
  }
}

function courseRecord(id: string, name: string): CourseRecord {
  return {
    id: id, name: name, chineseName: name, englishName: '',
    teacherName: '', teacherNumber: '', courseNumber: '', courseIndex: 0,
    unreadNoticeCount: 0, unfinishedAssignmentCount: 0, unreadFileCount: 0
  };
}

function outcome(domain: string, ok: boolean, reason: string = '', items: number = 0): DomainOutcome {
  return new DomainOutcome(domain, ok, reason, items);
}

export default function semesterSwitchTest() {
  describe('data.courses.resolveEffectiveSemester', () => {
    beforeEach(() => {
      clearRuntimeSemesterOverride();
      clearSelectedSemesterId();
    });

    it('prefers override over selection over the site current semester', 0, () => {
      // 三档都在：覆盖赢。
      setRuntimeSemesterOverride(PICKED);
      setSelectedSemesterId('2024-2025-2');
      let resolved: EffectiveSemester = resolveEffectiveSemester({
        siteCurrentSemesterId: SITE_CURRENT, explicitSelection: ''
      });
      expect(resolved.semesterId).assertEqual(PICKED);
      expect(resolved.source).assertEqual('override');

      // 没有覆盖：进程级选择赢过站点当前学期。
      clearRuntimeSemesterOverride();
      resolved = resolveEffectiveSemester({
        siteCurrentSemesterId: SITE_CURRENT, explicitSelection: ''
      });
      expect(resolved.semesterId).assertEqual('2024-2025-2');
      expect(resolved.source).assertEqual('selection');

      // 显式参数优先于进程级选择（旧调用点仍走这条）。
      resolved = resolveEffectiveSemester({
        siteCurrentSemesterId: SITE_CURRENT, explicitSelection: PICKED
      });
      expect(resolved.semesterId).assertEqual(PICKED);
      expect(resolved.source).assertEqual('selection');

      // 都没有：站点当前学期。
      clearSelectedSemesterId();
      resolved = resolveEffectiveSemester({
        siteCurrentSemesterId: SITE_CURRENT, explicitSelection: ''
      });
      expect(resolved.semesterId).assertEqual(SITE_CURRENT);
      expect(resolved.source).assertEqual('site-current');

      // 三档都空：显式的 none（调用方据此报错，绝不静默跟随）。
      resolved = resolveEffectiveSemester({ siteCurrentSemesterId: '', explicitSelection: '' });
      expect(resolved.semesterId).assertEqual('');
      expect(resolved.source).assertEqual('none');
    });

    it('rejects malformed selections instead of treating them as a switch', 0, () => {
      expect(setSelectedSemesterId('2025-2026')).assertFalse();
      expect(setSelectedSemesterId('junk')).assertFalse();
      expect(selectedSemesterForFetch()).assertEqual('');
      expect(setSelectedSemesterId('  2025-2026-2 ')).assertTrue();
      expect(selectedSemesterForFetch()).assertEqual('2025-2026-2');
    });
  });

  describe('features.courses.semesterSelectionReachesFetchPaths', () => {
    beforeEach(() => {
      clearRuntimeSemesterOverride();
      clearSelectedSemesterId();
    });

    it('lets CourseListStore write the process-wide selection', 0, async () => {
      const repository: FakeCourseRepository = new FakeCourseRepository(false);
      const store: CourseListStore = new CourseListStore(repository);
      store.markSwitchingTo(PICKED);
      await store.selectSemester(PICKED);
      // 进程级状态里能看到它（公告 / 文件两条路径读的就是这一份）。
      expect(selectedSemesterForFetch()).assertEqual(PICKED);
      expect(repository.requests[0]).assertEqual(PICKED);
      expect(store.semesterId).assertEqual(PICKED);
    });

    it('drives the course path from the process-wide selection', 0, async () => {
      const port: ScriptedFetchPort = fullPort();
      setSelectedSemesterId(PICKED);
      const semesters: HttpSemesterSource = new HttpSemesterSource(logger, port);
      const courses: HttpCourseListSource = new HttpCourseListSource(logger, port, semesters);
      const source: HttpCourseFetchSource = new HttpCourseFetchSource(port, semesters, courses,
        strictPureBase64Decoder, logger);
      // 显式参数留空 ⇒ 生效值只可能来自进程级选择。
      const snapshot: CourseSnapshot = await source.fetchWithSession(SESSION, '');
      expect(snapshot.semesterId).assertEqual(PICKED);
      expect(snapshot.semesterSource).assertEqual('selection');
      const asked: string[] = askedSemesters(port);
      expect(asked.length).assertEqual(1);
      expect(asked[0]).assertEqual(PICKED);
    });

    it('drives the notice path from the process-wide selection', 0, async () => {
      const port: ScriptedFetchPort = fullPort();
      setSelectedSemesterId(PICKED);
      const semesters: HttpSemesterSource = new HttpSemesterSource(logger, port);
      const courses: HttpCourseListSource = new HttpCourseListSource(logger, port, semesters);
      const source: HttpNoticeFetchSource =
        new HttpNoticeFetchSource(port, semesters, courses, strictPureBase64Decoder);
      const notices: Notice[] = await source.fetchWithSession(SESSION);
      // 关键判据：公告路径的**课程列表请求 URL 带上了选中学期**（此前不带 ⇒ 永远站点当前学期）。
      const asked: string[] = askedSemesters(port);
      expect(asked.length).assertEqual(1);
      expect(asked[0]).assertEqual(PICKED);
      expect(notices.length > 0).assertTrue();
    });

    it('drives the file path from the process-wide selection', 0, async () => {
      const port: ScriptedFetchPort = fullPort();
      setSelectedSemesterId(PICKED);
      const semesters: HttpSemesterSource = new HttpSemesterSource(logger, port);
      const courses: HttpCourseListSource = new HttpCourseListSource(logger, port, semesters);
      const source: HttpFileFetchSource =
        new HttpFileFetchSource(port, semesters, courses, logger);
      const result = await source.fetchWithSession(SESSION, '');
      expect(result.semesterId).assertEqual(PICKED);
      // 判别性判据：课程列表请求 URL 的学期段是**选中的那个**（此前文件路径只认覆盖 /
      // 站点当前 ⇒ 这里会是 2026-2027-1）。
      const asked: string[] = askedSemesters(port);
      expect(asked.length).assertEqual(1);
      expect(asked[0]).assertEqual(PICKED);
      // 两门课各一条文件（夹具与课程数一致，顺带证明取数确实跑了）。
      expect(result.files.length).assertEqual(2);
    });

    it('keeps following the site current semester when nothing is selected', 0, async () => {
      const port: ScriptedFetchPort = fullPort();
      const semesters: HttpSemesterSource = new HttpSemesterSource(logger, port);
      const courses: HttpCourseListSource = new HttpCourseListSource(logger, port, semesters);
      const noticeSource: HttpNoticeFetchSource =
        new HttpNoticeFetchSource(port, semesters, courses, strictPureBase64Decoder);
      const fileSource: HttpFileFetchSource =
        new HttpFileFetchSource(port, semesters, courses, logger);
      await noticeSource.fetchWithSession(SESSION);
      const fileResult = await fileSource.fetchWithSession(SESSION, '');
      expect(fileResult.semesterId).assertEqual(SITE_CURRENT);
      const asked: string[] = askedSemesters(port);
      expect(asked.length).assertEqual(2);
      expect(asked[0]).assertEqual(SITE_CURRENT);
      expect(asked[1]).assertEqual(SITE_CURRENT);
    });

    it('fails the notice path explicitly when there is no effective semester', 0, async () => {
      // 非空端口：学期解析成功，但三档都没有值不可能发生；这里用"站点当前学期为空"的形状。
      const port: ScriptedFetchPort = new ScriptedFetchPort()
        .route('getCurrentAndNextSemester', '{"result":{},"message":"success","resultList":[]}');
      const semesters: HttpSemesterSource = new HttpSemesterSource(logger, port);
      const courses: HttpCourseListSource = new HttpCourseListSource(logger, port, semesters);
      const source: HttpNoticeFetchSource =
        new HttpNoticeFetchSource(port, semesters, courses, strictPureBase64Decoder);
      let message: string = '';
      try {
        await source.fetchWithSession(SESSION);
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message.includes('semester resolution failed')
        || message.includes('no effective semester')).assertTrue();
    });
  });

  describe('features.courses.switchResultClassification', () => {
    it('classifies all success, partial failure and total failure', 0, () => {
      expect(classifySwitchResult([
        outcome(SWITCH_DOMAIN_COURSES, true), outcome(SWITCH_DOMAIN_NOTICES, true),
        outcome(SWITCH_DOMAIN_FILES, true)
      ])).assertEqual(SWITCH_RESULT_SUCCESS);

      expect(classifySwitchResult([
        outcome(SWITCH_DOMAIN_COURSES, true), outcome(SWITCH_DOMAIN_NOTICES, false, 'boom'),
        outcome(SWITCH_DOMAIN_FILES, true)
      ])).assertEqual(SWITCH_RESULT_PARTIAL);

      expect(classifySwitchResult([
        outcome(SWITCH_DOMAIN_COURSES, false, 'a'), outcome(SWITCH_DOMAIN_NOTICES, false, 'b'),
        outcome(SWITCH_DOMAIN_FILES, false, 'c')
      ])).assertEqual(SWITCH_RESULT_FAILED);
    });

    it('treats a domain that reports failure as failed even though its promise resolved', 0, () => {
      // 三条 store 的 refresh() 都把异常吞进 errorMessage 并 **resolve**（既有降级口径），
      // 所以「promise fulfilled」不等于成功 —— 成败只看这一次调用自己报的返回值。
      const failed: DomainOutcome =
        buildDomainOutcome(SWITCH_DOMAIN_NOTICES, false,
          'notice refresh aborted by evidence switch', 2);
      expect(failed.ok).assertFalse();
      expect(failed.reason).assertEqual('notice refresh aborted by evidence switch');
      // 正对照：报了成功 ⇒ 成功。
      const ok: DomainOutcome = buildDomainOutcome(SWITCH_DOMAIN_FILES, true, '', 4);
      expect(ok.ok).assertTrue();
      expect(ok.reason).assertEqual('');
      // 一个域失败、两个成功 ⇒ 部分失败（**绝不**落进 success 档）。
      expect(classifySwitchResult([
        buildDomainOutcome(SWITCH_DOMAIN_COURSES, true, '', 7), failed, ok]))
        .assertEqual(SWITCH_RESULT_PARTIAL);
      // 三个域都报失败 ⇒ 全失败。
      const allBad: DomainOutcome[] = [failed,
        buildDomainOutcome(SWITCH_DOMAIN_COURSES, false, 'boom', 0),
        buildDomainOutcome(SWITCH_DOMAIN_FILES, false, 'boom', 0)];
      expect(classifySwitchResult(allBad)).assertEqual(SWITCH_RESULT_FAILED);
    });

    it('never reports success when exactly one domain fails', 0, () => {
      // 负对照：三域里任一失败都不能落进 success 档（"绝不假装切换成功"）。
      const domains: string[] = [SWITCH_DOMAIN_COURSES, SWITCH_DOMAIN_NOTICES, SWITCH_DOMAIN_FILES];
      for (let i = 0; i < domains.length; i++) {
        const outcomes: DomainOutcome[] = [];
        for (let j = 0; j < domains.length; j++) {
          outcomes.push(outcome(domains[j], j !== i, j === i ? 'offline' : ''));
        }
        expect(classifySwitchResult(outcomes)).assertEqual(SWITCH_RESULT_PARTIAL);
      }
    });

    it('summarizes failure reasons as a single truncated line', 0, () => {
      expect(summarizeReason('')).assertEqual('unknown');
      const twoLines: string = 'first line' + String.fromCharCode(10) + 'second line';
      expect(summarizeReason(twoLines)).assertEqual('first line second line');
      let long: string = '';
      for (let i = 0; i < 400; i++) {
        long = long + 'x';
      }
      expect(summarizeReason(long).length).assertEqual(141);
      expect(summarizeReason(long).endsWith('…')).assertTrue();
      expect(summarizeReason(long).startsWith('xxx')).assertTrue();
    });
  });

  describe('ui.components.toastDurationForSemesterSwitch', () => {
    it('keeps the evidence durations off in the commit state', 0, () => {
      // 提交态：两个取证覆盖都必须是 0，且解析器落回参考实现的 3000ms 档。
      expect(TOAST_MILLIS_FOR_EVIDENCE).assertEqual(0);
      expect(SEMESTER_SWITCH_TOAST_MILLIS_FOR_EVIDENCE).assertEqual(0);
      expect(resolveToastMillis(0)).assertEqual(3000);
      // 显式时长优先（学期切换的结果提示要能被帧 / dump 读到）。
      expect(resolveToastMillis(45000)).assertEqual(45000);
    });
  });
}
