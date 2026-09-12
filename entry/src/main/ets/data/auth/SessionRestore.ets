/*
 * 冷启动静默重建会话 + 运行期会话失效的显式降级（data/auth，ticket 08）。
 *
 * 这一层把 ticket 06 的三个零件接起来，并补上 07 留下的认证门所缺的那一步：
 *   - `LoginClient`  —— 7 步纯 HTTP 登录（**零 WebView**）；
 *   - `ReAuthCoordinator` —— 单飞：并发 N 个调用共享同一个登录 Promise（照 source.ts:111-121）；
 *   - `SessionGate`   —— 任务层：会话失效（'[]' ∪ 403/login_timeout）时重登并**只重试一次**。
 *
 * 对应参考实现：`src/data/source.ts` 的 `withNativeReAuth` / `loginWithFingerPrint`。
 * 本文件的两条硬约束都来自 spec 第 5 节与 ADR-0004：
 *   1. **降级必须显式**：任何非预期结果（含服务端直接拒绝：信任过期 / 403 / login_timeout）
 *      都返回 `requiresEnrollment() === true`，绝不静默失败、绝不把空列表交给界面；
 *   2. **绝不用 Mock / 空列表兜底**：这里没有任何"失败就返回空集合"的分支。
 *
 * 与台账第 2 条的关系（docs/reference-quirks.md，已复审）：`SessionGate` 原样保留原生路径
 * 『结果恰好是 '[]' 时重登』的语义；**新增**的是"重登之后仍然是 '[]'"这一支——06 交付时
 * 用 `ReAuthRunResult.sessionLostAfterReAuth` 标记它并留了"调用方据此升级为 Enrollment"的口子，
 * 本文件就是那个调用方：`AuthedTaskRunner` 把它翻成 requiresEnrollment，**不出现空列表**。
 *
 * 单测（注入式，无平台依赖）：entry/src/test/SessionRestore.test.ets。
 */

import { Logger } from '../../core/log/Logger';
import { CredentialRecord } from '../../domain/auth/CredentialRecord';
import { Session } from '../remote/Requests';
import { Credentials, FailReason, LoginResult } from './AuthTypes';
import { ReAuthCoordinator, ReAuthRunResult, SessionGate, TaskOutcome } from './ReAuth';

/**
 * 凭据库里的记录 → 登录流要的入参。
 *
 * 映射只此一处：07 的 `CredentialRecord`（含 schemaVersion）与 06 的 `Credentials`（登录表单字段）
 * 是同三个指纹 + 账号口令的两个视图，任何一处漏字段都会让"服务端登记的指纹 ≠ 重登出示的指纹"
 * （spec 第 5 节 / 验收第 2 条），所以要能单测（见 SessionRestore.test）。
 */
export function credentialsFor(record: CredentialRecord): Credentials {
  return {
    username: record.username,
    password: record.password,
    fingerPrint: record.fingerPrint,
    fingerGenPrint: record.fingerGenPrint,
    fingerGenPrint3: record.fingerGenPrint3
  };
}

/**
 * 冷启动重登的**整体**超时（毫秒）。
 *
 * 平台自己的 connectTimeout=15s / readTimeout=30s 已经给定上界；这条是"平台行为不符合
 * 预期时 LOADING 也不会无限期挂住"的保险（验收第 2 条：断网启动不卡在加载态）。
 * 取得比 15s 大，避免把"网慢但能通"误判成断网。
 */
export const RESTORE_TIMEOUT_MILLIS: number = 20000;

/** 冷启动会话恢复的结果类别。 */
export enum SessionRestoreKind {
  /** 会话已在内存里重建成功。 */
  RESTORED = 'restored',
  /** 没有可用凭据（首次安装 / 已登出 / 凭据损坏）——不是错误，是"需要登记"。 */
  NO_CREDENTIALS = 'noCredentials',
  /** 网络层不通（status=0，或整体超时）：提示"检查网络后重试"。 */
  OFFLINE = 'offline',
  /** 服务端拒绝或任何非预期响应（信任过期 / 403 / login_timeout / 页面改版 / 验证码）：必须重新验证。 */
  REJECTED = 'rejected'
}

