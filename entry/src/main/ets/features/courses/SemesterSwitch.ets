/*
 * 学期切换的**一次编排**（features/courses）。
 *
 * ## 为什么需要单独一层
 *
 * 学期切换不是"改一个字段"：四条取数路径（课程 / 作业共用课程快照、公告、文件）
 * 都要按新选择重取一遍，用户要看到"正在切换"与"切成了没有"。此前学期页的动作是
 * 「同步记选择 → 立刻 pop」——后台那一轮重取没有任何进度指示，用户看到的是
 * "点一下返回了、列表还是旧的"。
 *
 * 本模块把切换做成**一次编排**：
 *   1. 同步写入进程级选择（`setSelectedSemesterId`）——四条路径下次取数都会读到它；
 *   2. **并发等待全部域落地**（`Promise.allSettled`，单个域失败不拖垮其它域）；
 *   3. 给出**结果分类**（全部成功 / 部分失败 / 全部失败）+ 逐域明细；
 *   4. **不自动返回**：调用方（学期页）留在栈顶，由用户自己按返回。
 *
 * ## 结果分类是纯函数
 *
 * `classifySwitchResult` 不碰任何 store / 网络，单测直接钉三种结果与提示选择
 * （见 entry/src/test/SemesterSwitch.test.ets）。
 *
 * ## 与"课程域失败时保留旧数据"的关系
 *
 * 课程域失败时 `CourseListStore.refresh()` 自己保留旧快照并置 `errorMessage`；
 * 本模块**不**清空任何列表，只负责把"哪个域失败、原因要点"如实汇总出来 ——
 * 绝不假装切换成功。
 */

import { Logger } from '../../core/log/Logger';
import { CourseListStore } from './CourseListStore';
import { courseListStore } from './CourseListStoreProvider';
import { NoticeListStore } from '../notices/NoticeListStore';
import { noticeListStore } from '../notices/NoticeListStoreProvider';
import { FileListStore } from '../files/FileListStore';
import { fileListStore } from '../files/FileListStoreProvider';
import { setSelectedSemesterId } from '../../data/courses/SemesterOverride';

const logger: Logger = new Logger('features.courses.switch');

/** 一个域取数失败时的原因摘要上限（提示里给"要点"，不是整段堆栈）。 */
const REASON_LIMIT: number = 140;

/**
 * 【取证开关】**只服务取证**：> 0 时在三个域开始取数之前等这么多毫秒。
 *
 * 为什么需要它：一次切换的墙钟是 5–7 s，而本仓库的 `devecocli ui layout/screenshot`
 * 单次要 10–35 s —— "切换中"那一帧没有可靠的窗口（AGENTS.md：时间敏感的证据不要赌手速，
 * 要把延迟直接改大）。提交态必须是 0；实际生效值由 switchSemester 打进 hilog（消费点自证）。
 */
export const SWITCH_DELAY_FOR_EVIDENCE: number = 0;

/** 课程域（课程列表 + 作业 + 课程详情三域内容，来自同一次抓取）。 */
export const SWITCH_DOMAIN_COURSES: string = 'courses';
/** 公告域。 */
export const SWITCH_DOMAIN_NOTICES: string = 'notices';
/** 文件域。 */
export const SWITCH_DOMAIN_FILES: string = 'files';

/** 域的固定顺序（提示里"哪个域失败"按它列举，保证同一输入同一措辞）。 */
export const SWITCH_DOMAINS: string[] = [
  SWITCH_DOMAIN_COURSES, SWITCH_DOMAIN_NOTICES, SWITCH_DOMAIN_FILES
];

/** 三个结果档。 */
export const SWITCH_RESULT_SUCCESS: string = 'success';
export const SWITCH_RESULT_PARTIAL: string = 'partial';
export const SWITCH_RESULT_FAILED: string = 'failed';

