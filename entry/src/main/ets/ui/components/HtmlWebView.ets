/*
 * 公告正文的 Web 容器（公告详情 / 作业详情… 共用）。
 *
 * 对应参考实现 `reference/learnOH-old/src/components/AutoHeightWebView.tsx`，
 * 两条桥都重新设计过（RN 的桥在 ArkWeb 上不存在）。
 *
 * ## 1. 测高（内容高度自适应、无内部滚动条）
 *
 * 参考实现（:24-48）注入脚本取
 * `max(documentElement.clientHeight, documentElement.scrollHeight, body.clientHeight, body.scrollHeight)`
 * 经 `window.ReactNativeWebView.postMessage` 回传，原生侧 `setHeight`。
 *
 * ArkWeb 没有 `postMessage` 端口，因此：
 *   - 测高脚本换成 domain/render/WebViewTemplate.MEASURE_SCRIPT（同一 max 公式，另纳入
 *     `#root.scrollHeight`，理由见该文件注释），经 `javaScriptProxy` 注册的
 *     `window.learnOHBridge.onHeight` 回传；
 *   - 注入脚本尾部还有一段**桥自证**（把 `typeof window.learnOHBridge` 与它的方法名经桥写进
 *     hilog）。没有这条正向证据时，"高度没回传"分不清是桥没注入、脚本没跑、还是量出来是 0 ——
 *     设备上正是靠它定位到"脚本压根没被注入"（AGENTS.md 取证要求）；
 *   - 首次 `onLoadFinished` 后原生侧再轮询几次 `window.learnOHMeasure()`：KaTeX 字体从
 *     CDN 到达后重排、图片解码完成都会改变高度，而 RN 的 `load` 一次性回调没有这个问题
 *     的对应物（参考实现在 load 时测一次就定死，容器高度靠 RN 的 WebView 自身行为兜底）；
 *   - **只有外层 Scroll 滚动**：Web 组件高度 = 测到的内容高度，内部不留滚动条。
 *
 * ## 2. cookie / CSRF 端口
 *
 * 参考实现（:57-71,90-92）从 `CookieManager.get(Urls.learn)` 与 `dataSource.getCSRFToken()`
 * 取值，写进请求头与模板。本工程没有这两个全局单例，会话由 `SessionHeaderProvider`
 * （core/web/SessionHeaderProvider.ets，**只在内存**）提供：CSRF 令牌进模板；cookie 则由本
 * 组件逐条写进**容器的** cookie 存储（见 syncSessionCookies）——容器与应用 HTTP 栈是两套
 * 互不相通的存储，正文里的子资源（图片）要带着同一个会话才会被站点鉴权。
 * 打开容器时把**实际生效值**（写入条数、容器存储里读回的条数与名字、令牌是否存在）打进 hilog。
 *
 * ## 3. 链接（行为明确 = 外部打开）
 *
 * 参考实现（:50-55）`onNavigationStateChange` 里 `navigationType === 'click'` →
 * `stopLoading()` + `Linking.openURL(url)`，`originWhitelist: ['*']`。
 * 即正文里**所有**链接都跳系统浏览器，不在容器内导航。ArkWeb 的等价勾子是
 * `onLoadIntercept`：主框架请求一旦在**首次加载完成之后**发起（= 用户点击链接，
 * 或链接自己触发导航），就 `startAbility` 打开系统浏览器并 `return true` 中止容器内导航。
 */
import { common } from '@kit.AbilityKit';
import { openExternalUrl } from './ExternalLink';
import { resourceManager } from '@kit.LocalizationKit';
import { webview } from '@kit.ArkWeb';
import { Logger } from '../../core/log/Logger';
import { resolveTheme } from '../theme/Tokens';
import { LEARN_URL, SessionHeaderProvider } from '../../core/web/SessionHeaderProvider';
import { CookiePair, parseCookieHeaderPairs } from '../../core/http/CookieJar';
import { buildWebCookieWrites, WebCookieWrite } from '../../core/web/WebSessionCookie';
import {
  DARK_READER_FILE, KATEX_AUTO_RENDER_FILE, KATEX_SCRIPT_FILE, KATEX_STYLES_FILE, WEB_ASSET_DIR, readRawFileText
} from '../../core/web/WebPageAssets';
import { MEASURE_SCRIPT, TemplateAssets, getWebViewTemplate } from '../../domain/render/WebViewTemplate';

const logger: Logger = new Logger('ui.webview');

