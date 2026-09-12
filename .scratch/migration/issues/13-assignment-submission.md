# 13: 作业提交

**What to build:** 在作业详情提交正文与附件（来自文件管理器或相册），上传进度可见，提交成功后状态与附件同步更新。

**Blocked by:** 10（作业列表 + 详情）

**Status:** ready-for-agent

- [ ] 可填写正文并提交，服务端接受且详情反映新状态
- [ ] 可从文件管理器与相册各选一个附件，可移除未提交与已提交的附件
- [ ] 上传进度可见；失败有明确提示且不丢失已填内容
- [ ] 提交成功后详情显示已提交状态与附件
- [ ] 真机截图

## Comments

### 统筹提示（2026-09-12，**用户提供的事实**）—— 提交功能**无法用真实数据测试**

- 用户账号 **2026-2027 学年秋季学期没有作业**，而 **2025-2026 学年春季学期的作业已全部截止**。
- ⇒ 本 ticket 验收第 1 条（"服务端接受且详情反映新状态"）**在本账号上无法真实达成**：不存在一个"可提交"的真实作业。
- **绝对不要**为了取证对已截止的作业强行提交：那是**真实写操作、不可逆**，会污染用户账号（且用户只有一个账号）。默认路径是**不提交**。
- 因此本轮判据改为：
  1. 提交链路的**组装**（multipart 构造、字段名、`_csrf` 附加、进度回调、失败不丢已填内容、可移除附件）用**单测 + 本地假服务端/夹具**证明；
  2. 上传前的**只读**部分尽量用真实数据（详情页能正确显示"未提交"状态、附件、截止状态）；
  3. **"服务端接受"这一条明确记为未验证**（原因：无可用真实作业），并写清复现条件：**一旦出现真实未截止作业**（例如新学期开学留下一次真实作业）必须补一次端到端。
- 若将来确实需要真实提交：**先问统筹**，不要自行决定。
### ticket 13 交付

**结论**：提交链路（组装 → 发送 → 状态机 → 界面）已交付，判据是**单测 + 假端口**；
**服务端接受未验证**（本账号没有可提交的真实作业）；**本轮没有发生任何真实提交**（见未验证项 2）。

#### 字段与端点对照（本工程 ↔ 参考实现）

| 项 | 参考实现（`reference/learnOH-old/src/data/source.ts`） | 本工程 | 判据 |
| --- | --- | --- | --- |
| 端点 | `POST {learn}/b/wlxt/kczy/zy/student/tjzy`（:149） | `SUBMIT_ASSIGNMENT_PATH`（`data/assignments/SubmitAssignment.ets`） | 单测断言 URL |
| `_csrf` | `addCSRF(url)` 追加到 URL（:75-80, :168） | `withCsrf(LEARN_ORIGIN + path, session.csrfToken)` | 单测断言 `?_csrf=` |
| 表单字段 | `xszyid` / `zynr` / `isDeleted`（:175-179），**无 `id`** | `UploadFormParams` 同三字段、同顺序 | 单测（字节级字段顺序 + 显式断言无 name=id 段） |
| 文件部分 | multipart，字段名 `fileupload`，文件名 = 用户选定/改过的名字 | `makeUploadFile(name, mime, data, DEFAULT_FILE_FIELD)` | 单测（fileupload 段、中文名 RFC 5987 `filename*`） |
| 无附件 | 不写文件部分 | `UploadSpec.file === undefined` | 单测 `sendsNoFilePartWhenOnlyContentIsGiven` |
| 移除附件 | `isDeleted='1'`、`content=''`、无附件 | `planSubmission` 的 removeAttachment 分支 | 单测 `removeAttachmentSendsIsDeletedOneEmptyContentAndNoFile` |
| 空提交早退 | 直接返回、不发请求（:161-163） | `AssignmentSubmitter.submit(undefined)` | 单测 `doesNotSendAnyRequestWhenThereIsNothingToSubmit` |
| 正文初值 | `removeTags(submittedContent).replace('-->','')`（:83-85，只替第一处） | `initialSubmissionContent` | 单测 |
| 失败不丢内容 | catch 里只复位 uploading/error/progress（:233-237） | 状态机 `submitFailed` | 单测逐字段比较 |
| 二次确认 | `Alert.alert(title, message, [cancel, ok])`（:250-268） | 系统对话框（`getPromptAction().showDialog`），取消即不发请求 | 设备 C2/C3 + 日志 |
| 「之前分享的」 | :294-302, :376-380 | **不移植** | 偏离 26 |
| 新附件行点击 | :358-374（本地 URI 进 FileDetail） | **不可点** | 偏离 27 |

#### `UploadSpec` / `UploadFormParams` 的形状变更（ticket 05 遗留的对不上）

