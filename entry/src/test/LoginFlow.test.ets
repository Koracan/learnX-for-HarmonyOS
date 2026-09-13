/*
 * 登录流单测：7 步纯 HTTP 登录，端口与加密器都注入。
 *
 * 覆盖：请求序列与 URL、**桌面 Chrome UA 出现在每个请求**（派单 2(a)）、
 * **登录前显式重置 cookie jar**（派单 2(b)）、multipart 字段（含恒空的 i_captcha）、
 * SM2 密文原样进 i_pass（不再重复拼 04）、会话组装、以及全部失败分类 + 降级 Enrollment 判定。
 *
 * 夹具成色：#sm2publicKey 片段是 [抓取]，其余响应是 [反推]；SM2 密文用 [设备] 真实向量做替身。
 */

import { describe, it, expect } from '@ohos/hypium';
import { Logger } from '../main/ets/core/log/Logger';
import { CookieJar } from '../main/ets/core/http/CookieJar';
import { CredentialEncryptor, Credentials, EncryptorResult, FailReason, LoginResult } from
  '../main/ets/data/auth/AuthTypes';
import {
  ID_LOGIN_CHECK_URL, ID_LOGIN_URL, LEARN_STUDENT_COURSE_LIST_URL, LoginClient, roamUrl
} from '../main/ets/data/auth/LoginClient';
import { RawFetchPort, RawRequest, RawResponse } from '../main/ets/data/remote/Port';
import { HttpMethod, Session, USER_AGENT } from '../main/ets/data/remote/Requests';
import { decodeUtf8 } from './TestHelpers';
import {
  COURSE_LIST_PAGE_HTML, COURSE_LIST_PAGE_EN_HTML, ID_CHECK_CAPTCHA_HTML, ID_CHECK_WITH_TICKET_HTML,
  REAL_ID_LOGIN_FORM_SNIPPET, REAL_SM2_PUBLIC_KEY, SM2_WIRE
} from './fixtures/AuthFixtures';

const ID_DOMAIN: string = 'https://id.tsinghua.edu.cn';
const TICKET: string = 'ST-1234567-abcdef';

const CREDS: Credentials = {
  username: 'student1',
  password: 'secret-pw',
  fingerPrint: 'FP-AAA',
  fingerGenPrint: 'GP-BBB',
  fingerGenPrint3: 'GP3-CCC'
};

function response(status: number, body: string, setCookie: string, url: string): RawResponse {
  const headers: Record<string, string> = {};
  headers['content-type'] = 'text/html';
  return {
    ok: status >= 200 && status < 400,
    status: status,
    body: body,
    setCookie: setCookie,
    headers: headers,
    requestUrl: url
  };
}

/** 脚本化原始端口：按调用顺序返回预置响应，并记录每个请求。 */
class ScriptedRawPort implements RawFetchPort {
  readonly requests: RawRequest[] = [];
  private scripted: RawResponse[] = [];
  private cursor: number = 0;

  push(item: RawResponse): ScriptedRawPort {
    this.scripted.push(item);
    return this;
  }

  async sendRaw(spec: RawRequest): Promise<RawResponse> {
    this.requests.push(spec);
    if (this.scripted.length === 0) {
      return response(500, '', '', spec.url);
    }
    const index: number = this.cursor < this.scripted.length ? this.cursor : this.scripted.length - 1;
    this.cursor++;
    return this.scripted[index];
  }
}

/** 记录加密器调用。 */
class StubEncryptor {
  readonly seen: string[] = [];
  fail: boolean = false;

  encrypt: CredentialEncryptor = (password: string, publicKeyHex: string): EncryptorResult => {
    this.seen.push(password + '|' + publicKeyHex);
    if (this.fail) {
      return { ok: false, cipherText: '', error: 'stub failure' };
    }
    return { ok: true, cipherText: SM2_WIRE };
  };
}

function headerText(request: RawRequest): string {
  const keys: string[] = Object.keys(request.headers);
  let text: string = '';
  for (let i = 0; i < keys.length; i++) {
    text += keys[i] + '=' + request.headers[keys[i]] + '; ';
  }
  return text;
}

/** 从 multipart 体里取某个字段的值（字段名后的空行到下一个 CRLF）。 */
function formValueOf(text: string, name: string): string {
  const marker: string = 'name="' + name + '"';
  const at: number = text.indexOf(marker);
  if (at < 0) {
    return '(missing)';
  }
  const afterName: number = at + marker.length;
  const blank: number = text.indexOf('\r\n\r\n', afterName);
  if (blank < 0) {
    return '(malformed)';
  }
  const start: number = blank + 4;
  const end: number = text.indexOf('\r\n', start);
  return end < 0 ? text.substring(start) : text.substring(start, end);
}

