/*
 * 认证界面状态（features/auth）：登记生命周期与授权给 HTTP 客户端的会话。
 *
 * 领域 store 用 @ObservedV2 / @Trace，视图直接读。视图只读这里的字段，
 * 编排（读凭据 → 静默重登 / 打开网页登记 → 收割会话 → 落盘 → 回到主界面）封在本类里。
 *
 * 三条硬约束的落点：
 *   - **冷启动重建会话**：`start()` 在冷启动时用持久化凭据走**纯 HTTP** 重建会话
 *     （data/auth/SessionRestore），用户无需任何输入；
 *   - **任何非预期结果**（含信任过期 / 403 / login_timeout / 断网）
 *     走 `applyRestoreResult` 的失败支——**显式**回到 UNENROLLED 并给出可理解的提示，
 *     不停在 LOADING、不静默失败、**不出现空列表**（主壳只在有会话时才显示）；
 *   - **登记后的指纹**：保存的 fingerPrint 就是我们注入的那个（completeEnrollment
 *     里把"注入值 vs DOM 观测值"的一致性写成日志）；任何失败/取消都不写凭据；指纹只脱敏进日志。
 *
 * 会话绝不落盘（ADR-0004）：本文件不 import 任何 preferences / 文件 / asset 的写接口。
 */

import { Logger } from '../../core/log/Logger';
import { updateWebSessionHeader } from '../../core/web/SessionHeaderProvider';
import { EnrollmentSessionResult } from '../../data/auth/EnrollmentSession';
import { SessionRestoreResult } from '../../data/auth/SessionRestore';
import { Credentials, FailReason, LoginResult } from '../../data/auth/AuthTypes';
import { Session } from '../../data/remote/Requests';
import {
  EnrollmentDomValues, EnrollmentFingerPrint, SAVE_FINGER_PATH, credentialRecordFor,
  describeEnrollmentDomValues, resolveEnrollmentFingerPrint
} from '../../domain/auth/EnrollmentScript';
import { CredentialRecord } from '../../domain/auth/CredentialRecord';
import { redactSecret } from '../../domain/auth/DeviceIdentity';
import { fingerprintDigest } from '../../domain/auth/FingerprintDigest';
import { AuthServices, authServices } from './AuthServices';
import {
  MOCK_USERNAME, describeMockMode, enterMockMode as enterMockModeFlag, exitMockMode
} from '../mock/MockMode';

const logger: Logger = new Logger('features.auth.store');

/** 认证阶段。LOADING 只出现在"启动时读凭据 + 静默重登"的一瞬间。 */
export enum AuthPhase {
  LOADING = 'loading',
  UNENROLLED = 'unenrolled',
  ENROLLING = 'enrolling',
  ENROLLED = 'enrolled'
}

/** 用户可见的失败提示（页面据此选 i18n 文案）。 */
export enum AuthFailure {
  NONE = 'none',
  SESSION = 'session',
  PERSIST = 'persist',
  INJECTION = 'injection',
  ABORTED = 'aborted',
  /** 会话/信任已失效：需要重新验证（重新走一次设备登记）。 */
  REAUTH = 'reauth',
  /** 网络不通：提示检查网络并可重试（不做静默重试循环）。 */
  OFFLINE = 'offline'
}

@ObservedV2
export class AuthStore {
  @Trace phase: AuthPhase = AuthPhase.LOADING;
  @Trace failure: AuthFailure = AuthFailure.NONE;
  /** 网页登记页顶部的诊断行（脱敏；设备取证时一眼能看出走到哪一步）。 */
  @Trace statusLine: string = '';
  /** 当前处于 Mock 模式（guest/guest 登录；见 features/mock/MockMode）。 */
  @Trace mockActive: boolean = false;
  /** 已登记的账号名（只用于界面显示，不写日志）。 */
  @Trace accountLabel: string = '';
  /** 冷启动重登的**脱敏**诊断（原因/状态码；界面不显示原文，只进日志与取证）。 */
  @Trace restoreDiagnostic: string = '';
  /** 用户点了"重试"且静默重登正在进行（界面据此禁用按钮，避免并发触发）。 */
  @Trace busy: boolean = false;

  private username: string = '';
  private password: string = '';
  private fingerPrint: string = '';
  private deviceName: string = '';
  private readonly services: AuthServices;

  constructor(services: AuthServices) {
    this.services = services;
  }

