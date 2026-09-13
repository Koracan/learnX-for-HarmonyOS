/*
 * 网页设备登记容器（features/auth）：加载 ID 登录页、注入脚本、识别成功信号、收割会话。
 *
 * 与参考实现（reference/learnOH-old/src/screens/SSO.tsx + helpers/preval/sso.js）的对应：
 *   - 页面地址、注入脚本、roaming URL 判定一致；
 *   - **不一致的地方**（有意，已登记在 ticket Comments）：旧实现拦到 roaming URL 后**取消**导航，
 *     再用 thu-learn-lib 走一次纯 HTTP 登录；本工程按 spec 第 5 节**放行**这段导航，让浏览器把
 *     漫游走完，然后从 Web 引擎收割会话 cookie 交给 HTTP jar（EnrollmentSession）。
 *     这样"用户的短信验证结果"与"应用的会话"是同一个会话，不存在再登一次时服务端又要求
 *     二次验证的不确定性。
 *
 * ArkWeb 的三条实测约束（ticket 04，见 ui/components/HtmlWebView.ets 注释）：
 *   1. `runJavaScript` 的返回值恒为 null ⇒ 页面里的值只能经 `javaScriptProxy` 回传；
 *   2. `javaScriptProxy` 只注入对象、不执行脚本 ⇒ 注入脚本必须另经 `javaScriptOnDocumentStart`；
 *   3. 桥对象必须是 class 实例，方法名要出现在 `methodList` 里。
 *
 * 安全纪律：
 *   - 登录 URL 与漫游 URL 都含票据/查询串，日志只打 host+path（见 pathOf）；
 *   - 指纹只以脱敏形式进日志（域名/长度/布尔）。
 */