`UploadFormParams` 由 `{id, xszyid}` 改为 `{xszyid, zynr, isDeleted}`；`UploadSpec` 的
`fileName` / `contentType` / `data` 收成一个可选的 `file`（无附件时不写文件部分）。
`id` 属于**作业描述接口**（`PostFormSpec.id`，发 `id=<zyid>`），参考实现的提交不发它。
**无边界说明负担的依据**：本次改动前 `FetchPort.upload` 没有任何调用点 ——
`grep -rn upload entry/src` 只命中定义（`Port.ets`）、实现（`HttpFetchPort.ets`）与两个测试替身的方法签名
（`DataFetch.test.ets` / `CourseData.test.ets`）。`Port.ets` 里那句把 `id` 说成提交接口字段的注释也一并改对。

#### 单测证据（假端口 + 假执行器，无平台依赖）

新增 `entry/src/test/AssignmentSubmission.test.ets`（14 条）并在 `List.test.ets` 注册；覆盖：

1. 字段顺序 `xszyid → zynr → isDeleted → fileupload → 结束边界`，且**无 `id`**；URL 带 `?_csrf=`；
   `fileupload` 字段名；中文 + 空格文件名 `作业 一.pdf` → `filename` 原文 + `filename*=UTF-8''…%20…`；
2. 无附件不写文件部分；移除态 `isDeleted='1'` + `zynr=''` + 无文件；
3. **空提交一个请求都不发**（端口 `uploads.length === 0`）；
4. 进度回调分段 0 → 0.25 → 0.5 → 1，且正文不丢；
5. **失败后 `content` / `customAttachmentName` / `attachment` 逐字段不变**（`submitFailed`），失败后 `canSubmit` 仍为 true；
6. 会话失效 ⇒ `requiresEnrollment=true`（既有 `AuthedTaskRunner` 口径）；
7. 响应判定（`result:error` / 非 JSON 含 error / 正常 JSON / 空正文）；
8. 默认附件名（中/英、`image/jpeg → jpeg`、未知 → `bin`）；自定义名去点 + 拼回扩展名（含参考实现的 `x.undefined`）；
9. 平台 URI → 文件名/MIME（中文 + 空格 + `?query` + 取不到时退回默认名）；正文初值。

**服务端接受这一条没有用假服务端回包冒充**：没有真实未截止作业，因此没有端到端证据。

#### 只读真实数据与 picker（模拟器 Pura 90 / `127.0.0.1:5555` / HarmonyOS 6.1.0(23)）

证据目录 `.scratch/submission/evidence/`（**逐文件的论断表**见其 `README.md`）。要点：

- 春季（`--ps lohSemester 2025-2026-2`）列表 全部 57 / 未完成 0 / 已完成 57，全部已截止（`A1`）；
- 已截止作业详情：chip、截止时间 + 已截止、作业附件、**已提交**（附件 + 提交于 2026-06-27 09:58）、
  成绩 10 + 批改人/时间、作业内容；**页头右侧多出本轮新增的提交入口**（`A2`）；
- 点该入口（已截止）⇒ hilog `submission entry blocked: past deadline=2026-06-28 23:59`（`A4`）；
  **toast 未抓到**（截图时延远大于 toast 时长），`A3` 只是一张同屏画面，**不**充当 toast 证据；
- 夹具构建（`MOCK_ASSIGNMENTS_FOR_EVIDENCE=true`，只为让提交页可达）下：提交页初始态（`B3`，「提交」灰）、
  两个 picker **都能打开**（`B4/B5/B8`）、取消 ⇒ 空数组算取消不算失败（`B-log`）、
  输入正文后「提交」变紫可用（`C1`）、点「提交」出二次确认（`C2`）、点「取消」后内容仍在且无请求（`C3` + `C-log`）；
- 提交态（`MOCK=false`）装机后仍是真实 57 条 + `assignments evidence: mock=false`（`D1/D2`）；
- 产物级：解 hap 后 `ets/modules.abc` 里本轮符号 = true、历史探针串 = false、
  `pendingAssignmentData` = **false**（`hap-modules-abc-symbols.txt`）。

#### 未验证项与复现条件

1. **服务端接受未验证**。原因：本账号 2026-2027 秋季 **0 条**作业，2025-2026 春季 **57 条全部已截止**。
   复现条件：一旦出现真实未截止作业 → 打开详情 → 提交入口 → 填正文/选附件 → 提交 → 确定；
   期望 hilog 出现 `data.assignments.submit sending …` 与 `response status=200 … ok=true`，
   随后重取数的列表与详情反映新状态与附件。
2. **本轮没有任何真实写操作**：设备上唯一走到「点提交」的路径在**二次确认弹窗处被取消**（C2 → C3），
   日志里没有任何 `data.assignments.submit sending` 行；夹具用的是虚构 `studentHomeworkId`，也没发出去。
