/*
 * 认证域类型（data/auth）：失败分类、凭据入参、登录结果。
 *
 * 失败分类**照搬 thu-learn-lib 的 FailReason 字符串值**（node_modules/thu-learn-lib/lib/module/types.js:3-14），
 * 这样日志里的原因与参考实现可以逐字比对；新增项会显式标注「新增」。
 *
 * 边界：登录能力**通过入参接收账号/口令/三个指纹**，自己不读凭据库——
 * 凭据加密落盘归 CredentialStore；可选注入 provider 只是为了兼容参考实现的调用形态。
 */

import { Session } from '../remote/Requests';

/** 登录/重登失败原因。 */
export enum FailReason {
  /** 成功（占位，便于结果类型统一走一个字段）。 */
  NONE = 'none',
  NO_CREDENTIAL = 'no credential provided',
  ERROR_SETTING_COOKIES = 'could not set cookies',
  ERROR_FETCH_FROM_ID = 'could not fetch ticket from id.tsinghua.edu.cn',
  /** 新增：登录检查响应里没有票据链接（服务端要求验证码/改版时走这里，必须可诊断）。 */
  NO_TICKET_IN_RESPONSE = 'no ticket anchor in id login check response',
  ERROR_ROAMING = 'could not roam to learn.tsinghua.edu.cn',
  INVALID_RESPONSE = 'invalid response',
  NOT_LOGGED_IN = 'not logged in or login timeout',
  UNEXPECTED_STATUS = 'unexpected status',
  /**
   * 新增：**网络层根本没拿到响应**（平台失败时 status=0）。
   *
   * 为什么单独一类：断网启动要给可理解的提示、网络恢复后重试能成功。
   * 若把它并进 ERROR_FETCH_FROM_ID / NO_TICKET_IN_RESPONSE，日志与界面都会把"没网"
   * 说成"登录页改版/被拒"，用户拿不到可行动的提示。**它不是服务端给的错误码**，
   * 因此与 UNEXPECTED_STATUS（拿到响应但状态码非预期）刻意分开。
   */
  NETWORK_UNREACHABLE = 'network unreachable'
}

/**
 * 网络失败判据：**平台没拿到任何响应**时为 true（status=0，即 HttpClient 的
 * `HttpResponse.failure`）。服务端给了 4xx/5xx 时 status>0，不算网络失败——
 * 那种情况走 UNEXPECTED_STATUS / ERROR_ROAMING 等分类，语义不同。
 */
export function isNetworkFailure(status: number, ok: boolean): boolean {
  return !ok && status === 0;
}

/** 登录所需凭据（由凭据库或调用方提供；本模块不读盘）。 */
export interface Credentials {
  username: string;
  password: string;
  fingerPrint: string;
  fingerGenPrint: string;
  fingerGenPrint3: string;
}

/** 凭据提供者（参考实现里由 store 提供）。 */
export type CredentialProvider = () => Promise<Credentials>;

/** 一次登录的结果。 */
export class LoginResult {
  readonly ok: boolean;
  readonly reason: FailReason;
  readonly session: Session | undefined;
  /** 站点语言（课程列表页的 languagejs 标签；取不到时为 zh）。 */
  readonly language: string;
  /** 诊断串：只放可安全记录的信息（状态码、缺失环节、是否像登录页），不放口令/密文。 */
  readonly diagnostic: string;

  private constructor(ok: boolean, reason: FailReason, session: Session | undefined,
    language: string, diagnostic: string) {
    this.ok = ok;
    this.reason = reason;
    this.session = session;
    this.language = language;
    this.diagnostic = diagnostic;
  }

  static success(session: Session, language: string): LoginResult {
    return new LoginResult(true, FailReason.NONE, session, language, 'ok');
  }

  static failure(reason: FailReason, diagnostic: string): LoginResult {
    return new LoginResult(false, reason, undefined, 'zh', diagnostic);
  }

  /**
   * **任何非预期响应（含服务端拒绝）一律降级到 Enrollment**，
   * 不做静默重试循环，也不做过期主动提醒（Q25）。
   *
   * 这里刻意做成「只有成功才不需要登记」：失败原因只用于诊断与日志，
   * 不用于决定「要不要重试」——因为没有重试。改这条语义等于改 spec，先改文档。
   */
  requiresEnrollment(): boolean {
    return !this.ok;
  }
}

/** 密码加密器签名（见 core/crypto/Sm2Cipher）：登录流把它当依赖注入。 */
export interface EncryptorResult {
  ok: boolean;
  cipherText: string;
  error?: string;
}

export type CredentialEncryptor = (password: string, publicKeyHex: string) => EncryptorResult;
