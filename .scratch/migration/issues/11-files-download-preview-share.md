# 11: 文件列表 + 详情 + 下载 + 预览 + 分享

**What to build:** 文件 tab 显示真实文件，详情可下载（进度可见）、在应用内预览 PDF 与图片、分享或交给其他应用打开；文件设置（使用文档目录、省略课程名、清理缓存）生效。

**Blocked by:** 09（公告切真实数据 + 快照）

**Status:** verified-partial（模拟器口径；1/4/5 通过、2 一半且 PDF 转 ticket 18、3 机制成立、6 转 18）

- [x] 列表按上传时间倒序，显示大小与类型（我独立复验：春季 95 条、每行类型+大小+相对时间）
- [ ] 下载显示进度，完成后可预览；PDF 与图片在应用内打开，无需跳转第三方
- [x] 会话过期导致下载到登录页时能被识别并给出正确提示，不留下损坏文件（**机制**由注入替身单测钉住；设备侧未复现，见验收第 3 节）
- [x] 分享面板可调起；含中文与空格的路径可用（证据 C2 + README 引用的 hilog 行；**原始日志未落文件**，见验收第 4 节）
- [x] 清理缓存后文件真正消失；使用文档目录与省略课程名两个设置均生效（两个设置我独立复跑：根 cache→documents、文件名去课程名前缀）
- [ ] 真机截图（**转 ticket 18**）

## Comments

### 统筹提示（2026-09-12，**用户提供的事实**）—— 本学期**文件非空**，可直接用真实数据验收

- 用户账号 **2026-2027 学年秋季学期**：**公告、文件、课程都有非空数据**；**只有作业为空**。
- ⇒ 本 ticket 的列表 / 下载 / 预览 / 分享**不需要学期切换**就能拿到真实数据；**空结果应视为失败信号**（端点 / 参数 / 会话 / 解析），**不要**解释成"本学期没文件"。
- 期望与网页端对照：条数、顺序（按上传时间倒序）、大小与类型。
- 与作业线（ticket 10/13）的区别记牢：那两条本学期为空，要真实数据必须切到 **2025-2026 学年春季学期**（见 ticket 12 的统筹提示）。

### 边界说明（2026-09-12，由 ticket 10 带入）—— "附件 → FileDetail" 的路由已接通，真身仍全是你的

ticket 10 的作业详情把**四类附件**（attachment / submittedAttachment / gradeAttachment / answerAttachment）
都接到 ticket 04 的 `ROUTE_FILE_DETAIL`（`features/notices/NoticeRoutes.ets`）与
`FileDetailPlaceholderPage` 上（照参考实现 `AssignmentDetail.tsx:132-145` 的 `handleFileOpen`）。
你实现真身时会碰到四件事：

1. **`FileDetailRouteParams.noticeId` 有两个来源**：公告详情传**公告 id**（`NoticeDetail.tsx:64`），
   作业详情传**附件 id**（`AssignmentDetail.tsx:134`）。参考实现里这个字段只用来拼下载目录名
   （`helpers/fs.ts:54`：`${dir}/${file.courseName}/${file.id}`），所以两种都能用。
   字段名保留 `noticeId` 是为了不动 ticket 04 已验收的导航契约（我**没有**改它的形状）。
2. **作业附件的 `id` 可能是空串**：真实数据里提交附件的下载地址是**路径形态** ——
   `/b/wlxt/kczy/zy/student/downloadFile/2025-2026-2151371080/2023011272_ZY_178014313120047eacdb87a-…` ——
   没有 `fileId=` / `wjid=` 查询参数，`domain/parse/Attachment` 取不到 id ⇒ `noticeId` 为空
   （实测 hilog：`assignment attachment tapped: kind=main … id=`）。
   真身若要"按文件缓存 / 去重"，**必须为这种情况兜底**（例如用 downloadUrl 的末段做键），
   别把空串直接当目录名。
3. **ticket 10 只做掉了"列表要全 + 可点 + 目标路由明确"**：下载（进度可见）、应用内预览 PDF 与图片、
   分享、三个文件设置（文档目录 / 省略课程名 / 清理缓存）、"会话过期导致下载到登录页"的识别——
   **全部还是你的**（本 ticket 的验收第 1-5 条一条未动）。本轮没有实现任何下载或落盘代码，
   也没有改 ticket 05 的 `helpers` 等价物。