/** 一个域的取数结果（成功标记 + 失败原因要点 + 条目数）。 */
export class DomainOutcome {
  readonly domain: string;
  readonly ok: boolean;
  /** 失败时是**要点**（已截断到 REASON_LIMIT），成功时是空串。 */
  readonly reason: string;
  readonly items: number;

  constructor(domain: string, ok: boolean, reason: string, items: number) {
    this.domain = domain;
    this.ok = ok;
    this.reason = reason;
    this.items = items;
  }
}

/** 整轮切换的结果。 */
export class SwitchResult {
  readonly kind: string;
  readonly targetSemesterId: string;
  readonly domains: DomainOutcome[];
  readonly elapsedMs: number;

  constructor(kind: string, targetSemesterId: string, domains: DomainOutcome[], elapsedMs: number) {
    this.kind = kind;
    this.targetSemesterId = targetSemesterId;
    this.domains = domains;
    this.elapsedMs = elapsedMs;
  }

  /** 是否全部成功。 */
  isSuccess(): boolean {
    return this.kind === SWITCH_RESULT_SUCCESS;
  }

  /** 失败的域（按 SWITCH_DOMAINS 的顺序）。 */
  failedDomains(): string[] {
    const out: string[] = [];
    for (let i = 0; i < SWITCH_DOMAINS.length; i++) {
      const name: string = SWITCH_DOMAINS[i];
      for (let j = 0; j < this.domains.length; j++) {
        if (this.domains[j].domain === name && !this.domains[j].ok) {
          out.push(name);
        }
      }
    }
    return out;
  }

  /** 第一条失败原因要点（全失败 / 部分失败时给用户的一句话）。 */
  firstReason(): string {
    for (let i = 0; i < this.domains.length; i++) {
      if (!this.domains[i].ok) {
        return this.domains[i].reason;
      }
    }
    return '';
  }
}

/** 失败原因 → 提示里的要点（单行、截断、空原因也有话说）。 */
export function summarizeReason(raw: string): string {
  const flat: string = raw.split('\n').join(' ').split('\r').join(' ').trim();
  if (flat.length === 0) {
    return 'unknown';
  }
  return flat.length > REASON_LIMIT ? flat.substring(0, REASON_LIMIT) + '…' : flat;
}

/**
 * **纯函数**：逐域结果 → 结果档。
 * 全部成功 ⇒ success；有失败但至少一个成功 ⇒ partial；全失败 ⇒ failed。
 */
export function classifySwitchResult(outcomes: DomainOutcome[]): string {
  let okCount: number = 0;
  let failCount: number = 0;
  for (let i = 0; i < outcomes.length; i++) {
    if (outcomes[i].ok) {
      okCount++;
    } else {
      failCount++;
    }
  }
  if (failCount === 0) {
    return SWITCH_RESULT_SUCCESS;
  }
  return okCount === 0 ? SWITCH_RESULT_FAILED : SWITCH_RESULT_PARTIAL;
}

/** 一行汇总（hilog 自证：目标学期 + 结果档 + 逐域 + 耗时）。 */
export function describeSwitchResult(result: SwitchResult): string {
  const parts: string[] = [];
  for (let i = 0; i < result.domains.length; i++) {
    const outcome: DomainOutcome = result.domains[i];
    parts.push(outcome.domain + '=' + (outcome.ok ? 'ok' : 'fail')
      + '(' + outcome.items.toString() + ')');
  }
  return 'semester switch finished: target=' + result.targetSemesterId
    + ' result=' + result.kind
    + ' domains=[' + parts.join(' ') + ']'
    + ' elapsedMs=' + result.elapsedMs.toString();
}

/**
 * 切换学期：**同步记选择 + 等待全部域落地**。
 *
 * 返回整轮结果（调用方据此给成功 / 部分失败 / 失败提示，并**留在学期页**）。
 * 这里不 pop、不切页 —— "不自动返回"由调用方保证。
 */
