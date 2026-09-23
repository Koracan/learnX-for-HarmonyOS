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
 * **不解码 HTML 实体**（照参考实现）。
 *
 * 文件末尾的 `isNoLoginResponse` 与 `isSessionLostErrorMessage` 不是"登录页解析"，而是同一件事的
 * **判据侧**：什么算"会话没了"只在这一个文件里定义（结果层 / 异常层两条，见各自的说明）。
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
 * （src/data/source.ts:104）。
 */
export function isEmptyListResult(body: string): boolean {
  return body === '[]';
}

/**
 * 「当前学期响应不可用」的稳定标记（**异常层**的会话失效判据）。
 *
 * 站点在会话失效时用 **HTTP 200 + 一个不含 `xnxq` 的 JSON 错误信封**回答
 * `getCurrentAndNextSemester`（设备实测正文 69 字符）——它既不是 `'[]'`、也不含
 * `login_timeout`，所以结果层那两条既有判据都看不见它。抛出这条消息的唯一实现在
 * `data/courses/SemesterFetcher.currentSemesterId`；三域取数源（courses / notices / files）
 * 会把它包成 `semester resolution failed: …` 再抛出。
 *
 * 为什么标记放在 auth 层：它是**会话失效判据**的一部分（与 isNoLoginResponse / isEmptyListResult
 * 同源），不是某一域的解析细节。产生方 import 它，不各写一遍字面量。
 */
export const UNUSABLE_SEMESTER_RESPONSE_MARKER: string = 'no xnxq in current semester response';

/**
 * 取数任务**抛出**的错误是否表示会话失效。
 *
 * 为什么需要它：学期是取数的前置条件，拿不到就没有可返回的结果 —— 三域取数源在"学期解析"
 * 这一步失败时是**抛错**而不是返回 TaskOutcome，而 SessionGate 只分类**返回**的结果。于是
 * "会话过期 → 自动重登 + 只重试一次"这条既有链路会被整条绕过。设备现象（2026-09，驻留后台后
 * 回到前台刷新作业）：直接显示 `semester resolution failed: no xnxq in current semester response: bytes=69`。
 *
 * 判据刻意**收窄到这一条**：网络层失败（status=0）与 403 由 `AuthedTaskRunner` 的既有映射负责；
 * 其它抛错（课程列表形状不符等）保持原样上报，不在这里被吞成"会话失效"。
 */
export function isSessionLostErrorMessage(message: string): boolean {
  return message.length > 0 && message.includes(UNUSABLE_SEMESTER_RESPONSE_MARKER);
}

/** 响应体是否像 ID 登录页（诊断「服务端要求浏览器」这条降级路径）。 */
export function looksLikeIdLoginPage(body: string): boolean {
  if (!body) {
    return false;
  }
  return body.includes('sm2publicKey') || body.includes('/do/off/ui/auth/login/form');
}
