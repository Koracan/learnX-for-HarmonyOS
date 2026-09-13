/*
 * 登记落盘与会话收割单测（1/3/4 三块的注入式部分）。
 *
 * 覆盖：
 *   - CredentialStore：写/读/清、**不完整记录拒绝落盘**、损坏与未知版本一律当作"没有凭据"；
 *   - CookieJar.absorbCookieHeader：浏览器 Cookie 头 → 内存 jar（域/路径/名字）；
 *   - EnrollmentSession：收割成功建会话、空头/403/登录页三种非预期结果**全部降级失败**且不重试；
 *   - ADR-0004：会话 cookie 只进内存 jar，**没有任何一次秘密存储写入**。
 */

import { describe, it, expect } from '@ohos/hypium';
import { CookieJar, CookiePair, parseCookieHeaderPairs } from '../main/ets/core/http/CookieJar';
import { Logger } from '../main/ets/core/log/Logger';
import { FailReason } from '../main/ets/data/auth/AuthTypes';
import { CREDENTIAL_ALIAS, CredentialStore } from '../main/ets/data/auth/CredentialStore';
import { EnrollmentSession, EnrollmentSessionResult } from '../main/ets/data/auth/EnrollmentSession';
import { LEARN_ORIGIN, LEARN_STUDENT_COURSE_LIST_URL } from '../main/ets/data/auth/LoginClient';
import { CredentialRecord, createCredentialRecord } from '../main/ets/domain/auth/CredentialRecord';
import { COURSE_LIST_PAGE_HTML, COURSE_LIST_PAGE_EN_HTML } from './fixtures/AuthFixtures';
import {
  FakeSecretStore, HARVESTED_COOKIE_HEADER, HARVESTED_COOKIE_HEADER_ONE, ScriptedRawPort,
  SYNTHETIC_FINGERPRINT, SYNTHETIC_FINGER_GEN_PRINT, SYNTHETIC_FINGER_GEN_PRINT3, SYNTHETIC_PASSWORD,
  SYNTHETIC_USERNAME, rawResponse
} from './fixtures/EnrollmentFixtures';

/** 会话失效时服务端回的登录页（\`looksLikeIdLoginPage\` 的判据形态）。 */
const LOGIN_PAGE_BODY: string = '<!DOCTYPE html><html><body>'
  + '<form id="theform" action="/do/off/ui/auth/login/check">'
  + '<div id="sm2publicKey">04abcd</div><input id="i_user"></form></body></html>';

function sampleRecord(): CredentialRecord {
  return createCredentialRecord(SYNTHETIC_USERNAME, SYNTHETIC_PASSWORD, SYNTHETIC_FINGERPRINT,
    SYNTHETIC_FINGER_GEN_PRINT, SYNTHETIC_FINGER_GEN_PRINT3);
}

function sessionFor(port: ScriptedRawPort, jar: CookieJar): EnrollmentSession {
  return new EnrollmentSession(jar, port, new Logger('test.enrollment'));
}

