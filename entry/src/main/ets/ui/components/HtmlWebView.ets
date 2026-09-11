/*
 * 公告正文的 Web 容器（公告详情 / 作业详情… 共用）。
 *
 * 对应参考实现 `reference/learnOH-old/src/components/AutoHeightWebView.tsx`，
 * 两条桥都重新设计过（RN 的桥在 ArkWeb 上不存在）。
 *
 * ## 1. 测高（验收第 2 条：内容高度自适应、无内部滚动条）
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
 * 取值，写进请求头与模板。本工程这两个全局单例都不存在，且 **cookie 只在内存、不落盘**
 * （spec 第 4 节 / ADR-0004），因此收敛成 `SessionHeaderProvider` 端口
 * （core/web/SessionHeaderProvider.ets）：Mock 阶段返回空串，ticket 06/09 注入真实值。
 * 打开容器时把**实际生效值**（cookie 条目数 / 令牌是否存在）打进 hilog。
 *
 * ## 3. 链接（验收第 4 条：行为明确 = 外部打开）
 *
 * 参考实现（:50-55）`onNavigationStateChange` 里 `navigationType === 'click'` →
 * `stopLoading()` + `Linking.openURL(url)`，`originWhitelist: ['*']`。
 * 即正文里**所有**链接都跳系统浏览器，不在容器内导航。ArkWeb 的等价勾子是
 * `onLoadIntercept`：主框架请求一旦在**首次加载完成之后**发起（= 用户点击链接，
 * 或链接自己触发导航），就 `startAbility` 打开系统浏览器并 `return true` 中止容器内导航。
 */
import { common, Want } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { webview } from '@kit.ArkWeb';
import { Logger } from '../../core/log/Logger';
import { LEARN_URL, SessionHeaderProvider } from '../../core/web/SessionHeaderProvider';
import {
  DARK_READER_FILE, KATEX_AUTO_RENDER_FILE, KATEX_SCRIPT_FILE, KATEX_STYLES_FILE, WEB_ASSET_DIR, readRawFileText
} from '../../core/web/WebPageAssets';
import { MEASURE_SCRIPT, TemplateAssets, getWebViewTemplate } from '../../domain/render/WebViewTemplate';

const logger: Logger = new Logger('ui.webview');

/** 加载完成后原生侧再催测高几次（覆盖 KaTeX 字体/图片到达后的重排）。 */
const MEASURE_ATTEMPTS: number = 8;
const MEASURE_ATTEMPT_INTERVAL_MILLIS: number = 400;

/** 注入桥的对象名；必须与 MEASURE_SCRIPT 里的 `window.learnOHBridge` 一致。 */
const BRIDGE_NAME: string = 'learnOHBridge';

/**
 * 覆盖 `#root` 的 `height:100%`。
 *
 * 参考实现的模板给 `#root` 写 `height:100%`（html.ts:44-48），在 RN 的 WebView 里
 * 那是"填满容器"的意思。这里容器高度**由内容决定**，若保留 100% 就成了循环依赖：
 * `#root` 永远等于视口高，一旦内容更高就出现内部滚动条（验收第 2 条不允许），
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

/** 打开系统浏览器（参考实现 `Linking.openURL` 的 ArkTS 对应物）。 */
function openExternalUrl(url: string): void {
  if (url.length === 0) {
    return;
  }
  try {
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    };
    // getContext() 的静态类型是 Context，startAbility 在 UIAbilityContext 上；
    // 组件运行在 UIAbility 里，故这里收窄（拿不到就落回 catch，不抛给调用方）。
    const context: common.UIAbilityContext = getContext() as common.UIAbilityContext;
    context.startAbility(want);
    logger.info('external link opened in system browser: ' + url);
  } catch (error) {
    logger.error('open external url failed: ' + url + ' (' + (error as Error).message + ')');
  }
}

@Component
export struct HtmlWebView {
  /** 正文 HTML（未做空正文兜底；本组件按 emptyText 兜底，对齐 NoticeDetail.tsx:54）。 */
  @Prop content: string = '';
  /** 空正文时显示的文案（`loh_no_notice_content` = 无通知内容）。 */
  @Prop emptyText: string = '';
  @Prop isDark: boolean = false;
  @Prop surfaceColor: string = '';
  /** 会话注入端口（features 注入；Mock 阶段是空实现）。 */
  session: SessionHeaderProvider | null = null;

  /** 测到的内容高度（CSS px，当 vp 用；换算式见 ticket 04 Comments）。 */
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

  private buildHtml(): string {
    this.loadAssetsOnce();
    const body: string = this.content.trim().length > 0 ? this.content : '<p>' + this.emptyText + '</p>';
    const token: string = this.session === null ? '' : this.session.csrfToken();
    const html: string = getWebViewTemplate(body, this.isDark, this.surfaceColor, token, LEARN_URL, this.assets);
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
   *   3. `loadData` + baseUrl（本实现）：桥可用，且文档按 learn 站点解析相对链接。
   *
   * 注意 `javaScriptProxy` 与"文档开始注入脚本"是两件事：桥对象注入后，**必须**有
   * `javaScriptOnDocumentStart`（见 INJECTED_SCRIPTS）把测高脚本放进页面，
   * 否则不会有人调用桥。这条也是实测踩出来的。
   */
  private loadHtmlFromCache(): void {
    const html: string = this.buildHtml();
    const baseUrl: string = LEARN_URL + '/learnoh/notice-detail.html';
    try {
      // baseUrl + historyUrl 都给：baseUrl 让文档有 learn 站点的网络来源
      // （参考实现 AutoHeightWebView.tsx:87-89 的 `source.baseUrl = Urls.learn`），
      // historyUrl 让 `new URL()` / 相对链接解析按 learn 站点来（对齐参考实现）。
      this.controller.loadData(html, 'text/html', 'UTF-8', baseUrl, baseUrl);
      logger.info('loadData issued: htmlChars=' + html.length.toString() + ' baseUrl=' + baseUrl);
    } catch (error) {
      logger.error('loadData failed: ' + (error as Error).message);
    }
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
    this.attemptsLeft = MEASURE_ATTEMPTS;
    this.requestMeasure();
    this.scheduleNextMeasure();
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
      Web({ src: '', controller: this.controller })
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
        .backgroundColor(this.surfaceColor)
    }
    .width('100%')
    .height(this.heightVp())
  }
}
