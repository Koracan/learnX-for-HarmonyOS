# learnOH 移植 —— 鸿蒙能力地图（事实）

来源：本机 SDK `C:\Program Files\Huawei\DevEco Studio\sdk\default`（`sdk-pkg.json`/`oh-uni-package.json` 显示已安装 **API 24 / HarmonyOS 6.1.1**）+ developer.huawei.com / ohpm.openharmony.cn 检索。
未设置 `DEVECO_SDK_HOME`/`HOS_SDK_HOME`；`mise.toml` 只固定 `npm:@deveco/deveco-cli`。
本文件只记录事实。**注意**：本工程与旧 RN 工程的下限差异见文末。

## 1. SDK 全覆盖（无需第三方）

| 能力 | API / 组件 |
| --- | --- |
| HTTP | `@ohos.net.http` |
| 文件 | `@ohos.file.fs`、`@ohos.file.hash` |
| KV / 关系存储 | `@ohos.data.preferences`、`@ohos.data.relationalStore` |
| 安全存储 | asset store / `@ohos.security.huks` |
| 密码学 | `@ohos.security.cryptoFramework`：AES/RSA/**SM2**/SM3/SM4/SHA/MD5/HMAC + `createRandom` |
| Web | `component/web.d.ts` + `@ohos.web.webview`（ArkWeb） |
| PDF | HMS `@hms.officeservice.PdfView`（pdfservice） |
| 选择器 | Document/PhotoViewPicker |
| 文件预览 | HMS `@hms.filemanagement.filepreview` |
| 分享 | HMS systemShare `ShareController` |
| 剪贴板 / 提示 | `@ohos.pasteboard`、promptAction、bindSheet / bindContentCover |
| i18n | `@ohos.i18n` / intl / resourceManager |
| 设备与窗口 | deviceInfo / display / window |
| 图标 | SymbolGlyph（renderingStrategy/effectStrategy/symbolEffect） |
| 动效与手势 | `animateTo` + `gesture.d.ts` + `sharedTransition`/`geometryTransition` |
| 长列表 | LazyForEach + `List.cachedCount` |
| 生命周期 | UIAbility onForeground/onBackground、Want/startAbility |
| 通知 / 后台 | notificationManager、backgroundTaskManager |

## 2. 真缺口（需第三方 / 自研 / NAPI）

1. **HTML 解析与 DOM 查询 —— SDK 不含**。SDK 只有 `@ohos.convertxml`（仅 XML）。ohpm：`@ohos/htmlparser2` 1.0.4（2026-08-18 发布）+ domutils/domhandler/domelementtype/css-select 依赖栈；**cheerio 零命中**。RN 版整个数据层都依赖 HTML 抓取（`src/helpers/html.ts`、`thu-learn-lib` 的 cheerio、`DataProcessorModule.ts` 的正则流式解析）。
2. **ArkWeb 与 HTTP 栈的 cookie/会话共享**：`@ohos.net.http` 只有 `HttpResponse.cookies`（字符串，**没有 cookie store**）；rcp（`@hms.collaboration.rcp` / RemoteCommunicationKit）有 `CookieRepository.create()/setCookies/getAllCookies/getCookiesForUrl` + Session/SessionConfiguration，但属 **HMS-only**；ArkWeb 用独立的 `webview.WebCookieManager` 存储。三者之间需手工搭桥。旧 `DataProcessorModule.ts` 走的是"`@ohos.net.http` + 手工 Cookie 头"这条路。
3. **图标字体**：无 vector-icons 等价库；用 SymbolGlyph 或手工加载 TTF。
4. **WebView 自适应高度**：Web 组件**无 onMeasure**，必须 `runJavaScript()` 回传高度（WebMessagePort 或 javaScriptProxy）。
5. **模糊搜索**：无系统 SDK。ohpm：`@ohos/flexsearch` 2.0.1（Apache-2.0，2025-04-14，points=25）、`@isrc/fuse.js` 1.0.1（2023-09-28）。
6. **推送**：旧 RN 应用**没有任何推送实现**（只有未被引用的翻译键 `pushNotifications`/`copyPushNotificationToken`）。原生侧需要 HMS Push Kit（`@hms.core.push.serviceNotification`）+ AGC 配置，工作量 UNKNOWN。

## 3. 关键版本事实

| | 旧 RN 工程 `reference/learnOH-old/harmony/build-profile.json5` | 本工程 `build-profile.json5` |
| --- | --- | --- |
| targetSdkVersion | 6.0.0(20) | 6.1.0(23) |
| compatibleSdkVersion | **6.0.0(20)** | **6.1.0(23)** |
| runtimeOS | HarmonyOS | HarmonyOS |
| bundleName | com.koracan.learnOH | com.koracan.learnOH（相同） |
| versionCode / versionName | 1000042 / 1.1.0 | 1000042 / 1.1.0（尚未提升） |

