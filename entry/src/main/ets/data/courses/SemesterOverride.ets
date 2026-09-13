/*
 * 当前学期的**脚本可驱动覆盖**（data/courses）。
 *
 * ## 为什么需要它（不是可选的便利功能）
 *
 * 统筹给的事实：本账号 **2026-2027 学年秋季学期没有作业**，真实作业只能在
 * **2025-2026 学年春季学期**取到；而作业与提交的验收都必须拿到真实作业数据。
 * 也就是说，"把当前学期切到 2025-2026-2"是**别人的取证工具**，而且必须**不经界面交互**
 * 就能驱动（见统筹提示）。
 *
 * ## 三条入口（优先级从高到低）
 *
 * | 入口 | 怎么用 | 生效范围 |
 * | --- | --- | --- |
 * | 运行期 want 参数 | `hdc shell aa start -a EntryAbility -b com.koracan.learnOH --ps lohSemester 2025-2026-2` | 本进程 |
 * | 构建期常量 | 改 `SEMESTER_OVERRIDE_FOR_EVIDENCE` 后重建 | 该产物 |
 * | 界面选择 | 课程 tab 头部 → 学期切换 | 本进程（界面在 refresh 时把它作为选择传入） |
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
 * ## 自证生效
 *
 * `describeSemesterOverride()` 会把**常量值 / 运行期值 / 实际生效值 / 来源**打成一行 hilog
 * （AGENTS.md：取证开关必须自证生效，不能"以为它生效了"）。每次课程刷新都会打这一行。
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
