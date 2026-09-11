/*
 * 纯 HTTP 登录（data/auth）：7 步走完「取公钥 → SM2 加密口令 → 换票据 → 漫游 → 抓 CSRF」。
 *
 * 参考实现的对应物是 thu-learn-lib 的 getRoamingTicket()/login()
 * （node_modules/thu-learn-lib/lib/module/index.js:101-183），本文件逐步照搬，差异都在注释里写明：
 *
 *  1. 登录前**显式重置**内存 cookie jar（jar.reset + resetIdDomainSession）：
 *     对应参考实现 src/data/source.ts:11-46 的 clearLoginCookies（平台能力缺口补丁，锁定行为）。
 *  2. GET ID 登录表单 → 取 #sm2publicKey（真实页面是 div 的文本，已用抓下来的页面核实）。
 *  3. POST ID 登录检查：**multipart/form-data**（参考实现用 FormData），字段含恒为空的 i_captcha；
 *     口令字段是 '04' + SM2 密文（SM2 细节见 core/crypto/Sm2Cipher）。
 *  4. 取响应里第一个 <a> 的 href 末段作为票据；取不到 → NO_TICKET_IN_RESPONSE（验证码/改版诊断出口）。
 *  5. GET 漫游；非 2xx → ERROR_ROAMING。
 *  6. GET 学生课程列表页，取 CSRF 与语言（正则逐字照参考实现）。
 *  7. 组装内存会话（cookie 头来自 jar；csrf 令牌来自页面）。
 *
 * 边界面（ticket 06 派单 D）：**凭据由入参或注入的 provider 提供，本文件不读任何凭据存储**。
 * 失败一律返回 LoginResult（不抛异常），且 requiresEnrollment() 为 true —— 见 AuthTypes。
 */

import { Logger } from '../../core/log/Logger';
import { CookieJar } from '../../core/http/CookieJar';
import { buildMultipartBody, MultipartBody } from '../upload/Multipart';
import { newBoundary } from '../upload/UploadForm';
import { encodeUtf8 } from '../../core/codec/TextCodec';
import { HttpMethod, Session, USER_AGENT } from '../remote/Requests';
import { RawFetchPort, RawRequest, RawResponse } from '../remote/Port';
import { Credentials, CredentialProvider, CredentialEncryptor, FailReason, LoginResult } from './AuthTypes';
import {
  extractCsrfToken, extractLanguage, extractSm2PublicKey, extractTicket, looksLikeIdLoginPage
} from './LoginParsers';

export const ID_ORIGIN: string = 'https://id.tsinghua.edu.cn';
export const LEARN_ORIGIN: string = 'https://learn.tsinghua.edu.cn';
/** ID 登录表单地址（照参考实现 urls.js:10）。 */
export const ID_LOGIN_URL: string =
  'https://id.tsinghua.edu.cn/do/off/ui/auth/login/form/bb5df85216504820be7bba2b0ae1535b/0';
/** ID 登录检查地址（照参考实现 urls.js:11）。 */
export const ID_LOGIN_CHECK_URL: string = 'https://id.tsinghua.edu.cn/do/off/ui/auth/login/check';
/** 学生课程列表页（登录后抓 CSRF 的那一页，照 urls.js:21）。 */
export const LEARN_STUDENT_COURSE_LIST_URL: string = 'https://learn.tsinghua.edu.cn/f/wlxt/index/course/student/';

/** 漫游地址（照参考实现 urls.js:12）。 */
export function roamUrl(ticket: string): string {
  return LEARN_ORIGIN + '/b/j_spring_security_thauth_roaming_entry?ticket=' + ticket;
}

export interface LoginClientOptions {
  jar: CookieJar;
  port: RawFetchPort;
  encrypt: CredentialEncryptor;
  logger: Logger;
  /** 可选：参数缺失时回落（参考实现把 store 接在这里；本模块不读盘）。 */
  provider?: CredentialProvider;
}