- 旧仓库 README 写"HarmonyOS 5+"，但其 build-profile 下限是 API 20 —— **README 与工程实际不符，以 API 20 为准**。
- 两工程 bundleName 相同 ⇒ 同一次升级。下限抬高会导致 HarmonyOS 5.x/6.0 设备在应用市场看不到该更新。
- 本机只装了 API 24 SDK；工程声明 23 且可正常构建（devecocli 已跑通签名构建与真机部署）。

## 4. 具体坑（有证据的）

- **ohpm 工具链**：`ohpm` CLI 6.1.2.285 **没有 search 命令**；registry 检索 API = `https://ohpm.openharmony.cn/ohpmweb/registry/oh-package/openapi/v1/search?condition=<q>&pageNum=1&pageSize=10&sortedType=relevancy&isHomePage=false`。registry 配置在 `C:\Users\korac\.ohpm\.ohpmrc`。
- **HTML 解析包**：`@ohos/htmlparser2` 1.0.4（MIT，2026-08-18，points=25，单一发布者）+ domutils 3.2.2 / domhandler 5.0.3 / domelementtype 2.3.0 / css-what / parse-srcset。**css-select 是否真能跑任意 CSS 选择器未验证**（注册表列出但未拆包）。cheerio 零命中。
- **三个互不相通的 cookie 存储**：`@ohos.net.http`（只有响应上的 `cookies: string`）、rcp 的 `CookieRepository`（HMS）、ArkWeb 的 `WebCookieManager`。登录发生在 WebView、抓取发生在 HTTP 栈 ⇒ **必须显式搭桥**。旧实现是绕过的：全程手工传 Cookie 头（`DataProcessorModule.ts:116,146,171,311,335,416,531`）。
- **安全存储的可用性陷阱**：`@ohos.security.asset` 的取回受 `Accessibility` 约束（设备解锁后/首次解锁后才可读），**模拟器或无锁屏设备会失败**，调用方必须能降级——与旧 `src/helpers/secureStorage.ts` 里已有的同类注释一致。
- **选择器 URI 的持久化**：`picker.DocumentViewPicker/PhotoViewPicker` 选中的 URI 要长期可用，必须再走 `@ohos.fileshare`（`PolicyInfo`/`OperationMode`/persistPermission）——**容易漏**。
- **promptAction**：优先用 `UIContext.getPromptAction()`；裸 `promptAction` 模块函数已标记 deprecated-with-replacement。Toast/Snackbar/Portal 需手搓（`bindSheet` = bottom sheet，`bindContentCover` = modal）。
- **Web 三件事**：`loadUrl` 接受 `Resource`（本地 HTML/资源可加载）；**无 onMeasure**（高度必须注入 JS + `WebMessagePort`/`javaScriptProxy` 回传）；暗色要靠注入 `<style>` 或 `darkMode`/`forceDarkAccess`，darkreader 那套要重做。
- **无 preval / 无构建期 require**：katex 与 darkreader 的 JS/CSS 只能作为 **rawfile 资源**打进包再注入 Web。
- **SymbolGlyph 的名字集与 MaterialCommunityIcons 不同**，需要一张名称映射表；或自带 TTF + 手写映射。
- **LazyForEach 需要自己实现 `IDataSource`**（totalCount/getData/register/unregister + DataChangeListener），且没有 `getItemLayout`，定高项靠 `cachedCount`。
- **无 worklet 模型**：reanimated 的 sharedValue 只能改写为 `@State`/`@Observed` + `animateTo`；页面转场用 `sharedTransition`/`geometryTransition`；下拉刷新用 `component/refresh.d.ts`。
- **`@ohos.window` 的沉浸式 setter 签名未确证**（`setImmersiveModeEnabledState`/`setWindowDecorVisible` 的 grep 无定论）。
- **HMS Core 依赖**：PDF Kit / Preview Kit / Push Kit / rcp 都属 HMS，需要目标设备（MatePad Air, API 24）上有对应 HMS Core 版本——**未验证**。

## 5. 本轮的 UNKNOWN

- 本机**没有 API 23 SDK 副本**，只有 API 24（6.1.1）；工程的 `6.1.0(23)` 只是 build-profile 声明。
- `cryptoFramework` 的 `createMd`/`createCipher` 接受的确切算法字符串（d.ts 里没有枚举，仅文档文字提及 AES/SM3/SM4/RSA）。
- ohpm htmlparser2/domutils 栈是否支持任意 CSS 选择器。
- `module.json5` 里的深链/App Linking intent-filter（未查）。
- ArkTS 严格模式下移植 redux/redux-persist/thunk 状态层的可行性（未做运行期验证）。