3. **选到文件未验证**（picker 能开，但没有内容可选）：用户区为空、`hdc file send` 的文件不被「最近」收录、
   「浏览 → 我的手机」对 `hdc` 点击无响应（两次点击截图字节相同）、相册 `itemCount: 0`。
   复现条件：设备用户区里有任意文件（或图库里有照片）→ 提交页 → 文件/照片 → 选中 →
   期望出现附件行 + 自定义名输入框 + 提交按钮可用。
4. **上传进度条、失败提示（不丢内容）在设备上未验证**（都需要真实请求）。二者的可单测部分已由单测覆盖。
5. **取消语义已实测**（原为未定项）：取消 ⇒ `select` resolve 成空数组（不抛异常），被当作 cancelled、不发 toast；
   这一条同时消除了 `AttachmentPickers` 文件头里的不确定表述。

#### 门禁数字（提交前真跑）

| 门禁 | 结果 |
| --- | --- |
| `hvigorw … test --no-incremental`（先删 `entry/.test`，`DEVECO_SDK_HOME` 已设） | **Tests run: 348, Failure: 0, Error: 0, Pass: 348, Ignore: 0**（基线 334，本轮 +14） |
| 后台 `hvigorw … assembleHap --no-incremental` | BUILD SUCCESSFUL |
| 产物检索（解 hap → `ets/modules.abc`） | 本轮符号 = true，历史探针串 = false |
| `node scripts/check-domain-purity.mjs` | PASS（21 个领域源文件） |
| `node scripts/check-import-graph.mjs` | PASS（163 个源文件；孤儿仅 `EntryBackupAbility.ets` / `pages/Index.ets`） |
| `node scripts/check-i18n-keys.mjs` | RESULT: OK（manifest 302 键；base/zh_CN/en_US missing=empty=extra=0；140 个引用键全解析） |
| `node scripts/check-generated-fresh.mjs` | PASS（6 个生成物 + 2 个生成器） |

#### 代价与已知取舍

1. **`AuthedTaskRunner` 的「重登后只重试一次」会作用于上传**：传输层失败（status 0 被映射成 403）会触发一次
   重登并**重发一次提交**；若第一次其实已到达服务端而响应丢失，理论上存在重复提交。这是「所有请求都走既有
   `AuthedTaskRunner`」这条硬约束的直接后果（参考实现是先登录再单次提交、不重试）；本轮**无法用真实提交评估
   其概率**，如实记录、不改 runner。
2. **成功后重取数用 `CourseListStore.refresh()`**（整轮课程 + 三域），而不是参考实现的 `getAssignmentsForCourse(courseId)`
   （按课程）—— 本工程没有按课程取数这条路径。代价：一次多余的全量抓取；收益：不新增第二条取数链路。
3. **新增 1 条 i18n UI 键** `ui_assignment_submission_time`（整条 dayjs 模式含前缀，逐字取自
   `AssignmentSubmission.tsx:445-453`）：键总数 301 → 302，`I18n.test.ets` 的计数常量随之 +1。
4. **新增 1 枚图标** `AppIcon.FILE_UPLOAD`（MaterialIcons `file-upload`，码位 0xE2C6 抄自
   `react-native-vector-icons@10.2.0` 的 glyphmap）：`IconCatalog.ets` 闭集与 `IconCatalog.test.ets` 期望表 +1（15 → 16）。
5. **不移植「之前分享的」（偏离 26）与新附件行不可点（偏离 27）**：理由、替代验收标准与
   「参考实现自己也没给它写过非 null 值」的检索证据见 `docs/accepted-deviations.md`。
6. **页面只由应用构建覆盖编译**：`AssignmentSubmissionPage` / `AttachmentPickers` /
   `features/assignments/repository/*` **不在** local 单测的编译可达集里（`entry/.test` 的编译缓存与覆盖率报告都不含它们），
   所以它们的编译正确性只由 `assembleHap` 保证 —— 与 ticket 05 的教训同源，避免后来者以为「单测全绿」覆盖了界面。

#### 并发备注（**与开工前提不符，按实记录**）

开工时被告知「目前无并行 agent」，但本轮进行期间观察到一个**并行写者**：`docs/reference-quirks.md` 在我写入
索引行之后被追加了 **第 28 条**（标题含「ticket 16 侦察，2026-09-13」），`.scratch/migration/issues/16-split-view-breakpoints.md`
也处于已修改状态（`git status` 可见）。未发生冲突：我的两条索引行（26/27）仍在，第 28 条在其后；**编号上我避开了 28**，
本 ticket 的平台事实登记为 **第 29 条**。我的提交只暂存本 ticket 的文件（不含 ticket 16 的 issue 文件），
但 `docs/reference-quirks.md` 会**一并带上** ticket 16 的第 28 条（提交信息里已注明归因）。