  /** 是否显示网页登记容器。 */
  isEnrolling(): boolean {
    return this.phase === AuthPhase.ENROLLING;
  }

  isEnrolled(): boolean {
    return this.phase === AuthPhase.ENROLLED;
  }

  /** 静默重登进行中（含用户手动重试）。 */
  isRestoring(): boolean {
    return this.busy;
  }

  /** 网页容器构造注入脚本要用的值（口令只在内存里存在到登记结束）。 */
  enrollmentPassword(): string {
    return this.password;
  }

  enrollmentUsername(): string {
    return this.username;
  }

  enrollmentFingerPrint(): string {
    return this.fingerPrint;
  }

  enrollmentDeviceName(): string {
    return this.deviceName;
  }

  /** 网页容器把"走到哪一步"报回来（只进界面与日志，不影响流程判定）。 */
  noteStatus(text: string): void {
    this.statusLine = text;
    logger.info('enrollment status: ' + text);
  }

  /**
   * 冷启动入口：读凭据 → **纯 HTTP 静默重建会话** → 主壳；任何失败都显式回登录页。
   *
   * 与登记阶段的差别（有意）：登记只判定"有没有凭据"，这里追加"会话真的建起来了吗"。
   * 于是 ENROLLED 的含义从"已登记"收紧为"已登记**且**会话可用"——因为主壳要发真实请求，
   * 让它带着一个不存在的会话显示数据，就是被禁止的"空列表"。
   */
  async start(): Promise<void> {
    this.phase = AuthPhase.LOADING;
    this.failure = AuthFailure.NONE;
    this.restoreDiagnostic = '';
    logger.info('startup: restoring session from persisted credentials (pure HTTP, no webview)');
    await this.restoreSession('startup');
  }

  /**
   * 用户点"重试"：重走一次静默重登。
   *
   * 刻意不做成自动轮询（Q25：不做静默重试循环）：这里是**一次**用户动作触发
   * **一次**尝试。断网时界面给出提示，恢复网络后点一下即可成功。
   * 失败时 phase 保持在 UNENROLLED（不闪回 LOADING），用户填了一半的输入不会被清掉。
   */
  async retryRestore(): Promise<void> {
    if (this.busy) {
      logger.info('startup: retry ignored (a restore is already in flight)');
      return;
    }
    this.busy = true;
    this.failure = AuthFailure.NONE;
    logger.info('startup: user requested retry of the silent re-auth (single attempt, no loop)');
    try {
      await this.restoreSession('retry');
    } finally {
      this.busy = false;
    }
  }

  /**
   * 运行期会话失效（数据路径在 AuthedTaskRunner 判定 requiresEnrollment 时调用）：
   * 显式回登录页并说明需要重新验证。**不是**主动过期提醒（那被 Q25 明确否掉），
   * 而是在服务端事实上拒绝之后被动降级。
   */
  onSessionLost(diagnostic: string): void {
    this.services.session.forgetSession();
    updateWebSessionHeader('', '');
    this.failure = AuthFailure.REAUTH;
    this.restoreDiagnostic = diagnostic;
    this.phase = AuthPhase.UNENROLLED;
    logger.warn('session lost while running -> login page (re-verification required) diag=' + diagnostic);
  }

  /** 读凭据 + 重建会话的公共路径（start 与用户重试共用）。 */
  private async restoreSession(origin: string): Promise<void> {
    const record: CredentialRecord | undefined = await this.services.credentials.load();
    if (record === undefined) {
      this.services.session.setCredentials(null);
      this.services.session.forgetSession();
      this.failure = AuthFailure.NONE;
      this.phase = AuthPhase.UNENROLLED;
      logger.info('startup(' + origin + '): no persisted credentials -> login page');
      return;
    }
    this.services.session.setCredentials(record);
    // 冷启动 / 重试都从"没有会话"开始：不拿上一次的陈旧 cookie 去试（口径同 source.ts:11-46）
    this.services.session.forgetSession();
    this.accountLabel = record.username;
    const result: SessionRestoreResult = await this.services.restorer.restore();
    this.applyRestoreResult(result, origin);
  }

