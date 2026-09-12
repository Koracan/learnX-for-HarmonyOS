/*
 * 下载响应的**落盘前**判定 —— 纯函数，零平台依赖（见 scripts/check-domain-purity.mjs）。
 *
 * ## 为什么是"落盘前看 Content-Type"而不是参考实现那套启发式
 *
 * 参考实现（`reference/learnOH-old/src/helpers/fs.ts:125-158`）只能在**文件落盘之后**
 * 用"文件 < 5000 字节且内容含 `<html`/`location.href`"来**猜**"下载到的是登录页"。
 * 台账第 1 条把它登记为"平台下载库的补丁"，并要求新实现在 **HTTP 层**解决：
 * 落盘前检查状态码与 `Content-Type`，命中 HTML 就**不写文件**。
 * 本文件就是那条判据；`<5000 字节 + 含 <html>` 这条启发式**没有**被搬过来。
 *
 * ## 可判定性的边界（别把它说成比实际更强）
 *
 * 平台会**自动跟随 302**，所以"会话失效"在下载链路上的可观察形态是
 * **status=200 + Content-Type: text/html**（登录页正文）。这正是本判据的靶心。
 * `Content-Type` **缺失**时无法判定，按"接受"处理并把缺失本身记进日志——
 * 这是诚实的不确定性，不是"猜它是登录页"。
 */

/** 一次下载响应的落盘判定。 */
export interface DownloadDecision {
  /** true = 可以把响应体写进文件。 */
  accept: boolean;
  /** '' = 接受；否则是拒绝原因（进日志与界面文案）。 */
  reason: string;
}

/** 接受时的空原因。 */
export const DOWNLOAD_ACCEPT: string = '';

/** 归一化 Content-Type：取分号前的媒体类型、去空白、小写。 */
export function normalizeContentType(raw: string): string {
  const text: string = raw === undefined || raw === null ? '' : raw;
  const semicolon: number = text.indexOf(';');
  const media: string = semicolon >= 0 ? text.substring(0, semicolon) : text;
  return media.trim().toLowerCase();
}

/**
 * 命中 HTML 的判据（**只按 Content-Type**）：
 * `text/html` 与 `application/xhtml+xml`。
 * 站点自己的错误页也是 `text/html`（台账第 17 条实测 `status=403 text/html`），
 * 所以未知状态的 HTML 一律按"会话/接口异常"处理，不落盘。
 */
export function isHtmlLikeContentType(contentType: string): boolean {
  const media: string = normalizeContentType(contentType);
  return media === 'text/html' || media === 'application/xhtml+xml';
}

/** 站点用它回错误详情（JSON），也不是文件内容。 */
export function isJsonContentType(contentType: string): boolean {
  const media: string = normalizeContentType(contentType);
  return media === 'application/json' || media === 'text/json';
}

/**
 * 落盘前判定。规则（顺序即优先级）：
 *   1. 状态码非 200 → 拒绝（原因 `status:<code>`）—— 参考实现也在落盘后查这一条；
 *   2. `Content-Type` 是 HTML → 拒绝（原因 `html-login-page`）；
 *   3. `Content-Type` 是 JSON → 拒绝（原因 `json-error-page`）；
 *   4. 其余（含 Content-Type 缺失）→ 接受。
 */
export function evaluateDownloadContentType(contentType: string): DownloadDecision {
  if (isHtmlLikeContentType(contentType)) {
    return { accept: false, reason: 'html-login-page' };
  }
  if (isJsonContentType(contentType)) {
    return { accept: false, reason: 'json-error-page' };
  }
  return { accept: true, reason: DOWNLOAD_ACCEPT };
}

/**
 * 状态码判定（对应参考实现 fs.ts:130-139 的 `statusCode !== 200 → unlink + throw`）。
 *
 * **为什么与 Content-Type 判定分开**：平台只在 `requestInStream` **结束**时通过 promise
 * 给出状态码，而响应头（含 Content-Type）在**第一个字节之前**就能看到。所以
 * "HTML 登录页不落盘"这条能在写第一个字节前生效，而"状态码非 200"只能是
 * "流结束后删除刚写的文件 + 明确报错"。这个次序是**平台能力**决定的，不是取巧
 * （平台自动跟随 302，会话失效在下载链路上的形态就是 200 + text/html，
 * 所以真正要拦的那一类恰好落在**前**一条判据上）。
 */