/** 一次冷启动会话恢复的结果（不抛异常，失败也是结果）。 */
export class SessionRestoreResult {
  readonly kind: SessionRestoreKind;
  readonly reason: FailReason;
  readonly session: Session | undefined;
  readonly language: string;
  /** 诊断串：只有状态码/原因/字节数这类可安全记录的信息（绝不含 cookie 值或口令）。 */
  readonly diagnostic: string;

  private constructor(kind: SessionRestoreKind, reason: FailReason, session: Session | undefined,
    language: string, diagnostic: string) {
    this.kind = kind;
    this.reason = reason;
    this.session = session;
    this.language = language;
    this.diagnostic = diagnostic;
  }

  static restored(session: Session, language: string, diagnostic: string): SessionRestoreResult {
    return new SessionRestoreResult(SessionRestoreKind.RESTORED, FailReason.NONE, session, language, diagnostic);
  }

  static noCredentials(diagnostic: string): SessionRestoreResult {
    return new SessionRestoreResult(SessionRestoreKind.NO_CREDENTIALS, FailReason.NO_CREDENTIAL,
      undefined, 'zh', diagnostic);
  }

  static offline(reason: FailReason, diagnostic: string): SessionRestoreResult {
    return new SessionRestoreResult(SessionRestoreKind.OFFLINE, reason, undefined, 'zh', diagnostic);
  }

  static rejected(reason: FailReason, diagnostic: string): SessionRestoreResult {
    return new SessionRestoreResult(SessionRestoreKind.REJECTED, reason, undefined, 'zh', diagnostic);
  }

  /** 由一次登录结果分类（唯一入口：三种失败的分野只写在这一处）。 */
  static forLoginResult(result: LoginResult, diagnostic: string): SessionRestoreResult {
    if (result.ok && result.session !== undefined) {
      return SessionRestoreResult.restored(result.session, result.language, diagnostic);
    }
    if (result.reason === FailReason.NO_CREDENTIAL) {
      return SessionRestoreResult.noCredentials(diagnostic);
    }
    if (result.reason === FailReason.NETWORK_UNREACHABLE) {
      return SessionRestoreResult.offline(result.reason, diagnostic);
    }
    return SessionRestoreResult.rejected(result.reason, diagnostic);
  }

  ok(): boolean {
    return this.kind === SessionRestoreKind.RESTORED;
  }

  /** spec 第 5 节：失败一律降级到 Enrollment（界面侧据此回登录页并说明需要重新验证）。 */
  requiresEnrollment(): boolean {
    return !this.ok();
  }

  /** 是否属于"网络不通"（界面提示与"重试"入口据此区分于"信任过期"）。 */
  isOffline(): boolean {
    return this.kind === SessionRestoreKind.OFFLINE;
  }
}

/** 取当前内存会话（设备侧接到 AuthSession.current；测试里给一个可变持有者）。 */
export type CurrentSession = () => Session | null;

/** 带会话的任务：**每次调用都取当前会话**（重登后 cookie 会轮换，不能用旧的那个）。 */
export type SessionTask = (session: Session) => Promise<TaskOutcome>;

/** 网络层失败（status=0）在任务层的替身结果：让 SessionGate 的并集判定触发重登，而不是当成空响应。 */
function gateOutcomeFor(outcome: TaskOutcome): TaskOutcome {
  if (outcome.status === 0) {
    // 403 是 noLogin 的既有判据之一（index.js:21）。这里只借它表达"这次任务没有会话可谈"，
    // 不改变任务本身的失败分类：真正的失败原因由随后的登录结果给出。
    return { status: 403, body: '', responseUrl: outcome.responseUrl };
  }
  return outcome;
}

/** SessionRestorer 的依赖（对象入参，避免位置参数越加越长）。 */
export interface SessionRestorerOptions {
  coordinator: ReAuthCoordinator;
  /** 当前内存会话：已有时直接复用，**不再登录**（否则数据路径每个任务都会重登一次）。 */
  currentSession: CurrentSession;
  logger: Logger;
  timeoutMillis?: number;
}

