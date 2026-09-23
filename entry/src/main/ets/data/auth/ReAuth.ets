/*
 * 重登协调（data/auth）：把参考实现的**两条**重登路径合成一个出口。
 *
 * 参考实现有两个触发条件，各有出处——
 *   A. 原生处理器路径：结果字符串**恰好等于** '[]'（src/data/source.ts:104），重登后**只重试一次**；
 *   B. thu-learn-lib 路径：noLogin(res) = URL 含 login_timeout 或 status == 403
 *      （node_modules/thu-learn-lib/lib/module/index.js:21），重登后仍 noLogin → NOT_LOGGED_IN，
 *      状态码非 200 → UNEXPECTED_STATUS（:46-71）。
 *
 * 本文件取**并集**作为触发条件，但两条分支**各自保留原来的失败语义**（不是把两条揉成一条）：
 *
 * | 首次结果 | 重登 | 重试后的结果 | 返回 |
 * | --- | --- | --- | --- |
 * | 非 '[]' 且非 noLogin | 不触发 | —— | ok，原值 |
 * | '[]' | 触发（单飞） | 仍是 '[]' | ok，原值 + sessionLostAfterReAuth=true（照 A：原生路径不重分类） |
 * | noLogin(403/login_timeout) | 触发（单飞） | 仍 noLogin | 失败 NOT_LOGGED_IN |
 * | noLogin | 触发（单飞） | 状态码非 200 | 失败 UNEXPECTED_STATUS |
 * | 任意 | 登录本身失败 | —— | 失败（透传登录原因，requiresEnrollment=true） |
 * | 任务**抛出**"当前学期响应不可用" | 触发（单飞） | 仍抛同样的错 | 失败 NOT_LOGGED_IN |
 *
 * 最后一行是**异常层**的会话失效：三域取数源在"学期解析"这一步失败时是抛错而不是返回结果
 * （学期是前置条件，拿不到就没有可返回的东西），而本类只分类**返回**的 TaskOutcome ⇒ 抛错会
 * 整条绕过"重登 + 只重试一次"。`runTask` 把这种抛错折成 noLogin（借既有判据，不新增分类），
 * 于是既有的重登、只重试一次与降级语义原样生效。
 *
 * 单飞照搬 source.ts:111-121 的 reAuthPromise：并发 N 个请求只触发一次登录。
 * 任何失败都 requiresEnrollment=true —— 「任何非预期响应一律降级 Enrollment」，
 * 这条在代码里是显式的（见 AuthTypes.LoginResult.requiresEnrollment 与 ReAuthRunResult）。
 */

import { Logger } from '../../core/log/Logger';
import { FailReason, LoginResult } from './AuthTypes';
import { isNoLoginResponse, isEmptyListResult, isSessionLostErrorMessage } from './LoginParsers';

/** 被包装任务的返回：状态 + 响应体 + 响应 URL（三域抓取里 value 就是 JSON 字符串）。 */
export interface TaskOutcome {
  status: number;
  body: string;
  /** 响应 URL；平台不暴露重定向后的最终 URL 时给请求 URL（见 LoginParsers 说明）。 */
  responseUrl: string;
}

/** 会话失效的判定结果。 */
export enum SessionLostKind {
  NONE = 'none',
  EMPTY_LIST = 'emptyList',
  NO_LOGIN = 'noLogin'
}

/** 判定一个任务结果是否表示会话失效（并集）。 */
export function sessionLostKind(outcome: TaskOutcome): SessionLostKind {
  if (isEmptyListResult(outcome.body)) {
    return SessionLostKind.EMPTY_LIST;
  }
  if (isNoLoginResponse(outcome.status, outcome.responseUrl, outcome.body)) {
    return SessionLostKind.NO_LOGIN;
  }
  return SessionLostKind.NONE;
}

/** 一次带重登的任务结果。 */
export class ReAuthRunResult {
  readonly ok: boolean;
  readonly reason: FailReason;
  readonly value: string;
  readonly reAuthAttempted: boolean;
  /** 重登后仍然失效（A 分支专用：值仍是 '[]'；调用方据此可升级为 Enrollment）。 */
  readonly sessionLostAfterReAuth: boolean;
  readonly diagnostic: string;

  private constructor(ok: boolean, reason: FailReason, value: string, reAuthAttempted: boolean,
    sessionLostAfterReAuth: boolean, diagnostic: string) {
    this.ok = ok;
    this.reason = reason;
    this.value = value;
    this.reAuthAttempted = reAuthAttempted;
    this.sessionLostAfterReAuth = sessionLostAfterReAuth;
    this.diagnostic = diagnostic;
  }

  static success(value: string, reAuthAttempted: boolean, sessionLostAfterReAuth: boolean,
    diagnostic: string): ReAuthRunResult {
    return new ReAuthRunResult(true, FailReason.NONE, value, reAuthAttempted, sessionLostAfterReAuth, diagnostic);
  }

  static failure(reason: FailReason, reAuthAttempted: boolean, diagnostic: string): ReAuthRunResult {
    return new ReAuthRunResult(false, reason, '', reAuthAttempted, true, diagnostic);
  }

