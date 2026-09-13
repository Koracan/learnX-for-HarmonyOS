/*
 * cookie jar（core）：**纯内存、零平台依赖**，可单测。
 *
 * 为什么自己写：ADR-0004 决定**不持久化会话 cookie**，会话只在内存里；参考实现依赖
 * `@react-native-cookies/cookies`（平台 WebView 的 cookie 存储），恰好是要丢掉的那一层。
 *
 * 与参考实现的行为对齐（`src/data/source.ts:11-46`）：
 *   - 登录**之前**显式重置（`clearAll` + 把 id 域的 `JSESSIONID` 置空），注释原文
 *     "HarmonyOS cookies may persist unexpectedly"——不依赖"反正是空的"；
 *   - 这里的等价实现是 `reset()` + `resetIdDomainSession()`，由 LoginClient 在登录前调用。
 *
 * 安全：cookie 值是会话秘密，**日志只出现域名/名字/条数/总长度，不出现值**（见 `describe()`）。
 * 这些日志会被导出功能写进文件，所以脱敏是硬要求而不是风格偏好。
 */

/** 一个 cookie。 */
export interface JarCookie {
  name: string;
  value: string;
  /** 规范化后的域（小写、无前导点）。 */
  domain: string;
  path: string;
  secure: boolean;
  httpOnly: boolean;
  /**
   * 是否显式带过期时间（Expires / Max-Age）。
   *
   * 不能只看 `expiresAt > 0`：`Expires=Thu, 01 Jan 1970 00:00:00 GMT` 解析出来正好是 0，
   * 与「没有过期时间」撞值（单测抓到过这个 bug）。
   */
  hasExpires: boolean;
  /** 过期时刻（毫秒）；`hasExpires` 为 false 时无意义。 */
  expiresAt: number;
}

/** 取域：既接受 host，也接受完整 URL（登录流习惯传 URL）。 */
function normalizeDomain(domainOrUrl: string): string {
  const raw: string = domainOrUrl.trim();
  if (raw.startsWith('http://') || raw.startsWith('https://')) {
    return hostOf(raw);
  }
  return raw.startsWith('.') ? raw.substring(1).toLowerCase() : raw.toLowerCase();
}

