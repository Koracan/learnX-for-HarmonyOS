/*
 * 生效学期的**唯一优先级实现**（data/courses）：脚本覆盖 / 界面选择 / 站点当前学期。
 *
 * ## 为什么需要它（不是可选的便利功能）
 *
 * 统筹给的事实：本账号 **2026-2027 学年秋季学期没有作业**，真实作业只能在
 * **2025-2026 学年春季学期**取到；而作业与提交的验收都必须拿到真实作业数据。
 * 也就是说，"把当前学期切到 2025-2026-2"是**别人的取证工具**，而且必须**不经界面交互**
 * 就能驱动。
 *
 * ## 三条入口（优先级从高到低）
 *
 * | 入口 | 怎么用 | 生效范围 |
 * | --- | --- | --- |
 * | 运行期 want 参数 | `hdc shell aa start -a EntryAbility -b com.koracan.learnOH --ps lohSemester 2025-2026-2` | 本进程 |
 * | 构建期常量 | 改 `SEMESTER_OVERRIDE_FOR_EVIDENCE` 后重建 | 该产物 |
 * | 界面选择 | 课程 tab 头部 → 学期切换 | 本进程（界面在 refresh 时写入本模块） |
 *
 * **覆盖优先于界面选择**：它只服务取证，被设置时就是权威值；界面仍显示"实际生效值"。
 *
 * ## 为什么运行期参数而不是读写沙箱文件
 *
 * 实测（模拟器 Pura 90 / 127.0.0.1:5555，2026-09-12）：
 * `hdc file send <local> /data/app/el2/100/base/com.koracan.learnOH/haps/entry/files/...`
 * → `[Fail]Error opening file: permission denied`（应用沙箱目录 shell 用户不可写；
 * 反向的 `hdc file recv` 可以，所以诊断文件能被取回）。
 * 而 `aa start --ps <key> <value>` 实测可用（`start ability successfully.`），
 * 且是**一次命令、无需重建**——这才是能真正当"取证工具"的那条路。
 *
 * ## 界面选择也是**进程级**状态
 *
 * 学期选择不是某个页面自己的字段：课程 / 作业 / 公告 / 文件四条取数路径都要读它。
 * 它存在进程内存里（`selectedSemesterId`），由 CourseListStore 在选择发生时写入；
 * 不落盘（会话与凭据都不落盘，学期选择属于同一次运行期的界面状态）。
 *
 * ## 自证生效
 *
 * `describeSemesterOverride()` 会把**常量值 / 运行期值 / 实际生效值 / 来源**打成一行 hilog；
 * `resolveEffectiveSemester()` 的调用点各自再打一行带 semester 与 source 的日志
 * （AGENTS.md：取证开关必须自证生效，不能"以为它生效了"）。
 *
 * ## 提交态的取值
 *
 * `SEMESTER_OVERRIDE_FOR_EVIDENCE` 与运行期值在**提交态均为空**（等价于"跟随站点当前学期"）。
 */

import { isValidSemesterId } from '../../domain/model/Semester';

/** `aa start --ps` 的键名（脚本入口）。 */
export const SEMESTER_WANT_PARAM: string = 'lohSemester';

/** 构建期覆盖开关；提交态为空串。 */
export const SEMESTER_OVERRIDE_FOR_EVIDENCE: string = '';

/** 运行期覆盖（由 EntryAbility 从 want 参数写入；不改就一直是空）。 */
let runtimeOverride: string = '';

/** 界面选择的学期（进程级；由 CourseListStore 在选择发生时写入）。 */
let selectedSemesterId: string = '';

/** 只接受合法学期标识（形状不合法的值**不生效**，避免把打字错误当成"切过去了"）。 */
export function normalizeSemesterOverride(raw: string): string {
  const text: string = typeof raw === 'string' ? raw.trim() : '';
  return isValidSemesterId(text) ? text : '';
}

/**
 * 设置运行期覆盖。返回是否被接受（false = 值不是合法的 `YYYY-YYYY-N`，未生效）。
 * 调用方（EntryAbility）负责把结果打进日志。
 */
export function setRuntimeSemesterOverride(raw: string): boolean {
  const value: string = normalizeSemesterOverride(raw);
  if (value.length === 0) {
    return false;
  }
  runtimeOverride = value;
  return true;
}