  /** 失败一律降级到 Enrollment（唯一出口）。 */
  requiresEnrollment(): boolean {
    return !this.ok;
  }
}

/** 登录动作（由 LoginClient 提供，测试里给替身）。 */
export type LoginAction = () => Promise<LoginResult>;

/**
 * 单飞重登协调器：并发调用共享同一个登录 Promise（照 source.ts:111-121）。
 * 只重试一次由 SessionGate 保证；本类只保证「不并发重复登录」。
 */
export class ReAuthCoordinator {
  private readonly login: LoginAction;
  private readonly logger: Logger;
  private inFlight: Promise<LoginResult> | undefined = undefined;
  private started: number = 0;

  constructor(login: LoginAction, logger: Logger) {
    this.login = login;
    this.logger = logger;
  }

  /** 实际发起过的登录次数（测试断言单飞用）。 */
  startedCount(): number {
    return this.started;
  }

  async ensureSession(): Promise<LoginResult> {
    if (this.inFlight === undefined) {
      this.started++;
      this.logger.info('reAuth: starting login #' + this.started.toString());
      const pending: Promise<LoginResult> = this.login();
      this.inFlight = pending;
      pending.then((result: LoginResult): void => {
        this.inFlight = undefined;
        if (result.ok) {
          this.logger.info('reAuth: login ok');
        } else {
          this.logger.warn('reAuth: login failed reason=' + result.reason + ' diag=' + result.diagnostic);
        }
      }).catch((error: Error): void => {
        this.inFlight = undefined;
        this.logger.error('reAuth: login threw: ' + error.message);
      });
    } else {
      this.logger.info('reAuth: joining in-flight login');
    }
    return this.inFlight;
  }
}

/** 带重登的任务执行器。 */
export class SessionGate {
  private readonly coordinator: ReAuthCoordinator;
  private readonly logger: Logger;

  constructor(coordinator: ReAuthCoordinator, logger: Logger) {
    this.coordinator = coordinator;
    this.logger = logger;
  }

  /** 跑一次任务；会话失效则（单飞）重登并**只重试一次**。 */
  async run(task: () => Promise<TaskOutcome>): Promise<ReAuthRunResult> {
    const first: TaskOutcome = await this.runTask(task);
    const kind: SessionLostKind = sessionLostKind(first);
    if (kind === SessionLostKind.NONE) {
      return ReAuthRunResult.success(first.body, false, false,
        'status=' + first.status.toString());
    }
    this.logger.warn('session lost kind=' + kind + ' status=' + first.status.toString()
      + ' bytes=' + first.body.length.toString());

    const loginResult: LoginResult = await this.coordinator.ensureSession();
    if (!loginResult.ok) {
      return ReAuthRunResult.failure(loginResult.reason, true,
        'reAuth login failed: ' + loginResult.diagnostic);
    }

    const retry: TaskOutcome = await this.runTask(task);
    const retryKind: SessionLostKind = sessionLostKind(retry);
    if (kind === SessionLostKind.NO_LOGIN) {
      if (retryKind === SessionLostKind.NO_LOGIN) {
        return ReAuthRunResult.failure(FailReason.NOT_LOGGED_IN, true,
          'still noLogin after reAuth status=' + retry.status.toString());
      }
      if (retry.status !== 200) {
        return ReAuthRunResult.failure(FailReason.UNEXPECTED_STATUS, true,
          'unexpected status after reAuth: ' + retry.status.toString());
      }
      return ReAuthRunResult.success(retry.body, true, false, 'status=' + retry.status.toString());
    }
    // A 分支（'[]'）：照原生处理器路径，重登后原样返回结果；仍失效时显式标记
    const stillLost: boolean = retryKind !== SessionLostKind.NONE;
    if (stillLost) {
      this.logger.warn('session still lost after reAuth kind=' + retryKind);
    }
    return ReAuthRunResult.success(retry.body, true, stillLost,
      'status=' + retry.status.toString() + ' stillLost=' + stillLost.toString());
  }

  /**
   * 跑一次任务，并把**抛出来的**会话失效折成 noLogin 结果（`status=403`）。
   *
   * 为什么必须有这一条：见文件头的异常层说明。折成 403 是**借既有判据**
   * （`isNoLoginResponse` 的两条之一），不新增分类 —— 于是"重登后仍抛同样的错"自然落进
   * 既有的 NOT_LOGGED_IN 降级分支，界面显示 `loh_session_expired` 而不是原始错误串。
   *
   * 不是会话原因的抛错**照原样抛出**：由仓储 / 界面显式失败，不在这里被吞成"会话失效"
   * （例如"课程列表形状不符"这类站点改版信号）。
   */
  private async runTask(task: () => Promise<TaskOutcome>): Promise<TaskOutcome> {
    try {
      return await task();
    } catch (error) {
      const message: string = (error as Error).message;
      if (isSessionLostErrorMessage(message)) {
        this.logger.warn('session lost by thrown error (treated as noLogin): ' + message);
        return { status: 403, body: '', responseUrl: '' };
      }
      // arkts-limited-throw：只能抛 Error 类型，所以重新包装（消息逐字保留）。
      throw new Error(message);
    }
  }
}