  /**
   * 恢复结果的唯一出口：成功进主壳，**其余一律显式降级**。
   *
   * 注意这里没有、也不该有"失败就用 Mock / 空集合兜底"的分支：界面只有 ENROLLED 才会
   * 渲染主壳，所以降级后不存在"空列表"这种中间态。
   */
  private applyRestoreResult(result: SessionRestoreResult, origin: string): void {
    this.restoreDiagnostic = result.diagnostic;
    if (result.ok()) {
      this.failure = AuthFailure.NONE;
      this.statusLine = '';
      this.phase = AuthPhase.ENROLLED;
      logger.info('startup(' + origin + '): session rebuilt via pure HTTP, zero webview'
        + ' language=' + result.language
        + ' session=' + this.services.session.getJar().describe()
        + ' diag=' + result.diagnostic);
      return;
    }
    this.failure = result.isOffline() ? AuthFailure.OFFLINE : AuthFailure.REAUTH;
    this.phase = AuthPhase.UNENROLLED;
    logger.warn('startup(' + origin + '): session NOT rebuilt kind=' + result.kind
      + ' reason=' + result.reason
      + ' offline=' + result.isOffline().toString()
      + ' -> login page (re-verification required) diag=' + result.diagnostic);
  }

  /**
   * Mock 模式登录：参考实现 `screens/Login.tsx:43-46` 的那一支。
   *
   * **一行请求都不发、也不打开网页登记**：直接进主壳，数据由 `data/mock/Mock*Repository` 提供
   * （判据在 `features/mock/MockMode`，消费点在四个仓储 provider）。
   * 不写任何凭据（`CredentialStore` 一行都没碰）——会话与凭据都不落盘是本工程既有的口径
   * （ADR-0004），mock 模式因此只活到本进程结束。
   */
  loginAsMockUser(): void {
    this.forgetEnrollmentInputs();
    this.services.session.clear();
    this.services.session.setCredentials(null);
    enterMockModeFlag();
    this.mockActive = true;
    this.accountLabel = MOCK_USERNAME;
    this.failure = AuthFailure.NONE;
    this.statusLine = '';
    this.restoreDiagnostic = '';
    this.phase = AuthPhase.ENROLLED;
    logger.info('mock login accepted: phase=ENROLLED (zero network, zero webview); ' + describeMockMode());
  }

  /**
   * 退出登录：参考实现 `Settings.tsx:37-57` 确认后那三个动作的对应物。
   *
   * | 参考实现 | 这里 |
   * | --- | --- |
   * | `dataSource.logout()`（**服务端**注销会话） | **不移植**：本工程的数据层没有"服务端登出"这个用例。见偏离说明 |
   * | `clearLoginCookies()`（清 WebView / 平台 cookie） | `session.clear()`（内存 cookie jar + Session + 凭据缓存） |
   * | `dispatch(clearStore())`（清 state） | `credentials.clear()`（asset store 里的持久化凭据）+ 把 store 显式降级回 `UNENROLLED` |
   *
   * 要的可观察量是"凭据被清除并回到登录页"，这三步合起来就是它。
   * `credentials.clear()` 先于状态回落执行：清盘失败也照样回登录页，但日志里能看见 `cleared=false`。
   */
  async logout(): Promise<void> {
    logger.info('logout requested: clearing session and persisted credentials');
    let cleared: boolean = false;
    try {
      cleared = await this.services.credentials.clear();
    } catch (error) {
      logger.error('logout: credentials.clear threw: ' + (error as Error).message);
    }
    this.services.session.clear();
    updateWebSessionHeader('', '');
    this.forgetEnrollmentInputs();
    exitMockMode();
    this.mockActive = false;
    this.accountLabel = '';
    this.failure = AuthFailure.NONE;
    this.statusLine = '';
    this.restoreDiagnostic = '';
    this.phase = AuthPhase.UNENROLLED;
    logger.info('logout complete: credentialsCleared=' + cleared.toString()
      + ' phase=' + this.phase + '; ' + describeMockMode());
  }

  /** 点"登录"→ 生成指纹与 deviceName，打开网页登记。 */
  beginEnrollment(username: string, password: string): boolean {
    const fingerprint: string = this.services.newFingerprint();
    if (fingerprint.length === 0) {
      this.failure = AuthFailure.INJECTION;
      this.phase = AuthPhase.UNENROLLED;
      logger.error('beginEnrollment aborted: no fingerprint from platform random');
      return false;
    }
    this.username = username;
    this.password = password;
    this.fingerPrint = fingerprint;
    this.deviceName = this.services.deviceName();
    this.failure = AuthFailure.NONE;
    this.statusLine = '';
    this.phase = AuthPhase.ENROLLING;
    logger.info('enrollment started: usernameChars=' + username.length.toString()
      + ' fingerprint=' + redactSecret(fingerprint)
      + ' deviceName=' + this.deviceName
      + ' saveFingerPath=' + SAVE_FINGER_PATH);
    return true;
  }

