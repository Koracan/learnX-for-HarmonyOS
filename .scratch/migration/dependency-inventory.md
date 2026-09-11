# learnOH 移植 —— 依赖事实清单

来源：`reference/learnOH-old/`（只读）。本文件只记录**事实**，不含决策。决策见 `docs/adr/` 与 `spec.md`。
生成方式：子代理只读勘探 + 父代理抽样复核（第 1、2、6 节的加粗行已亲自复核）。

---

## 1. react-native-learn-oh-data-processor（v1.0.6）—— 承重层，且已是 ArkTS

- 包内 `harmony/entry/src/main/cpp/generated/LearnOHDataProcessor.{h,cpp}` 仅 21+28 行 codegen 样板（注册 methodMap），**不是实现**。
- 真正的实现在 `node_modules/react-native-learn-oh-data-processor/harmony/learn_oh_data_processor/src/main/ets/DataProcessorModule.ts`，**548 行 / 25336 字节**。
- 依赖：`@ohos.net.http`、`@ohos.util`（Base64Helper/TextDecoder/TextEncoder）、`@ohos.file.fs`。由 `DataProcessorPackage.ets`(12 行) 注册，TurboModule 名 `LearnOHDataProcessor`，规格文件 `src/specs/v1/NativeLearnOHDataProcessor.ts`。

**JS API（8 个方法）**

| 方法 | 行为 |
| --- | --- |
| `processNotices/processAssignments/processFiles(rawJson, courseNamesJson)` | 纯 reshape：按 courseId 注入 `courseName/courseTeacherName`，按 `publishTime/deadline/uploadTime` 倒序 |
| `fetchAssignments(courseIds, cookie, csrfToken)` | 3 个列表端点（zyListWj/Yjwg/Ypg）× N 课程，POST `aoData=[{wlkcid}]` 解析 `aaData`；再逐条 POST `/zy/student/detail` + GET viewCj(viewZy) HTML，用正则从 `class="list fujian clearfix"` 块（2000 字符窗口）抓最多 4 个附件，按 id 去重合并 |
| `fetchNotices(courseIds, cookie, csrfToken)` | 2 个端点（pageListXsbyWgq/Ygq），Base64 解 `ggnr`，必要时 GET beforeViewXs 抓 `ml-10` 附件锚点 |
| `fetchFiles(courseIds, cookie, csrfToken)` | GET `kjxxbByWlkcidAndSizeForStudent?size=200`，映射 `object[]` |
| `post(url, cookie, csrfToken, params, filePath?, fileName?, fileType?, requestId?)` | 手写 multipart/form-data（自造 boundary，fs.openSync/readSync 读进 ArrayBuffer），用 http 的 `dataSendProgress` 发 `LearnOHUploadProgress` 设备事件 |
| `moveToBackground()` | `uiAbilityContext.moveAbilityToBackground()` |

内部工具函数：`decodeHTML`（6 个实体）、`unwrapDownloadUrl`（从 `openNewWindow?...downloadUrl=` 提取真实下载地址）、`decodeBase64`。

**RN 耦合面 = 4 行（父代理逐行复核）**

| 行 | 内容 | 替代方案 |
| --- | --- | --- |
| 1 | `import { AnyThreadTurboModule } from '@rnoh/react-native-openharmony/ts'` | 删除 |
| 46 | `export class DataProcessorModule extends AnyThreadTurboModule` | 普通 class |
| 452 | `await this.ctx.uiAbilityContext.moveAbilityToBackground()` | 注入 `common.UIAbilityContext` |
| 520 | `this.ctx.rnInstance.emitDeviceEvent('LearnOHUploadProgress', …)` | 回调 / `@ohos.events.emitter` |

其余 544 行是纯 ArkTS。另有 19 处 `any` 与对象展开（L51/52/55、L68/69/72、L85/86/89、L127、L132-135、L301、L322、L325、L408、L424）——ArkTS 1.1 可编译，linter 会告警。

---

## 2. thu-learn-lib 4.0.0（`github:Koracan/thu-learn-lib`）

**存在于 `reference/learnOH-old/node_modules/thu-learn-lib`**，type=module，main `./lib/module/index.js`。

