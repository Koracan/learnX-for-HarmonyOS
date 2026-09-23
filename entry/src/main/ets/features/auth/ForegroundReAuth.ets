/*
 * 回到前台时的静默重登（features/auth）。
 *
 * 出处：参考实现 `src/App.tsx:774-818` —— AppState 变 active 时，若"未登录"或
 * **闲置超过 10 分钟**（`idleTime > 10 * 60 * 1000`，:796）就 `dispatch(login({reset:true}))`。
 * 本文件只搬**闲置**这一支："未登录"那一支由数据路径惰性兜住（没有内存会话时
 * `SessionRestorer.restore()` 本来就会重登）。
 *
 * 为什么这一支不能省：会话 cookie **只在内存**（ADR-0004），而服务端会自己让它过期。
 * 进程驻留后台时，内存里那份会话会变成"看着有、服务端已经不认"；而 `restore()` 对
 * **已有**会话是短路的（否则数据路径每个请求都会重登一次）⇒ 运行期没有任何时机去换一份新的。
 * 设备实测（2026-09）：驻留后台数小时后回到前台，刷新直接显示
 * `semester resolution failed: no xnxq in current semester response: bytes=69`。
 *
 * 失败不打扰界面：这是一次**提前量**。失败时下一次真实请求仍会走 `SessionGate` 的
 * "重登 + 只重试一次"，由那里决定是否降级到 Enrollment。
 *
 * 边界：本文件**不 import 任何平台 / 装配单例**（重登动作由调用方注入），所以它可以在
 * host 单测里直接跑（见 entry/src/test/ForegroundReAuth.test.ets）。
 */

import { Logger } from '../../core/log/Logger';
import { SessionRestoreResult } from '../../data/auth/SessionRestore';

const logger: Logger = new Logger('features.auth.foreground');

/** 闲置多久后回到前台必须换会话。取值逐字照参考实现 `App.tsx:796`（10 分钟）。 */
export const IDLE_REAUTH_THRESHOLD_MILLIS: number = 10 * 60 * 1000;

/**
 * 纯判据：`backgroundedAtMillis` 进后台、`nowMillis` 回到前台，是否该重新登录。
 *
 * `backgroundedAtMillis <= 0`（从没进过后台 —— 冷启动那次 onForeground）返回 false：
 * 冷启动的重登由 `AuthStore.start()` / 数据路径负责，这里不重复发起。
 */
export function shouldReAuthAfterIdle(backgroundedAtMillis: number, nowMillis: number): boolean {
  if (backgroundedAtMillis <= 0) {
    return false;
  }
  return nowMillis - backgroundedAtMillis >= IDLE_REAUTH_THRESHOLD_MILLIS;
}

/** 一次静默重登（设备侧是 `AuthServices.refreshSession`；测试里给替身）。 */
export type SessionRefreshAction = () => Promise<SessionRestoreResult>;

/**
 * 动作：回到前台，闲置过阈值就换一次会话。**不等待**（`onForeground` 是同步回调）。
 *
 * @returns 是否发起了这次重登（供调用方与测试观察）；发起后的结果只进日志。
 */
export function reAuthAfterIdle(backgroundedAtMillis: number, nowMillis: number,
  refresh: SessionRefreshAction): boolean {
  // 冷启动那次 onForeground 的 backgroundedAt 是 0：此时"闲置时长"没有意义，
  // 落成 0 而不是 now − 0（否则日志会写着闲置 56 年，把"没进过后台"读成"闲置很久"）。
  const idleMs: number = backgroundedAtMillis > 0 ? nowMillis - backgroundedAtMillis : 0;
  if (!shouldReAuthAfterIdle(backgroundedAtMillis, nowMillis)) {
    logger.info('foreground re-auth skipped: backgroundedAt=' + backgroundedAtMillis.toString()
      + ' idleMs=' + idleMs.toString()
      + ' thresholdMs=' + IDLE_REAUTH_THRESHOLD_MILLIS.toString());
    return false;
  }
  logger.info('foreground re-auth: idleMs=' + idleMs.toString()
    + ' >= ' + IDLE_REAUTH_THRESHOLD_MILLIS.toString() + ' -> refreshing the session');
  refresh().then((result: SessionRestoreResult): void => {
    logger.info('foreground re-auth settled: ok=' + result.ok().toString()
      + ' kind=' + result.kind + ' ' + result.diagnostic);
  }).catch((error: Error): void => {
    logger.warn('foreground re-auth threw: ' + error.message);
  });
  return true;
}