  /** 用户中途放弃（关闭网页 / 返回）。回到登录页，不残留半登记状态。 */
  cancelEnrollment(): void {
    logger.info('enrollment cancelled by user: phase=' + this.phase);
    this.failure = AuthFailure.ABORTED;
    this.forgetEnrollmentInputs();
    this.phase = AuthPhase.UNENROLLED;
  }

  /**
   * 登记成功：先建会话、再落盘，最后交给 HTTP 客户端与 Web 容器。
   *
   * 顺序是有意的——**会话建不起来就不写凭据**：否则重启后会以"已登记"启动但没有任何会话，
   * 正是要避免的"半登记状态"。
   */
  async completeEnrollment(dom: EnrollmentDomValues, browserCookieHeader: string): Promise<boolean> {
    logger.info('enrollment roaming reached: ' + describeEnrollmentDomValues(dom));
    // **生效指纹（应用侧指纹的落点）**：权威顺序见 resolveEnrollmentFingerPrint ——
    // saveFinger 的 XHR **实际发出**值 > 登录页 DOM 值 > 我们生成的兜底 UUID。
    // **D1（2026-09-12 设备实测）**：saveFinger 优先是必须的。信任按指纹登记，服务端记下的就是它在
    // saveFinger 里收到的那个值；旧代码落盘的是"表单 DOM 值"，而 saveFinger 被我们自己的 XHR patch
    // 覆盖成了另一个值（32 vs 36），登记值与落盘值不一致 ⇒ 重登必然再要一次短信。
    // 三处同值（表单 / saveFinger / 落盘）由同一次登记的 dom 快照给出，来源打进日志。
    const resolvedFingerPrint: EnrollmentFingerPrint = resolveEnrollmentFingerPrint(this.fingerPrint, dom);
    const effectiveFingerPrint: string = resolvedFingerPrint.value;
    const usingFallback: boolean = resolvedFingerPrint.source === 'generatedFallback';
    logger.info('enrollment fingerprint effective: value=' + redactSecret(effectiveFingerPrint)
      + ' source=' + resolvedFingerPrint.source
      + ' pageDomSource=' + (dom.fingerPrintSource.length > 0 ? dom.fingerPrintSource : 'unknown')
      + ' usingFallback=' + usingFallback.toString()
      + ' generatorValue=' + redactSecret(this.fingerPrint)
      + ' saveFingerPatched=' + dom.saveFingerPatched.toString());

    if (effectiveFingerPrint.length === 0) {
      // 页面没给出值、我们也没有兜底值：无法确定"服务端登记的是哪一个" —— 显式失败，不猜。
      logger.error('enrollment aborted: no fingerprint available (page empty and no fallback)');
      this.failure = AuthFailure.INJECTION;
      this.forgetEnrollmentInputs();
      this.phase = AuthPhase.UNENROLLED;
      return false;
    }

    const adopted: EnrollmentSessionResult = await this.services.enrollment.adopt(browserCookieHeader);
    let session: Session | undefined = adopted.session;
    let language: string = adopted.language;
    let via: string = 'browser-cookie-adopt';
    let diagnostic: string = adopted.diagnostic;

    if (!adopted.ok || session === undefined) {
      // **登记路径对齐参考实现（2026-09-12）**：adopt() 本身就是相对参考实现的偏离——它收割 WebView
      // 的 cookie 再 GET 课程页。参考实现（SSO.tsx + src/data/source.ts:30-46）**根本不采纳** WebView 的
      // cookie：WebView 只用于 (a) 确认凭据可用、(b) 拿走三个指纹，然后用 username/password + 三个指纹
      // 走一遍纯 HTTP 登录（= 本工程已实现的 LoginClient 7 步，对齐 thu-learn-lib）。
      // 这里两条都跑：adopt 的结局**完整记录**（成功率与诊断都要），失败才回落到参考实现那条路。
      // 用户今天在另一台设备上装的旧版 learnOH 首次登录仍可用 ⇒ 这条路今天仍然成立。
      logger.warn('enrollment adopt failed: reason=' + adopted.reason + ' diag=' + adopted.diagnostic
        + ' -> fallback to pure HTTP login (reference path: username/password + three fingerprints)');
      const credentials: Credentials = {
        username: this.username,
        password: this.password,
        fingerPrint: effectiveFingerPrint,
        fingerGenPrint: dom.fingerGenPrint,
        fingerGenPrint3: dom.fingerGenPrint3
      };
      const httpResult: LoginResult = await this.services.loginClient.login(credentials);
      // **这一行回答"用户下一次还要不要花一条短信"**：ticket=ok ⇒ 取票据那一步过了（信任已生效）；
      // secondAuthOrCaptcha=true ⇒ 服务端又要二次验证/验证码（NO_TICKET_IN_RESPONSE），下一次仍要短信。
      logger.info('enrollment http login: ok=' + httpResult.ok.toString()
        + ' ticket=' + (httpResult.ok ? 'ok' : 'none')
        + ' secondAuthOrCaptcha=' + (httpResult.reason === FailReason.NO_TICKET_IN_RESPONSE).toString()
        + ' reason=' + httpResult.reason
        + ' fingerprintSource=' + resolvedFingerPrint.source
        + ' finger3Chars=(' + dom.fingerGenPrint.length.toString() + ','
        + dom.fingerGenPrint3.length.toString() + ')'
        + ' diag=' + httpResult.diagnostic);
      if (httpResult.ok && httpResult.session !== undefined) {
        session = httpResult.session;
        language = httpResult.language;
        via = 'pure-http-login';
        diagnostic = 'adopt failed (' + adopted.reason + '); http login: ' + httpResult.diagnostic;
      } else {
        logger.error('enrollment session failed: reason=' + adopted.reason + ' diag=' + adopted.diagnostic
          + ' httpLoginReason=' + httpResult.reason + ' httpLoginDiag=' + httpResult.diagnostic);
        this.failure = AuthFailure.SESSION;
        this.forgetEnrollmentInputs();
        this.phase = AuthPhase.UNENROLLED;
        return false;
      }
    }
    logger.info('enrollment session established: via=' + via + ' diag=' + diagnostic);

    const record: CredentialRecord = credentialRecordFor(this.username, this.password, effectiveFingerPrint, dom);
    const saved: boolean = await this.services.credentials.save(record);
    // 第三点：**从存储读回**再算摘要（不是拿内存里的对象算）——这样"落盘值"才是真的落盘值。
    const readBack: CredentialRecord | undefined = await this.services.credentials.load();
    const persistedFingerPrint: string = readBack === undefined ? '' : readBack.fingerPrint;
    const formDigest: string = fingerprintDigest(dom.fingerPrint);
    const xhrDigest: string = fingerprintDigest(dom.saveFingerFingerprint);
    const persistedDigest: string = fingerprintDigest(persistedFingerPrint);
    logger.info('enrollment fingerprint digest equation: formFieldDom=' + formDigest
      + ' saveFingerXhr=' + xhrDigest
      + ' persistedReadBack=' + persistedDigest
      + ' formEqualsPersisted=' + (formDigest === persistedDigest).toString()
      + ' xhrEqualsPersisted=' + (xhrDigest === persistedDigest).toString()
      + ' saveFingerObserved=' + (dom.saveFingerFingerprint.length > 0).toString());
    if (!saved) {
      logger.error('enrollment aborted: credentials could not be persisted');
      this.failure = AuthFailure.PERSIST;
      this.forgetEnrollmentInputs();
      this.phase = AuthPhase.UNENROLLED;
      return false;
    }

    this.services.session.adopt(session);
    this.services.session.setCredentials(record);
    updateWebSessionHeader(session.cookie, session.csrfToken);
    this.accountLabel = record.username;
    this.failure = AuthFailure.NONE;
    this.statusLine = '';
    this.forgetEnrollmentInputs();
    this.phase = AuthPhase.ENROLLED;
    logger.info('enrollment complete: language=' + language
      + ' via=' + via
      + ' diag=' + diagnostic
      + ' session=' + this.services.session.getJar().describe());
    return true;
  }

  /** 口令等输入只活到登记结束（成功或失败都一样）。 */
  private forgetEnrollmentInputs(): void {
    this.username = '';
    this.password = '';
    this.fingerPrint = '';
    this.deviceName = '';
  }
}

/** 进程内单例（pages/Index 与登录页共用）。 */
export const authStore: AuthStore = new AuthStore(authServices);