- LOC（编译后 ESM）：index.js 1053、urls.js 147、utils.js 61、types.js 92 = **1353**。类型：index.d.ts 116、types.d.ts 377、urls.d.ts 77、utils.d.ts 13。
- 依赖：`cheerio` 1.0.0-rc.12、`entities` ^7、`fetch-cookie` 3.0.1、`tough-cookie` 4.1.4、`js-base64` ^3.7.8、`node-fetch-native` ^1.6.7、`sm-crypto` ^0.3.13。这些都不是 RN 安全的，全部要靠 ArkTS 侧替代。
- 导出：`addCSRFTokenToUrl(url, token)`（追加 `_csrf` 查询参数）+ `class Learn2018Helper`，32 个成员：getCSRFToken/setCSRFToken、getRoamingTicket、login、logout、getUserInfo、getCalendar、getSemesterIdList、getCurrentSemester、getCourseList、getNotificationList(+Kind)、getFileList、getFileCategoryList、getFileListByCategory、getHomeworkList(+AtUrl)、getExcellentHomeworkListByHomework、getDiscussionList、getAnsweredQuestionList、getQuestionnaireList(+AtUrl,+Detail)、addToFavorites/removeFromFavorites/getFavorites/pinFavoriteItem/unpinFavoriteItem、setComment/getComments、sortCourses、submitHomework、setLanguage/getCurrentLanguage。
- 主机：id.tsinghua.edu.cn、learn.tsinghua.edu.cn、zhjw.cic.tsinghua.edu.cn。全局 `fetch` + fetch-cookie/tough-cookie 的 CookieJar。
- **登录 = GET id 登录表单 → `sm2.doEncrypt(password, #sm2publicKey)`（国密 SM2，从页面抓公钥）→ POST check → ticket → LEARN_AUTH_ROAM → 从课程列表页正则抓 `_csrf` 与语言。** 所有请求过 `#withReAuth`（掉登录后重登重试）。
- 内容接口是 JSON（`json.result==='success'`）；公告正文是 Base64 的 `ggnr`；`getCalendar` 用 `Function(...)` 求值 JSONP（**ArkTS 禁用，必须重写**）。
- HTML 解析（cheerio, xml:true）：getUserInfo（`a.user-log`、`.fl.up-img-info p:nth-child(2) label`）、parseNotificationDetail/parseHomeworkAtUrl/parseHomeworkFile（`div.list.fujian.clearfix`、`span.ftitle`，fujian 块顺序 = 附件/答案/已提交/成绩）+ `decodeHTML`、`formatFileSize`、GRADE_LEVEL_MAP、CONTENT_TYPE_MAP。

**在 src 中的调用点**：`data/source.ts`（`new Learn2018Helper({fetch: 套 UA 的 fetch, provider: () => redux 凭据})`、`login`、`getCSRFToken`、`addCSRFTokenToUrl`）；`helpers/html.ts:68`（CSRF 注入 WebView）；`helpers/parse.ts`（ApiError/FailReason）；`data/types/state.ts`（CourseInfo/FailReason/Homework/Notification/File/UserInfo 直接复用为实体类型）；`helpers/i18n.ts`（HomeworkGradeLevel → 翻译键）；`data/mock.ts`（HomeworkCompletionType/HomeworkSubmissionType）；`screens/AssignmentDetail.tsx`、`AssignmentSubmission.tsx`（RemoteFile）；`data/actions/courses.ts`、`user.ts`。

**实际运行期只调用了 10 个方法**：login、logout、getCSRFToken、getHomeworkList、getNotificationList、getFileList、getCourseList、getSemesterIdList、getCurrentSemester、getUserInfo。**批量 `getAll*ForCourses` 完全不走 thu-learn-lib**，走第 1 节的 ArkTS 模块。

---

## 3. 第三方 JS 库（按调用点核实）

| 库 | 用途 / 状态 |
| --- | --- |
| @reduxjs/toolkit 2.2.1 | data/store.ts:19 configureStore；selectors/filteredData.ts:1 createSelector |
| redux 5 / react-redux 9 / redux-thunk 3 / typesafe-actions 5 | store 组合、Provider/useSelector、ThunkAction 类型、10 个 actions/reducers 文件 |
| redux-persist 6 | store.ts（persistStore/persistReducer/autoMergeLevel2）+ 每 slice PersistConfig + App.tsx PersistGate |
| axios 1.13.2 | **src 内 0 引用** |
| memfs 4.17.2 | **src 内 0 引用** |
| fuse.js 7 | hooks/useSearch.ts：三域模糊搜索 + 手工精确标题/课程名合并（因为 fuse "漏掉明显匹配"） |
| dayjs 1.11.19 | 48 处：解析/格式化/相对时间；App.tsx:96-102 relativeTime 插件 + zh-cn/en |
| he 1.2.0 | helpers/html.ts:15-17 实体解码 + 去标签 |
| katex 0.16.27 | preval 把 katex.min.js/auto-render.min.js/min.css 内联进 WebView 模板（html.ts:57,103,111），字体改写到 fastly.jsdelivr CDN |
| darkreader 4.9.112 | preval 打包 darkreader.js；html.ts:92,95 注入并在暗色时 `DarkReader.enable({darkSchemeBackgroundColor})` |
| mime-types 3 | data/source.ts:208 上传 Content-Type；helpers/fs.ts:191 分享 MIME；AssignmentSubmission.tsx:29 |
| react-native-url-polyfill 2 | polyfills.js:4 `import '.../auto'`（全局 URL/URLSearchParams，addCSRFTokenToUrl 依赖） |
| buffer 6 | polyfills.js:1-2 `global.Buffer = Buffer` |
| path 0.12.7 | 仅构建期：preval/readFile.js:2、sso.preval.js:4 |
| metro / babel-plugin-preval | 构建期：`.env` 与 node_modules 文件在打包时烘进 bundle（katex/darkreader/sso/env 四个 preval 产物是构建步骤，不是运行期依赖） |

