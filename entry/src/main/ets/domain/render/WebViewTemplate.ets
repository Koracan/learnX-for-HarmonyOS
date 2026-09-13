/*
 * 公告正文的 Web 容器模板 —— **纯字符串逻辑，零平台依赖**（见 scripts/check-domain-purity.mjs）。
 *
 * 逐项移植自参考实现 `reference/learnOH-old/src/helpers/html.ts:27-118` 的
 * `getWebViewTemplate`（平台无关的 HTML/CSS/JS），差异只有一处、见下「资产」。
 *
 * ## 为什么要拆出 `assets`
 *
 * 参考实现用 `@preval` 在**构建期**把 katex/darkreader 读成字符串内联进模板
 * （`helpers/preval/*.preval.js`），合计约 630 KB。ArkTS 没有 preval，把这 630 KB
 * 写成 .ets 字符串字面量在编译期与内存上都不划算，所以：
 *   - 资产放 `entry/src/main/resources/rawfile/webview/`，运行时读出（core/web/WebPageAssets.ets）；
 *   - 本文件只做**拼装**，资产以参数传入 —— 于是它保持纯函数，可被 host 单测直接覆盖
 *     （ticket 04 Comments 第 5 节要求的断言语义）。
 *
 * ## 与参考实现的逐项对照
 *
 * | 模板里的东西 | 参考实现 | 这里 |
 * | --- | --- | --- |
 * | viewport `width=device-width, initial-scale=1` | html.ts:37 | 同 |
 * | CSP `upgrade-insecure-requests` | html.ts:38 | 同 |
 * | `body{margin:0;padding:1rem}` | html.ts:40-43 | 同 |
 * | `#root{height:100%;width:100%;overflow:auto}` | html.ts:44-48 | 同 |
 * | `#root > p:first-child/:last-child` 去外边距 | html.ts:49-54 | 同 |
 * | KaTeX 样式（字体 URL 已重写为 CDN） | html.ts:56-58 | 同（重写在复制资产时做） |
 * | `addCSRFTokenToUrl` 注入脚本 | html.ts:60-86 | 同 + 平台回退（见下） |
 * | DarkReader 段（仅深色时注入） | html.ts:88-101 | 同 |
 * | katex + auto-render 脚本 | html.ts:102-104 | 同 |
 * | `renderMathInElement(#root, {throwOnError:false})` | html.ts:110-114 | 同 |
 * | 正文占位 `content || "<p>noNoticeContent</p>"` | NoticeDetail.tsx:54 | 由调用方传入（buildNoticeContent） |
 *
 * ## 平台回退：`new URL()` 在 `loadData` 下不可用
 *
 * 参考实现的注入脚本用 `new URL(url)` 取 hostname（html.ts:61-65）。ArkWeb 用
 * `loadData` 加载 data: URL 时，该文档**没有网络来源**，浏览器会禁用 `URL` 构造器
 * （WHATWG 把 `about:blank` / `data:` 等列为 opaque origin 下的禁用接口；后果是
 * `new URL('https://x/y')` 抛 TypeError）。照抄会让**每一条** href/src 都更新失败。
 * 这不是"顺手修好参考实现"，而是**同一个意图在另一个平台上的等价实现**：
 *   - hostname 以 `tsinghua.edu.cn` 结尾 → 追加 `_csrf`（与参考实现同一条件）；
 *   - 解析不出来时**也**追加（参考实现在老环境能解析、会追加；只有末尾带 `#fragment`
 *     时参考实现会丢掉 fragment，此处把 fragment 显式拼回）。
 *
 * ## 安全边界变更：`</script>` 转义
 *
 * 参考实现把 `content` 直接拼进模板，模板里若干内联 `<script>`。正文里若含字面量
 * `</script>`，HTML 解析器会**提前结束**那个 script 元素，后续正文被当成裸 JS 执行
 * （参考实现的模板缺少 `</script>` 转义；同项目已为登录页注入面写过同类加固，
 * 见 spec 第 5 节）。这里把正文里的 `</script` 转义成 `<\/script`，对正文渲染无影响
 * （HTML 里 `<\/script` 不是有效标签，文本原样显示），但能堵住这条注入路径。
 * 单元测试 `escapesScriptEndTagsInContent` 守住它。
 */

