/*
 * 网络出口审计（data/remote）：**本应用真正发出过多少次 HTTP 请求**的进程内计数。
 *
 * ## 为什么需要它
 *
 * 验收要求"以 guest/guest 登录进入 Mock 模式……**不发起真实网络请求**"。
 * 要证明"没发生"，光看界面不像样的数据是不够的 —— 必须有一个**消费点自证**：计数为 0，
 * 而且这个计数必须打在**唯一的请求出口**上，否则"某个角落偷偷发了请求"就无迹可寻。
 *
 * 本工程的真实 HTTP 出口只有两处（其余一切都经由它们）：
 *   1. `data/remote/HttpClient`（`@ohos.net.http` 的 `request`，覆盖 fetch / 上传 / 原始请求）；
 *   2. `data/remote/HttpDownloadPort`（`requestInStream`，流式下载）。
 * 两处都在**发出去之前**调用 `noteNetworkAttempt()`，所以计数就是"应用发出的请求数"。
 *
 * ## 它不是一个"开关"
 *
 * 计数器**不改变任何行为**，也不参与任何判定：它只把"第几次请求、去哪个地址、什么用途"
 * 写进 hilog，并提供一个可读的计数给界面自证行。提交态保留它（诊断价值 > 一点点日志量）。
 */

import { Logger } from '../../core/log/Logger';

const logger: Logger = new Logger('data.remote.audit');

/** 进程内计数（模块级；测试可用 resetNetworkAudit 复位）。 */
let attempts: number = 0;
let lastUrl: string = '';
let lastKind: string = '';

/**
 * 记一次**即将发出**的网络请求，返回累计次数。
 * @param kind 用途标签（`fetch` / `download` / `upload` / `raw`）
 * @param url 请求地址（日志里逐字保留，便于区分"哪个消费点漏出去了"）
 */
export function noteNetworkAttempt(kind: string, url: string): number {
  attempts++;
  lastUrl = url;
  lastKind = kind;
  logger.info('network request #' + attempts.toString() + ' kind=' + kind + ' url=' + url);
  return attempts;
}

/** 已发出的网络请求次数。 */
export function networkAttemptCount(): number {
  return attempts;
}

/** 一行自证串（界面自证行与 hilog 共用）。 */
export function describeNetworkAudit(): string {
  return 'network audit: attempts=' + attempts.toString()
    + ' lastKind=' + (lastKind.length === 0 ? 'none' : lastKind)
    + ' lastUrl=' + (lastUrl.length === 0 ? 'none' : lastUrl);
}

/** 复位（只给单测用；运行期没有调用者）。 */
export function resetNetworkAudit(): void {
  attempts = 0;
  lastUrl = '';
  lastKind = '';
}
