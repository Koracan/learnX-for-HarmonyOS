/*
 * 登录页解析（data/auth）——**纯函数，零平台依赖**，可夹具单测。
 *
 * 三条正则与参考实现（thu-learn-lib/lib/module/index.js）**逐字保真**，因为它们决定登录成不成：
 *   1. #sm2publicKey 取**元素文本**并 trim（:118，cheerio XML 模式）。真实登录页里它是
 *      <div style="display:none" id="sm2publicKey">04d0c9…</div>——**不是** input 的 value，
 *      这一点已用抓下来的真实页面核实（见 entry/src/test/fixtures/AuthFixtures.ets）。
 *   2. 票据取**第一个 <a>** 的 href 里最后一个 '=' 之后的部分（:131-133）。
 *   3. CSRF 正则 /^.*&_csrf=(\S*)"/gm：'.*' **贪婪** ⇒ 每行取到的是**最后一个** &_csrf=，
 *      且必须有 '&' 前缀（:171-179）。语言正则要求整串标签精确匹配，含前导斜杠（:180-182）。
 *
 * 与 docs/reference-quirks.md 第 4 条一致：**不解码 HTML 实体**（照参考实现）。
 */

/** 抽取 #sm2publicKey 的文本（真实页面是 div 的文本；兼容 input 的 value 形态）。 */
export function extractSm2PublicKey(html: string): string {
  if (!html) {
    return '';
  }
  const asText: RegExpMatchArray | null =
    html.match(/<[a-zA-Z][^>]*id\s*=\s*["']sm2publicKey["'][^>]*>([\s\S]*?)<\/[a-zA-Z]+>/);
  if (asText !== null) {
    const stripped: string = asText[1].replace(/<[^>]*>/g, '').trim();
    if (stripped.length > 0) {
      return stripped;
    }
  }
  const asValue: RegExpMatchArray | null =
    html.match(/<[a-zA-Z][^>]*id\s*=\s*["']sm2publicKey["'][^>]*value\s*=\s*["']([^"']*)["']/);
  if (asValue !== null) {
    return asValue[1].trim();
  }
  return '';
}

/**
 * 登录检查响应 → 漫游票据。
 * 照参考实现：取**第一个 <a>** 的 href，再取最后一个 '=' 之后的部分。
 * 取不到（例如服务端要求验证码时页面里没有那个链接）返回空串——失败必须由「空票据」暴露。
 */
export function extractTicket(responseHtml: string): string {
  if (!responseHtml) {
    return '';
  }
  const anchor: RegExpMatchArray | null = responseHtml.match(/<a[^>]*href\s*=\s*["']([^"']*)["']/i);
  if (anchor === null) {
    return '';
  }
  const href: string = anchor[1];
  const lastEq: number = href.lastIndexOf('=');
  if (lastEq < 0) {
    return '';
  }
  let ticket: string = href.substring(lastEq + 1);
  const amp: number = ticket.indexOf('&');
  if (amp >= 0) {
    // 参考实现用 split('=').slice(-1)[0]，不切 &；票据 URL 没有后续参数，这里截尾只是防御
    ticket = ticket.substring(0, amp);
  }
  return ticket.trim();
}

/** CSRF 正则（逐字照参考实现；贪婪 '.*' 决定取每行**最后一个** &_csrf=）。 */
export const CSRF_PATTERN: RegExp = /^.*&_csrf=(\S*)"/gm;

/** 语言正则（整串标签精确匹配，含前导斜杠）。 */
export const LANGUAGE_PATTERN: RegExp = /<script src="\/f\/wlxt\/common\/languagejs\?lang=(zh|en)"><\/script>/g;

/** 从课程列表页抽 CSRF 令牌；取不到返回空串。 */
export function extractCsrfToken(pageHtml: string): string {
  if (!pageHtml) {
    return '';
  }
  const pattern: RegExp = new RegExp(CSRF_PATTERN.source, 'gm');
  const matched: RegExpExecArray | null = pattern.exec(pageHtml);
  if (matched === null) {
    return '';
  }
  return matched[1];
}

/** 从课程列表页抽语言（zh/en）；取不到返回空串，由调用方取默认值。 */
export function extractLanguage(pageHtml: string): string {
  if (!pageHtml) {
    return '';
  }
  const pattern: RegExp = new RegExp(LANGUAGE_PATTERN.source, 'g');
  const matched: RegExpExecArray | null = pattern.exec(pageHtml);
  if (matched === null) {
    return '';
  }
  return matched[1];
}

/**
 * 子串出现次数（大小写敏感，不重叠）。
 *
 * 用途：登录检查响应里出现几次 `doubleAuth`——站点要求二次验证/验证码时给的就是那套页面
 * （doubleAuth.bundle.js）。**它只是诊断计数，不是分类依据**：分类仍由「有没有票据链接」决定
 * （LoginClient.extractTicket）。有一条计数，日志就能区分"又被要求二次验证"与"页面改版/其他拒绝"。
 */
export function countOccurrences(haystack: string, needle: string): number {
  if (haystack.length === 0 || needle.length === 0) {
    return 0;
  }
  let count: number = 0;
  let from: number = 0;
  while (true) {
    const at: number = haystack.indexOf(needle, from);
    if (at < 0) {
      return count;
    }
    count++;
    from = at + needle.length;
  }
}

/**
 * 会话失效判据（thu-learn-lib 路径）：URL 含 login_timeout 或状态码 403（index.js:21）。
 * **平台不暴露重定向后的最终 URL**，所以这里再补一条响应体判据，构成「并集」而不是替代。
 */
export function isNoLoginResponse(status: number, responseUrl: string, body: string): boolean {
  if (status === 403) {
    return true;
  }
  if (responseUrl.length > 0 && responseUrl.includes('login_timeout')) {
    return true;
  }
  return body.length > 0 && body.includes('login_timeout');
}

/**
 * 原生处理器路径的判据：结果字符串**恰好等于** '[]'
 * （src/data/source.ts:104；语义见 docs/reference-quirks.md 第 2 条，锁定）。
 */
export function isEmptyListResult(body: string): boolean {
  return body === '[]';
}

/** 响应体是否像 ID 登录页（诊断「服务端要求浏览器」这条降级路径，验收第 5 条）。 */
export function looksLikeIdLoginPage(body: string): boolean {
  if (!body) {
    return false;
  }
  return body.includes('sm2publicKey') || body.includes('/do/off/ui/auth/login/form');
}
