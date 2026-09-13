/*
 * Web 容器会话写入参数（纯函数）单测。
 *
 * 钉住两件事：
 *   - `Cookie` 头（`a=1; b=2`）被拆成逐条 `Set-Cookie` 形态的值，值里的 `=` 不被切坏，
 *     空 name 的段被丢掉；
 *   - 写入参数恒为 incognito + includeHttpOnly（会话不落盘；JSESSIONID 可能是 HttpOnly），
 *     且 URL 是调用方给的 learn 源。
 *
 * 空串 / 只有空白 ⇒ 一个 cookie 都不写（未登录、登出后容器里不能留可用会话）。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  WEB_COOKIE_INCLUDE_HTTP_ONLY, WEB_COOKIE_INCOGNITO, WebCookieWrite, buildWebCookieWrites
} from '../main/ets/core/web/WebSessionCookie';

const LEARN_URL: string = 'https://learn.tsinghua.edu.cn';

export default function webSessionCookieTest() {
  describe('core.WebSessionCookie', () => {
    it('writesNothingWithoutASession', 0, () => {
      expect(buildWebCookieWrites('', LEARN_URL).length).assertEqual(0);
      expect(buildWebCookieWrites('   ', LEARN_URL).length).assertEqual(0);
      expect(buildWebCookieWrites('; ; ', LEARN_URL).length).assertEqual(0);
    });

    it('splitsCookieHeaderIntoOneWritePerCookie', 0, () => {
      const writes: WebCookieWrite[] = buildWebCookieWrites('JSESSIONID=abc123; SERVERID=node1', LEARN_URL);
      expect(writes.length).assertEqual(2);
      expect(writes[0].name).assertEqual('JSESSIONID');
      expect(writes[0].value).assertEqual('JSESSIONID=abc123');
      expect(writes[1].name).assertEqual('SERVERID');
      expect(writes[1].value).assertEqual('SERVERID=node1');
    });

    it('keepsEqualsInsideValueAndTrimsSpaces', 0, () => {
      const writes: WebCookieWrite[] = buildWebCookieWrites('  a=b=c ; d=  ', LEARN_URL);
      expect(writes.length).assertEqual(2);
      expect(writes[0].value).assertEqual('a=b=c');
      expect(writes[1].value).assertEqual('d=');
      expect(writes[1].valueChars).assertEqual(0);
    });

    it('alwaysTargetsLearnInIncognitoWithHttpOnly', 0, () => {
      const writes: WebCookieWrite[] = buildWebCookieWrites('JSESSIONID=abc123', LEARN_URL);
      expect(writes.length).assertEqual(1);
      expect(writes[0].url).assertEqual(LEARN_URL);
      expect(writes[0].incognito).assertTrue();
      expect(writes[0].includeHttpOnly).assertTrue();
      expect(WEB_COOKIE_INCOGNITO).assertTrue();
      expect(WEB_COOKIE_INCLUDE_HTTP_ONLY).assertTrue();
    });

    it('skipsMalformedSegmentsInsteadOfWritingEmptyCookies', 0, () => {
      const writes: WebCookieWrite[] = buildWebCookieWrites('novalue; =empty; ok=1', LEARN_URL);
      expect(writes.length).assertEqual(1);
      expect(writes[0].value).assertEqual('ok=1');
    });

    it('exposesOnlyValueLengthForLogs', 0, () => {
      const writes: WebCookieWrite[] = buildWebCookieWrites('JSESSIONID=abcdef', LEARN_URL);
      expect(writes[0].valueChars).assertEqual(6);
    });
  });
}