/** 取 URL 的 host（小写）。解析不了时返回空串。 */
export function hostOf(url: string): string {
  const matched: RegExpMatchArray | null = url.match(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/([^/?#]+)/);
  if (matched === null) {
    return '';
  }
  let host: string = matched[1].toLowerCase();
  const at: number = host.lastIndexOf('@');
  if (at >= 0) {
    host = host.substring(at + 1);
  }
  const colon: number = host.lastIndexOf(':');
  if (colon >= 0 && host.indexOf(']') < colon) {
    host = host.substring(0, colon);
  }
  return host;
}

/** 取 URL 的路径（无查询串）。解析不了时返回 '/'。 */
export function pathOf(url: string): string {
  const matched: RegExpMatchArray | null = url.match(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/[^/?#]*([^?#]*)/);
  if (matched === null || matched[1].length === 0) {
    return '/';
  }
  return matched[1];
}

/** RFC 6265 default-path：请求路径去掉最后一段。 */
export function defaultPathFor(requestPath: string): string {
  if (requestPath.length === 0 || requestPath.charAt(0) !== '/') {
    return '/';
  }
  const lastSlash: number = requestPath.lastIndexOf('/');
  if (lastSlash <= 0) {
    return '/';
  }
  return requestPath.substring(0, lastSlash);
}

/** cookie 域是否覆盖 host（含子域；尾点与大小写已规范化）。 */
export function domainMatches(cookieDomain: string, host: string): boolean {
  const domain: string = cookieDomain.startsWith('.') ? cookieDomain.substring(1) : cookieDomain;
  if (domain.length === 0 || host.length === 0) {
    return false;
  }
  if (host === domain) {
    return true;
  }
  return host.endsWith('.' + domain);
}

/** cookie 路径是否覆盖请求路径（RFC 6265 的规则，含 `/foo` 匹配 `/foo/bar` 但不匹配 `/foobar`）。 */
export function pathMatches(cookiePath: string, requestPath: string): boolean {
  if (cookiePath === requestPath) {
    return true;
  }
  if (!requestPath.startsWith(cookiePath)) {
    return false;
  }
  if (cookiePath.endsWith('/')) {
    return true;
  }
  return requestPath.charAt(cookiePath.length) === '/';
}

/** 判断 ''' , ''' 之后的这段文本是否像一个新 cookie 的起点（`name=`）。 */
function looksLikeCookieStart(text: string, from: number): boolean {
  let i: number = from;
  while (i < text.length && (text.charAt(i) === ' ' || text.charAt(i) === '\t')) {
    i++;
  }
  let sawTokenChar: boolean = false;
  while (i < text.length) {
    const ch: string = text.charAt(i);
    if (ch === '=') {
      return sawTokenChar;
    }
    if (ch === ' ' || ch === '\t' || ch === ';' || ch === ',') {
      return false;
    }
    sawTokenChar = true;
    i++;
  }
  return false;
}

/**
 * 把平台给出的 Set-Cookie 串拆成单个 cookie 串。
 *
 * 平台（`@ohos.net.http` 的 `response.cookies`）把多个 Set-Cookie 拼成一个字符串，
 * 而 `Expires=Wed, 21 Oct 2026 07:28:00 GMT` **本身含逗号**，所以不能简单按逗号切：
 * 只有当逗号后面像 `name=` 时才算边界，且跳过引号内的内容。
 */
export function splitSetCookieHeader(raw: string): string[] {
  const parts: string[] = [];
  if (!raw) {
    return parts;
  }
  let start: number = 0;
  let inQuotes: boolean = false;
  for (let i = 0; i < raw.length; i++) {
    const ch: string = raw.charAt(i);
    if (ch === '"') {
      inQuotes = !inQuotes;
      continue;
    }
    if (ch === ',' && !inQuotes && looksLikeCookieStart(raw, i + 1)) {
      parts.push(raw.substring(start, i).trim());
      start = i + 1;
    }
  }
  const tail: string = raw.substring(start).trim();
  if (tail.length > 0) {
    parts.push(tail);
  }
  return parts;
}

/** cookie 头里的一对 name=value。 */
export interface CookiePair {
  name: string;
  value: string;
}

/**
 * 解析 `Cookie` 头形态的字符串（`a=1; b=2`）。
 *
 * 与 `parseSetCookie` 的区别：这里**没有属性段**，只按 `;` 切对；空 name 的对被丢掉
 * （宁可少写一个 cookie，也不要写进去一个空的）。值里允许出现 `=`（取第一个等号切分）。
 */
export function parseCookieHeaderPairs(header: string): CookiePair[] {
  const pairs: CookiePair[] = [];
  if (header.length === 0) {
    return pairs;
  }
  const segments: string[] = header.split(';');
  for (let i = 0; i < segments.length; i++) {
    const segment: string = segments[i].trim();
    if (segment.length === 0) {
      continue;
    }
    const eq: number = segment.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    const name: string = segment.substring(0, eq).trim();
    if (name.length === 0) {
      continue;
    }
    pairs.push({ name: name, value: segment.substring(eq + 1).trim() });
  }
  return pairs;
}

/** 解析单个 Set-Cookie 串；缺少 name 或 name 非法时返回 undefined。 */
export function parseSetCookie(one: string, requestUrl: string): JarCookie | undefined {
  const segments: string[] = one.split(';');
  const first: string = segments.length > 0 ? segments[0].trim() : '';
  const eq: number = first.indexOf('=');
  if (eq <= 0) {
    return undefined;
  }
  const name: string = first.substring(0, eq).trim();
  const value: string = first.substring(eq + 1).trim();
  if (name.length === 0) {
    return undefined;
  }
  const host: string = hostOf(requestUrl);
  const cookie: JarCookie = {
    name: name,
    value: value,
    domain: host,
    path: defaultPathFor(pathOf(requestUrl)),
    secure: false,
    httpOnly: false,
    hasExpires: false,
    expiresAt: 0
  };
  const now: number = Date.now();
  for (let i = 1; i < segments.length; i++) {
    const segment: string = segments[i].trim();
    const sep: number = segment.indexOf('=');
    const key: string = (sep < 0 ? segment : segment.substring(0, sep)).trim().toLowerCase();
    const attrValue: string = sep < 0 ? '' : segment.substring(sep + 1).trim();
    if (key === 'domain' && attrValue.length > 0) {
      cookie.domain = attrValue.startsWith('.') ? attrValue.substring(1).toLowerCase() : attrValue.toLowerCase();
    } else if (key === 'path' && attrValue.length > 0) {
      cookie.path = attrValue;
    } else if (key === 'secure') {
      cookie.secure = true;
    } else if (key === 'httponly') {
      cookie.httpOnly = true;
    } else if (key === 'max-age') {
      const seconds: number = Number.parseInt(attrValue, 10);
      if (!Number.isNaN(seconds)) {
        cookie.hasExpires = true;
        cookie.expiresAt = now + seconds * 1000;
      }
    } else if (key === 'expires' && attrValue.length > 0) {
      const parsed: number = Date.parse(attrValue);
      if (!Number.isNaN(parsed)) {
        cookie.hasExpires = true;
        cookie.expiresAt = parsed;
      }
    }
  }
  return cookie;
}

/* ------------------------------------------------------------------ *
 * 平台 `response.cookies` 的**第二种形态**（实测）： 
 * Netscape cookie-file 行——**制表符分隔的 7 个字段**，不是 `name=value; attrs`。
 *
 * 为什么必须支持：`@ohos.net.http` 的 `HttpResponse.cookies` 文档只写
 * "Cookies returned by the server."，不写格式；实测（模拟器 Pura 90）给出的是
 *
 *   #HttpOnly_id.tsinghua.edu.cn<TAB>FALSE<TAB>/<TAB>FALSE<TAB>0<TAB>JSESSIONID<TAB>FB9C…
 *
 * 而只认 `name=value` 的解析器在这里 `indexOf('=') <= 0` **直接落空** ⇒ 一个 cookie 都不入库
 * ⇒ 后续请求带着空 JSESSIONID 发出。这是"我们发出去的请求不完备"的真因，不是站点行为异常。
 *
 * 字段顺序：domain / includeSubdomains / path / secure / expiry / name / value。
 *   - `#HttpOnly_` 前缀表示 httpOnly，**域是去掉该前缀之后的部分**；
 *     以 `#` 开头的行通常是注释，但这一种**不是注释**，不能跳过；
 *   - `expiry` 为 0 ⇒ 会话 cookie（无过期时间）；
 *   - 域可能带前导点；
 *   - 值里允许出现 `=`（只切第 6 个制表符）。
 * ------------------------------------------------------------------ */

/** 制表符分隔的字段数（Netscape 形态有 7 个字段 = 6 个制表符）。 */
function tabFieldCount(line: string): number {
  let count: number = 1;
  for (let i = 0; i < line.length; i++) {
    if (line.charAt(i) === '\t') {
      count++;
    }
  }
  return count;
}

/**
 * 这一行是不是 Netscape cookie-file 行。
 *
 * 判据刻意宽：`#HttpOnly_` 前缀是强信号；否则看制表符字段数 ≥ 7。
 * 宁可把可疑行当 Netscape 解析（解析不出来也没什么可丢的），也不要把标准
 * `Set-Cookie` 误判成 Netscape（那才会丢 cookie）。
 */
export function looksLikeNetscapeCookieLine(line: string): boolean {
  const text: string = line.trim();
  if (text.length === 0) {
    return false;
  }
  if (text.startsWith('#HttpOnly_')) {
    return true;
  }
  return tabFieldCount(text) >= 7;
}

/** 解析一条 Netscape cookie-file 行；不是该形态或字段不合法时返回 undefined。 */
export function parseNetscapeCookieLine(line: string, requestUrl: string): JarCookie | undefined {
  let text: string = line;
  if (text.endsWith('\r')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.trim().length === 0) {
    return undefined;
  }
  let httpOnly: boolean = false;
  if (text.startsWith('#HttpOnly_')) {
    httpOnly = true;
    text = text.substring('#HttpOnly_'.length);
  } else if (text.startsWith('#')) {
    // 真正的注释行（平台不会给，防御性跳过）
    return undefined;
  }
  const fields: string[] = text.split('\t');
  if (fields.length < 7) {
    return undefined;
  }
  const domainRaw: string = fields[0].trim();
  const path: string = fields[2].trim();
  const secureText: string = fields[3].trim().toUpperCase();
  const expiryText: string = fields[4].trim();
  const name: string = fields[5].trim();
  // 值里允许含 '='，也可能含制表符（切出来多于 7 段时全部并回值）
  const value: string = fields.length > 7 ? fields.slice(6).join('\t') : fields[6];
  if (name.length === 0) {
    return undefined;
  }
  const domain: string = domainRaw.startsWith('.') ? domainRaw.substring(1).toLowerCase() : domainRaw.toLowerCase();
  if (domain.length === 0) {
    return undefined;
  }
  let hasExpires: boolean = false;
  let expiresAt: number = 0;
  const seconds: number = Number.parseInt(expiryText, 10);
  if (!Number.isNaN(seconds) && seconds > 0) {
    hasExpires = true;
    expiresAt = seconds * 1000;
  }
  return {
    name: name,
    value: value,
    domain: domain,
    path: path.length > 0 ? path : defaultPathFor(pathOf(requestUrl)),
    // host-only cookie（includeSubdomains 为 FALSE）在域不覆盖请求 host 时不可用
    secure: secureText === 'TRUE',
    httpOnly: httpOnly,
    hasExpires: hasExpires,
    expiresAt: expiresAt
  };
}

/**
 * 一次 Set-Cookie 串的来源（**自证用**：到底走的是哪条解析入口）。
 *
 * - `netscape` —— 平台 `HttpResponse.cookies` 的 Netscape 制表符行；
 * - `standard` —— 标准的 `name=value; attrs` 形态；
 * - `mixed`    —— 同一串里两种都出现过（实测未出现，保留以防平台混发）。
 */
export type SetCookieSource = 'standard' | 'netscape' | 'mixed' | 'empty';

/** 一次吸收的结果（自证日志用：来源 / 吸收数 / 跳过数）。 */
export interface SetCookieAbsorbResult {
  stored: number;
  source: SetCookieSource;
  skipped: number;
}

/** 解析结果 + 来源标注。 */
export interface ParsedSetCookieResponse {
  cookies: JarCookie[];
  source: SetCookieSource;
  /** 被跳过的行数（空行/注释/解析不出），用于自证"没有静默丢东西"。 */
  skipped: number;
}

/**
 * 把一次响应的 `response.cookies` / `response.header['set-cookie']` 解析成 cookie，
 * **逐行**判定形态：一行一条，Netscape 行与标准行都支持。
 */
export function parseSetCookieResponse(raw: string, requestUrl: string): ParsedSetCookieResponse {
  const cookies: JarCookie[] = [];
  let netscapeLines: number = 0;
  let standardLines: number = 0;
  let skipped: number = 0;
  if (raw === undefined || raw === null || raw.length === 0) {
    return { cookies: cookies, source: 'empty', skipped: 0 };
  }
  const lines: string[] = raw.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line: string = lines[i];
    if (line.trim().length === 0) {
      continue;
    }
    if (looksLikeNetscapeCookieLine(line)) {
      const parsed: JarCookie | undefined = parseNetscapeCookieLine(line, requestUrl);
      if (parsed === undefined) {
        skipped++;
      } else {
        cookies.push(parsed);
        netscapeLines++;
      }
      continue;
    }
    // 标准形态：一条物理行里可能用逗号拼了多个 cookie（Expires 含逗号，靠启发式切）
    const parts: string[] = splitSetCookieHeader(line);
    let storedHere: number = 0;
    for (let p = 0; p < parts.length; p++) {
      const parsed: JarCookie | undefined = parseSetCookie(parts[p], requestUrl);
      if (parsed === undefined) {
        continue;
      }
      cookies.push(parsed);
      standardLines++;
      storedHere++;
    }
    if (storedHere === 0) {
      skipped++;
    }
  }
  let source: SetCookieSource = 'empty';
  if (netscapeLines > 0 && standardLines > 0) {
    source = 'mixed';
  } else if (netscapeLines > 0) {
    source = 'netscape';
  } else if (standardLines > 0) {
    source = 'standard';
  }
  return { cookies: cookies, source: source, skipped: skipped };
}

/**
 * 内存 cookie jar。
 *
 * 只保存"能发出去"的 cookie：同名同域同路径的后写覆盖先写；已过期的直接不存。
 * 不落盘（ADR-0004），不跨进程。
 */
export class CookieJar {
  private cookies: JarCookie[] = [];

  /** 全部清空（对应参考实现的 `CookieManager.clearAll(true)`）。 */
  reset(): void {
    this.cookies = [];
  }

  size(): number {
    return this.cookies.length;
  }

  /**
   * 重置某个域上的 `JSESSIONID`（对应参考实现 `clearLoginCookies` 的第二半：
   * 把 id 域的 JSESSIONID 置空）。空值不会进 Cookie 头，见 `cookieHeaderFor`。
   */
  resetIdDomainSession(idDomainOrUrl: string): void {
    const idDomain: string = normalizeDomain(idDomainOrUrl);
    const kept: JarCookie[] = [];
    for (let i = 0; i < this.cookies.length; i++) {
      const cookie: JarCookie = this.cookies[i];
      const isSession: boolean = cookie.name === 'JSESSIONID' && domainMatches(cookie.domain, idDomain);
      if (!isSession) {
        kept.push(cookie);
      }
    }
    this.cookies = kept;
    this.set('JSESSIONID', '', idDomain, '/');
  }

  /** 显式写入一个 cookie（参考实现用 `CookieManager.set` 的那条路径）。 */
  set(name: string, value: string, domainOrUrl: string, path: string): void {
    const cookie: JarCookie = {
      name: name,
      value: value,
      domain: normalizeDomain(domainOrUrl),
      path: path,
      secure: false,
      httpOnly: false,
      hasExpires: false,
      expiresAt: 0
    };
    this.store(cookie);
  }

  /**
   * 由**浏览器**给出的 `Cookie` 头形态字符串写入（登记收割路径）。
   *
   * 为什么需要这条入口：设备登记的会话是在 ArkWeb 里建立的（用户在那里完成短信验证），
   * 拿到的就是 `WebCookieManager.fetchCookieSync(url)` 返回的 `a=1; b=2` 形态文本——
   * 它没有域/路径/属性，只有一个"这些就是发给该 URL 的 cookie"的事实。于是按该 URL 的
   * host 与 `/` 路径存入（正是 cookie 头能被发出去的最小充分条件）。
   *
   * 返回写入条数，便于调用方判断"到底有没有收割到会话"。
   */
  absorbCookieHeader(header: string, url: string): number {
    const pairs: CookiePair[] = parseCookieHeaderPairs(header);
    const domain: string = hostOf(url);
    for (let i = 0; i < pairs.length; i++) {
      this.set(pairs[i].name, pairs[i].value, domain, '/');
    }
    return pairs.length;
  }

  /**
   * 由一次响应的 Set-Cookie 串写入（可含多个 cookie）。
   *
   * **逐行**判定形态——平台 `HttpResponse.cookies` 给的是 Netscape 制表符行，
   * 而 `response.header['set-cookie']` 给的是标准形态；两种都要能吸收。
   * 想连来源一起看时用 `setFromResponseDetailed`（调用方据此打自证日志）。
   */
  setFromResponse(setCookie: string, requestUrl: string): number {
    return this.setFromResponseDetailed(setCookie, requestUrl).stored;
  }

  /** 同 `setFromResponse`，但把"哪条来源、吸收到几个、跳过几行"一并带回（自证用）。 */
  setFromResponseDetailed(setCookie: string, requestUrl: string): SetCookieAbsorbResult {
    const parsed: ParsedSetCookieResponse = parseSetCookieResponse(setCookie, requestUrl);
    let stored: number = 0;
    for (let i = 0; i < parsed.cookies.length; i++) {
      this.store(parsed.cookies[i]);
      stored++;
    }
    return { stored: stored, source: parsed.source, skipped: parsed.skipped };
  }

  /** 组装某个 URL 的 Cookie 头；空值 cookie 不发。 */
  cookieHeaderFor(url: string): string {
    const host: string = hostOf(url);
    const path: string = pathOf(url);
    const secure: boolean = url.startsWith('https://');
    const now: number = Date.now();
    const pairs: string[] = [];
    for (let i = 0; i < this.cookies.length; i++) {
      const cookie: JarCookie = this.cookies[i];
      if (cookie.value.length === 0) {
        continue;
      }
      if (cookie.hasExpires && cookie.expiresAt <= now) {
        continue;
      }
      if (!domainMatches(cookie.domain, host)) {
        continue;
      }
      if (!pathMatches(cookie.path, path)) {
        continue;
      }
      if (cookie.secure && !secure) {
        continue;
      }
      pairs.push(cookie.name + '=' + cookie.value);
    }
    return pairs.join('; ');
  }

  /** 诊断串：只含域名、名字、条数与总长度，**不含 cookie 值**。 */
  describe(): string {
    const domains: string[] = [];
    const names: string[] = [];
    let totalLength: number = 0;
    for (let i = 0; i < this.cookies.length; i++) {
      const cookie: JarCookie = this.cookies[i];
      if (domains.indexOf(cookie.domain) < 0) {
        domains.push(cookie.domain);
      }
      if (names.indexOf(cookie.name) < 0) {
        names.push(cookie.name);
      }
      totalLength += cookie.value.length;
    }
    return 'cookies=' + this.cookies.length.toString()
      + ' domains=[' + domains.join(',') + ']'
      + ' names=[' + names.join(',') + ']'
      + ' valueChars=' + totalLength.toString();
  }

  /**
   * 本次**实际会发出**的 Cookie 头摘要（自证用）：条数 + 每条的 `名字(值长度)`。
   *
   * 为什么需要：'我们发出去的请求完不完整' 必须是可观察量——空 JSESSIONID 曾经静默地
   * 发了半个月，日志里只留下一个 `valueChars=0`。
   * **绝不落值**：只有名字与长度。
   */
  cookieSummaryFor(url: string): string {
    const host: string = hostOf(url);
    const path: string = pathOf(url);
    const secure: boolean = url.startsWith('https://');
    const now: number = Date.now();
    const parts: string[] = [];
    for (let i = 0; i < this.cookies.length; i++) {
      const cookie: JarCookie = this.cookies[i];
      if (cookie.value.length === 0) {
        continue;
      }
      if (cookie.hasExpires && cookie.expiresAt <= now) {
        continue;
      }
      if (!domainMatches(cookie.domain, host)) {
        continue;
      }
      if (!pathMatches(cookie.path, path)) {
        continue;
      }
      if (cookie.secure && !secure) {
        continue;
      }
      parts.push(cookie.name + '(' + cookie.value.length.toString() + ')');
    }
    if (parts.length === 0) {
      return 'sent=0 names=[]';
    }
    return 'sent=' + parts.length.toString() + ' names=[' + parts.join(',') + ']';
  }

  /** 仅测试/诊断：克隆出一份快照（不含值的使用请走 describe）。 */
  snapshot(): JarCookie[] {
    const copy: JarCookie[] = [];
    for (let i = 0; i < this.cookies.length; i++) {
      const cookie: JarCookie = this.cookies[i];
      copy.push({
        name: cookie.name, value: cookie.value, domain: cookie.domain, path: cookie.path,
        secure: cookie.secure, httpOnly: cookie.httpOnly,
        hasExpires: cookie.hasExpires, expiresAt: cookie.expiresAt
      });
    }
    return copy;
  }

  private store(cookie: JarCookie): void {
    if (cookie.value.length === 0 && cookie.name !== 'JSESSIONID') {
      return;
    }
    const now: number = Date.now();
    if (cookie.hasExpires && cookie.expiresAt <= now) {
      // 已过期：等价于删除同名同域同路径的旧值
      this.removeMatching(cookie);
      return;
    }
    this.removeMatching(cookie);
    this.cookies.push(cookie);
  }

  private removeMatching(cookie: JarCookie): void {
    const kept: JarCookie[] = [];
    for (let i = 0; i < this.cookies.length; i++) {
      const existing: JarCookie = this.cookies[i];
      const same: boolean = existing.name === cookie.name
        && existing.domain === cookie.domain
        && existing.path === cookie.path;
      if (!same) {
        kept.push(existing);
      }
    }
    this.cookies = kept;
  }
}