/*
 * cookie jar 单测。
 *
 * 覆盖：Set-Cookie 拆多 cookie（含 Expires 里的逗号）、域/路径匹配、Cookie 头拼接、
 * 同名同域同路径覆盖、过期删除、id 域 JSESSIONID 重置、诊断串不泄漏值。
 *
 * 夹具成色：[反推]（见 fixtures/README.md 与 AuthFixtures.ets 头注释）。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  CookieJar, JarCookie, ParsedSetCookieResponse, splitSetCookieHeader, parseSetCookie,
  parseNetscapeCookieLine, looksLikeNetscapeCookieLine, parseSetCookieResponse,
  hostOf, pathOf, defaultPathFor, domainMatches, pathMatches
} from '../main/ets/core/http/CookieJar';
import {
  SET_COOKIE_TWO_COOKIES, SET_COOKIE_WITH_EXPIRES, SET_COOKIE_EMPTY_JSESSIONID,
  NETSCAPE_COOKIE_LINE, NETSCAPE_COOKIE_TWO_LINES, NETSCAPE_COOKIE_VALUE_WITH_EQUALS
} from './fixtures/AuthFixtures';

const ID_URL: string = 'https://id.tsinghua.edu.cn/do/off/ui/auth/login/check';
const LEARN_LIST_URL: string = 'https://learn.tsinghua.edu.cn/b/wlxt/kcgg/wlkc_ggb/student/pageListXsbyWgq';
const LEARN_PAGE_URL: string = 'https://learn.tsinghua.edu.cn/f/wlxt/index/course/student/';
const ID_ORIGIN: string = 'https://id.tsinghua.edu.cn';

export default function cookieJarTest() {
  describe('core.CookieJar', () => {
    it('splitsCombinedSetCookieHeaderWithoutBreakingExpires', 0, () => {
      const two: string[] = splitSetCookieHeader(SET_COOKIE_TWO_COOKIES);
      expect(two.length).assertEqual(2);
      expect(two[0]).assertEqual('JSESSIONID=ABC123; Path=/; HttpOnly');
      expect(two[1]).assertEqual('SERVERID=node1; Path=/');
      const one: string[] = splitSetCookieHeader(SET_COOKIE_WITH_EXPIRES);
      expect(one.length).assertEqual(1);
      expect(splitSetCookieHeader('').length).assertEqual(0);
    });

    it('parsesAttributesIncludingExpiresSecureHttpOnly', 0, () => {
      const cookie: JarCookie | undefined = parseSetCookie(SET_COOKIE_WITH_EXPIRES, ID_URL);
      expect(cookie !== undefined).assertTrue();
      expect(cookie?.name).assertEqual('CASTGC');
      expect(cookie?.value).assertEqual('TGT-1');
      expect(cookie?.domain).assertEqual('id.tsinghua.edu.cn');
      expect(cookie?.path).assertEqual('/');
      expect(cookie?.secure).assertTrue();
      expect(cookie?.httpOnly).assertTrue();
      expect((cookie?.expiresAt ?? 0) > 0).assertTrue();
      expect(parseSetCookie('novalue', ID_URL) === undefined).assertTrue();
    });

    it('defaultsPathToRequestDirectory', 0, () => {
      expect(hostOf(ID_URL)).assertEqual('id.tsinghua.edu.cn');
      expect(pathOf(ID_URL)).assertEqual('/do/off/ui/auth/login/check');
      expect(defaultPathFor('/do/off/ui/auth/login/check')).assertEqual('/do/off/ui/auth/login');
      expect(defaultPathFor('/a')).assertEqual('/');
      expect(hostOf('not a url')).assertEqual('');
      expect(pathOf('not a url')).assertEqual('/');
    });

    it('matchesDomainsAndPathsLikeRfc6265', 0, () => {
      expect(domainMatches('learn.tsinghua.edu.cn', 'learn.tsinghua.edu.cn')).assertTrue();
      expect(domainMatches('.tsinghua.edu.cn', 'learn.tsinghua.edu.cn')).assertTrue();
      expect(domainMatches('.tsinghua.edu.cn', 'id.tsinghua.edu.cn')).assertTrue();
      expect(domainMatches('learn.tsinghua.edu.cn', 'id.tsinghua.edu.cn')).assertFalse();
      expect(domainMatches('tsinghua.edu.cn', 'nottsinghua.edu.cn')).assertFalse();
      expect(pathMatches('/', '/b/wlxt/x')).assertTrue();
      expect(pathMatches('/b/', '/b/wlxt/x')).assertTrue();
      expect(pathMatches('/b', '/b/wlxt/x')).assertTrue();
      expect(pathMatches('/b/', '/f/wlxt/x')).assertFalse();
      expect(pathMatches('/bar', '/barbaz')).assertFalse();
    });

    it('keepsCookiesPerDomainAndJoinsHeader', 0, () => {
      const jar: CookieJar = new CookieJar();
      jar.setFromResponse(SET_COOKIE_TWO_COOKIES, ID_URL);
      jar.set('SERVERID', 'learn1', 'learn.tsinghua.edu.cn', '/');
      expect(jar.size()).assertEqual(3);
      const idHeader: string = jar.cookieHeaderFor(ID_URL);
      expect(idHeader.includes('JSESSIONID=ABC123')).assertTrue();
      expect(idHeader.includes('learn1')).assertFalse();
      expect(idHeader.includes('node1')).assertTrue();
      const learnHeader: string = jar.cookieHeaderFor(LEARN_LIST_URL);
      expect(learnHeader).assertEqual('SERVERID=learn1');
      expect(jar.cookieHeaderFor('https://zhjw.cic.tsinghua.edu.cn/x')).assertEqual('');
    });

    it('replacesSameNameDomainPathAndDropsExpired', 0, () => {
      const jar: CookieJar = new CookieJar();
      jar.setFromResponse('SERVERID=old; Path=/', LEARN_PAGE_URL);
      jar.setFromResponse('SERVERID=new; Path=/', LEARN_PAGE_URL);
      expect(jar.size()).assertEqual(1);
      expect(jar.cookieHeaderFor(LEARN_PAGE_URL)).assertEqual('SERVERID=new');
      jar.setFromResponse('SERVERID=x; Path=/; Max-Age=0', LEARN_PAGE_URL);
      expect(jar.size()).assertEqual(0);
      jar.setFromResponse('SERVERID=y; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT', LEARN_PAGE_URL);
      expect(jar.size()).assertEqual(0);
    });

    it('resetsIdDomainSessionAndOmitsEmptyValueFromHeader', 0, () => {
      const jar: CookieJar = new CookieJar();
      jar.setFromResponse(SET_COOKIE_TWO_COOKIES, ID_URL);
      jar.set('SERVERID', 'learn1', 'learn.tsinghua.edu.cn', '/');
      // 传 URL 与传 host 都要能规范化
      jar.resetIdDomainSession(ID_ORIGIN);
      const idHeader: string = jar.cookieHeaderFor(ID_URL);
      expect(idHeader.includes('JSESSIONID')).assertFalse();
      expect(idHeader.includes('SERVERID')).assertTrue();
      jar.set('JSESSIONID', 'AGAIN', 'id.tsinghua.edu.cn', '/');
      expect(jar.cookieHeaderFor(ID_URL).includes('AGAIN')).assertTrue();
      jar.resetIdDomainSession('id.tsinghua.edu.cn');
      expect(jar.cookieHeaderFor(ID_URL).includes('AGAIN')).assertFalse();
      const learnHeader: string = jar.cookieHeaderFor(LEARN_LIST_URL);
      expect(learnHeader).assertEqual('SERVERID=learn1');
      jar.reset();
      expect(jar.size()).assertEqual(0);
      expect(jar.cookieHeaderFor(ID_URL)).assertEqual('');
      expect(jar.cookieHeaderFor(LEARN_LIST_URL)).assertEqual('');
    });


    /* ------------------------------------------------------------------
     * 平台 `HttpResponse.cookies` 的 Netscape 制表符形态。
     * 夹具是设备上逐字观测到的那一行（见 AuthFixtures 与 experiment-w12/E5）。
     * ------------------------------------------------------------------ */

    it('parsesPlatformNetscapeCookieLineVerbatim', 0, () => {
      // 逐字观测行：`#HttpOnly_` 前缀 ⇒ httpOnly=true 且域要剥掉前缀
      expect(looksLikeNetscapeCookieLine(NETSCAPE_COOKIE_LINE)).assertTrue();
      const cookie: JarCookie | undefined = parseNetscapeCookieLine(NETSCAPE_COOKIE_LINE, ID_URL);
      expect(cookie !== undefined).assertTrue();
      expect(cookie?.name).assertEqual('JSESSIONID');
      expect(cookie?.value).assertEqual('FB9C7214ABA6E5BDE3BCD45DA90494CC.authweb1');
      expect(cookie?.domain).assertEqual('id.tsinghua.edu.cn');
      expect(cookie?.path).assertEqual('/');
      expect(cookie?.httpOnly).assertTrue();
      expect(cookie?.secure).assertFalse();
      // expiry=0 ⇒ 会话 cookie
      expect(cookie?.hasExpires).assertFalse();
      expect(cookie?.expiresAt).assertEqual(0);
    });

    it('absorbsPlatformNetscapeLineIntoCookieHeader', 0, () => {
      // 这一条是本轮的真因验证：修复前 `setFromResponse` 吸收 0 条
      const jar: CookieJar = new CookieJar();
      const absorbed = jar.setFromResponseDetailed(NETSCAPE_COOKIE_LINE, ID_URL);
      expect(absorbed.stored).assertEqual(1);
      expect(absorbed.source).assertEqual('netscape');
      expect(jar.size()).assertEqual(1);
      expect(jar.cookieHeaderFor(ID_URL)).assertEqual('JSESSIONID=FB9C7214ABA6E5BDE3BCD45DA90494CC.authweb1');
      // 自证串只出现名字与长度
      expect(jar.cookieSummaryFor(ID_URL)).assertEqual('sent=1 names=[JSESSIONID(41)]');
    });

    it('parsesNetscapeMultipleLinesAndAttributes', 0, () => {
      const parsed: ParsedSetCookieResponse = parseSetCookieResponse(NETSCAPE_COOKIE_TWO_LINES, ID_URL);
      expect(parsed.source).assertEqual('netscape');
      expect(parsed.cookies.length).assertEqual(2);
      expect(parsed.cookies[0].name).assertEqual('JSESSIONID');
      expect(parsed.cookies[1].name).assertEqual('CASTGC');
      // 前导点域要去掉点
      expect(parsed.cookies[1].domain).assertEqual('tsinghua.edu.cn');
      expect(parsed.cookies[1].secure).assertTrue();
      expect(parsed.cookies[1].hasExpires).assertTrue();
      expect(parsed.cookies[1].expiresAt).assertEqual(1893456000 * 1000);
      // 子域覆盖：域是 .tsinghua.edu.cn ⇒ learn 也能带
      const jar: CookieJar = new CookieJar();
      jar.setFromResponse(NETSCAPE_COOKIE_TWO_LINES, ID_URL);
      expect(jar.cookieHeaderFor('https://learn.tsinghua.edu.cn/f/x').includes('CASTGC')).assertTrue();
      expect(jar.cookieHeaderFor('https://learn.tsinghua.edu.cn/f/x').includes('JSESSIONID')).assertFalse();
    });

    it('parsesNetscapeValueContainingEqualsAndCustomPath', 0, () => {
      const cookie: JarCookie | undefined =
        parseNetscapeCookieLine(NETSCAPE_COOKIE_VALUE_WITH_EQUALS, ID_URL);
      expect(cookie !== undefined).assertTrue();
      expect(cookie?.name).assertEqual('TOKEN');
      expect(cookie?.value).assertEqual('YWJjPT0=');
      expect(cookie?.path).assertEqual('/do/off');
      expect(cookie?.httpOnly).assertFalse();
      // 路径不覆盖时不发
      const jar: CookieJar = new CookieJar();
      jar.setFromResponse(NETSCAPE_COOKIE_VALUE_WITH_EQUALS, ID_URL);
      expect(jar.cookieHeaderFor(ID_URL).includes('TOKEN')).assertTrue();
      expect(jar.cookieHeaderFor('https://id.tsinghua.edu.cn/other').includes('TOKEN')).assertFalse();
    });

    it('keepsStandardSetCookieParsingAlongsideNetscape', 0, () => {
      // 两条入口都要能用：标准形态仍然走 splitSetCookieHeader + parseSetCookie
      const standard: ParsedSetCookieResponse = parseSetCookieResponse(SET_COOKIE_TWO_COOKIES, ID_URL);
      expect(standard.source).assertEqual('standard');
      expect(standard.cookies.length).assertEqual(2);
      expect(standard.cookies[0].name).assertEqual('JSESSIONID');
      // 混发（实测未出现，防御）：两种形态各算各的
      const mixed: ParsedSetCookieResponse =
        parseSetCookieResponse(NETSCAPE_COOKIE_LINE + '\n' + 'SERVERID=node1; Path=/', ID_URL);
      expect(mixed.source).assertEqual('mixed');
      expect(mixed.cookies.length).assertEqual(2);
      // 空串
      expect(parseSetCookieResponse('', ID_URL).source).assertEqual('empty');
    });

    it('presetEmptyJsessionIdDoesNotOverrideAbsorbedValue', 0, () => {
      // resetIdDomainSession 会预置一条空 JSESSIONID；真实值吸收进来必须把它顶掉，
      // 而且此后再 reset 之前，发出的头里必须是真值（不是空值被静默丢弃）。
      const jar: CookieJar = new CookieJar();
      jar.reset();
      jar.resetIdDomainSession(ID_ORIGIN);
      expect(jar.cookieHeaderFor(ID_URL)).assertEqual('');
      expect(jar.cookieSummaryFor(ID_URL)).assertEqual('sent=0 names=[]');
      jar.setFromResponse(NETSCAPE_COOKIE_LINE, ID_URL);
      expect(jar.size()).assertEqual(1);
      expect(jar.cookieHeaderFor(ID_URL).includes('FB9C7214')).assertTrue();
      expect(jar.cookieSummaryFor(ID_URL)).assertEqual('sent=1 names=[JSESSIONID(41)]');
    });

    it('doesNotTreatTabsFreeSetCookieAsNetscape', 0, () => {
      // 反之的误判也要防：标准形态不能被当成 Netscape 行
      expect(looksLikeNetscapeCookieLine('JSESSIONID=ABC; Path=/; HttpOnly')).assertFalse();
      expect(parseNetscapeCookieLine('JSESSIONID=ABC; Path=/; HttpOnly', ID_URL) === undefined).assertTrue();
      expect(looksLikeNetscapeCookieLine('')).assertFalse();
      expect(looksLikeNetscapeCookieLine('# a comment')).assertFalse();
      expect(parseNetscapeCookieLine('# a comment', ID_URL) === undefined).assertTrue();
      // 字段不足 7 个 ⇒ 不是 Netscape
      expect(looksLikeNetscapeCookieLine('a\tb\tc')).assertFalse();
    });

    it('neverLogsCookieValues', 0, () => {
      const jar: CookieJar = new CookieJar();
      jar.setFromResponse(SET_COOKIE_TWO_COOKIES, ID_URL);
      const described: string = jar.describe();
      expect(described.includes('ABC123')).assertFalse();
      expect(described.includes('node1')).assertFalse();
      expect(described.includes('JSESSIONID')).assertTrue();
      expect(described.includes('cookies=2')).assertTrue();
      jar.setFromResponse(SET_COOKIE_EMPTY_JSESSIONID, ID_URL);
      expect(jar.cookieHeaderFor(ID_URL).includes('JSESSIONID=')).assertFalse();
    });
  });
}