import { decodeAllEntities } from '../parse/Text';

/** Web 容器模板需要的外部资产（由 core 从 rawfile 读出后传入）。 */
export interface WebPageAssets {
  /** `katex.min.css`（`url(fonts/` 已重写为 CDN 绝对地址）。 */
  katexStyles: string;
  /** `katex.min.js` + `contrib/auto-render.min.js`。 */
  katexScript: string;
  /** `darkreader.js`（仅深色时用）。 */
  darkReaderScript: string;
}

/** 注入脚本可用的资产（DarkReader 只在深色时需要，故单列）。 */
export interface TemplateAssets {
  katexStyles: string;
  katexScript: string;
  darkReaderScript?: string;
}

/** 模板占位符：HTML 注释形态，正常正文不会自然命中。 */
const TOKEN_HEAD = '<!--learnoh:head-->';
const TOKEN_DARK = '<!--learnoh:dark-->';
const TOKEN_KATEX = '<!--learnoh:katex-->';

/** 深色皮肤默认底色（与主题令牌 DARK_COLORS.surface 同值，取不到时兜底）。 */
export const DEFAULT_DARK_BACKGROUND: string = '#1E1A1D';

/** `#([0-9a-fA-F]{3,8})` 或 `rgb(a)` / `hsl(a)` 形态；其余一律回退。 */
const COLOR_PATTERN = /^(#[0-9a-fA-F]{3,8}|rgba?\([0-9.,% ]+\)|hsla?\([0-9.,% ]+\))$/;

/** 把颜色值收敛成可安全写进 JS 字符串字面量的形态，避免注入。 */
export function sanitizeColor(value: string | undefined): string {
  if (value === undefined) {
    return DEFAULT_DARK_BACKGROUND;
  }
  const trimmed: string = value.trim();
  if (trimmed.length === 0) {
    return DEFAULT_DARK_BACKGROUND;
  }
  return COLOR_PATTERN.test(trimmed) ? trimmed : DEFAULT_DARK_BACKGROUND;
}

/**
 * JS 字符串字面量（单引号）。模板里所有插值都过它，避免正文/颜色里的引号闭合字面量。
 * 顺序要紧：先转义反斜杠，再转义引号与控制字符。
 */
export function jsStringLiteral(value: string): string {
  let out: string = value.split('\\').join('\\\\');
  out = out.split("'").join("\\'");
  out = out.split('\r').join('\\r');
  out = out.split('\n').join('\\n');
  out = out.split('\u2028').join('\\u2028');
  out = out.split('\u2029').join('\\u2029');
  return "'" + out + "'";
}

/** 空正文兜底：`<p>无通知内容</p>`（对齐 NoticeDetail.tsx:54 的 `content || "<p>" + t(...) + "</p>"`）。 */
export function buildNoticeContent(content: string, emptyText: string): string {
  const trimmed: string = content.trim();
  if (trimmed.length === 0) {
    return '<p>' + escapeScriptEndTags(emptyText) + '</p>';
  }
  return escapeScriptEndTags(content);
}

/** 正文里出现字面量 `</script` 时会提前结束模板里的内联 script，这里转义掉。 */
export function escapeScriptEndTags(content: string): string {
  return content.split('</script').join('<\\/script');
}

/**
 * 测高脚本（对应参考实现 AutoHeightWebView.tsx:24-48 的 `injectedScript`，同一公式）。
 *
 * 与参考实现的两点差别，都是平台适配而非语义变更：
 *  1. 回传通道换成 javaScriptProxy 注入的桥（`window.learnOHBridge.onHeight`），
 *     语义同 `window.ReactNativeWebView.postMessage`；桥还没注入时退回 `console.log`
 *     并把值交给原生 `onConsole` 解析（ArkWeb 没有 RN 那个固定 message 通道）。
 *  2. 参考实现只在 `load` 时测一次；这里额外挂 ResizeObserver 与 `fonts.ready`，
 *     否则 KaTeX 字体从 CDN 到达后重排、公告里的图片解码完成都会让高度变短/变长，
 *     而"内容高度自适应"要的是**最终**高度。
 *
 * 取数口径仍是参考实现那条 `max(...)`，但把 `#root` 也纳入：模板给 `body` 加了
 * `padding: 1rem`，任何 `body.scrollHeight` 都**含**这 16px 内边距；原生侧若照它设高，
 * Web 组件的 viewport 就比视口内容高 16px，页面`#root{height:100%}`又跟着变高，
 * 于是越量越高（每帧 +16px，实测会滚到几千像素）。纳入 `#root.scrollHeight`
 * （内容盒，不含 padding）后取 max 仍覆盖"内容比视口高"的原始意图，同时不再自增。
 */
export const MEASURE_SCRIPT: string = `
(function () {
  var BRIDGE = 'learnOHBridge';
  function report(h) {
    try {
      var bridge = window[BRIDGE];
      if (bridge && typeof bridge.onHeight === 'function') {
        bridge.onHeight(String(h));
        return;
      }
    } catch (e) {
      // 落到下面的 console 回退
    }
    try {
      console.log('learnoh:height:' + h);
    } catch (e2) {
    }
  }
  function measure() {
    var d = document;
    var root = d.getElementById('root');
    var h = Math.max(
      (root && root.scrollHeight) || 0,
      (root && root.offsetHeight) || 0,
      (d.documentElement && d.documentElement.clientHeight) || 0,
      (d.documentElement && d.documentElement.scrollHeight) || 0,
      (d.body && d.body.clientHeight) || 0,
      (d.body && d.body.scrollHeight) || 0
    );
    if (h > 0) {
      report(h);
    }
  }
  window.learnOHMeasure = measure;
  var timer = null;
  function schedule() {
    if (timer !== null) {
      return;
    }
    timer = setTimeout(function () {
      timer = null;
      try {
        measure();
      } catch (e) {
      }
    }, 50);
  }
  function settle(rounds) {
    measure();
    if (rounds > 0) {
      setTimeout(function () {
        settle(rounds - 1);
      }, 250);
    }
  }
  window.addEventListener('load', function () {
    settle(8);
  });
  window.addEventListener('resize', schedule);
  try {
    if (window.ResizeObserver && document.body) {
      var observer = new ResizeObserver(schedule);
      observer.observe(document.documentElement);
      observer.observe(document.body);
    }
  } catch (e) {
  }
  try {
    if (document.fonts && document.fonts.ready && document.fonts.ready.then) {
      document.fonts.ready.then(schedule);
    }
  } catch (e) {
  }
  measure();
})();
`;

/**
 * scheme（含冒号）结束处的下标；不是 `scheme:` 开头时返回 0。
 * 手写扫描而不是正则：`resolveNoticeUrl` 与注入脚本里的 `schemeEnd` 必须逐字同构。
 */
function schemeEnd(url: string): number {
  if (url.length === 0) {
    return 0;
  }
  const first: number = url.charCodeAt(0);
  const firstIsAlpha: boolean = (first >= 65 && first <= 90) || (first >= 97 && first <= 122);
  if (!firstIsAlpha) {
    return 0;
  }
  for (let i = 1; i < url.length; i++) {
    const code: number = url.charCodeAt(i);
    const ch: string = url.charAt(i);
    const isAlpha: boolean = (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
    const isDigit: boolean = code >= 48 && code <= 57;
    if (isAlpha || isDigit || ch === '+' || ch === '-' || ch === '.') {
      continue;
    }
    return ch === ':' ? i + 1 : 0;
  }
  return 0;
}

/** `scheme://authority` 这一段（不含路径 / 查询 / 片段）；不是网络绝对地址时返回空串。 */
export function siteOrigin(url: string): string {
  const end: number = schemeEnd(url);
  if (end === 0 || url.substring(end, end + 2) !== '//') {
    return '';
  }
  let stop: number = url.length;
  const slash: number = url.indexOf('/', end + 2);
  if (slash >= 0 && slash < stop) {
    stop = slash;
  }
  const query: number = url.indexOf('?', end + 2);
  if (query >= 0 && query < stop) {
    stop = query;
  }
  const hash: number = url.indexOf('#', end + 2);
  if (hash >= 0 && hash < stop) {
    stop = hash;
  }
  return url.substring(0, stop);
}

/** base 的目录（含末尾 `/`）；查询与片段先丢掉。`origin` 必须是它的来源段。 */
function baseDirectory(base: string, origin: string): string {
  const rest: string = base.substring(origin.length);
  let stop: number = rest.length;
  const query: number = rest.indexOf('?');
  if (query >= 0 && query < stop) {
    stop = query;
  }
  const hash: number = rest.indexOf('#');
  if (hash >= 0 && hash < stop) {
    stop = hash;
  }
  const path: string = rest.substring(0, stop);
  const slash: number = path.lastIndexOf('/');
  if (slash < 0) {
    return origin + '/';
  }
  return origin + path.substring(0, slash + 1);
}

/** RFC 3986 §5.2.4 的去点段；输入是以 `/` 开头的路径。 */
export function removeDotSegments(path: string): string {
  const out: string[] = [];
  let input: string = path;
  while (input.length > 0) {
    if (input.indexOf('../') === 0) {
      input = input.substring(3);
      continue;
    }
    if (input.indexOf('./') === 0) {
      input = input.substring(2);
      continue;
    }
    if (input.indexOf('/./') === 0) {
      input = '/' + input.substring(3);
      continue;
    }
    if (input === '/.') {
      input = '/';
      continue;
    }
    if (input.indexOf('/../') === 0) {
      input = '/' + input.substring(4);
      out.pop();
      continue;
    }
    if (input === '/..') {
      input = '/';
      out.pop();
      continue;
    }
    if (input === '.' || input === '..') {
      break;
    }
    let next: number = input.indexOf('/', 1);
    if (next < 0) {
      next = input.length;
    }
    out.push(input.substring(0, next));
    input = input.substring(next);
  }
  return out.join('');
}

/**
 * 把正文里的相对地址解析到站点地址；注入脚本里的 `resolveSiteUrl` 与它同一套规则。
 *
 * | 输入 | 结果 |
 * | --- | --- |
 * | 带 scheme（`https:` / `data:` / `mailto:` …） | 原样返回 |
 * | `//host/path`（协议相对） | 原样返回，交给浏览器按文档 scheme 解析 |
 * | `#fragment` / 空串 | 原样返回 |
 * | `/path`（根相对） | 站点来源 + `/path` |
 * | `a/b` / `./a` / `../a`（路径相对） | base 的目录 + 相对路径，再去掉点段 |
 *
 * `base` 是**这次请求的响应地址**（公告详情就是带 query 的 `beforeViewXs`）：同一条公告
 * 换一个请求地址会解析到不同目录，这正是相对地址该有的行为。base 不是网络绝对地址时
 * 原样返回——没有可用的站点来源，不猜。
 */
export function resolveNoticeUrl(url: string, base: string): string {
  if (url.length === 0) {
    return url;
  }
  if (schemeEnd(url) > 0) {
    return url;
  }
  if (url.substring(0, 2) === '//' || url.charAt(0) === '#') {
    return url;
  }
  const origin: string = siteOrigin(base);
  if (origin.length === 0) {
    return url;
  }
  let path: string = url;
  let suffix: string = '';
  let cut: number = -1;
  const query: number = url.indexOf('?');
  if (query >= 0) {
    cut = query;
  }
  const hash: number = url.indexOf('#');
  if (hash >= 0 && (cut < 0 || hash < cut)) {
    cut = hash;
  }
  if (cut >= 0) {
    path = url.substring(0, cut);
    suffix = url.substring(cut);
  }
  const combined: string = path.charAt(0) === '/'
    ? origin + path
    : baseDirectory(base, origin) + path;
  return origin + removeDotSegments(combined.substring(origin.length)) + suffix;
}

/**
 * 注入脚本里 `resolveSiteUrl` 一族（与 `resolveNoticeUrl` 同一套规则）。
 * 页面里没有 `URL` 构造器可用，所以这段必须是自足的手写实现；
 * 用模板字符串而不是单引号拼接，是为了和上面的纯函数保持逐行可对照。
 */
const RESOLVE_SITE_URL_SCRIPT: string = `
function schemeEnd(url) {
  if (!url || url.length === 0) { return 0; }
  var first = url.charCodeAt(0);
  if (!((first >= 65 && first <= 90) || (first >= 97 && first <= 122))) { return 0; }
  for (var i = 1; i < url.length; i++) {
    var code = url.charCodeAt(i);
    var ch = url.charAt(i);
    var isAlpha = (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
    var isDigit = code >= 48 && code <= 57;
    if (isAlpha || isDigit || ch === "+" || ch === "-" || ch === ".") { continue; }
    return ch === ":" ? i + 1 : 0;
  }
  return 0;
}
function siteOrigin(url) {
  var end = schemeEnd(url);
  if (end === 0 || url.substring(end, end + 2) !== "//") { return ""; }
  var stop = url.length;
  var slash = url.indexOf("/", end + 2);
  if (slash >= 0 && slash < stop) { stop = slash; }
  var query = url.indexOf("?", end + 2);
  if (query >= 0 && query < stop) { stop = query; }
  var hash = url.indexOf("#", end + 2);
  if (hash >= 0 && hash < stop) { stop = hash; }
  return url.substring(0, stop);
}
function baseDirectory(base, origin) {
  var rest = base.substring(origin.length);
  var stop = rest.length;
  var query = rest.indexOf("?");
  if (query >= 0 && query < stop) { stop = query; }
  var hash = rest.indexOf("#");
  if (hash >= 0 && hash < stop) { stop = hash; }
  var path = rest.substring(0, stop);
  var slash = path.lastIndexOf("/");
  if (slash < 0) { return origin + "/"; }
  return origin + path.substring(0, slash + 1);
}
function removeDotSegments(path) {
  var out = [];
  var input = path;
  while (input.length > 0) {
    if (input.indexOf("../") === 0) { input = input.substring(3); continue; }
    if (input.indexOf("./") === 0) { input = input.substring(2); continue; }
    if (input.indexOf("/./") === 0) { input = "/" + input.substring(3); continue; }
    if (input === "/.") { input = "/"; continue; }
    if (input.indexOf("/../") === 0) { input = "/" + input.substring(4); out.pop(); continue; }
    if (input === "/..") { input = "/"; out.pop(); continue; }
    if (input === "." || input === "..") { break; }
    var next = input.indexOf("/", 1);
    if (next < 0) { next = input.length; }
    out.push(input.substring(0, next));
    input = input.substring(next);
  }
  return out.join("");
}
function resolveSiteUrl(url, base) {
  if (!url) { return url; }
  if (schemeEnd(url) > 0) { return url; }
  if (url.substring(0, 2) === "//" || url.charAt(0) === "#") { return url; }
  var origin = siteOrigin(base);
  if (!origin) { return url; }
  var path = url;
  var suffix = "";
  var cut = -1;
  var query = url.indexOf("?");
  if (query >= 0) { cut = query; }
  var hash = url.indexOf("#");
  if (hash >= 0 && (cut < 0 || hash < cut)) { cut = hash; }
  if (cut >= 0) { path = url.substring(0, cut); suffix = url.substring(cut); }
  var combined = path.charAt(0) === "/" ? origin + path : baseDirectory(base, origin) + path;
  return origin + removeDotSegments(combined.substring(origin.length)) + suffix;
}
`;

/**
 * 链接重写注入脚本：**先**把相对地址解析到站点地址（`resolveSiteUrl`），**再**按原有条件
 * 与追加方式补 `_csrf`（`addCSRFTokenToUrl`）。两件事条件彼此独立：解析只认「有没有
 * scheme」，追加只认「hostname 是否 tsinghua.edu.cn」。
 *
 * `token` / `learnUrl` / `baseUrl` 都过 jsStringLiteral，于是里面的引号、反斜杠不能逃逸出
 * 字面量。`baseUrl` 是这次请求的响应地址（由调用方从公告记录推导），不是合成路径。
 */
export function buildCsrfScript(token: string, learnUrl: string, baseUrl: string): string {
  return RESOLVE_SITE_URL_SCRIPT
    + 'function addCSRFTokenToUrl(url, token) {\n'
    + '  var fragment = "";\n'
    + '  var raw = String(url);\n'
    + '  var hashIndex = raw.indexOf("#");\n'
    + '  if (hashIndex >= 0) {\n'
    + '    fragment = raw.substring(hashIndex);\n'
    + '    raw = raw.substring(0, hashIndex);\n'
    + '  }\n'
    + '  if (!/^[a-zA-Z][a-zA-Z0-9+.\\-]*:\\/\\//.test(raw)) {\n'
    + '    return url;\n'
    + '  }\n'
    + '  var prefix = ' + jsStringLiteral(learnUrl) + ';\n'
    + '  if (prefix.length > 0 && raw.indexOf(prefix) === 0) {\n'
    + '    raw = raw.substring(prefix.length);\n'
    + '  }\n'
    + '  var slash = raw.indexOf("/");\n'
    + '  var authority = slash >= 0 ? raw.substring(0, slash) : raw;\n'
    + '  var path = slash >= 0 ? raw.substring(slash) : "/";\n'
    + '  var at = authority.lastIndexOf("@");\n'
    + '  if (at >= 0) {\n'
    + '    authority = authority.substring(at + 1);\n'
    + '  }\n'
    + '  var colon = authority.lastIndexOf(":");\n'
    + '  var hostname = colon >= 0 ? authority.substring(0, colon) : authority;\n'
    + '  var shouldAppend = hostname.length === 0;\n'
    + '  if (!shouldAppend) {\n'
    + '    var suffix = "tsinghua.edu.cn";\n'
    + '    shouldAppend = hostname === suffix\n'
    + '      || hostname.substring(hostname.length - suffix.length - 1) === "." + suffix;\n'
    + '  }\n'
    + '  if (!shouldAppend) {\n'
    + '    return url;\n'
    + '  }\n'
    + '  var query = path.indexOf("?");\n'
    + '  var addition = "_csrf=" + encodeURIComponent(token);\n'
    + '  if (query < 0) {\n'
    + '    path = path + "?" + addition;\n'
    + '  } else {\n'
    + '    path = path + "&" + addition;\n'
    + '  }\n'
    + '  return authority + path + fragment;\n'
    + '}\n'
    + 'var csrfToken = ' + jsStringLiteral(token) + ';\n'
    + 'var learnOhBase = ' + jsStringLiteral(baseUrl) + ';\n'
    + 'document.addEventListener("DOMContentLoaded", function () {\n'
    + '  var nodes = document.querySelectorAll("[href]");\n'
    + '  for (var i = 0; i < nodes.length; i++) {\n'
    + '    var element = nodes[i];\n'
    + '    var url = element.getAttribute("href");\n'
    + '    if (url) {\n'
    + '      element.setAttribute("href", addCSRFTokenToUrl(resolveSiteUrl(url, learnOhBase), csrfToken));\n'
    + '    }\n'
    + '  }\n'
    + '  var sources = document.querySelectorAll("[src]");\n'
    + '  for (var j = 0; j < sources.length; j++) {\n'
    + '    var node = sources[j];\n'
    + '    var src = node.getAttribute("src");\n'
    + '    if (src) {\n'
    + '      node.setAttribute("src", addCSRFTokenToUrl(resolveSiteUrl(src, learnOhBase), csrfToken));\n'
    + '    }\n'
    + '  }\n'
    + '});\n';
}

/** 模板骨架：与参考实现的字符串逐段对应，资产处留注释占位符。 */
function templateShell(content: string, darkMode: boolean, backgroundColor: string): string {
  const darkSection: string = darkMode
    ? '\n      <script>\n        ' + TOKEN_DARK + '\n      </script>\n'
      + '      <script>\n        DarkReader.enable({\n'
      + '          darkSchemeBackgroundColor: ' + jsStringLiteral(backgroundColor) + '\n'
      + '        });\n      </script>\n      '
    : '';
  return '\n'
    + '  <!DOCTYPE html>\n'
    + '  <html lang="zh-cmn-Hans">\n'
    + '    <head>\n'
    + '      <meta charset="utf-8" />\n'
    + '      <meta name="viewport" content="width=device-width, initial-scale=1" />\n'
    + '      <meta http-equiv="Content-Security-Policy" content="upgrade-insecure-requests" />\n'
    + '      <style>\n'
    + '        body {\n'
    + '          margin: 0px;\n'
    + '          padding: 1rem;\n'
    + '        }\n'
    + '        #root {\n'
    + '          height: 100%;\n'
    + '          width: 100%;\n'
    + '          overflow: auto;\n'
    + '        }\n'
    + '        #root > p:first-child {\n'
    + '          margin-top: 0px;\n'
    + '        }\n'
    + '        #root > p:last-child {\n'
    + '          margin-bottom: 0px;\n'
    + '        }\n'
    + '      </style>\n'
    + '      <style>\n'
    + '        ' + TOKEN_HEAD + '\n'
    + '      </style>\n'
    + '      <script>\n'
    + '        ' + '{{csrf}}' + '\n'
    + '      </script>\n'
    + darkSection
    + '      <script>\n'
    + '        ' + TOKEN_KATEX + '\n'
    + '      </script>\n'
    + '    </head>\n'
    + '    <body>\n'
    + '      <div id="root">\n'
    + '        ' + content + '\n'
    + '      </div>\n'
    + '      <script>\n'
    + '        renderMathInElement(document.querySelector("#root"), {\n'
    + '          throwOnError: false\n'
    + '        });\n'
    + '      </script>\n'
    + '    </body>\n'
    + '  </html>\n';
}

/** HTML 注释：`<!--(.*?)-->`（非贪婪，不跨注释；参考实现用正则，这里手写以避开 RegExp 结构类型）。 */
function stripHtmlComments(html: string): string {
  let out: string = '';
  let cursor: number = 0;
  while (cursor < html.length) {
    const start: number = html.indexOf('<!--', cursor);
    if (start < 0) {
      out += html.substring(cursor);
      break;
    }
    out += html.substring(cursor, start);
    const end: number = html.indexOf('-->', start + 4);
    if (end < 0) {
      // 注释没闭合：参考实现的 `<!--(.*?)-->` 匹配不到 ⇒ **整段保留**。照做。
      out += html.substring(start);
      break;
    }
    cursor = end + 3;
  }
  return out;
}

/**
 * 去掉 HTML 标签：`<...>`，**允许标签里含换行**（参考实现的正则是 `/<(?:.|\n)*?>/gm`）。
 * 遇到没闭合的 `<` 时原样保留（参考实现同样匹配不到）。
 */
function stripHtmlTags(html: string): string {
  let out: string = '';
  let cursor: number = 0;
  while (cursor < html.length) {
    const start: number = html.indexOf('<', cursor);
    if (start < 0) {
      out += html.substring(cursor);
      break;
    }
    out += html.substring(cursor, start);
    const end: number = html.indexOf('>', start + 1);
    if (end < 0) {
      out += html.substring(start);
      break;
    }
    cursor = end + 1;
  }
  return out;
}

/** 折叠连续空白（两个及以上）成单个空格（参考实现 `/\s\s+/g` → ' '）。 */
function collapseWhitespace(text: string): string {
  let out: string = '';
  let pendingSpace: boolean = false;
  for (let i = 0; i < text.length; i++) {
    const ch: string = text.charAt(i);
    const code: number = text.charCodeAt(i);
    const isSpace: boolean = code === 32 || code === 9 || code === 10 || code === 13
      || code === 12 || code === 11 || code === 0x00A0;
    if (isSpace) {
      pendingSpace = true;
      continue;
    }
    if (pendingSpace && out.length > 0) {
      out += ' ';
    }
    pendingSpace = false;
    out += ch;
  }
  return out;
}

/**
 * `removeTags` —— 参考实现 `reference/learnOH-old/src/helpers/html.ts:11-22` 的等价物。
 *
 * 依次做四件事（顺序与参考实现逐条一致）：
 *   1. 去 HTML 注释 `<!--...-->`；
 *   2. 去标签 `<...>`（允许跨行）；
 *   3. **实体解码**（`he.decode` 等价物，含 `&#39;` / `&#x27;` 数字实体，见 domain/parse/Text）；
 *   4. 折叠连续空白并 `trim`。
 *
 * **渲染层是"解码"的**：解析层刻意不解码，解码推迟到这里。
 * 公告卡片用它渲染**标题与正文预览**（NoticeCard.tsx:42,72）。
 * 解析或解码出错时返回空串（参考实现的 `catch { return '' }`）。
 */
export function removeTags(html: string | undefined): string {
  if (html === undefined || html === null || html.length === 0) {
    return '';
  }
  try {
    const withoutComments: string = stripHtmlComments(html);
    const withoutTags: string = stripHtmlTags(withoutComments);
    const decoded: string = decodeAllEntities(withoutTags);
    return collapseWhitespace(decoded).trim();
  } catch (error) {
    return '';
  }
}

/** 一次性替换全部出现（ArkTS 的 String.replace 只换第一处，故用 split/join）。 */
export function replaceAllLiteral(text: string, from: string, to: string): string {
  if (from.length === 0) {
    return text;
  }
  return text.split(from).join(to);
}

/**
 * 生成内联 HTML 模板（对应参考实现 `getWebViewTemplate`）。
 *
 * @param content 公告正文 HTML（调用方已做空正文兜底，见 buildNoticeContent）
 * @param darkMode 是否深色：**只**决定 DarkReader 段是否注入，不改其它结构
 * @param backgroundColor DarkReader 的 `darkSchemeBackgroundColor`（surface 色）
 * @param csrfToken CSRF 令牌（会话态；Mock 下为空串）
 * @param learnUrl learn 站点前缀，用来把绝对 URL 还原成 "//host/path" 形态
 * @param baseUrl 这次请求的响应地址：相对链接 / 图片按它解析到站点地址
 * @param assets 外部资产（katex 样式与脚本、可选 darkreader）
 */
export function getWebViewTemplate(
  content: string,
  darkMode: boolean,
  backgroundColor: string,
  csrfToken: string,
  learnUrl: string,
  baseUrl: string,
  assets: TemplateAssets
): string {
  let out: string = templateShell(content, darkMode, sanitizeColor(backgroundColor));
  out = replaceAllLiteral(out, TOKEN_HEAD, assets.katexStyles);
  out = replaceAllLiteral(out, TOKEN_KATEX, assets.katexScript);
  if (darkMode) {
    out = replaceAllLiteral(out, TOKEN_DARK, assets.darkReaderScript === undefined ? '' : assets.darkReaderScript);
  }
  out = replaceAllLiteral(out, '{{csrf}}', buildCsrfScript(csrfToken, learnUrl, baseUrl));
  return out;
}