---

## 4. @react-native-ohos/* → 调用点（package.json 列 24 个，实际构建进宿主 20 个）

导入用的是**规范 RN 包名**，映射写在每个包的 `harmony.alias` 里。

| 包@版本 | 用在 | 调用的 API |
| --- | --- | --- |
| async-storage 1.21.1-rc.3 | data/store.ts:18、reducers/root.ts:4 | 默认 AsyncStorage（getItem/setItem/removeItem） |
| cookies 6.3.0 | data/source.ts、helpers/fs.ts、components/AutoHeightWebView.tsx | CookieManager.clearAll(true)/set(url,cookie,useWebKit)/get(url) |
| react-native-device-info 14.0.5 | constants/DeviceInfo.ts | getBuildNumber/isTablet/getSystemVersion/getModel |
| react-native-document-picker 9.3.2 | AssignmentSubmission.tsx:122,138 | pick、types.allFiles、isCancel |
| react-native-file-viewer 2.2.0 | helpers/fs.ts:174 | FileViewer.open(path,{showOpenWithDialog:true}) |
| react-native-fs 2.21.0 | helpers/fs.ts、FileDetail.tsx:74 | DocumentDirectoryPath、CachesDirectoryPath、mkdir、exists、downloadFile({fromUrl,toFile,headers,begin,progress}).promise、stat、unlink、readFile |
| react-native-gesture-handler 2.23.2-rc.1 | App.tsx:12、CardWrapper.tsx:4-5、FilterList.tsx:8 | GestureHandlerRootView、Swipeable、RectButton、FlatList |
| react-native-image-picker 8.2.2-rc.1 | AssignmentSubmission.tsx:147 | launchImageLibrary({mediaType:'mixed',selectionLimit:1}) → didCancel、assets[].uri/type/fileName/fileSize |
| react-native-immersive（Koracan fork） | App.tsx:11,686 | Immersive.setImmersive(bool) |
| react-native-localize 3.4.2 | helpers/i18n.ts:1,10 | getLocales()[0].languageTag |
| react-native-pdf 6.8.0 | FileDetail.tsx:171 + Index.ets 注册 `PDF_VIEW_TYPE` | `<Pdf source={{uri:path}} fitPolicy={0} style>` |
| react-native-reanimated 3.18.1-rc.1 | components/Filter.tsx:4-9 + babel 插件 | Animated、Easing、useAnimatedStyle、useSharedValue、withTiming |
| react-native-safe-area-context 5.1.1-rc.1 | App.tsx:32-34、SafeArea.tsx、HeaderTitle.tsx、Search.tsx | SafeAreaProvider、useSafeAreaFrame、useSafeAreaInsets |
| react-native-screens 4.8.1-rc.7 | App.tsx:47 | `enableScreens(false)`（**故意禁用**） |
| react-native-secure-key-store 2.1.0-rc.1 | helpers/secureStorage.ts | set(key,value)/get(key)/remove(key) |
| react-native-securerandom 1.1.0-rc.1 | helpers/fingerprint.ts:9 | generateSecureRandom(16)（该文件是**死代码**） |
| react-native-share 12.1.1-rc.3 | helpers/fs.ts:188 | Share.open({url,type,title,showAppsToView,failOnCancel}) |
| react-native-tab-view 4.0.12 | CourseDetail.tsx:6-11 | TabBar、TabView、SceneRendererProps、NavigationState |
| react-native-webview 13.15.1 | AutoHeightWebView.tsx、SSO.tsx、FileDetail.tsx | injectedJavaScript(BeforeContentLoaded)、onMessage、onNavigationStateChange、onLoadProgress、onShouldStartLoadWithRequest、javaScriptEnabled、originWhitelist、sharedCookiesEnabled、allowFileAccess、source{uri,html,baseUrl,headers}、ref.stopLoading() |
| stack 7.2.11-rc.1 | App.tsx（多数屏） | createStackNavigator、StackNavigationOptions、CardStyleInterpolators、StackScreenProps |
| 未使用（src 0 引用） | elements、react-native-blob-util、pager-view | elements/pager-view 是 stack/tab-view 的传递依赖 |
| 非 ohos 导航包 | @react-navigation/native 7.1.6、native-stack ^7.2.0、bottom-tabs 7.3.10 | NavigationContainer、createNativeStackNavigator、createBottomTabNavigator、useBottomTabBarHeight、StackActions、useIsFocused |