/** 加载完成后原生侧再催测高几次（覆盖 KaTeX 字体/图片到达后的重排）。 */
const MEASURE_ATTEMPTS: number = 8;
const MEASURE_ATTEMPT_INTERVAL_MILLIS: number = 400;

/**
 * 取证开关：加载完成后在页面里量一次**深色是否真的生效**，并把结果经桥写进 hilog。
 *
 * 为什么需要它："深浅色下正文对比度均可读"这条要求里，"没变深"有两种可能——
 * DarkReader 没生效，或模板的 dark 分支没进去。只看截图分不出来，所以把页面侧的
 * 三个事实（DarkReader 是否定义/是否 enabled、body 的计算背景色、模板 dark 段是否在 DOM 里）
 * 打进我们自己的日志。**提交态 false**（它的实际生效值同时会被记一条日志，自证开关状态）。
 */
const EVIDENCE_THEME_AUDIT: boolean = false;

/** 注入桥的对象名；必须与 MEASURE_SCRIPT 里的 `window.learnOHBridge` 一致。 */
const BRIDGE_NAME: string = 'learnOHBridge';

/**
 * 覆盖 `#root` 的 `height:100%`。
 *
 * 参考实现的模板给 `#root` 写 `height:100%`（html.ts:44-48），在 RN 的 WebView 里
 * 那是"填满容器"的意思。这里容器高度**由内容决定**，若保留 100% 就成了循环依赖：
 * `#root` 永远等于视口高，一旦内容更高就出现内部滚动条（不允许），
 * 且 `scrollHeight` 会随原生设高而同步增长（每帧 +1，越量越高）。故让它回到
 * `height:auto`（内容撑开），`overflow` 也不再需要 `auto`。
 * 样式插在 katex 样式**之后**，`!important` 保证不被覆盖。
 */
const ROOT_STYLE_OVERRIDE: string = '\n/* learnOH: #root 高度由内容决定（见同目录 HtmlWebView.ets 的 ROOT_STYLE_OVERRIDE 注释） */\n'
  + '#root { height: auto !important; overflow: visible !important; }\n';

/** 给注入脚本尾部追加的桥自证（正向证据：桥确实被注入）。 */
const BRIDGE_PROBE: string = '\n'
  + 'try {\n'
  + '  var learnOhType = typeof window.' + BRIDGE_NAME + ';\n'
  + '  var learnOhKeys = "";\n'
  + '  try { learnOhKeys = Object.keys(window.' + BRIDGE_NAME + ').join(","); } catch (learnOhKeyError) {}\n'
  + '  window.' + BRIDGE_NAME + '.log("bridge=" + learnOhType + " keys=" + learnOhKeys);\n'
  + '} catch (learnOhProbeError) {\n'
  + '  document.title = "P=" + learnOhProbeError;\n'
  + '}\n';

/**
 * 测高探针：在页面里现场算一遍同一个 `max(...)` 并把结果**作为 runJavaScript 的返回值**
 * 送回原生。返回值是一段 `k=v;k=v` 文本（不依赖 javaScriptProxy，也不依赖 console 通道），
 * 于是它同时回答三个问题：文档解析到哪一步、桥在不在、量到多少。
 */
/**
 * 注入脚本（文档开始加载时执行，`javaScriptOnDocumentStart` 的 `scriptRules: ['*']`）。
 *
 * **为什么必须显式注入**：参考实现把这段脚本交给 RN 的
 * `injectedJavaScriptBeforeContentLoaded`（AutoHeightWebView.tsx:76），ArkWeb 的等价物
 * 就是 `javaScriptOnDocumentStart`。不注入的话模板里根本没有执行它的地方，测高与桥自证
 * 都不会发生（这一点在设备上踩过：只看到"高度没回传"，分不清是桥坏还是脚本没跑）。
 */
export const INJECTED_SCRIPTS: ScriptItem[] = [
  { script: MEASURE_SCRIPT + BRIDGE_PROBE, scriptRules: ['*'] }
];

/**
 * 页面 → 原生的桥。方法名必须出现在 `javaScriptProxy.methodList` 里。
 * 方法体只把调用转发给组件（ArkUI 要求注册对象是 class 实例）。
 */
class LearnOhWebBridge {
  private readonly forward: (method: string, payload: string) => void;

  constructor(forward: (method: string, payload: string) => void) {
    this.forward = forward;
  }

  onHeight(payload: string): void {
    this.forward('onHeight', payload);
  }

  onExternalLink(payload: string): void {
    this.forward('onExternalLink', payload);
  }

