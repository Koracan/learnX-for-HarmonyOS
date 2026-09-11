/*
 * 认证界面状态（features/auth）：登记生命周期与授权给 HTTP 客户端的会话。
 *
 * spec 第 3 节：领域 store 用 @ObservedV2 / @Trace，视图直接读。视图只读这里的字段，
 * 编排（读凭据 → 打开网页登记 → 收割会话 → 落盘 → 回到主界面）封在本类里。
 *
 * 三条硬约束的落点：
 *   - **验收第 2 条**：保存的 fingerPrint 就是我们注入 saveFinger/表单的那一个
 *     （completeEnrollment 里把"注入值 vs DOM 观测值"的一致性写成日志）；
 *   - **验收第 4 条**：任何失败/取消都回到 UNENROLLED，且**不写凭据**（先建会话、后落盘）；
 *   - **验收第 5 条**：所有指纹字段只以脱敏形式进日志。
 *
 * 会话绝不落盘（ADR-0004）：本文件不 import 任何 preferences / 文件 / asset 的写接口。
 */

import { Logger } from '../../core/log/Logger';
import { updateWebSessionHeader } from '../../core/web/SessionHeaderProvider';
import { EnrollmentSessionResult } from '../../data/auth/EnrollmentSession';
import { Session } from '../../data/remote/Requests';
import {
  EnrollmentDomValues, SAVE_FINGER_PATH, credentialRecordFor, describeEnrollmentDomValues
} from '../../domain/auth/EnrollmentScript';
import { CredentialRecord } from '../../domain/auth/CredentialRecord';
import { redactSecret, sameSecret } from '../../domain/auth/DeviceIdentity';
import { fingerprintDigest } from '../../domain/auth/FingerprintDigest';
import { AuthServices, authServices } from './AuthServices';

const logger: Logger = new Logger('features.auth.store');

/** 认证阶段。LOADING 只出现在"启动时读凭据"的一瞬间。 */
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
  ABORTED = 'aborted'
}

@ObservedV2
export class AuthStore {
  @Trace phase: AuthPhase = AuthPhase.LOADING;
  @Trace failure: AuthFailure = AuthFailure.NONE;
  /** 网页登记页顶部的诊断行（脱敏；设备取证时一眼能看出走到哪一步）。 */
  @Trace statusLine: string = '';
  /** 已登记的账号名（只用于界面显示，不写日志）。 */
  @Trace accountLabel: string = '';

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
   * 启动时读凭据：有完整凭据即"已登记"。
   *
   * 注意这里**不**建立 HTTP 会话——冷启动用凭据静默重登是 ticket 08 的范围；
   * 本 ticket 要证明的是"凭据加密落盘，重启后仍处于已登记状态"（验收第 3 条）。
   */
  async loadPersisted(): Promise<void> {
    const record: CredentialRecord | undefined = await this.services.credentials.load();
    if (record === undefined) {
      this.services.session.setCredentials(null);
      this.phase = AuthPhase.UNENROLLED;
      logger.info('startup: not enrolled -> login page');
      return;
    }
    this.services.session.setCredentials(record);
    this.accountLabel = record.username;
    this.phase = AuthPhase.ENROLLED;
    logger.info('startup: enrolled -> main shell (credentials from asset store)');
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

  /** 用户中途放弃（关闭网页 / 返回）。验收第 4 条：回到登录页，不残留半登记状态。 */
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
   * 正是验收第 4 条要避免的"半登记状态"。
   */
  async completeEnrollment(dom: EnrollmentDomValues, browserCookieHeader: string): Promise<boolean> {
    logger.info('enrollment roaming reached: ' + describeEnrollmentDomValues(dom));
    const agrees: boolean = sameSecret(this.fingerPrint, dom.fingerPrint);
    logger.info('enrollment fingerprint agreement: injected=' + redactSecret(this.fingerPrint)
      + ' observedInDom=' + redactSecret(dom.fingerPrint)
      + ' agree=' + agrees.toString()
      + ' saveFingerPatched=' + dom.saveFingerPatched.toString());

    if (dom.fingerPrint.length === 0) {
      // 页面上从头到尾没见过 #fingerPrint：注入没跑起来（页面改版/字段改名），
      // 此时"服务端登记的指纹"无法证明是哪一个 —— 显式失败，不猜。
      logger.error('enrollment aborted: #fingerPrint was never observed in the page');
      this.failure = AuthFailure.INJECTION;
      this.forgetEnrollmentInputs();
      this.phase = AuthPhase.UNENROLLED;
      return false;
    }
    if (!agrees) {
      // 观测到但与我们注入的不同：saveFinger 仍上报我们的值（那是信任登记的落点），
      // 但表单里的值不是我们的 —— 必须留下**可诊断**的记录，而不是静默继续。
      logger.error('enrollment fingerprint mismatch: the page kept its own fingerprint;'
        + ' saveFinger report still uses the injected one');
    }

    const outcome: EnrollmentSessionResult = await this.services.enrollment.adopt(browserCookieHeader);
    const session: Session | undefined = outcome.session;
    if (!outcome.ok || session === undefined) {
      logger.error('enrollment session failed: reason=' + outcome.reason + ' diag=' + outcome.diagnostic);
      this.failure = AuthFailure.SESSION;
      this.forgetEnrollmentInputs();
      this.phase = AuthPhase.UNENROLLED;
      return false;
    }

    const record: CredentialRecord = credentialRecordFor(this.username, this.password, this.fingerPrint, dom);
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
    logger.info('enrollment complete: language=' + outcome.language
      + ' diag=' + outcome.diagnostic
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