---

## 5. 旧仓库文档记录的平台限制

- `skills/skills.md`：约束"不引入 expo-*"，优先 react-native-paper + @react-native-ohos。Phase 1-3 完成（原生 TurboModule 解析/下载、搜索、提交+原生进度、SplitView、withNativeReAuth、应用内 PDF/图片预览、swipe-to-hide）；Phase 4 未完成（CourseX、后台抓取+通知、设置子页、分享导出）。
- `.github/copilot-instructions.md`：绝对导入以 src 为根；禁止改 `node_modules/**`、`cpp/generated/**`、`build/**`、`tmp/**`；"保持 enableScreens(false)"；**"修 HarmonyOS bug 时不得以 src-reference 为参考"**；全局 `LogBox.ignoreAllLogs(true)`；架构参考 https://deepwiki.com/Koracan/learnX-for-HarmonyOS。
- `skill-ani.md`：Harmony 端 native-stack 转场动画默认不生效，需全局显式开动画并在分屏时设 `animation:'none'`（即 hooks/useNavigationAnimation.ts 的由来）。
- `skill-header.md`：react-navigation 的 header 不会因标题过长而动态避让 headerRight（FileDetail 重叠），只能在 HeaderTitle.tsx 里绕。
- `skill-favorite.md` / `skill-hide-course.md`：用 `RectButton` 替代原生 ripple，解决鸿蒙上"横滑时按下态无法取消/误触"。
- `skill-calendar-sync.md`：参考实现需要 expo-calendar，**RNOH/HarmonyOS 无支持**，需基于 HarmonyOS CalendarManager 自写原生模块；低优先级、未实现。
- `skill-settings.md`：文件缓存可选 DocumentDirectoryPath（永久）/ CachesDirectoryPath；removeFileDir；省略课程名命名。
- `mock.md`：状态契约的唯一权威是 `src/data/types/state.ts`，**明确不是 src-reference**；`settings.immersiveMode` 只存在于鸿蒙版。
- 缺失：`skills.md` 引用的 skill-notice.md / skill-reauth.md / skill-am.md / skill-file.md  / skill-course.md **不存在**（现存 13 个文件：@react-navigation-native-stack、mock、react-native-gesture-handler、react-native-screens、skill-ani、skill-archive、skill-calendar-sync、skill-favorite、skill-header、skill-hide-course、skill-settings、skills、succ.txt）。

---

## 6. 旧工程的两处"平台补丁"揭示的缺口

`scripts/patch_harmony_oh_modules.ps1`（193 行，`npm run patch:ohos-deps`）只补 2 个包，且补的是 `harmony/entry/oh_modules/` 下的副本：

1. `@react-native-ohos/react-native-file-viewer/.../RNFileViewerTurboModule.ts`：注入 `normalizeLocalPath()` 去重复 `file://` 前缀，让 fs.stat / OpenFile / fileUri.getUriFromPath / filePreview.canPreview 都走规范化路径。缺陷：模块假定传入裸沙箱路径，而应用传的是 `file://` URI。
2. `@react-native-ohos/react-native-share/.../utils/FileUtils.ts`：注入 `normalizePathForFs`（去 `file://`）与 `normalizeUriForShare`（`content://` 保留；`/` 开头转 `fileUri.getUriFromPath`），修 `isLocalFile`、`copyUriFromUrl`、`copyFileFromOriginPath`、`getUrlSuffix`。缺陷：模块只认 `content://`/`file://`，把 `file://` 直接丢给 `fs.openSync`。

两处补丁都是幂等的（正则/Contains 守卫，内容不变则不写）。

`scripts/sync-harmony-aliases.js`（136 行，postinstall）：扫 `node_modules/@react-native-ohos`(与 -oh-tpl) 的 `harmony.alias`，写进 tsconfig.json 的 `compilerOptions.paths`（baseUrl 为 src）。**显式排除 securerandom 与 immersive**（原因未写明）。暴露的缺口：RNOH 工具链不会自动把 RN 包名解析到 @react-native-ohos 包，每个依赖都要手写 alias + TS path 映射；20 个模块里有 2 个需要改源码才能处理普通沙箱路径。

---

## 7. 待确认（UNKNOWN）

- `helpers/env.ts` 的 `.env` 真实内容（`DUMMY_USERNAME=guest`/`DUMMY_PASSWORD=guest` 由作业 A 从 Login.tsx 匹配逻辑反推；.env 文件本身未读）。
- About/Help 的外链目标未读。
- settings 里的日历/提醒字段（assignmentCalendarId、alarm* 等）在仓库内无任何实现消费，是否曾被原生模块消费未知。
- sync-harmony-aliases.js 排除 securerandom/immersive 的原因。