  log(payload: string): void {
    this.forward('log', payload);
  }
}

/*
 * 打开外部链接的 `openExternalUrl` 已搬到 `ui/components/ExternalLink.ets`：
 * 设置页 / 帮助页 / 关于页要的是同一件事，实现只留一份。
 */

@Component
export struct HtmlWebView {
  /** 正文 HTML（未做空正文兜底；本组件按 emptyText 兜底，对齐 NoticeDetail.tsx:54）。 */
  @Prop content: string = '';
  /** 空正文时显示的文案（`loh_no_notice_content` = 无通知内容）。 */
  @Prop emptyText: string = '';
  /**
   * 深色标志。**带 @Watch**：深浅色变化时必须重新送入模板——见 onThemeChanged 的注释。
   */
  @Prop @Watch('onThemeChanged') isDark: boolean = false;
  // 底色**不再作为 @Prop 传入**：它与 isDark 必须同源。实测教训是 ArkUI 里
  // `@Prop isDark` 的 @Watch 可能早于同批的其它 @Prop 赋值触发，于是"深色标志已更新、
  // 底色还是浅色"，DarkReader 拿到浅底色 → 深色文字配浅底不可读。
  // 现在两者都由 isDark 推导（见 surfaceColor()），不存在不一致的窗口。
  /** 会话注入端口（features 注入；Mock 阶段是空实现）。 */
  session: SessionHeaderProvider | null = null;
  /**
   * 正文所属页面的地址（**这次请求的响应地址**，公告详情就是带 query 的 `beforeViewXs`）。
   * 正文里的相对链接 / 图片按它解析到站点地址；空串时回落到 learn 站点根——
   * 相对地址总要有一个基准，没有基准就只能原样交给浏览器（多半解析不到站点上）。
   */
  @Prop baseUrl: string = '';

  /** 测到的内容高度（CSS px，当 vp 用；换算式见 HtmlWebView 的测高说明）。 */
  @State measuredHeight: number = 0;

  private loaded: boolean = false;
  private attemptsLeft: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: LearnOhWebBridge = new LearnOhWebBridge((method: string, payload: string): void => {
    this.onBridgeCall(method, payload);
  });
  private assets: TemplateAssets = { katexStyles: '', katexScript: '', darkReaderScript: '' };
  private assetsLoaded: boolean = false;
  /** 最近一次生成的 HTML 长度（只进日志；正文本身不写日志）。 */
  private htmlChars: number = 0;

  aboutToAppear(): void {
    try {
      webview.WebviewController.initializeWebEngine();
    } catch (error) {
      logger.warn('initializeWebEngine failed: ' + (error as Error).message);
    }
  }

  /** 四份 rawfile 资产读一次（对应参考实现的 preval 内联，只是改到运行时）。 */
  private loadAssetsOnce(): void {
    if (this.assetsLoaded) {
      return;
    }
    this.assetsLoaded = true;
    let manager: resourceManager.ResourceManager | null = null;
    try {
      const context: common.Context = getContext(this) as common.Context;
      manager = context.resourceManager;
    } catch (error) {
      logger.error('no host context for rawfile assets: ' + (error as Error).message);
      return;
    }
    const base: string = WEB_ASSET_DIR + '/';
    const styles: string = readRawFileText(manager, base + KATEX_STYLES_FILE) + ROOT_STYLE_OVERRIDE;
    const script: string = readRawFileText(manager, base + KATEX_SCRIPT_FILE)
      + '\n' + readRawFileText(manager, base + KATEX_AUTO_RENDER_FILE);
    const darkReader: string = readRawFileText(manager, base + DARK_READER_FILE);
    this.assets = { katexStyles: styles, katexScript: script, darkReaderScript: darkReader };
    logger.info('web assets loaded: katexStyles=' + styles.length.toString()
      + ' katexScript=' + script.length.toString()
      + ' darkReader=' + darkReader.length.toString()
      + ' dark=' + this.isDark.toString());
  }

  /** 容器底色：与 isDark 同源（深色取 DARK_COLORS.surface，浅色取 LIGHT_COLORS.surface）。 */
  private surfaceColor(): string {
    return resolveTheme(this.isDark).colors.surface;
  }

  /** 生效的基础地址：`baseUrl` 空时回落站点根，`loadData` 与注入脚本**取同一个值**。 */
  private effectiveBaseUrl(): string {
    const trimmed: string = this.baseUrl.trim();
    return trimmed.length > 0 ? trimmed : LEARN_URL + '/';
  }