4. 我改到的文件只有两处**注释**：`features/notices/NoticeRoutes.ets`、
   `features/notices/FileDetailPlaceholderPage.ets`；导航契约（字段名、参数形状、路由名）原样未动。

（工单里的"验收第 6 条 真机截图"同样按 AGENTS.md 转 ticket 18 的一次性复验。）


### ticket 11 交付

**Status 留给统筹。** 来源：模拟器 Pura 90 / `127.0.0.1:5555` / HarmonyOS 6.1.0(23)，2026-09-12；
源码版本 `HEAD=ac2e2a0` + 脏工作区（`git status --porcelain` sha1 `0a04f68f…`）。
**证据总入口**：`.scratch/files/evidence/README.md`（本地保留、不入库）。

#### 落地清单

| 层 | 文件 | 作用 |
| --- | --- | --- |
| domain | `domain/files/FilePath.ets` | 落盘根（文档/缓存）、缓存键（**空 id 兜底**）、文件名形状（省略课程名）、`formatSize`、`TYPE SIZE` 一行、pdf/图片分档 |
| domain | `domain/files/FileDownloadPolicy.ets` | **落盘前**判定（状态码 / `text/html` / JSON）、会话失效原因分类、`appendCsrfToken`（按 `searchParams.set` 语义）、`redactCsrfToken` |
| data | `data/remote/DownloadPort.ets` + `HttpDownloadPort.ets` | 新的**兄弟**端口（`FetchPort` 一行未动）：`requestInStream` + `dataReceive`，真字节进度；头到达即判、拒绝即刻 `destroy`（**一个字节都不写**） |
| data | `data/files/FileStorePort.ets` + `DeviceFileStore.ets` | 文件系统端口（`@ohos.file.fs`）：写 sink、递归删目录 |
| data | `data/files/FileDownloader.ets` | 编排：缓存命中 → 建目录 → 头判定 → 写 → 状态码复核 → 收尾（失败一律删目标路径）；`clearCache()` |
| data | `data/files/FileRepository.ets` / `FileFetchSource.ets` / `RealFileRepository.ets` | 文件 tab 自己的取数（学期 → 课程列表 → `FilesFetcher`）与下载，二者都走 `AuthedTaskRunner` |
| data | `data/settings/FileSettings.ets` + `PreferencesFileSettings.ets` | 两个设置项的值/语义/持久化 + 取证用运行时覆盖（**界面入口归 ticket 17**） |
| features | `features/files/FilesPage.ets` / `FileDetailPage.ets` / `FileSettingsPage.ets` / `FileListStore.ets` / `FileRoutes.ets` / `repository/FileRepositoryProvider.ets` | 列表（上传时间倒序 + 类型/大小）、详情（下载进度 / 应用内预览 / 分享）、文件设置（两个开关 + 清理缓存） |
| 接线 | `features/shell/ShellTabs.ets`、`notices/NoticesPage.ets`、`assignments/AssignmentsPage.ets`、`courses/CoursesPage.ets` | 文件 tab 换成真身；三条 `ROUTE_FILE_DETAIL` 与 `ROUTE_COURSE_FILE_DETAIL` 都渲染 `FileDetailPage`；**删掉两个占位页** |
| i18n | `scripts/i18n-ui-strings.mjs` + 3 个 `string.json` + `I18nKeys.ets` | 新增 27 条 `ui_*`（含 PDF 翻页 3 条），键总数 270 → 297 |

#### 逐条验收

