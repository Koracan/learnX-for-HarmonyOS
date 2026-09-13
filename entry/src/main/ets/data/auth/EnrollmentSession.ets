/*
 * 登记会话收割（data）：把浏览器里建立的会话交给 HTTP 客户端。
 *
 * 「onLoadIntercept 检测到 roaming URL 即成功 → **提取 cookie 同步给 HTTP jar**
 * → 持久化凭据」。本文件就是中间那一步：
 *   1. 用浏览器给出的 Cookie 头重建内存 jar（ADR-0004：只在内存，绝不落盘）；
 *   2. 用这个会话 GET 一次学生课程列表页，取 **CSRF 令牌**与语言（正则与 LoginParsers 共用）；
 *   3. 交给调用方一个可用的 Session（cookie 随响应轮换，随时用 sessionForLearn 重组）。
 *
 * 为什么不再做一次纯 HTTP 登录：浏览器已经完整走过「ID 登录 → 短信验证 → 漫游」，
 * 再登一次不但多余，还会引入"服务端此刻是否要求二次验证"的不确定性。参考实现当年
 * 确实又登了一次（src/screens/SSO.tsx:60 → loginWithFingerPrint），那是它只能靠表单
 * 回传 FormData 的被动结果；本工程走 spec 明写的"提取 cookie"。
 *
 * 失败处理（Q25）：**任何非预期响应都返回失败，不重试、不轮询**，
 * 由调用方降级回 Enrollment。
 */

import { CookieJar } from '../../core/http/CookieJar';
import { Logger } from '../../core/log/Logger';
import { LEARN_ORIGIN, LEARN_STUDENT_COURSE_LIST_URL } from './LoginClient';
import { extractCsrfToken, extractLanguage, looksLikeIdLoginPage } from './LoginParsers';
import { FailReason } from './AuthTypes';
import { RawFetchPort, RawResponse } from '../remote/Port';
import { HttpMethod, Session, USER_AGENT } from '../remote/Requests';

/** 收割结果（不抛异常）。 */
export class EnrollmentSessionResult {
  readonly ok: boolean;
  readonly reason: FailReason;
  readonly session: Session | undefined;
  readonly language: string;
  /** 诊断串：只放状态码、字节数、cookie 条数这类可安全记录的信息。 */
  readonly diagnostic: string;

  private constructor(ok: boolean, reason: FailReason, session: Session | undefined,
    language: string, diagnostic: string) {
    this.ok = ok;
    this.reason = reason;
    this.session = session;
    this.language = language;
    this.diagnostic = diagnostic;
  }

  static success(session: Session, language: string, diagnostic: string): EnrollmentSessionResult {
    return new EnrollmentSessionResult(true, FailReason.NONE, session, language, diagnostic);
  }

  static failure(reason: FailReason, diagnostic: string): EnrollmentSessionResult {
    return new EnrollmentSessionResult(false, reason, undefined, 'zh', diagnostic);
  }
}

function headersFor(url: string, jar: CookieJar): Record<string, string> {
  const headers: Record<string, string> = {};
  headers['User-Agent'] = USER_AGENT;
  headers['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';
  const cookie: string = jar.cookieHeaderFor(url);
  if (cookie.length > 0) {
    headers['Cookie'] = cookie;
  }
  return headers;
}

export class EnrollmentSession {
  private readonly jar: CookieJar;
  private readonly port: RawFetchPort;
  private readonly logger: Logger;

  constructor(jar: CookieJar, port: RawFetchPort, logger: Logger) {
    this.jar = jar;
    this.port = port;
    this.logger = logger;
  }

  getJar(): CookieJar {
    return this.jar;
  }

  /**
   * 用浏览器收割到的 Cookie 头建立 HTTP 会话。
   *
   * @param browserCookieHeader `WebCookieManager.fetchCookieSync(LEARN_URL)` 的原始返回
   */
  async adopt(browserCookieHeader: string): Promise<EnrollmentSessionResult> {
    // 与 LoginClient 登录前一样：显式重置，不依赖"反正 jar 是空的"（source.ts:11-46）
    this.jar.reset();
    const imported: number = this.jar.absorbCookieHeader(browserCookieHeader, LEARN_ORIGIN);
    this.logger.info('enrollment session: harvested=' + imported.toString()
      + ' headerChars=' + browserCookieHeader.length.toString()
      + ' ' + this.jar.describe());
    if (imported === 0) {
      return EnrollmentSessionResult.failure(FailReason.ERROR_SETTING_COOKIES,
        'browser cookie header was empty (headerChars=0)');
    }

    const response: RawResponse = await this.port.sendRaw({
      url: LEARN_STUDENT_COURSE_LIST_URL,
      method: HttpMethod.GET,
      headers: headersFor(LEARN_STUDENT_COURSE_LIST_URL, this.jar)
    });
    if (response.setCookie.length > 0) {
      const absorbed: number = this.jar.setFromResponse(response.setCookie, response.requestUrl);
      this.logger.info('enrollment session: absorbed=' + absorbed.toString() + ' ' + this.jar.describe());
    }
    if (!response.ok || response.status < 200 || response.status >= 300) {
      return EnrollmentSessionResult.failure(FailReason.UNEXPECTED_STATUS,
        'course list status=' + response.status.toString()
          + (response.error === undefined ? '' : ' error=' + response.error));
    }

    const csrfToken: string = extractCsrfToken(response.body);
    if (csrfToken.length === 0) {
      // 会话没被服务端认（或页面改版）：显式失败，由调用方降级回 Enrollment。
      return EnrollmentSessionResult.failure(FailReason.NOT_LOGGED_IN,
        'no csrf token: status=' + response.status.toString()
          + ' bytes=' + response.body.length.toString()
          + ' idLoginPage=' + looksLikeIdLoginPage(response.body).toString());
    }
    const language: string = extractLanguage(response.body);
    const resolvedLanguage: string = language.length > 0 ? language : 'zh';
    const session: Session = { cookie: this.jar.cookieHeaderFor(LEARN_ORIGIN), csrfToken: csrfToken };
    this.logger.info('enrollment session: ok csrfChars=' + csrfToken.length.toString()
      + ' cookieChars=' + session.cookie.length.toString()
      + ' language=' + resolvedLanguage
      + ' ' + this.jar.describe());
    return EnrollmentSessionResult.success(session, resolvedLanguage,
      'harvested=' + imported.toString() + ' csrfChars=' + csrfToken.length.toString());
  }
}