  private buildHtml(): string {
    this.loadAssetsOnce();
    const body: string = this.content.trim().length > 0 ? this.content : '<p>' + this.emptyText + '</p>';
    const token: string = this.session === null ? '' : this.session.csrfToken();
    const html: string = getWebViewTemplate(body, this.isDark, this.surfaceColor(), token, LEARN_URL,
      this.effectiveBaseUrl(), this.assets);
    this.htmlChars = html.length;
    return html;
  }

  /** 桥的每一次调用都落在这里。 */
  private onBridgeCall(method: string, payload: string): void {
    if (method === 'onHeight') {
      this.applyMeasuredHeight(payload, 'bridge');
      return;
    }
    if (method === 'onExternalLink') {
      openExternalUrl(payload);
      return;
    }
    logger.info('page log: ' + payload);
  }

  private applyMeasuredHeight(payload: string, source: string): void {
    const value: number = Number.parseInt(payload, 10);
    if (Number.isNaN(value) || value <= 0 || value === this.measuredHeight) {
      return;
    }
    this.measuredHeight = value;
    logger.info('content height: ' + value.toString() + ' source=' + source);
  }

  /**
   * 送入正文模板（`loadData` + `baseUrl`，对齐参考实现的 `source={{html, baseUrl}}`）。
   *
   * 设备上实测过的三条路（都留了日志，便于复核）：
   *   1. `loadData` 不带 baseUrl：桥**可用**，但文档是 opaque origin，`new URL()` 不可用；
   *   2. `loadUrl('file://…')` 写进 cacheDir：ArkWeb 直接 `ERR_ACCESS_DENIED`
   *      （应用沙箱文件路径默认不允许被 Web 加载），页面白屏；
   *   3. `loadData` + baseUrl（本实现）：桥可用，且文档按该地址解析相对链接。
   *      baseUrl 取**这次请求的响应地址**（公告记录里的 url）：相对地址落在站点上的
   *      真实目录里，而不是某个合成路径下的目录。
   *
   * 注意 `javaScriptProxy` 与"文档开始注入脚本"是两件事：桥对象注入后，**必须**有
   * `javaScriptOnDocumentStart`（见 INJECTED_SCRIPTS）把测高脚本放进页面，
   * 否则不会有人调用桥。这条也是实测踩出来的。
   */
  /**
   * 深浅色变化 → 重新送入模板。
   *
   * **这是实测抓出来的缺陷**：`loadData` 只在 `onControllerAttached` 里调用一次，改
   * `@Prop isDark` 不会让 ArkWeb 重新加载（控制器已附着，`src` 也没变），于是控制条显示
   * `dark=true`、正文却仍是浅色——"切换后正文即时更新"因此不成立。
   * 修法就是在标志变化时自己再送一次（同时把 `loaded` 归位，见 loadHtmlFromCache）。
   */
  onThemeChanged(): void {
    if (!this.loaded) {
      // 首次加载还没完成时不用重入：onControllerAttached 会带着最新标志送一次。
      logger.info('theme changed before first load: native.isDark=' + this.isDark.toString());
      return;
    }
    logger.info('theme changed -> reload content: native.isDark=' + this.isDark.toString());
    this.loadHtmlFromCache();
  }

  private loadHtmlFromCache(): void {
    this.syncSessionCookies();
    const html: string = this.buildHtml();
    const baseUrl: string = this.effectiveBaseUrl();
    // 归位：onLoadIntercept 用 `loaded` 区分"首次加载"与"用户点链接"，
    // 重送模板时主框架请求会被当成点击而被外部打开（实测风险），所以必须先置 false。
    this.loaded = false;
    try {
      // baseUrl + historyUrl 都给：baseUrl 让文档有站点来源，historyUrl 让相对链接解析
      // 按**这次请求的响应地址**来（参考实现给的是站点根 `Urls.learn`，这里更精确：
      // 公告正文的相对图片是相对它自己那一页的目录）。两者取同一个值，
      // 与注入脚本里 `learnOhBase` 用的也是它——不让「文档基准」与「脚本基准」有机会不一致。
      this.controller.loadData(html, 'text/html', 'UTF-8', baseUrl, baseUrl);
      logger.info('loadData issued: htmlChars=' + html.length.toString() + ' baseUrl=' + baseUrl);
    } catch (error) {
      logger.error('loadData failed: ' + (error as Error).message);
    }
  }