/**
 * 冷启动重登入口：把「已有会话直接复用 + 单飞 + 整体超时 + 失败分类」收在一个出口。
 *
 * 单飞用 06 的 `ReAuthCoordinator`（绝不自己再造一个 inFlight）；本类额外做的只有：
 *   - **会话短路**：内存里已有会话就直接返回它——数据路径每个请求都会问一次，
 *     没有这条短路，N 个请求就会并发触发 N 次登录（验收第 4 条要的正是"只登录一次"）；
 *   - 整体超时（见 RESTORE_TIMEOUT_MILLIS）；
 *   - 把 LoginResult 翻成界面可用的三类（无凭据 / 断网 / 被拒）。
 *
 * 注意：超时不会取消已经发出的 HTTP 请求（平台没有取消口）。超时后那次登录若最终成功，
 * 会话会由 login action 写进内存，但本次结果仍是 OFFLINE——界面据此停在登录页，
 * 用户点"重试"时会重新走一次（不做静默循环）。
 */
export class SessionRestorer {
  private readonly coordinator: ReAuthCoordinator;
  private readonly currentSession: CurrentSession;
  private readonly logger: Logger;
  private readonly timeoutMillis: number;
  private inFlight: Promise<SessionRestoreResult> | undefined = undefined;
  private attempts: number = 0;
  private lastLanguage: string = 'zh';

  constructor(options: SessionRestorerOptions) {
    this.coordinator = options.coordinator;
    this.currentSession = options.currentSession;
    this.logger = options.logger;
    this.timeoutMillis = options.timeoutMillis === undefined ? RESTORE_TIMEOUT_MILLIS : options.timeoutMillis;
  }

  /** 实际发起过的恢复次数（单测断言单飞用；并发 N 个 restore() 时它必须是 1）。 */
  attemptCount(): number {
    return this.attempts;
  }

  /**
   * 恢复会话。并发调用共享同一次登录（单飞）；失败不抛异常。
   */
  async restore(): Promise<SessionRestoreResult> {
    const existing: Session | null = this.currentSession();
    if (existing !== null) {
      this.logger.info('restore: session already in memory; no login needed');
      return SessionRestoreResult.restored(existing, this.lastLanguage, 'session already established');
    }
    if (this.inFlight === undefined) {
      this.attempts++;
      this.logger.info('restore: silent re-auth #' + this.attempts.toString()
        + ' starting (pure HTTP, no webview)');
      const pending: Promise<SessionRestoreResult> = this.attempt();
      this.inFlight = pending;
      pending.then((settled: SessionRestoreResult): void => {
        this.inFlight = undefined;
      }).catch((error: Error): void => {
        this.inFlight = undefined;
        this.logger.error('restore: unexpected throw: ' + error.message);
      });
    } else {
      this.logger.info('restore: joining in-flight re-auth');
    }
    return this.inFlight;
  }

  private async attempt(): Promise<SessionRestoreResult> {
    const timedOut: LoginResult = LoginResult.failure(FailReason.NETWORK_UNREACHABLE,
      'silent re-auth timed out after ' + this.timeoutMillis.toString() + 'ms');
    let timer: number = -1;
    const timeout: Promise<LoginResult> = new Promise<LoginResult>(
      (resolve: (value: LoginResult) => void): void => {
        timer = setTimeout((): void => {
          resolve(timedOut);
        }, this.timeoutMillis);
      });
    const contenders: Promise<LoginResult>[] = [this.coordinator.ensureSession(), timeout];
    const raced: LoginResult = await Promise.race(contenders);
    if (timer >= 0) {
      clearTimeout(timer);
    }

    const diagnostic: string = raced === timedOut
      ? raced.diagnostic
      : 'reason=' + raced.reason + ' diag=' + raced.diagnostic;
    const result: SessionRestoreResult = SessionRestoreResult.forLoginResult(raced, diagnostic);
    if (result.ok()) {
      this.lastLanguage = result.language;
      this.logger.info('restore: session rebuilt via pure HTTP (no webview) kind=' + result.kind
        + ' language=' + result.language + ' ' + diagnostic);
    } else {
      this.logger.warn('restore: NOT rebuilt kind=' + result.kind
        + ' requiresEnrollment=' + result.requiresEnrollment().toString()
        + ' offline=' + result.isOffline().toString() + ' ' + diagnostic);
    }
    return result;
  }
}

/** 一次"带会话的任务"的结果。 */
export class AuthedRunResult {
  readonly ok: boolean;
  readonly reason: FailReason;
  readonly value: string;
  readonly reAuthAttempted: boolean;
  /** 验收第 3 条 / spec 第 5 节：true = 调用方必须回登录页并说明需要重新验证。 */
  readonly requiresEnrollment: boolean;
  readonly diagnostic: string;