/** 正常路径的四个响应。 */
function happyScript(port: ScriptedRawPort): ScriptedRawPort {
  return port
    .push(response(200, REAL_ID_LOGIN_FORM_SNIPPET, 'JSESSIONID=IDABC; Path=/; HttpOnly', ID_LOGIN_URL))
    .push(response(200, ID_CHECK_WITH_TICKET_HTML, '', ID_LOGIN_CHECK_URL))
    .push(response(200, '<html>roamed</html>', 'JSESSIONID=LEARN999; Path=/', roamUrl(TICKET)))
    .push(response(200, COURSE_LIST_PAGE_HTML, 'SERVERID=s1; Path=/', LEARN_STUDENT_COURSE_LIST_URL));
}

function newClient(port: ScriptedRawPort, jar: CookieJar, encryptor: StubEncryptor): LoginClient {
  return new LoginClient({
    jar: jar,
    port: port,
    encrypt: encryptor.encrypt,
    logger: new Logger('data.auth.test')
  });
}

export default function loginFlowTest() {
  describe('data.auth.LoginClient', () => {
    it('runsTheSevenStepLoginAndBuildsInMemorySession', 0, async () => {
      const port: ScriptedRawPort = happyScript(new ScriptedRawPort());
      const jar: CookieJar = new CookieJar();
      const encryptor: StubEncryptor = new StubEncryptor();
      const result: LoginResult = await newClient(port, jar, encryptor).login(CREDS);
      expect(result.ok).assertTrue();
      expect(result.requiresEnrollment()).assertFalse();
      expect(result.reason).assertEqual(FailReason.NONE);
      const session: Session | undefined = result.session;
      expect(session !== undefined).assertTrue();
      expect(session?.csrfToken).assertEqual('SECOND_TOKEN');
      expect(session?.cookie).assertEqual('JSESSIONID=LEARN999; SERVERID=s1');
      expect(result.language).assertEqual('zh');
      expect(port.requests.length).assertEqual(4);
      expect(port.requests[0].url).assertEqual(ID_LOGIN_URL);
      expect(port.requests[0].method).assertEqual(HttpMethod.GET);
      expect(port.requests[1].url).assertEqual(ID_LOGIN_CHECK_URL);
      expect(port.requests[1].method).assertEqual(HttpMethod.POST);
      expect(port.requests[2].url).assertEqual(roamUrl(TICKET));
      expect(port.requests[3].url).assertEqual(LEARN_STUDENT_COURSE_LIST_URL);
      expect(encryptor.seen.length).assertEqual(1);
      expect(encryptor.seen[0]).assertEqual('secret-pw|' + REAL_SM2_PUBLIC_KEY);
    });

    it('sendsDesktopChromeUserAgentOnEveryRequest', 0, async () => {
      const port: ScriptedRawPort = happyScript(new ScriptedRawPort());
      const jar: CookieJar = new CookieJar();
      await newClient(port, jar, new StubEncryptor()).login(CREDS);
      for (let i = 0; i < port.requests.length; i++) {
        const ua: string = port.requests[i].headers['User-Agent'];
        expect(ua).assertEqual(USER_AGENT);
        expect(ua.includes('Windows NT 10.0')).assertTrue();
        expect(ua.includes('Chrome/120.0.0.0')).assertTrue();
      }
    });

    it('postsMultipartFieldsIncludingEmptyCaptchaAndRawCipherText', 0, async () => {
      const port: ScriptedRawPort = happyScript(new ScriptedRawPort());
      const jar: CookieJar = new CookieJar();
      await newClient(port, jar, new StubEncryptor()).login(CREDS);
      const check: RawRequest = port.requests[1];
      const contentType: string = check.headers['Content-Type'];
      expect(contentType.startsWith('multipart/form-data; boundary=')).assertTrue();
      expect(check.binaryBody !== undefined).assertTrue();
      const text: string = decodeUtf8(check.binaryBody as Uint8Array);
      expect(formValueOf(text, 'i_user')).assertEqual('student1');
      // 密文已经是 '04'+…，不能再拼一个 04（参考实现是 '04' + doEncrypt，doEncrypt 不带 04）
      expect(formValueOf(text, 'i_pass')).assertEqual(SM2_WIRE);
      expect(formValueOf(text, 'i_pass').startsWith('0404')).assertFalse();
      expect(formValueOf(text, 'singleLogin')).assertEqual('on');
      expect(formValueOf(text, 'fingerPrint')).assertEqual('FP-AAA');
      expect(formValueOf(text, 'fingerGenPrint')).assertEqual('GP-BBB');
      expect(formValueOf(text, 'fingerGenPrint3')).assertEqual('GP3-CCC');
      expect(formValueOf(text, 'i_captcha')).assertEqual('');
      expect(text.includes('name="i_captcha"')).assertTrue();
    });

    it('resetsTheCookieJarBeforeLoggingIn', 0, async () => {
      const jar: CookieJar = new CookieJar();
      jar.set('JSESSIONID', 'STALE-ID', 'id.tsinghua.edu.cn', '/');
      jar.set('SERVERID', 'STALE-LEARN', 'learn.tsinghua.edu.cn', '/');
      const port: ScriptedRawPort = happyScript(new ScriptedRawPort());
      const result: LoginResult = await newClient(port, jar, new StubEncryptor()).login(CREDS);
      expect(result.ok).assertTrue();
      // 第一个请求是 ID 登录表单：陈旧 cookie 必须已经不在
      expect(headerText(port.requests[0]).includes('STALE-ID')).assertFalse();
      expect(headerText(port.requests[0]).includes('STALE-LEARN')).assertFalse();
      expect(headerText(port.requests[2]).includes('STALE-LEARN')).assertFalse();
    });

    it('doesNotSendIdDomainCookiesToLearn', 0, async () => {
      const port: ScriptedRawPort = happyScript(new ScriptedRawPort());
      const jar: CookieJar = new CookieJar();
      await newClient(port, jar, new StubEncryptor()).login(CREDS);
      // 漫游请求发出时 learn 域还没有 cookie；漫游响应吸收后，课程列表页请求才带上它
      expect(headerText(port.requests[2]).includes('IDABC')).assertFalse();
      expect(headerText(port.requests[3]).includes('IDABC')).assertFalse();
      expect(headerText(port.requests[3]).includes('JSESSIONID=LEARN999')).assertTrue();
    });

    it('failsWithoutCredentialsAndSendsNothing', 0, async () => {
      const port: ScriptedRawPort = happyScript(new ScriptedRawPort());
      const result: LoginResult = await newClient(port, new CookieJar(), new StubEncryptor()).login();
      expect(result.ok).assertFalse();
      expect(result.reason).assertEqual(FailReason.NO_CREDENTIAL);
      expect(result.requiresEnrollment()).assertTrue();
      expect(port.requests.length).assertEqual(0);
    });

    it('fallsBackToTheInjectedProvider', 0, async () => {
      const port: ScriptedRawPort = happyScript(new ScriptedRawPort());
      const client: LoginClient = new LoginClient({
        jar: new CookieJar(),
        port: port,
        encrypt: new StubEncryptor().encrypt,
        logger: new Logger('data.auth.test'),
        provider: async (): Promise<Credentials> => CREDS
      });
      const result: LoginResult = await client.login();
      expect(result.ok).assertTrue();
      expect(port.requests.length).assertEqual(4);
    });

    it('classifiesMissingPublicKeyAsIdFetchFailure', 0, async () => {
      const port: ScriptedRawPort = new ScriptedRawPort()
        .push(response(200, '<html><body>no key here</body></html>', '', ID_LOGIN_URL));
      const result: LoginResult = await newClient(port, new CookieJar(), new StubEncryptor()).login(CREDS);
      expect(result.ok).assertFalse();
      expect(result.reason).assertEqual(FailReason.ERROR_FETCH_FROM_ID);
      expect(result.requiresEnrollment()).assertTrue();
      expect(result.diagnostic.includes('no #sm2publicKey')).assertTrue();
      expect(port.requests.length).assertEqual(1);
    });

    it('classifiesMissingTicketAsCaptchaOrUnexpectedPage', 0, async () => {
      const port: ScriptedRawPort = new ScriptedRawPort()
        .push(response(200, REAL_ID_LOGIN_FORM_SNIPPET, '', ID_LOGIN_URL))
        .push(response(200, ID_CHECK_CAPTCHA_HTML, '', ID_LOGIN_CHECK_URL));
      const result: LoginResult = await newClient(port, new CookieJar(), new StubEncryptor()).login(CREDS);
      expect(result.ok).assertFalse();
      expect(result.reason).assertEqual(FailReason.NO_TICKET_IN_RESPONSE);
      expect(result.diagnostic.includes('idLoginPage=false')).assertTrue();
      // "又被要求二次验证/验证码"与"页面改版"要能分开读：doubleAuth 计数进诊断串
      expect(result.diagnostic.includes('doubleAuthMentions=')).assertTrue();
      expect(port.requests.length).assertEqual(2);
    });

    it('flagsAnIdLoginPageReturnedInsteadOfATicket', 0, async () => {
      // 「服务端要求浏览器」的降级路径：回到登录页而不是给票据
      const port: ScriptedRawPort = new ScriptedRawPort()
        .push(response(200, REAL_ID_LOGIN_FORM_SNIPPET, '', ID_LOGIN_URL))
        .push(response(200, REAL_ID_LOGIN_FORM_SNIPPET, '', ID_LOGIN_CHECK_URL));
      const result: LoginResult = await newClient(port, new CookieJar(), new StubEncryptor()).login(CREDS);
      expect(result.reason).assertEqual(FailReason.NO_TICKET_IN_RESPONSE);
      expect(result.diagnostic.includes('idLoginPage=true')).assertTrue();
    });

    it('classifiesRoamingAndCsrfFailures', 0, async () => {
      const roamPort: ScriptedRawPort = new ScriptedRawPort()
        .push(response(200, REAL_ID_LOGIN_FORM_SNIPPET, '', ID_LOGIN_URL))
        .push(response(200, ID_CHECK_WITH_TICKET_HTML, '', ID_LOGIN_CHECK_URL))
        .push(response(500, 'boom', '', roamUrl(TICKET)));
      const roamResult: LoginResult = await newClient(roamPort, new CookieJar(), new StubEncryptor()).login(CREDS);
      expect(roamResult.reason).assertEqual(FailReason.ERROR_ROAMING);
      expect(roamResult.requiresEnrollment()).assertTrue();

      const csrfPort: ScriptedRawPort = new ScriptedRawPort()
        .push(response(200, REAL_ID_LOGIN_FORM_SNIPPET, '', ID_LOGIN_URL))
        .push(response(200, ID_CHECK_WITH_TICKET_HTML, '', ID_LOGIN_CHECK_URL))
        .push(response(200, '<html>roamed</html>', '', roamUrl(TICKET)))
        .push(response(200, '<html><body>no token</body></html>', '', LEARN_STUDENT_COURSE_LIST_URL));
      const csrfResult: LoginResult = await newClient(csrfPort, new CookieJar(), new StubEncryptor()).login(CREDS);
      expect(csrfResult.reason).assertEqual(FailReason.INVALID_RESPONSE);
      expect(csrfResult.requiresEnrollment()).assertTrue();
    });

    it('stopsBeforePostingWhenEncryptionFails', 0, async () => {
      const port: ScriptedRawPort = new ScriptedRawPort()
        .push(response(200, REAL_ID_LOGIN_FORM_SNIPPET, '', ID_LOGIN_URL));
      const encryptor: StubEncryptor = new StubEncryptor();
      encryptor.fail = true;
      const result: LoginResult = await newClient(port, new CookieJar(), encryptor).login(CREDS);
      expect(result.reason).assertEqual(FailReason.ERROR_FETCH_FROM_ID);
      expect(result.diagnostic.includes('sm2 encrypt failed: stub failure')).assertTrue();
      expect(port.requests.length).assertEqual(1);
    });

    it('readsLanguageFromTheCourseListPage', 0, async () => {
      const port: ScriptedRawPort = new ScriptedRawPort()
        .push(response(200, REAL_ID_LOGIN_FORM_SNIPPET, '', ID_LOGIN_URL))
        .push(response(200, ID_CHECK_WITH_TICKET_HTML, '', ID_LOGIN_CHECK_URL))
        .push(response(200, '<html>roamed</html>', '', roamUrl(TICKET)))
        .push(response(200, COURSE_LIST_PAGE_EN_HTML, '', LEARN_STUDENT_COURSE_LIST_URL));
      const result: LoginResult = await newClient(port, new CookieJar(), new StubEncryptor()).login(CREDS);
      expect(result.ok).assertTrue();
      expect(result.language).assertEqual('en');
      expect(result.session?.csrfToken).assertEqual('EN_TOKEN');
    });
  });
}