| # | 验收 | 结论 | 独立证据 | 可重跑命令 |
| --- | --- | --- | --- | --- |
| 1 | 列表按上传时间倒序、显示大小与类型 | **达成** | `evidence/A1-files-tab-autumn-list.png`（4 条；每行 `ZIP 212.0M` = 类型 + 大小） | `aa start`（无覆盖）→ `devecocli ui click --device 127.0.0.1:5555 660 2640` → `hilog -x` 里 `data.files fetched courses=2 items=4 … failures=0`、`files refresh done: items=4` |
| 2 | 下载显示进度，完成后可预览；PDF / 图片应用内 | **一半：进度达成；PDF 未达成（平台缺口）；图片未抓到样本** | 进度：`evidence/D1-progress-layout-during-download.json`（`下载中` / `330.64 MB / 700.48 MB` / `47.000000`）+ `D2-download-completed-info-panel.png`；PDF 缺口：`B2-pdfview-crash-hilog.txt`（`does not provide an export name 'pdfViewManager'`）与 `B4-pdf-preview-unsupported-note.png`（如实提示，不崩不跳第三方） | 点第 3 行（700 MB ZIP）→ 立刻 `devecocli ui layout --device 127.0.0.1:5555 --format json`（应见"下载中"与已接收/总量） |
| 3 | 会话过期下载到登录页 → 识别 + 提示 + 无损坏文件 | **机制达成（注入替身单测）；设备侧未抓到** | `entry/src/test/FileDownload.test.ets` 的 `neverOpensTheFileGateWhenTheResponseIsALoginPage`（`openCalls===0`、无文件、原因 `html-login-page`）与 `turnsALoginPageIntoRequiresEnrollmentWithoutLeavingAFile`（任务两次都 403、`requiresEnrollment=true`、无文件） | `hvigorw … test --no-incremental` |
| 4 | 分享面板可调起；含中文与空格的路径可用 | **达成** | `evidence/C2-share-panel.png`（系统分享面板 + 文件卡片）+ hilog `file detail share uri: file://…/%E8%BD%AF%E4%BB%B6…-16%20abstractio%20and%20refinement.pdf`（中文百分号编码、空格 `%20`） | 打开该 PDF → 点"分享"（1074,206）→ `hilog -x` 里 `file detail share uri/utd/calling show` |
| 5 | 清理缓存后文件真正消失；两个设置均生效 | **达成** | 设置：`file download plan: useDocumentDir=true omitCourseName=true root=…/files/learnX-files … path=…/期末复习.pdf`（根=文档、文件名不含课程名）+`E2-file-settings-page.png`；清理：`E3/E4` + `file cache cleared: … removed=true` + **清理后重开同一文件 `fromCache=false`**（`E5-redownload-after-clear.png`） | `aa start … --ps lohFileUseDocumentDir 1 --ps lohFileOmitCourseName 1`；随后在文件设置页点"清空文件缓存"→"确定" |
| 6 | 真机截图 | **转 ticket 18** | — | — |

#### 门禁（原始数字）

- 单测：**`Tests run: 325, Failure: 0, Error: 0, Pass: 325, Ignore: 0`**（基线 302，本 ticket +23 条）。
  命令：先删 `entry/.test`，再 `hvigorw --mode module -p module=entry@default -p product=default test --no-incremental`（`DEVECO_SDK_HOME` 已设）。
- 四个脚本：`check-domain-purity` **PASS**；`check-import-graph` **PASS**（仅入口文件在孤儿 WARN 列表）；`check-i18n-keys` **RESULT: OK**；`check-generated-fresh` **PASS**。
- 产物：`entry-default-signed.hap` 2,526,579 B @ 19:57:22；解包 `ets/modules.abc` 检索到新符号、检索不到已删占位页符号与 `officeservice.PdfView`（详见证据 README）。

#### 未验证项

1. **PDF 应用内预览**：模拟器上 HMS PDFKit 的两条入口都不可用（`PdfView` 运行期缺 `pdfViewManager`；`pdfservice` 原生模块加载失败）⇒ 本轮**未达成**，真机复验归 ticket 18。
2. **图片应用内预览**：本账号文件只有 PDF/ZIP（春季 95 条里扫过的大部分都是 PDF），**没有图片样本**。
3. **会话过期到登录页**：设备侧未抓到（只有注入替身单测）。
4. **进度条的像素截图**：未抓到（只有 layout dump 文本）。

#### 取样代价

约 10 次冷启动（含 `--ps` 覆盖）、3 次 `hdc install`、约 20 次 `devecocli ui`、6 次 `devecocli build`（1 次因 `@Builder toolbar` 与 `CustomComponent` 属性方法重名失败、1 次为 `PdfView` 崩溃修复）、2 次全量单测、1 次 700 MB 下载（已清）。