import { ConfigurationConstant } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { Logger } from '../../core/log/Logger';
import { CookiePair, parseCookieHeaderPairs } from '../../core/http/CookieJar';
import { i18nService } from '../../core/i18n/I18n';
import { LEARN_URL } from '../../core/web/SessionHeaderProvider';
import { ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { COLOR_MODE_KEY, LOCALE_VERSION_KEY } from '../../entryability/EntryAbility';
import {
  ENROLLMENT_DIAGNOSTICS_FOR_EVIDENCE, EnrollmentDomValues, SAVE_FINGER_PATH, buildEnrollmentScript,
  describeEnrollmentDomValues, emptyDomValues, mergeDomValues, parseEnrollmentValues
} from '../../domain/auth/EnrollmentScript';
import { redactSecret } from '../../domain/auth/DeviceIdentity';
import { fingerprintDigest } from '../../domain/auth/FingerprintDigest';

const logger: Logger = new Logger('features.enrollment');

/** ID 登录表单地址（与 LoginClient.ID_LOGIN_URL 逐字相同，参考实现 urls.js:10）。 */
export const ID_LOGIN_URL: string =
  'https://id.tsinghua.edu.cn/do/off/ui/auth/login/form/bb5df85216504820be7bba2b0ae1535b/0';

/** 成功信号：漫游入口（idp-login-flow.md 第 1 节）。 */
export const ROAMING_MARKER: string = 'j_spring_security_thauth_roaming_entry';

/** 桥对象名（必须与注入脚本里的 BRIDGE 名一致）。 */
export const ENROLLMENT_BRIDGE_NAME: string = 'learnOHEnrollmentBridge';

/** 见到漫游 URL 之后等多久再第一次收割（让 302 链与 Set-Cookie 落地）。 */
const FIRST_HARVEST_DELAY_MILLIS: number = 1500;
/** 收割重试次数与间隔（cookie 可能比 onLoadIntercept 晚一点才可见）。 */
const HARVEST_MAX_ATTEMPTS: number = 6;
const HARVEST_INTERVAL_MILLIS: number = 500;

/** 页面 console 转发的上限（每条再截断 240 字符）。 */
const CONSOLE_LINE_LIMIT: number = 80;

/** host + path（丢掉查询串）：日志里绝不出现票据。 */
export function pathOf(url: string): string {
  let text: string = url;
  const scheme: number = text.indexOf('://');
  if (scheme >= 0) {
    text = text.substring(scheme + 3);
  }
  const cut: number = text.indexOf('?');
  if (cut >= 0) {
    text = text.substring(0, cut);
  }
  const hash: number = text.indexOf('#');
  if (hash >= 0) {
    text = text.substring(0, hash);
  }
  return text;
}

/** 页面 → 原生的桥。方法名必须出现在 javaScriptProxy.methodList 里。 */
class EnrollmentBridge {
  private readonly forward: (method: string, first: string, second: string) => void;

  constructor(forward: (method: string, first: string, second: string) => void) {
    this.forward = forward;
  }

  /** 诊断通道（已脱敏）。 */
  report(kind: string, payload: string): void {
    this.forward('report', kind, payload);
  }

  /** 取值通道（可能是秘密，原生侧只保存不打印）。 */
  values(payload: string): void {
    this.forward('values', payload, '');
  }
}

@Component
export struct EnrollmentWebView {
  // 这三个值由 AuthStore 在"开始登记"时生成，组件挂载时是常量（登记期间不变）。
  username: string = '';
  password: string = '';
  fingerPrint: string = '';
  deviceName: string = '';

  onSucceeded: (dom: EnrollmentDomValues, cookieHeader: string) => void = () => {
  };
  /** 用户主动放弃（点「取消」）。 */
  onCancelled: () => void = () => {
  };
  /** 非预期结果（例如漫游后没收到任何 cookie）：降级回登录页，由调用方处理。 */
  onFailed: (reason: string) => void = () => {
  };
  onStatus: (text: string) => void = () => {
  };

  /** 系统配色与语言版本：登记页也要跟随应用主题与语言（ticket 01/02 的全局约定）。 */
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink(LOCALE_VERSION_KEY) localeVersion: number = 0;

  @State statusText: string = 'loading';
  /** 页面 console 的转发上限（每挂载一次计数）。 */
  private consoleLines: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();
  private scripts: ScriptItem[] = [];
  private dom: EnrollmentDomValues = emptyDomValues();
  private roamingSeen: boolean = false;
  private harvestStarted: boolean = false;
  private settled: boolean = false;
  private bridge: EnrollmentBridge = new EnrollmentBridge((method: string, first: string, second: string): void => {
    this.onBridgeCall(method, first, second);
  });

  aboutToAppear(): void {
    try {
      webview.WebviewController.initializeWebEngine();
    } catch (error) {
      logger.warn('initializeWebEngine failed: ' + (error as Error).message);
    }
    this.scripts = [{
      script: buildEnrollmentScript({
        username: this.username,
        password: this.password,
        fingerPrint: this.fingerPrint,
        deviceName: this.deviceName,
        bridgeName: ENROLLMENT_BRIDGE_NAME,
        // 文案由应用侧提供（i18n），不写死在注入脚本里。
        gateNoticeText: i18nService.t('ui_enrollment_fingerprint_not_ready')
      }),
      scriptRules: ['*']
    }];
    // 登记前把 Web 引擎的 cookie 清干净：残留的会话会让页面以为"已经登录过"。
    this.clearWebCookies('before-enrollment');
    this.publishStatus('prepare');
    logger.info('enrollment webview starting: urlPath=' + pathOf(ID_LOGIN_URL)
      + ' fingerprint=' + redactSecret(this.fingerPrint)
      + ' deviceName=' + this.deviceName
      + ' saveFingerPath=' + SAVE_FINGER_PATH
      + ' injectedChars=' + this.scripts[0].script.length.toString()
      // 取证开关必须自证生效（AGENTS.md）：这一行是"诊断到底开没开"的唯一判据。
      + ' diagnostics=' + ENROLLMENT_DIAGNOSTICS_FOR_EVIDENCE.toString());
  }

  aboutToDisappear(): void {
    // 不论成功/取消，离开登记页都把 Web 引擎的会话清掉：会话只应在内存 jar 里（ADR-0004）。
    this.clearWebCookies('on-disappear');
  }

  private clearWebCookies(when: string): void {
    try {
      webview.WebCookieManager.clearAllCookiesSync();
      logger.info('web cookies cleared: when=' + when);
    } catch (error) {
      logger.warn('clearAllCookiesSync failed: when=' + when + ' ' + (error as Error).message);
    }
  }

  private onBridgeCall(method: string, first: string, second: string): void {
    if (method === 'values') {
      this.dom = mergeDomValues(this.dom, parseEnrollmentValues(first));
      logger.info('enrollment dom values: ' + describeEnrollmentDomValues(this.dom));
      // 验收第 2 条的**三点等式**的前两点（第三点在 AuthStore 落盘读回后打）：
      // 只打 SHA256 前 8 位，原值绝不进日志。
      logger.info('enrollment fingerprint digest: point=formFieldDom value=' + fingerprintDigest(this.dom.fingerPrint)
        + ' point=saveFingerXhr value=' + fingerprintDigest(this.dom.saveFingerFingerprint));
      this.publishStatus('page');
      return;
    }
    // report：kind + 已脱敏的 payload
    logger.info('enrollment page report [' + first + '] ' + second);
    if (first === 'saveFingerResponse') {
      this.publishStatus('saveFingerResponse ' + second);
    } else if (first === 'preSubmitGate') {
      // 提交被自检拦下：界面与日志都要能看出"这一次没有发出去"。
      this.publishStatus('gate-blocked');
    } else if (first === 'diag:getFinger3' || first === 'diag:lf' || first === 'diag:lfrt'
      || first === 'diag:idb' || first === 'diag:env' || first === 'diag:console') {
      this.publishStatus(first);
    }
  }

  private theme(): ThemeTokens {
    return resolveTheme(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  /**
   * 状态行。字段名是 `lastReport=` 而不是 `stage=`——**这是 2026-09-12 的教训**：
   * 它装的是"最后一次桥上报的 kind"（诊断构建下会被 `diag:*` 覆写），
   * 叫 `stage` 会让人误以为它是"站点流程阶段"（用户那次失败截图里躺着的 `stage=diag:idb` 就是这样误导的）。
   * 判站点阶段请用具体行：`submitGate` / `enrollment navigate:` / `[xhr]` / `[pageScripts]`。
   */
  private publishStatus(lastReport: string): void {
    // 字段顺序是**故意**的：容器顶部那条状态行只有两行宽，末尾会被截断成 `…`。
    // 因此判定用的标志（诊断开关、自检、指纹来源）排在前面，长度类信息排在后面——
    // 2026-09-12 的取证就吃过一次亏：`diag=0` 落在被截掉的那半行里，没法与 `fpSource=page` 同屏。
    const text: string = 'lastReport=' + lastReport
      + ' diag=' + (ENROLLMENT_DIAGNOSTICS_FOR_EVIDENCE ? '1' : '0')
      + ' gate=' + (this.dom.gateBlocked ? '1' : '0')
      + ' fpSource=' + (this.dom.fingerPrintSource.length > 0 ? this.dom.fingerPrintSource : 'none')
      + ' f3Remote=' + this.dom.finger3RemoteOk.toString()
      + ' fpChars=' + this.dom.fingerPrint.length.toString()
      + ' fgChars=' + this.dom.fingerGenPrint.length.toString()
      + ' fg3Chars=' + this.dom.fingerGenPrint3.length.toString()
      + ' singleLogin=' + (this.dom.singleLoginChecked ? '1' : '0')
      + ' saveFinger=' + (this.dom.saveFingerPatched ? '1' : '0')
      + ' prefill=' + (this.dom.userPrefilled ? '1' : '0') + (this.dom.passPrefilled ? '1' : '0')
      + ' roaming=' + (this.roamingSeen ? '1' : '0');
    this.statusText = text;
    this.onStatus(text);
  }

  /**
   * 主框架请求。**登记期间一律放行**（返回 false）：
   * 用户必须能在容器内完成短信验证与随后的所有跳转；我们只在旁边记录里程碑。
   */
  private handleIntercept(event: OnLoadInterceptEvent): boolean {
    const url: string = event.data.getRequestUrl();
    const path: string = pathOf(url);
    if (url.indexOf(ROAMING_MARKER) >= 0) {
      if (!this.roamingSeen) {
        this.roamingSeen = true;
        logger.info('enrollment roaming reached: path=' + path + ' -> allow navigation, harvest afterwards');
        this.publishStatus('roaming');
        this.scheduleHarvest(FIRST_HARVEST_DELAY_MILLIS);
      }
      return false;
    }
    logger.info('enrollment navigate: ' + path);
    return false;
  }

  private scheduleHarvest(delayMillis: number): void {
    if (this.harvestStarted) {
      return;
    }
    this.harvestStarted = true;
    setTimeout(() => {
      this.tryHarvest(0);
    }, delayMillis);
  }

  /** 从 Web 引擎收割 learn 域的 cookie（不含值，只记条数与名字）。 */
  private tryHarvest(attempt: number): void {
    if (this.settled) {
      return;
    }
    let header: string = '';
    try {
      header = webview.WebCookieManager.fetchCookieSync(LEARN_URL);
    } catch (error) {
      logger.warn('fetchCookieSync failed: attempt=' + attempt.toString() + ' ' + (error as Error).message);
    }
    const names: string[] = [];
    const pairs: CookiePair[] = parseCookieHeaderPairs(header);
    for (let i = 0; i < pairs.length; i++) {
      names.push(pairs[i].name);
    }
    logger.info('enrollment harvest: attempt=' + attempt.toString()
      + ' entries=' + pairs.length.toString()
      + ' names=[' + names.join(',') + ']'
      + ' chars=' + header.length.toString());
    if (pairs.length === 0 && attempt < HARVEST_MAX_ATTEMPTS) {
      setTimeout(() => {
        this.tryHarvest(attempt + 1);
      }, HARVEST_INTERVAL_MILLIS);
      return;
    }
    this.settled = true;
    if (pairs.length === 0) {
      this.publishStatus('harvest-empty');
      this.onFailed('no session cookies after roaming (attempts=' + (attempt + 1).toString() + ')');
      return;
    }
    this.publishStatus('harvest-ok');
    this.onSucceeded(this.dom, header);
  }

  build() {
    Column() {
      Row() {
        Text(this.statusText)
          .fontSize(this.theme().typography.labelSmall.fontSize)
          .fontColor(this.theme().colors.onSurfaceVariant)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(i18nService.tKey($r('app.string.loh_cancel')))
          .fontSize(this.theme().typography.labelLarge.fontSize)
          .fontColor(this.theme().colors.primary)
          .padding({
            left: this.theme().sizes.space3,
            right: this.theme().sizes.space1,
            top: this.theme().sizes.space2,
            bottom: this.theme().sizes.space2
          })
          .onClick(() => {
            logger.info('enrollment cancel tapped by user');
            this.publishStatus('cancelled');
            this.onCancelled();
          })
      }
      .width('100%')
      .padding({
        left: this.theme().sizes.space3,
        right: this.theme().sizes.space3,
        top: this.theme().sizes.space1,
        bottom: this.theme().sizes.space1
      })
      .backgroundColor(this.theme().colors.surfaceVariant)

      Web({ src: ID_LOGIN_URL, controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .imageAccess(true)
        .onlineImageAccess(true)
        .javaScriptProxy({
          object: this.bridge,
          name: ENROLLMENT_BRIDGE_NAME,
          methodList: ['report', 'values'],
          controller: this.controller
        })
        .javaScriptOnDocumentStart(this.scripts)
        .onLoadIntercept((event: OnLoadInterceptEvent) => {
          return this.handleIntercept(event);
        })
        .onPageEnd((event: OnPageEndEvent) => {
          logger.info('enrollment page end: ' + pathOf(event.url));
        })
        // 页面自己的 console（例如 finger3.js 的 console.log('getFinger3 error')）转进我们的 hilog。
        // 真实登记失败时正是这句话没留下任何痕迹；上限 80 条、每条截断，避免刷屏。
        .onConsole((event: OnConsoleEvent) => {
          if (this.consoleLines >= CONSOLE_LINE_LIMIT) {
            return false;
          }
          this.consoleLines++;
          const text: string = event.message.getMessage();
          logger.info('enrollment page console [' + event.message.getMessageLevel().toString()
            + '] ' + pathOf(event.message.getSourceId()) + ':' + event.message.getLineNumber().toString()
            + ' ' + (text.length > 240 ? text.substring(0, 240) : text));
          return false;
        })
        .onErrorReceive((event: OnErrorReceiveEvent) => {
          logger.error('enrollment load error: ' + event.error.getErrorInfo()
            + ' url=' + (event.request === undefined ? '' : pathOf(event.request.getRequestUrl())));
        })
        .width('100%')
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().colors.surface)
  }
}
