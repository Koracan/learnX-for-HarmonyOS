/*
 * Mock 模式的**进程内开关**（features/mock）。
 *
 * ## 参考实现出处
 *
 * `screens/Login.tsx:43-46`：
 * ```ts
 * if (username === env.DUMMY_USERNAME && password === env.DUMMY_PASSWORD) {
 *   dispatch(setMockStore());   // 整个 state 换成 data/mock.ts，一行请求都不发
 *   return;
 * }
 * ```
 * `.env`（已被逐字核对）里 `DUMMY_USERNAME=guest`、`DUMMY_PASSWORD=guest`。
 *
 * ## 本工程的对应物
 *
 * 没有 redux，也没有"整棵 state"可以替换：开关在这里（进程内一个布尔），
 * **消费点是四个仓储 provider**（notice / course / file / 提交）：前三个据此返回
 * `data/mock/Mock*Repository`，提交那条返回 `data/mock/MockAssignmentSubmitter`
 * （本地样例提交出口，零网络，提交后回列表/详情能看到这条作业真的变成已提交）。
 * 开关与"当前登录的是不是 mock 用户"是同一件事的两种读法，
 * 但**只有这一个来源**，避免出现"AuthStore 说是 mock、provider 却不知道"。
 *
 * ## 为什么不做成持久化的
 *
 * 会话与凭据都不落盘（ADR-0004），mock 模式是"这次登录用样例数据"的一种**运行期**状态：
 * 进程重启后回到登录页，重新用 guest/guest 进入。参考实现的 mock 状态会被 redux-persist
 * 写进 SecureStorage（`reducers/root.ts:46-56` 白名单含 username/password），本工程**有意不照抄**。
 */

import { Logger } from '../../core/log/Logger';
import { describeNetworkAudit } from '../../data/remote/NetworkAudit';

const logger: Logger = new Logger('features.mock');

/** 参考实现 `.env` 里的 `DUMMY_USERNAME`（逐字核对）。 */
export const MOCK_USERNAME: string = 'guest';

/** 参考实现 `.env` 里的 `DUMMY_PASSWORD`（逐字核对）。 */
export const MOCK_PASSWORD: string = 'guest';

/** 进程内开关（默认关；提交态也是关）。 */
let active: boolean = false;

/**
 * 这对账号口令是不是 mock 账号（`Login.tsx:43` 的判据，逐字对应）。
 *
 * 大小写敏感、不做 trim —— 参考实现就是用 `useState` 里已经 trim 过的值做**严格相等**比较
 * （`Login.tsx:82,95` 的 `onChangeText={v => setUsername(v.trim())}`）。
 */
export function isMockCredentials(username: string, password: string): boolean {
  return username === MOCK_USERNAME && password === MOCK_PASSWORD;
}

/** 进入 Mock 模式（登录页判定通过时调用）。 */
export function enterMockMode(): void {
  active = true;
  logger.info('mock mode entered: username=' + MOCK_USERNAME
    + ' source=login-guest-credentials; ' + describeNetworkAudit());
}

/** 离开 Mock 模式（登出时调用）。 */
export function exitMockMode(): void {
  if (!active) {
    return;
  }
  active = false;
  logger.info('mock mode exited; ' + describeNetworkAudit());
}

/** 当前是否处于 Mock 模式（**唯一**的判据来源）。 */
export function isMockMode(): boolean {
  return active;
}

/** 一行自证串（设置页与登出日志共用：mock 状态 + 已发出的请求数）。 */
export function describeMockMode(): string {
  return 'mock mode: active=' + active.toString()
    + ' username=' + MOCK_USERNAME
    + ' ' + describeNetworkAudit();
}