export async function switchSemester(semesterId: string): Promise<SwitchResult> {
  const startedAt: number = Date.now();
  const accepted: boolean = setSelectedSemesterId(semesterId);
  const target: string = semesterId.trim();
  logger.info('semester switch started: target=' + target + ' accepted=' + accepted.toString());

  if (SWITCH_DELAY_FOR_EVIDENCE > 0) {
    logger.warn('switch delay override active: SWITCH_DELAY_FOR_EVIDENCE='
      + SWITCH_DELAY_FOR_EVIDENCE.toString() + ' ms before any domain fetch');
    await delayMillis(SWITCH_DELAY_FOR_EVIDENCE);
  }

  const courseStore: CourseListStore = courseListStore();
  // 让学期页的勾选标记立刻指向新选的那一行（列表内容仍是旧快照，直到新快照落地）。
  courseStore.markSwitchingTo(target);
  const noticeStore: NoticeListStore = noticeListStore();
  const fileStore: FileListStore = fileListStore();

  // 三条 store 的 refresh() 都**返回本轮是否成功**：成败判定只看这一次调用自己的返回值，
  // 不读共享的 errorMessage（并发的另一次成功取数会把它清空 ⇒ 会把失败报成成功）。
  const settled: PromiseSettledResult<boolean>[] = await Promise.allSettled([
    courseStore.refresh(),
    noticeStore.refresh(),
    fileStore.refresh()
  ]);

  const domains: DomainOutcome[] = [
    buildDomainOutcome(SWITCH_DOMAIN_COURSES, reportedOk(settled[0]),
      failureReason(settled[0], courseStore.errorMessage), courseStore.courses.length),
    buildDomainOutcome(SWITCH_DOMAIN_NOTICES, reportedOk(settled[1]),
      failureReason(settled[1], noticeStore.errorMessage), noticeStore.items.length),
    buildDomainOutcome(SWITCH_DOMAIN_FILES, reportedOk(settled[2]),
      failureReason(settled[2], fileStore.errorMessage), fileStore.files.length)
  ];
  const result: SwitchResult = new SwitchResult(classifySwitchResult(domains), target, domains,
    Date.now() - startedAt);
  logger.info(describeSwitchResult(result));
  if (!result.isSuccess()) {
    logger.warn('semester switch incomplete: failedDomains=[' + result.failedDomains().join(',')
      + '] firstReason=' + result.firstReason());
  }
  return result;
}

/** 取证延时（`SWITCH_DELAY_FOR_EVIDENCE` 专用；提交态永不进入）。 */
function delayMillis(millis: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, millis);
  });
}

/** 这一次域取数是否被 store 自己报成成功（promise 被拒 = 失败）。 */
function reportedOk(settled: PromiseSettledResult<boolean>): boolean {
  return settled.status === 'fulfilled' && settled.value;
}

/** 失败原因要点：promise 的 reject 原因优先，其次 store 的 errorMessage。 */
function failureReason(settled: PromiseSettledResult<boolean>, storeError: string): string {
  if (settled.status === 'rejected') {
    return (settled.reason as Error).message;
  }
  return storeError.length > 0 ? storeError : 'refresh reported failure without a reason';
}

/**
 * **纯函数**：一个域的一轮结果 → 结论。
 *
 * 成败**只由这一次调用自己的返回值决定**。为什么不看 store 的 `errorMessage`：
 * 三条 store 的 `refresh()` 都把异常吞进自己的 `errorMessage` 并 resolve（既有降级口径），
 * 而同一个实例上可能并发着另一次取数（页面 mount 的 `loadOnce`）——它成功时会把
 * `errorMessage` 清空，于是编排会把**已经失败**的那一轮读成成功。
 */
export function buildDomainOutcome(domain: string, reportedSuccess: boolean, reason: string,
  items: number): DomainOutcome {
  if (reportedSuccess) {
    return new DomainOutcome(domain, true, '', items);
  }
  return new DomainOutcome(domain, false, summarizeReason(reason), items);
}