export function evaluateDownloadStatus(status: number): DownloadDecision {
  if (status !== 200) {
    return { accept: false, reason: 'status:' + status.toString() };
  }
  return { accept: true, reason: DOWNLOAD_ACCEPT };
}

/** 组合判定（两条规则的唯一真源；单测钉住它，编排里按上面说的次序分别调用）。 */
export function evaluateDownloadResponse(status: number, contentType: string): DownloadDecision {
  const byStatus: DownloadDecision = evaluateDownloadStatus(status);
  if (!byStatus.accept) {
    return byStatus;
  }
  return evaluateDownloadContentType(contentType);
}

/**
 * 拒绝原因是否属于"会话没了"。
 *
 * HTML 登录页与 403 都算（台账第 17 条：站点对漏带 `_csrf` 的请求回自己的 403 页，
 * 而 `isNoLoginResponse` 把 403 当会话失效）；界面据此显示
 * `loh_session_expired` 而不是笼统的"下载失败"（验收第 3 条要"正确提示"）。
 */
export function isSessionLossReason(reason: string): boolean {
  return reason === 'html-login-page' || reason === 'status:403';
}

/**
 * 给下载地址追加 `_csrf`，语义**逐字等于**参考实现的 `addCSRF`
 * （`data/source.ts:75-78` → thu-learn-lib `addCSRFTokenToUrl`：
 * `new URL(url)` + `searchParams.set('_csrf', token)` + `toString()`）。
 *
 * 与 `data/remote/Requests.withCsrf` 的区别：那个是**无条件**拼 `?_csrf=`，
 * 只对"还没有查询串"的接口地址成立；下载地址里已经可能有 `?sfgk=0&wjid=…`，
 * 所以这里做真正的参数级替换（已存在 `_csrf` 时替换值而不是追加第二个）。
 * 空 token 同样写成 `_csrf=`（`set` 的语义）。
 */
export function appendCsrfToken(url: string, token: string): string {
  const text: string = url === undefined || url === null ? '' : url;
  let base: string = text;
  let fragment: string = '';
  const hash: number = text.indexOf('#');
  if (hash >= 0) {
    base = text.substring(0, hash);
    fragment = text.substring(hash);
  }
  const query: number = base.indexOf('?');
  const path: string = query >= 0 ? base.substring(0, query) : base;
  const existing: string = query >= 0 ? base.substring(query + 1) : '';
  const parts: string[] = existing.length > 0 ? existing.split('&') : [];
  let replaced: boolean = false;
  for (let i = 0; i < parts.length; i++) {
    const part: string = parts[i];
    const eq: number = part.indexOf('=');
    const name: string = eq >= 0 ? part.substring(0, eq) : part;
    if (name === '_csrf') {
      parts[i] = '_csrf=' + token;
      replaced = true;
    }
  }
  if (!replaced) {
    parts.push('_csrf=' + token);
  }
  return path + '?' + parts.join('&') + fragment;
}

/**
 * 打日志前把 `_csrf` 的值抹掉（**会话凭证绝不进 hilog**，spec 第 4 节 / ADR-0004）。
 * 保留参数名，于是"这次请求带没带 _csrf"仍可从日志判读（台账第 17 条的教训）。
 */
export function redactCsrfToken(url: string): string {
  const text: string = url === undefined || url === null ? '' : url;
  const marker: number = text.indexOf('_csrf=');
  if (marker < 0) {
    return text;
  }
  const valueStart: number = marker + '_csrf='.length;
  let valueEnd: number = text.indexOf('&', valueStart);
  if (valueEnd < 0) {
    valueEnd = text.length;
  }
  return text.substring(0, valueStart) + '***' + text.substring(valueEnd);
}

/**
 * 从响应头里取 Content-Length；取不到 / 非法 / 非正数时返回 -1（= 未知）。
 * `-1` 是**显式**的"不知道"，界面据此走不确定进度而不是假装 0%。
 */
export function parseContentLength(raw: string): number {
  const text: string = raw === undefined || raw === null ? '' : raw.trim();
  if (text.length === 0) {
    return -1;
  }
  const value: number = Number(text);
  if (Number.isNaN(value) || value <= 0) {
    return -1;
  }
  return Math.floor(value);
}