/** 原样返回运行期覆盖（可能是非法值，用于日志自证）。 */
export function rawRuntimeSemesterOverride(): string {
  return runtimeOverride;
}

export function clearRuntimeSemesterOverride(): void {
  runtimeOverride = '';
}

/** 实际生效的覆盖值：运行期优先，其次构建期常量；都没有则空串（= 跟随站点）。 */
export function effectiveSemesterOverride(): string {
  const runtime: string = normalizeSemesterOverride(runtimeOverride);
  if (runtime.length > 0) {
    return runtime;
  }
  return normalizeSemesterOverride(SEMESTER_OVERRIDE_FOR_EVIDENCE);
}

/** 生效值来自哪一条入口。 */
export function semesterOverrideSource(): string {
  if (normalizeSemesterOverride(runtimeOverride).length > 0) {
    return 'runtime-want-param';
  }
  if (normalizeSemesterOverride(SEMESTER_OVERRIDE_FOR_EVIDENCE).length > 0) {
    return 'build-constant';
  }
  return 'none';
}

/** 一行自证串（**必须**被写进 hilog）。 */
export function describeSemesterOverride(): string {
  return 'semester override: constant="' + SEMESTER_OVERRIDE_FOR_EVIDENCE
    + '" runtime="' + runtimeOverride
    + '" effective="' + effectiveSemesterOverride()
    + '" source=' + semesterOverrideSource();
}

/* ------------------------------------------------------------------ *
 * 界面选择（进程级）
 * ------------------------------------------------------------------ */

/** 记下界面选择（合法值才生效）；返回是否被接受。 */
export function setSelectedSemesterId(raw: string): boolean {
  const value: string = normalizeSemesterOverride(raw);
  if (value.length === 0) {
    return false;
  }
  selectedSemesterId = value;
  return true;
}

/** 当前界面选择的学期；没有选择时是空串。 */
export function selectedSemesterForFetch(): string {
  return normalizeSemesterOverride(selectedSemesterId);
}

/** 清空界面选择（回到"跟随站点当前学期"）。 */
export function clearSelectedSemesterId(): void {
  selectedSemesterId = '';
}

/* ------------------------------------------------------------------ *
 * 优先级：唯一实现
 * ------------------------------------------------------------------ */

/** 生效学期 + 来源。`semesterId` 为空串 = 三档都没给出可用值（调用方据此显式失败）。 */
export class EffectiveSemester {
  readonly semesterId: string;
  /** `override` / `selection` / `site-current` / `none`。 */
  readonly source: string;

  constructor(semesterId: string, source: string) {
    this.semesterId = semesterId;
    this.source = source;
  }
}

/** `resolveEffectiveSemester` 的可读输入（含测试用的显式参数）。 */
export interface SemesterInputs {
  /** 站点当前学期；解析失败时是空串。 */
  siteCurrentSemesterId: string;
  /** 界面显式传入的选择（旧调用点仍走这条）；空串 = 用进程级的界面选择。 */
  explicitSelection: string;
}

/**
 * 生效学期的**唯一**判定：脚本覆盖 > 界面选择 > 站点当前学期。
 *
 * 四条取数路径（课程 / 作业共用的课程快照、公告、文件）**都调用它**，
 * 不再各自抄一遍 if 链（此前课程与文件各有一份、公告侧还有第三套口径）。
 */
export function resolveEffectiveSemester(inputs: SemesterInputs): EffectiveSemester {
  const override: string = effectiveSemesterOverride();
  if (override.length > 0) {
    return new EffectiveSemester(override, 'override');
  }
  const explicit: string = normalizeSemesterOverride(inputs.explicitSelection);
  if (explicit.length > 0) {
    return new EffectiveSemester(explicit, 'selection');
  }
  const processSelection: string = selectedSemesterForFetch();
  if (processSelection.length > 0) {
    return new EffectiveSemester(processSelection, 'selection');
  }
  const siteCurrent: string = normalizeSemesterOverride(inputs.siteCurrentSemesterId);
  if (siteCurrent.length > 0) {
    return new EffectiveSemester(siteCurrent, 'site-current');
  }
  return new EffectiveSemester('', 'none');
}