  /**
   * 把应用内存会话写进**本容器的** cookie 存储。
   *
   * 为什么必须有这一步：容器里的 cookie 存储与应用 HTTP 栈互不相通。正文里的图片是 learn
   * 源上的子资源，由 ArkWeb 自己发请求；不写会话时它带着空/过期会话发出，服务端 302 到
   * 登录超时页，<img> 于是 naturalWidth=0（设备实测：complete=true、nat=0x0，同一 URL 的
   * 页面内 XHR 落在 /f/login_timeout、返回 text/html）。
   *
   * 只写 learn 源（LEARN_URL）：外部 CDN 的 katex / darkreader 不受影响。写入用
   * incognito=true + includeHttpOnly=true（见 core/web/WebSessionCookie.ets），会话只进内存态
   * 存储，不落盘（ADR-0004）。
   *
   * 先清空内存态存储再写：会话变化（重登）时同名 cookie 被覆盖，旧会话里独有的名字也不会
   * 残留；登出后 session 为空串 ⇒ 一条都不写，容器不再持有可用会话。
   *
   * 日志只打条数、名字与值长度 —— cookie 值是会话凭证，绝不进日志。
   */
  private syncSessionCookies(): void {
    const url: string = LEARN_URL;
    const header: string = this.session === null ? '' : this.session.cookieHeader();
    const writes: WebCookieWrite[] = buildWebCookieWrites(header, url);
    // 自证写入前的真实状态：新进程的第一次挂载即"重启后 ArkWeb 里没有残留会话"的判据。
    logger.info('web cookie sync: incognitoBefore=' + this.describeCookieStore(url, true)
      + ' persistentBefore=' + this.describeCookieStore(url, false)
      + ' sessionEntries=' + writes.length.toString());
    try {
      webview.WebCookieManager.clearAllCookiesSync(true);
    } catch (error) {
      logger.warn('clearAllCookiesSync(incognito) failed: ' + (error as Error).message);
    }
    if (writes.length === 0) {
      logger.info('web cookie sync: no session -> incognito store left empty');
      return;
    }
    let failed: number = 0;
    for (let i = 0; i < writes.length; i++) {
      const write: WebCookieWrite = writes[i];
      try {
        webview.WebCookieManager.configCookieSync(write.url, write.value, write.incognito, write.includeHttpOnly);
      } catch (error) {
        // 不静默：写入失败必须能从日志里看出来（名字与长度，不含值）。
        failed++;
        logger.error('configCookieSync failed: name=' + write.name
          + ' valueChars=' + write.valueChars.toString() + ' ' + (error as Error).message);
      }
    }
    logger.info('web cookie sync done: ok=' + (writes.length - failed).toString()
      + '/' + writes.length.toString() + ' incognitoAfter=' + this.describeCookieStore(url, true));
  }

  /** 读回 cookie 存储的实际内容，**只有条数与名字**（值不进日志）。无 cookie 时返回 none。 */
  private describeCookieStore(url: string, incognito: boolean): string {
    let header: string = '';
    try {
      header = webview.WebCookieManager.fetchCookieSync(url, incognito);
    } catch (error) {
      return 'none';
    }
    const pairs: CookiePair[] = parseCookieHeaderPairs(header);
    if (pairs.length === 0) {
      return 'none';
    }
    const names: string[] = [];
    for (let i = 0; i < pairs.length; i++) {
      names.push(pairs[i].name);
    }
    return 'entries=' + pairs.length.toString() + ' names=[' + names.join(',') + ']';
  }

  /** 高度：测到之前用 1（对齐参考实现的 `useState(1)`）。 */
  private heightVp(): number {
    return this.measuredHeight > 0 ? this.measuredHeight : 1;
  }

  private requestMeasure(): void {
    try {
      this.controller.runJavaScript('if (window.learnOHMeasure) { window.learnOHMeasure(); }');
    } catch (error) {
      logger.warn('runJavaScript(measure) failed: ' + (error as Error).message);
    }
  }

  /** 首次加载完成：立刻测一次，并在此后按间隔再测几次（字体/图片重排）。 */
  private handleLoadFinished(): void {
    this.loaded = true;
    // 自证开关状态：否则"没抓到审计行"分不清是开关没开还是没走到这一步。
    logger.info('load finished: native.isDark=' + this.isDark.toString()
      + ' themeAuditSwitch=' + EVIDENCE_THEME_AUDIT.toString());
    this.attemptsLeft = MEASURE_ATTEMPTS;
    this.requestMeasure();
    this.scheduleNextMeasure();
    if (EVIDENCE_THEME_AUDIT) {
      // 等字体/深色注入稳定后再量（DarkReader 是异步改造 DOM 的）。
      setTimeout(() => {
        this.auditTheme();
      }, 2500);
    }
  }

