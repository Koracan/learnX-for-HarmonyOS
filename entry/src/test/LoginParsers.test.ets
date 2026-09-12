/*
 * 登录页解析单测（ticket 06）：两条「逐字保真」正则 + 失效判据。
 *
 * 夹具成色：[抓取] 的 #sm2publicKey 片段（真实页面）+ [反推] 的检查响应/课程列表页。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  extractSm2PublicKey, extractTicket, extractCsrfToken, extractLanguage,
  isNoLoginResponse, isEmptyListResult, looksLikeIdLoginPage, countOccurrences, CSRF_PATTERN, LANGUAGE_PATTERN
} from '../main/ets/data/auth/LoginParsers';
import {
  REAL_ID_LOGIN_FORM_SNIPPET, REAL_SM2_PUBLIC_KEY, INPUT_STYLE_SM2_PUBLIC_KEY_HTML,
  ID_CHECK_WITH_TICKET_HTML, ID_CHECK_CAPTCHA_HTML, COURSE_LIST_PAGE_HTML, COURSE_LIST_PAGE_EN_HTML,
  LOGIN_TIMEOUT_BODY, EMPTY_LIST_BODY
} from './fixtures/AuthFixtures';

export default function loginParsersTest() {
  describe('data.auth.LoginParsers', () => {
    it('extractsRealSm2PublicKeyFromDivText', 0, () => {
      // [抓取] 真实页面里是 div 的文本（带 04 前缀，130 hex）
      const key: string = extractSm2PublicKey(REAL_ID_LOGIN_FORM_SNIPPET);
      expect(key).assertEqual(REAL_SM2_PUBLIC_KEY);
      expect(key.length).assertEqual(130);
      expect(key.startsWith('04')).assertTrue();
      // 相邻的 sm2publicKeyBackup 不能被误取
      expect(key.includes('deadbeef')).assertFalse();
    });

    it('supportsInputValueVariantAndRejectsMissing', 0, () => {
      expect(extractSm2PublicKey(INPUT_STYLE_SM2_PUBLIC_KEY_HTML)).assertEqual(REAL_SM2_PUBLIC_KEY);
      expect(extractSm2PublicKey('')).assertEqual('');
      expect(extractSm2PublicKey('<html><body>nothing</body></html>')).assertEqual('');
      expect(extractSm2PublicKey('<div id="sm2publicKeyOther">04aa</div>')).assertEqual('');
    });

    it('takesTicketFromFirstAnchorLastEqualsSegment', 0, () => {
      expect(extractTicket(ID_CHECK_WITH_TICKET_HTML)).assertEqual('ST-1234567-abcdef');
      expect(extractTicket(ID_CHECK_CAPTCHA_HTML)).assertEqual('');
      expect(extractTicket('')).assertEqual('');
      expect(extractTicket('<a href="/no/equals/here">x</a>')).assertEqual('');
    });

    it('csrfRegexIsGreedyAndRequiresAmpersandPrefix', 0, () => {
      // 同一行两个 &_csrf=：贪婪 '.*' ⇒ 取后一个
      expect(extractCsrfToken(COURSE_LIST_PAGE_HTML)).assertEqual('SECOND_TOKEN');
      // 只有 _csrf= 没有 & 前缀 ⇒ 不命中
      const onlyBare: string = '<div data-x="_csrf=BARE"></div>';
      expect(extractCsrfToken(onlyBare)).assertEqual('');
      expect(extractCsrfToken(COURSE_LIST_PAGE_EN_HTML)).assertEqual('EN_TOKEN');
      expect(extractCsrfToken('')).assertEqual('');
      expect(CSRF_PATTERN.source).assertEqual('^.*&_csrf=(\\S*)"');
    });

    it('extractsLanguageTagExactly', 0, () => {
      expect(extractLanguage(COURSE_LIST_PAGE_HTML)).assertEqual('zh');
      expect(extractLanguage(COURSE_LIST_PAGE_EN_HTML)).assertEqual('en');
      expect(extractLanguage('<script src="languagejs?lang=zh"></script>')).assertEqual('');
      expect(extractLanguage('')).assertEqual('');
      expect(LANGUAGE_PATTERN.source.includes('languagejs')).assertTrue();
    });

    it('classifiesSessionLossByUnionOfBothPaths', 0, () => {
      expect(isNoLoginResponse(403, 'https://learn/x', '')).assertTrue();
      expect(isNoLoginResponse(200, 'https://learn/f/login_timeout', '')).assertTrue();
      expect(isNoLoginResponse(200, 'https://learn/x', LOGIN_TIMEOUT_BODY)).assertTrue();
      expect(isNoLoginResponse(200, 'https://learn/x', '{"ok":1}')).assertFalse();
      // 原生处理器路径：**恰好等于** '[]'（锁定语义，带空格就不算）
      expect(isEmptyListResult(EMPTY_LIST_BODY)).assertTrue();
      expect(isEmptyListResult('[] ')).assertFalse();
      expect(isEmptyListResult(' [ ]')).assertFalse();
      expect(isEmptyListResult('{"a":1}')).assertFalse();
    });

    it('countsDoubleAuthMentionsForSecondFactorDiagnostics', 0, () => {
      // 站点要二次验证/验证码时给的是 doubleAuth 那套页面（doubleAuth.bundle.js）。
      // 计数让日志能区分"又被要求二次验证"与"页面改版/其他拒绝"（分类仍看有没有票据）。
      expect(countOccurrences('<script src="/b/doubleAuth/x.js"></script>', 'doubleAuth')).assertEqual(1);
      expect(countOccurrences('doubleAuthdoubleAuth', 'doubleAuth')).assertEqual(2);
      expect(countOccurrences(ID_CHECK_CAPTCHA_HTML, 'doubleAuth')).assertEqual(0);
      expect(countOccurrences('', 'doubleAuth')).assertEqual(0);
      expect(countOccurrences('abc', '')).assertEqual(0);
    });

    it('spotsIdLoginPageForDiagnostics', 0, () => {
      expect(looksLikeIdLoginPage(REAL_ID_LOGIN_FORM_SNIPPET)).assertTrue();
      expect(looksLikeIdLoginPage('<a href="/do/off/ui/auth/login/form/xx/0">x</a>')).assertTrue();
      expect(looksLikeIdLoginPage('<html>course list</html>')).assertFalse();
      expect(looksLikeIdLoginPage('')).assertFalse();
    });
  });
}