export default function enrollmentFlowTest() {
  describe('data.Enrollment', () => {
    it('roundTripsCredentialsThroughTheSecretStore', 0, async () => {
      const secrets: FakeSecretStore = new FakeSecretStore();
      const store: CredentialStore = new CredentialStore(secrets);
      expect(await store.save(sampleRecord())).assertTrue();
      const loaded: CredentialRecord | undefined = await store.load();
      expect(loaded !== undefined).assertTrue();
      expect(loaded?.username).assertEqual(SYNTHETIC_USERNAME);
      expect(loaded?.fingerPrint).assertEqual(SYNTHETIC_FINGERPRINT);
      const persisted: string | undefined = secrets.raw(CREDENTIAL_ALIAS);
      expect(persisted !== undefined).assertTrue();
      // 一个别名、一条记录：便于日后"是否存在凭据"只看一次读
      expect(persisted !== undefined && persisted.indexOf('"schemaVersion":1') >= 0).assertTrue();
    });

    it('refusesToPersistIncompleteCredentials', 0, async () => {
      const secrets: FakeSecretStore = new FakeSecretStore();
      const store: CredentialStore = new CredentialStore(secrets);
      // 不残留半登记状态 —— 半条凭据根本不写
      expect(await store.save(createCredentialRecord('u', 'p', '', '', ''))).assertFalse();
      expect(secrets.writes).assertEqual(0);
      expect(await store.load() === undefined).assertTrue();
    });

    it('treatsCorruptOrUnknownRecordsAsNoCredentials', 0, async () => {
      const secrets: FakeSecretStore = new FakeSecretStore();
      const store: CredentialStore = new CredentialStore(secrets);
      secrets.plant(CREDENTIAL_ALIAS, '{"schemaVersion":99,"username":"u"}');
      expect(await store.load() === undefined).assertTrue();
      secrets.plant(CREDENTIAL_ALIAS, 'not json');
      expect(await store.load() === undefined).assertTrue();
      secrets.plant(CREDENTIAL_ALIAS, '{"schemaVersion":1,"username":"u","password":"p","fingerPrint":""}');
      expect(await store.load() === undefined).assertTrue();
    });

    it('clearsCredentials', 0, async () => {
      const secrets: FakeSecretStore = new FakeSecretStore();
      const store: CredentialStore = new CredentialStore(secrets);
      await store.save(sampleRecord());
      expect(await store.clear()).assertTrue();
      expect(secrets.removes).assertEqual(1);
      expect(await store.load() === undefined).assertTrue();
    });

    it('parsesABrowserCookieHeaderIntoPairs', 0, () => {
      const pairs: CookiePair[] = parseCookieHeaderPairs('JSESSIONID=A B; SERVERID=node1; ; bad; k=a=b');
      expect(pairs.length).assertEqual(3);
      expect(pairs[0].name).assertEqual('JSESSIONID');
      expect(pairs[0].value).assertEqual('A B');
      expect(pairs[1].name).assertEqual('SERVERID');
      expect(pairs[2].name).assertEqual('k');
      expect(pairs[2].value).assertEqual('a=b');
      expect(parseCookieHeaderPairs('').length).assertEqual(0);
    });

    it('absorbsTheHarvestedCookiesForTheLearnDomainOnly', 0, () => {
      const jar: CookieJar = new CookieJar();
      const stored: number = jar.absorbCookieHeader(HARVESTED_COOKIE_HEADER, LEARN_ORIGIN + '/');
      expect(stored).assertEqual(4);
      const learnHeader: string = jar.cookieHeaderFor(LEARN_STUDENT_COURSE_LIST_URL);
      expect(learnHeader.indexOf('JSESSIONID=HARVEST-1') >= 0).assertTrue();
      expect(learnHeader.indexOf('SERVERID=node1') >= 0).assertTrue();
      // id 域不该拿到 learn 的 cookie
      expect(jar.cookieHeaderFor('https://id.tsinghua.edu.cn/do/off/ui/auth/login/check')).assertEqual('');
      // 诊断串不泄漏值
      expect(jar.describe().indexOf('HARVEST-1')).assertEqual(-1);
    });

    it('establishesASessionFromTheBrowserCookies', 0, async () => {
      const port: ScriptedRawPort = new ScriptedRawPort([
        rawResponse(200, COURSE_LIST_PAGE_HTML, 'SERVERID=node2; Path=/')
      ]);
      const jar: CookieJar = new CookieJar();
      const result: EnrollmentSessionResult = await sessionFor(port, jar).adopt(HARVESTED_COOKIE_HEADER);
      expect(result.ok).assertTrue();
      expect(result.reason).assertEqual(FailReason.NONE);
      // 贪婪正则取同一行的最后一个 &_csrf=（逐字保真）
      expect(result.session?.csrfToken).assertEqual('SECOND_TOKEN');
      expect(result.language).assertEqual('zh');
      const session = result.session;
      expect(session !== undefined && session.cookie.indexOf('JSESSIONID=HARVEST-1') >= 0).assertTrue();
      // 收割到的 cookie 真的进了请求头
      expect(port.lastCookieHeader().indexOf('JSESSIONID=HARVEST-1') >= 0).assertTrue();
      // 响应里的 Set-Cookie 会被吸收（会话 cookie 会轮换）
      expect(jar.cookieHeaderFor(LEARN_STUDENT_COURSE_LIST_URL).indexOf('SERVERID=node2') >= 0).assertTrue();
      expect(port.requests.length).assertEqual(1);
    });

    it('reportsTheSiteLanguageWhenItIsEnglish', 0, async () => {
      const port: ScriptedRawPort = new ScriptedRawPort([
        rawResponse(200, COURSE_LIST_PAGE_EN_HTML, '')
      ]);
      const result: EnrollmentSessionResult =
        await sessionFor(port, new CookieJar()).adopt(HARVESTED_COOKIE_HEADER_ONE);
      expect(result.ok).assertTrue();
      expect(result.language).assertEqual('en');
    });

    it('failsWithoutRequestingAnythingWhenNoCookieWasHarvested', 0, async () => {
      const port: ScriptedRawPort = new ScriptedRawPort([rawResponse(200, COURSE_LIST_PAGE_HTML, '')]);
      const result: EnrollmentSessionResult = await sessionFor(port, new CookieJar()).adopt('');
      expect(result.ok).assertFalse();
      expect(result.reason).assertEqual(FailReason.ERROR_SETTING_COOKIES);
      expect(port.requests.length).assertEqual(0);
    });

    it('failsOnAForbiddenCourseListPageWithoutRetrying', 0, async () => {
      const port: ScriptedRawPort = new ScriptedRawPort([rawResponse(403, 'Forbidden', '')]);
      const result: EnrollmentSessionResult =
        await sessionFor(port, new CookieJar()).adopt(HARVESTED_COOKIE_HEADER);
      expect(result.ok).assertFalse();
      expect(result.reason).assertEqual(FailReason.UNEXPECTED_STATUS);
      // 非预期响应一律降级，不做静默重试循环
      expect(port.requests.length).assertEqual(1);
    });

    it('failsWhenTheServerAnswersWithTheLoginPage', 0, async () => {
      const port: ScriptedRawPort = new ScriptedRawPort([rawResponse(200, LOGIN_PAGE_BODY, '')]);
      const result: EnrollmentSessionResult =
        await sessionFor(port, new CookieJar()).adopt(HARVESTED_COOKIE_HEADER);
      expect(result.ok).assertFalse();
      // 会话没被服务端认：可诊断分类（不是笼统的"失败"）
      expect(result.reason).assertEqual(FailReason.NOT_LOGGED_IN);
      expect(result.diagnostic.indexOf('idLoginPage=true') >= 0).assertTrue();
      expect(port.requests.length).assertEqual(1);
    });

    it('keepsTheSessionOutOfAnyPersistentStore', 0, async () => {
      const secrets: FakeSecretStore = new FakeSecretStore();
      const store: CredentialStore = new CredentialStore(secrets);
      const port: ScriptedRawPort = new ScriptedRawPort([rawResponse(200, COURSE_LIST_PAGE_HTML, '')]);
      const session: EnrollmentSession = sessionFor(port, new CookieJar());
      const result: EnrollmentSessionResult = await session.adopt(HARVESTED_COOKIE_HEADER);
      expect(result.ok).assertTrue();
      // 只写凭据、不写会话：这里连凭据都没写，所以秘密存储应当是**零写入**
      expect(secrets.writes).assertEqual(0);
      await store.save(sampleRecord());
      const stored: string = secrets.allValues()[0];
      expect(stored.indexOf('JSESSIONID')).assertEqual(-1);
      expect(stored.indexOf('SECOND_TOKEN')).assertEqual(-1);
      expect(stored.indexOf('csrf') ).assertEqual(-1);
    });
  });
}
