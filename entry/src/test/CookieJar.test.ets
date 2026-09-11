/*
 * cookie jar 单测（ticket 06 验收第 4 条）。
 *
 * 覆盖：Set-Cookie 拆多 cookie（含 Expires 里的逗号）、域/路径匹配、Cookie 头拼接、
 * 同名同域同路径覆盖、过期删除、id 域 JSESSIONID 重置、诊断串不泄漏值。
 *
 * 夹具成色：[反推]（见 fixtures/README.md 与 AuthFixtures.ets 头注释）。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  CookieJar, JarCookie, splitSetCookieHeader, parseSetCookie, hostOf, pathOf, defaultPathFor,
  domainMatches, pathMatches
} from '../main/ets/core/http/CookieJar';
import {
  SET_COOKIE_TWO_COOKIES, SET_COOKIE_WITH_EXPIRES, SET_COOKIE_EMPTY_JSESSIONID
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