#### 有意偏离（台账）

- **`docs/accepted-deviations.md` 第 22 条**（本 ticket 新增）：文件详情的"预览 / 打开"。
  先摆正参考实现的实际行为（**它本来就有应用内预览**：pdf 走 react-native-pdf、图片走 WebView；
  真正外跳的只有"打开"那个按钮的 `FileViewer.open`），再登记两条偏离：
  **B1 渲染器替换**（PDFKit 的 `pdfService` / ArkUI `Image`）、**B2 不再提供外跳"打开"动作**。
- **`docs/reference-quirks.md` 第 23 条【平台事实】**（本 ticket 新增）：`PdfView` 组件在模拟器上运行期不可用，
  以及改用 `pdfService` 的处置与证据。
  *流程说明（诚实记录）*：第 22 条的正文是在**同一轮**里先写台账、再改代码落地本 ticket 的文件详情页；
  严格意义上的"先改台账再改代码"在时间上并非"台账提交在前"，但台账文本先于代码定稿。
- **边界说明**（两边都写了）：ticket 04（占位页被真身取代 + 三个**可选**参数）、ticket 05/06（新增兄弟端口 `DownloadPort`，`FetchPort` 一行未动）、
  ticket 12（课程文件的占位页被真身取代）、ticket 17（文件设置：值/语义在我这儿，界面入口归你）。
- **未改的前提**：`FileDetailRouteParams.noticeId` 字段名与语义、三个 `ROUTE_*` 常量、`CourseFileDetailRouteParams` 形状都原样保留（只**追加可选字段**）。
### 统筹验收（2026-09-12，**模拟器** Pura 90 / HarmonyOS 6.1.0(23)）→ Status: verified-partial

**结论：第 1 / 4 / 5 条通过；第 2 条**一半**（下载进度与落盘通过，**PDF 应用内渲染在模拟器上平台不可用** ⇒ 转 ticket 18，替代验收标准**暂不定案**）；第 3 条机制成立、设备侧未复现；第 6 条转 ticket 18。**

#### 1. 我独立重跑 / 自查的（在 `fe5d0d5` / 工作区干净上）

| 检查 | 我的命令 | 我读到的结果 |
| --- | --- | --- |
| 全量单测 | 删 `entry/.test` + `test --no-incremental` | `Tests run: 325, Failure: 0, Error: 0`（基线 302，+23） |
| 四脚本 | 四个 `check-*.mjs` | PASS / PASS（孤儿仅两个入口文件）/ RESULT: OK / PASS；`git status` 干净。en_US 那条 untranslated 是 `ui_file_download_progress` = `%1$s / %2$s`，中英同值是**正确**的（纯格式串） |
| 产物级符号 | 我自己解 `entry-default-signed.hap`（2,526,579 B @19:57:22） | `ets/modules.abc` 1,099,016 B；命中 `learnX-files / lohFileUseDocumentDir / html-login-page / HttpDownloadPort / PdfDocument / getPagePixelMap / file detail share utd: / unavailable on this platform`；`FileDetailPlaceholderPage / officeservice.PdfView` 为 False |
| **文件线确实按学期取数**（我自己跑） | `--ps lohSemester 2025-2026-2` → 点文件 tab（660,2682）→ 全量 hilog | `data.files effective semester=2025-2026-2 source=override` → `data.files fetched courses=7 items=95 elapsedMs=241 requests=7 failures=0` → `files refresh done: items=95`；截图 95 条、每行 `PDF 276K` / `PDF 3.0M`（类型 + 大小）+ `3个月前` ⇒ 第 1 条成立 |
| **下载与降级**（我自己跑） | 点第一条（期末复习 PDF 276K）→ 全量 hilog | `file download plan: root=…/cache/learnX-files path=…/软件分析与验证-期末复习.pdf` → `GET …downloadFile?sfgk=0&wjid=…&_csrf=***` → `file download done: bytes=283252 expected=283252 contentType="application/pdf"` → `download report: ok=true … rejected= requiresEnrollment=false` → `file detail ready: … bytes=283252 fromCache=false` → **`file detail preview pdf unavailable on this platform: Cannot read property PdfDocument of undefined`**；界面**不崩、不跳第三方**，信息面板 +「该文件类型不支持应用内预览，可下载后分享给其他应用。」 |
| **两个设置真的改落盘**（我自己跑） | `--ps lohFileUseDocumentDir 1 --ps lohFileOmitCourseName 1` 冷启动后同样点第一条 | `effective file settings: useDocumentDir=true omitCourseName=true override…=true source=runtime-want-param`；`plan: root=/data/storage/el2/base/haps/entry/files/learnX-files … path=…/期末复习.pdf` —— 与我默认态那次（`cache/learnX-files` + `软件分析与验证-期末复习.pdf`）**可逐字段对比**：根 cache→documents、文件名去掉课程名前缀 ⇒ 第 5 条成立 |
| 我读过但没复跑的证据 | D1（进度）/ C2（分享面板）/ E3-E5（清理缓存因果）/ B2（PdfView 崩溃原文） | D1 的 layout 文本确实是 `下载中` / `330.64 MB / 700.48 MB` / `47.000000`（真字节，不是假进度）；E5 是「清理后重开同一文件 `fromCache=false`」的因果链，不只是「没抛异常」 |
| 设备卫生 | 我顺手删掉应用沙箱里 ticket 10 遗留的 `excellent-probe.txt` | 已删（仓库证据目录里有它的副本，删设备那份不影响取证） |