  private constructor(ok: boolean, reason: FailReason, value: string, reAuthAttempted: boolean,
    requiresEnrollment: boolean, diagnostic: string) {
    this.ok = ok;
    this.reason = reason;
    this.value = value;
    this.reAuthAttempted = reAuthAttempted;
    this.requiresEnrollment = requiresEnrollment;
    this.diagnostic = diagnostic;
  }

  static success(value: string, reAuthAttempted: boolean, diagnostic: string): AuthedRunResult {
    return new AuthedRunResult(true, FailReason.NONE, value, reAuthAttempted, false, diagnostic);
  }

  static degraded(reason: FailReason, reAuthAttempted: boolean, diagnostic: string): AuthedRunResult {
    return new AuthedRunResult(false, reason, '', reAuthAttempted, true, diagnostic);
  }

  /**
   * 由 SessionGate 的结果映射。**这里是"不出现空列表"的落点**：
   * 原生路径在重登后仍然返回 '[]' 时会静默成功（台账第 2 条的已知缺口），
   * 我们把它显式翻成"需要重新验证"，值也不往上传。
   */
  static fromGate(result: ReAuthRunResult): AuthedRunResult {
    // 顺序有意：`ReAuthRunResult.failure` **也会**把 sessionLostAfterReAuth 置 true，
    // 所以必须先看 ok——否则登录失败的原因（断网 / 被拒 / 无凭据）会被一律说成 NOT_LOGGED_IN，
    // 界面那条检查网络的提示就永远走不到（单测抓到过）。
    if (!result.ok) {
      return AuthedRunResult.degraded(result.reason, result.reAuthAttempted, result.diagnostic);
    }
    if (result.sessionLostAfterReAuth) {
      return AuthedRunResult.degraded(FailReason.NOT_LOGGED_IN, result.reAuthAttempted,
        'still an empty list after reAuth: ' + result.diagnostic);
    }
    return AuthedRunResult.success(result.value, result.reAuthAttempted, result.diagnostic);
  }

  isOffline(): boolean {
    return this.reason === FailReason.NETWORK_UNREACHABLE;
  }
}

/**
 * 数据路径的统一入口（ticket 09 的三域仓储用它）：
 *   1. 先确保有会话（冷启动时就是那次纯 HTTP 重登，单飞）；
 *   2. 任务会话失效（'[]' ∪ 403/login_timeout）时由 SessionGate 重登并只重试一次；
 *   3. 任何失败或"重登后仍失效"都返回 requiresEnrollment=true，**不返回空列表**。
 */
export class AuthedTaskRunner {
  private readonly restorer: SessionRestorer;
  private readonly gate: SessionGate;
  private readonly currentSession: CurrentSession;
  private readonly logger: Logger;

  constructor(restorer: SessionRestorer, gate: SessionGate, currentSession: CurrentSession, logger: Logger) {
    this.restorer = restorer;
    this.gate = gate;
    this.currentSession = currentSession;
    this.logger = logger;
  }

  async run(task: SessionTask): Promise<AuthedRunResult> {
    const restored: SessionRestoreResult = await this.restorer.restore();
    if (!restored.ok()) {
      this.logger.warn('authed task: no session -> enrollment required kind=' + restored.kind
        + ' ' + restored.diagnostic);
      return AuthedRunResult.degraded(restored.reason, false, 'no session: ' + restored.diagnostic);
    }

    const gateResult: ReAuthRunResult = await this.gate.run(async (): Promise<TaskOutcome> => {
      const session: Session | null = this.currentSession();
      if (session === null) {
        // 防御：会话在两次调用之间被清掉。用 noLogin 结果让 SessionGate 走一次重登，
        // 而不是拿空 cookie 去请求（那会得到登录页 HTML，被误判成"服务端拒绝"）。
        this.logger.warn('authed task: session disappeared before the request');
        return { status: 403, body: '', responseUrl: '' };
      }
      return gateOutcomeFor(await task(session));
    });

    const result: AuthedRunResult = AuthedRunResult.fromGate(gateResult);
    if (result.requiresEnrollment) {
      this.logger.warn('authed task: downgrading to enrollment reason=' + result.reason
        + ' reAuth=' + result.reAuthAttempted.toString() + ' ' + result.diagnostic);
    }
    return result;
  }
}