  /**
   * 取证用：把页面侧的深色事实经桥回传（`runJavaScript` 的返回值在设备上恒为 null，
   * 所以只能走桥）。日志里同时带上**原生侧的 isDark**，于是"模板没进 dark 分支"
   * 与"DarkReader 没生效"能区分开。
   */
  private auditTheme(): void {
    const script: string = 'var learnOhParts = [];'
      + 'learnOhParts.push("defined=" + (typeof DarkReader !== "undefined"));'
      + 'try { learnOhParts.push("enabled=" + DarkReader.isEnabled()); }'
      + ' catch (learnOhE1) { learnOhParts.push("enabled=err:" + learnOhE1); }'
      + 'try { learnOhParts.push("bodyBg=" + getComputedStyle(document.body).backgroundColor); }'
      + ' catch (learnOhE2) { learnOhParts.push("bodyBg=err"); }'
      + 'try { learnOhParts.push("bodyColor=" + getComputedStyle(document.body).color); }'
      + ' catch (learnOhE3) { learnOhParts.push("bodyColor=err"); }'
      + 'try { learnOhParts.push("darkCallInDom="'
      + ' + (document.documentElement.innerHTML.indexOf("DarkReader.enable") >= 0)); }'
      + ' catch (learnOhE4) { learnOhParts.push("darkCallInDom=err"); }'
      + 'window.' + BRIDGE_NAME + '.log("theme audit native.isDark=' + this.isDark.toString()
      + ' " + learnOhParts.join(" "));';
    try {
      this.controller.runJavaScript(script);
      logger.info('theme audit requested: native.isDark=' + this.isDark.toString()
        + ' auditSwitch=' + EVIDENCE_THEME_AUDIT.toString());
    } catch (error) {
      logger.warn('theme audit failed: ' + (error as Error).message);
    }
  }

  private scheduleNextMeasure(): void {
    if (this.attemptsLeft <= 0) {
      return;
    }
    this.attemptsLeft--;
    setTimeout(() => {
      this.requestMeasure();
      this.scheduleNextMeasure();
    }, MEASURE_ATTEMPT_INTERVAL_MILLIS);
  }

  /** 主框架请求：首次加载放行；之后（用户点链接）外部打开并中止容器内导航。 */
  private handleIntercept(event: OnLoadInterceptEvent): boolean {
    const url: string = event.data.getRequestUrl();
    if (!this.loaded) {
      logger.info('initial load allowed: ' + url);
      return false;
    }
    logger.info('link click -> external open: ' + url);
    openExternalUrl(url);
    return true;
  }

  build() {
    Column() {
      // incognitoMode(true)：本容器的 cookie 只存在内存、不写持久化文件（见 syncSessionCookies）。
      Web({ src: '', controller: this.controller, incognitoMode: true })
        .javaScriptOnDocumentStart(INJECTED_SCRIPTS)
        .onControllerAttached(() => {
          // 正文用 WebviewController.loadData 送入：WebAttribute.src 只接受
          // string | Resource（web.d.ts:5151），要送字符串 HTML 必须走控制器。
          this.loadHtmlFromCache();

        })
        .javaScriptAccess(true)
        .imageAccess(true)
        .onlineImageAccess(true)
        .domStorageAccess(true)
        .horizontalScrollBarAccess(false)
        .verticalScrollBarAccess(false)
        .javaScriptProxy({
          object: this.bridge,
          name: BRIDGE_NAME,
          methodList: ['onHeight', 'onExternalLink', 'log'],
          controller: this.controller
        })
        .onPageEnd((event: OnPageEndEvent) => {
          logger.info('onPageEnd: url=' + event.url);
        })
        .onErrorReceive((event: OnErrorReceiveEvent) => {
          logger.error('onErrorReceive: ' + event.error.getErrorInfo() + ' url='
            + (event.request === undefined ? '' : event.request.getRequestUrl()));
        })
        .onLoadFinished(() => {
          logger.info('onLoadFinished fired');
          this.handleLoadFinished();
        })
        .onLoadIntercept((event: OnLoadInterceptEvent) => {
          return this.handleIntercept(event);
        })
        .width('100%')
        .height(this.heightVp())
        .backgroundColor(this.surfaceColor())
    }
    .width('100%')
    .height(this.heightVp())
  }
}