**我没能自己抓到的一项（如实记）**：**下载进度**。我挑的样本只有 276 KB，`done` 在 120 ms 内发生，3 秒后的 dump 已是完成态 ⇒ 进度这条**采信 D1**，在此注明「我未复现」。

#### 2. 第 2 条 PDF 那一半：我的裁定

- **根因是平台缺口，不是我们偷偷跳第三方**：`PdfView` 组件运行期缺 `pdfViewManager`（崩溃重启，台账第 23 条 + `B2` 原文）；改用同套 `pdfService` 后是 `Cannot read property PdfDocument of undefined`（我自己那轮的原文）。
- **「如实提示 + 分享」这个处置我认可为本轮的正确行为**（不崩、不跳第三方、不留半成品）。
- **但它还不是「替代验收标准」**：验收第 2 条明确要求应用内打开 ⇒ **闭口时点定在 ticket 18 的真机复验**（MatePad Air 通常带 HMS Core）。若真机同样不可用，我才把「如实提示 + 分享」写成 `docs/accepted-deviations.md` **第 22 条的终态**替代验收标准（那是一次决策变更，要同时写进台账与 ticket 18）。
- **图片那一半缺样本**：春季 95 条我肉眼可见的全是 PDF、秋季 4 条是 ZIP ⇒ 无图片样本。文件路径 / URI 那半条链路已被 PDF 下载走通（同一个 `DeviceFileStore` / `FilePath`），**未验证的只是「解码并渲染图片」**。同样转 ticket 18。

#### 3. 第 3 条：机制成立、设备侧未复现（我认这个口径）

注入替身的单测钉住了两条分支（HTML 响应 ⇒ 不落盘 + 原因 `html-login-page`；两次 403 ⇒ `requiresEnrollment` + 无残留文件）。
设备侧「下载到登录页」未复现 —— 这需要人为破坏会话，属危险操作，**我不要求本轮硬造**，如实记为未抓到。

#### 4. 一处证据口径提醒（不影响结论）

分享那一条的**原始 hilog 没有落成证据文件**：`file detail share uri: …` 只在 README / 交付说明里被引用，证据目录里除 `B2` 外没有原始日志文件。
`C2` 截图能证明「面板可调起」，但「中文 + 空格被正确百分号编码」这一条按本仓库口径应当有一份**可重跑的原始输出**。建议在 ticket 18（或下次动这块时）补存一次 `hilog -x` 原文。

#### 5. 取样代价

1 次全量单测、2 次冷启动 + 3 次点击 + 3 次 layout/截图 + 2 次全量 hilog + 1 次 hap 解包（约 6 分钟设备窗口）。**设备锁与构建锁均已释放。**