function headersFor(url: string, jar: CookieJar, contentType?: string): Record<string, string> {
  const headers: Record<string, string> = {};
  headers['User-Agent'] = USER_AGENT;
  headers['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';
  if (contentType !== undefined) {
    headers['Content-Type'] = contentType;
  }
  const cookie: string = jar.cookieHeaderFor(url);
  if (cookie.length > 0) {
    headers['Cookie'] = cookie;
  }
  return headers;
}

function missing(value: string | undefined): boolean {
  return value === undefined || value === null || value.length === 0;
}

/** 7 步纯 HTTP 登录。 */
export class LoginClient {
  private readonly jar: CookieJar;
  private readonly port: RawFetchPort;
  private readonly encrypt: CredentialEncryptor;
  private readonly logger: Logger;
  private readonly provider: CredentialProvider | undefined;
  private lastLanguage: string = 'zh';

  constructor(options: LoginClientOptions) {
    this.jar = options.jar;
    this.port = options.port;
    this.encrypt = options.encrypt;
    this.logger = options.logger;
    this.provider = options.provider;
  }

  getJar(): CookieJar {
    return this.jar;
  }

  /** 用当前 jar 为 learn 域组一次会话（cookie 会随响应变化，随用随组）。 */
  sessionForLearn(csrfToken: string): Session {
    return { cookie: this.jar.cookieHeaderFor(LEARN_ORIGIN), csrfToken: csrfToken };
  }

  /** 登录。失败不抛异常，返回带原因与「需登记」判定的结果。 */
  async login(credentials?: Credentials): Promise<LoginResult> {
    const resolved: Credentials | undefined = await this.resolveCredentials(credentials);
    if (resolved === undefined) {
      return LoginResult.failure(FailReason.NO_CREDENTIAL, 'username/password/fingerPrint missing');
    }

    // 1) 登录前显式重置：不依赖「反正 jar 是空的」（照 source.ts:11-46，锁定行为）
    try {
      this.jar.reset();
      this.jar.resetIdDomainSession(ID_ORIGIN);
    } catch (error) {
      return LoginResult.failure(FailReason.ERROR_SETTING_COOKIES, (error as Error).message);
    }
    this.logger.info('login: jar reset -> ' + this.jar.describe());

    // 2) 取登录表单与公钥
    const formResponse: RawResponse = await this.fetchIdLoginForm();
    this.absorbCookies(formResponse);
    const publicKey: string = extractSm2PublicKey(formResponse.body);
    if (publicKey.length === 0) {
      return LoginResult.failure(FailReason.ERROR_FETCH_FROM_ID,
        'no #sm2publicKey in login form: status=' + formResponse.status.toString()
          + ' bytes=' + formResponse.body.length.toString()
          + ' idLoginPage=' + looksLikeIdLoginPage(formResponse.body).toString());
    }
    this.logger.info('login: id form ok status=' + formResponse.status.toString()
      + ' publicKeyChars=' + publicKey.length.toString()
      + ' jar=' + this.jar.describe());

    // 3) SM2 加密口令（失败不给服务端发半成品）
    const encrypted = this.encrypt(resolved.password, publicKey);
    if (!encrypted.ok || encrypted.cipherText.length === 0) {
      const why: string = encrypted.error === undefined ? 'unknown' : encrypted.error;
      return LoginResult.failure(FailReason.ERROR_FETCH_FROM_ID, 'sm2 encrypt failed: ' + why);
    }

    // 4) POST 登录检查（multipart；i_pass 已经是 '04'+密文）
    const checkResponse: RawResponse = await this.postLoginCheck(resolved, encrypted.cipherText);
    const ticket: string = extractTicket(checkResponse.body);
    if (ticket.length === 0) {
      return LoginResult.failure(FailReason.NO_TICKET_IN_RESPONSE,
        'no ticket anchor: status=' + checkResponse.status.toString()
          + ' bytes=' + checkResponse.body.length.toString()
          + ' idLoginPage=' + looksLikeIdLoginPage(checkResponse.body).toString());
    }
    this.logger.info('login: ticket ok status=' + checkResponse.status.toString()
      + ' ticketChars=' + ticket.length.toString());

    // 5) 漫游到 learn
    const roamResponse: RawResponse = await this.port.sendRaw({
      url: roamUrl(ticket),
      method: HttpMethod.GET,
      headers: headersFor(LEARN_ORIGIN, this.jar)
    });
    this.absorbCookies(roamResponse);
    if (!roamResponse.ok || roamResponse.status < 200 || roamResponse.status >= 300) {
      return LoginResult.failure(FailReason.ERROR_ROAMING,
        'roam status=' + roamResponse.status.toString()
          + (roamResponse.error === undefined ? '' : ' error=' + roamResponse.error));
    }
    this.logger.info('login: roam ok status=' + roamResponse.status.toString()
      + ' jar=' + this.jar.describe());

    // 6) 课程列表页 → CSRF + 语言
    const pageResponse: RawResponse = await this.port.sendRaw({
      url: LEARN_STUDENT_COURSE_LIST_URL,
      method: HttpMethod.GET,
      headers: headersFor(LEARN_STUDENT_COURSE_LIST_URL, this.jar)
    });
    this.absorbCookies(pageResponse);
    const csrfToken: string = extractCsrfToken(pageResponse.body);
    if (csrfToken.length === 0) {
      return LoginResult.failure(FailReason.INVALID_RESPONSE,
        'no csrf token: status=' + pageResponse.status.toString()
          + ' bytes=' + pageResponse.body.length.toString()
          + ' idLoginPage=' + looksLikeIdLoginPage(pageResponse.body).toString());
    }
    const language: string = extractLanguage(pageResponse.body);
    this.lastLanguage = language.length > 0 ? language : 'zh';

    // 7) 会话：cookie 头从 jar 取，令牌来自页面
    const session: Session = this.sessionForLearn(csrfToken);
    this.logger.info('login: success status=' + pageResponse.status.toString()
      + ' csrfChars=' + csrfToken.length.toString()
      + ' cookieChars=' + session.cookie.length.toString()
      + ' language=' + this.lastLanguage
      + ' jar=' + this.jar.describe());
    return LoginResult.success(session, this.lastLanguage);
  }

  private async fetchIdLoginForm(): Promise<RawResponse> {
    return this.port.sendRaw({
      url: ID_LOGIN_URL,
      method: HttpMethod.GET,
      headers: headersFor(ID_LOGIN_URL, this.jar)
    });
  }

  private async postLoginCheck(credentials: Credentials, cipherText: string): Promise<RawResponse> {
    const fields: Record<string, string> = {};
    fields['i_user'] = credentials.username;
    // 参考实现：'04' + sm2.doEncrypt(...)；assembleCipherText 已经把 04 拼好
    fields['i_pass'] = cipherText;
    fields['singleLogin'] = 'on';
    fields['fingerPrint'] = credentials.fingerPrint;
    fields['fingerGenPrint'] = credentials.fingerGenPrint;
    fields['fingerGenPrint3'] = credentials.fingerGenPrint3;
    // 参考实现恒发空串（index.js:126）；若服务端此刻要求验证码，会由「取不到票据」暴露
    fields['i_captcha'] = '';
    const boundary: string = newBoundary();
    const assembled: MultipartBody = buildMultipartBody(boundary, fields, undefined, encodeUtf8);
    const response: RawResponse = await this.port.sendRaw({
      url: ID_LOGIN_CHECK_URL,
      method: HttpMethod.POST,
      headers: headersFor(ID_LOGIN_CHECK_URL, this.jar, assembled.contentType),
      binaryBody: assembled.body
    });
    this.absorbCookies(response);
    return response;
  }

  /** 每次响应都把 Set-Cookie 吸收进 jar（会话 cookie 会在漫游与页面请求上轮换）。 */
  private absorbCookies(response: RawResponse): void {
    if (response.setCookie.length === 0) {
      return;
    }
    const stored: number = this.jar.setFromResponse(response.setCookie, response.requestUrl);
    if (stored > 0) {
      this.logger.info('login: absorbed cookies=' + stored.toString() + ' ' + this.jar.describe());
    }
  }

  private async resolveCredentials(credentials?: Credentials): Promise<Credentials | undefined> {
    if (credentials !== undefined
      && !missing(credentials.username) && !missing(credentials.password) && !missing(credentials.fingerPrint)) {
      return credentials;
    }
    if (this.provider === undefined) {
      return undefined;
    }
    try {
      const fromProvider: Credentials = await this.provider();
      if (missing(fromProvider.username) || missing(fromProvider.password) || missing(fromProvider.fingerPrint)) {
        return undefined;
      }
      return fromProvider;
    } catch (error) {
      this.logger.warn('login: provider failed: ' + (error as Error).message);
      return undefined;
    }
  }
}