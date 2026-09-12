# 10: 作业列表 + 详情

**What to build:** 作业 tab 显示真实作业（未到期在前、已过期在后），详情展示描述、附件、提交状态、成绩与优秀作业。

**Blocked by:** 09（已完成）、12（已完成）——两者均已 `verified`

**Status:** verified（模拟器口径；第 1–4 条 + 「优秀作业」补做通过；第 5 条真机转 ticket 18）

- [x] 列表按截止时间排序（未到期在前），显示状态标记与截止时间（模拟器：真实 57 条已核；「未到期在前」由夹具覆盖）
- [x] 详情正确显示描述（含公式）、本地化的成绩等级、四类附件（「公式」为夹具证据：真实 57 条无一条带公式）
- [x] 附件可点（四类均渲染并推 FileDetail 路由；**预览/下载真身归 ticket 11**，边界已在那边写明）
- [x] 无作业或全部已过期时显示正确空态（秋季真实 0 条 + 「未完成」视图空态各有独立截图）
- [ ] 真机截图（**转 ticket 18**；本 ticket 全部证据为模拟器口径）

## Comments

### 统筹提示（2026-09-12，**用户提供的事实**，非设备观测）—— 真实账号当前学期**没有作业**

- 用户账号在 **2026-2027 学年秋季学期没有作业** ⇒ 真实数据下**作业列表为空是正常现象**，不是缺陷、不是解析器出错、也不要当成"取数失败"。
- 因此本 ticket 的取证路径分三层，**别把空列表当失败**：
  1. **空态（验收第 4 条）**——在真实账号上这是常态，必须干净渲染（不是白屏、不是报错、也不是"空列表且无任何提示"）。这条**反而是本 ticket 在真实数据上唯一能一次跑通的判据**，请优先取证。
  2. **mock 数据**测列表/详情的渲染、排序与状态标记（ticket 03/05 的夹具仍可用）——按用户的意思，作业相关功能可以先用 mock 测。
  3. **真实数据**要拿到作业，必须切到 **2025-2026 学年春季学期**（上学期）：那需要学期切换能力（**ticket 12**），或在取证期用一个**开关守卫的学期覆盖**（开关**实际生效值**必须打进 hilog，取证后复原）。
- 切到上学期后的预期：作业**全部已截止** ⇒ 这条路径正好覆盖"已过期在后"的排序要求与"已过期"状态标记；**不要**期待未到期形态。
- 与 ticket 05 的关系：那批真实解析器至今**未被真实数据行使过**（此前业务数据层是 mock），所以拿到真实作业时**逐字段与网页端对照**。

### 统筹补充（2026-09-12，ticket 12 验收后）—— 取数前提、截止时间、以及"别把空当成同一个空"

1. **学期覆盖只作用于「课程这条线」，不会自动让作业 tab 切过去。** 我在模拟器上实测：`aa start … --ps lohSemester 2025-2026-2`
   且**不点课程 tab** 时，日志只有 `semester override: … effective="2025-2026-2"`，数据侧仍是
   `data.courses resolved semester=2026-2027-1 requested= courses=2`；点了课程 tab 才出现
   `effective semester=2025-2026-2 source=override` → `courses=7` → `assignments=57`。
   源码上：覆盖只在 `data/courses/CourseFetchSource.fetchWithSession()`（`CourseFetchSource.ets:90`）里被读，
   公告/作业路径的 `fetchWithSession(session)` 连学期参数都没有（`data/notices/RealNoticeRepository.ets:44`）。
   ⇒ **本 ticket 必须把"生效学期"接进自己的取数路径**：用 `effectiveSemesterOverride()`（优先级 override > 界面选择 > 站点当前学期），
   或直接复用课程线已抓到的 `CourseSnapshot.assignments`（覆盖态下就是春季那 57 条）。
   **否则在 `--ps lohSemester` 下作业 tab 仍取「站点当前学期」= 空**，而"空"同时也是账号事实 ⇒ 两个原因会在日志上长得一样，
   你会把"前提没接上"误判成"账号确实没作业"。取证时**必须**在 hilog 里看到 `effective semester=… source=override` 那一行。
2. **截止时间直接读 `Assignment.deadline`**：站点把 `jzsj` 下发成 epoch 毫秒**数字**（春季 57/57 条），ticket 12 已按 dayjs 对齐修好
   （数字 → 本地 `YYYY-MM-DD HH:mm`，字符串原样保留）。别再自己 `Number(...)`/`new Date(raw.jzsj)`。
   界面上已经能正常显示（ticket 12 的 E3：`2026-05-31 23:59` 等 3 条）。
3. **真实数据只能覆盖「已提交 / 已过期」两种形态**：春季 57 条作业**全部已截止**（账号事实），"未到期"形态只能靠 mock。
   **禁止**向任何已截止作业提交（见 ticket 13；那是真实且不可逆的写入）。
4. **取样成本**：一次「force-stop → `--ps` 启动 → 点课程/作业 tab → 全量 hilog」约 1–3 分钟设备窗口；
   春季那次抓取是 `requests=135 / elapsedMs=4548`（7 门课），比秋季（4 次请求）贵得多，别在一次会话里反复重抓。


### ticket 10 交付（2026-09-12，模拟器 Pura 90 / 127.0.0.1:5555 / HarmonyOS 6.1.0(23)）

**实现提交**：`a4285cee002daa9b5222dd6c9f922de0a83e845d`（源码 + 单测 + i18n 生成物）。
本节与 `docs/reference-quirks.md` 的第 19/20 条、ticket 05/11 的边界说明同属**第二个提交**（docs / 台账），
紧跟在实现提交之后。
**Status 留给统筹改**（本轮不自行置 `verified`）。

#### 1. 落地清单

| 文件 | 作用 |
| --- | --- |
| `entry/src/main/ets/features/assignments/AssignmentsPage.ets` | 作业 tab：列表 + 三个筛选片 + 详情栈根 |
| `entry/src/main/ets/features/assignments/AssignmentDetailPage.ets` | 作业详情：描述（Web/KaTeX）、提交、成绩、四类附件 |
| `entry/src/main/ets/features/assignments/AssignmentRoutes.ets` | `ROUTE_ASSIGNMENT_DETAIL`（从 ticket 12 的 `CourseRoutes` 收敛过来） |
| `entry/src/main/ets/features/assignments/AssignmentFilter.ets` | 纯规则：过滤视图、过期判定、空态判定 |
| `entry/src/main/ets/features/assignments/AssignmentText.ets` | 纯映射：成绩等级→资源键、完成/提交方式、截止状态、空态键 |
| `entry/src/main/ets/features/assignments/AssignmentEvidence.ets` | **提交态关闭**的取证夹具（4 条作业：未到期×2 / 已过期×2） |
| `entry/src/test/AssignmentList.test.ets` | 13 条单测（过滤/边界/排序/状态/等级表/空态/夹具开关） |
| `entry/src/test/DataFetch.test.ets` | +1 条：`assignmentsFetchSortsByDeadlineBeforeSplittingUpcomingAndPast` |
| `entry/src/main/ets/features/shell/ShellTabs.ets` | 作业 tab 从占位页换成 `AssignmentsPage` |
| `entry/src/main/ets/features/courses/{CoursesPage,CourseDetailPage,CourseRoutes,CourseDetailPlaceholder}.ets` | 作业详情占位页 → 真身（参数改成完整 `Assignment`） |
| `entry/src/main/ets/features/notices/{NoticeRoutes,FileDetailPlaceholderPage}.ets` | 只补注释：附件→FileDetail 的第二个调用方 |
| `entry/src/main/ets/domain/{model/ContentItem,parse/AssignmentParser}.ets` | `gradeLevel` / `gradeTime` 字段 + 三个时间字段规范化 |
| `entry/src/main/ets/data/remote/AssignmentsFetcher.ets` | 补上排序第一步（见台账第 19 条） |
| `scripts/i18n-ui-strings.mjs` + 4 个生成物 | 22 条 `ui_` 文案（267 键） |
| `docs/reference-quirks.md` | 新增第 19（两步排序，锁定）/ 20（完成方式数字枚举，锁定）条 |

#### 2. 逐条验收（每条：结论 + 独立证据 + 可重跑命令）

**第 1 条 · 按截止时间排序（未到期在前、已过期在后）、状态标记与截止时间**
- 结论：**达成**（真实数据 + 夹具）。春季 57 条真实作业列表顶部 `06-28 → 06-20 → 06-15 → 06-14 → 06-11`、
  底部 `05-21 → 05-18 → 05-17 → 05-14 → 05-10 → 05-08`，**严格按截止时间递减**；
  每条显示 `YYYY-MM-DD HH:mm` + 状态标记（未到期/已截止）+ 四枚状态图标（📎/✓/🎓/🔑）。
  "未到期在前"由夹具覆盖（真实账号两学期都取不到未到期形态）。
- 证据：`B1/B3-assignments-spring-list-*-final.png`、`B2/B4` 布局树、`B7-hilog-spring-assignments-full.txt`；
  夹具侧 `C1-assignments-mock-upcoming-final.png` + `C2`。
- 命令：

      hdc -t 127.0.0.1:5555 shell aa force-stop com.koracan.learnOH
      hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b com.koracan.learnOH --ps lohSemester 2025-2026-2
      devecocli ui click --device 127.0.0.1:5555 396 2682     # 作业 tab

**第 2 条 · 详情正确显示描述（含公式）、本地化的成绩等级、四类附件**
- 结论：**达成**。真实详情（`B5`）显示描述（WebView 渲染）、`成绩 10`、附件行；
  夹具详情（`C3`）把 `$$E = mc^2$$` 渲染成**行间公式**（截图里是排好版的公式，不是字面量）；
  `C5` 显示 `成绩 / 优秀`（`gradeLevel=distinction` 走本地化映射，不是 -85）；
  `C5b` 布局树四类附件行齐备（作业/我的提交/批改/答案附件）。
- 证据：`B5/B6`、`C3/C4`、`C5/C5b/C6/C6b`、`B7`（field 自证）、`C9b`。
- 命令：`devecocli ui click --device 127.0.0.1:5555 400 700`（列表第一条）。

**第 3 条 · 附件可点（目标路由明确）**
- 结论：**达成**。四类附件的行都推 `ROUTE_FILE_DETAIL`（ticket 04 的 `FileDetail`，参考
  `AssignmentDetail.tsx:143`），参数逐项对齐；落点是 `FileDetailPlaceholderPage`（真身归 ticket 11，
  边界说明已写进 ticket 11）。**实际点击过的 kind 有三种**：真实数据 main（`B7`）、
  submitted（`pre-fix/B9-hilog-file-detail-prefix.txt`）、夹具 answer（`C9b`：
  `attachment tapped: kind=answer … id=mock-att-answer`）；`grade`（批改附件）**没有单独点过** ——
  四类走的是同一个 handler 与同一条路由，差别只在参数；`C5b/C6b` 的布局树证明该行确实渲染且标了"批改附件"。
- 证据：`B8/B9`（真实 main 附件 → FileDetail 参数逐项）、`C7/C8`（夹具 answer 附件）、`B7/C9b`（hilog）。
- 命令：`devecocli ui click --device 127.0.0.1:5555 400 880`（详情页第一条附件行）。

**第 4 条 · 无作业或全部已过期时的空态**
- 结论：**达成**。秋季（真实账号 0 条）渲染 `暂无作业`（筛选片 0/0/0，不白屏、不报错）；
  春季（全部已提交）"未完成"视图为空时文案是 `没有未完成的作业`，与"暂无作业"**不同句**
  （`emptyStateKey` 按视图给键，单测钉住）。
- 证据：`A1/A2/A3`（秋季空态）；"未完成视图空态"的界面证据是 **`F1-assignments-spring-unfinished-empty-final.png`**
  + `F2-layout-spring-unfinished-empty-final.json`（补做轮抓到：筛选片"未完成 0"高亮、空态文案
  "没有未完成的作业"），机制证据另有单测 `emptyStateDependsOnTheViewAndOnBusy` +
  `allSubmittedAndPastShowsTheUnfinishedEmptyState`。
- 命令：`devecocli ui click --device 127.0.0.1:5555 411 492`（春季下点"未完成"筛选片）。

**第 5 条 · 真机截图**
- 结论：**未完成 → 转 ticket 18**（按 AGENTS.md 与 spec 第 8 节；真机 `3FYBB25407201890` 未连接）。
  本轮全部证据均为**模拟器**口径。

#### 3. 门禁（真跑）

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| 全量单测 | 删 `entry/.test` 后 `hvigorw --mode module -p module=entry@default -p product=default test --no-incremental` | `.test/default/intermediates/test/coverage_data/test_result.txt` 末行 **Tests run: 294, Failure: 0, Error: 0, Pass: 294**（基线 279，+15） |
| 构建 | `devecocli build` | BUILD SUCCESSFUL，产物 `entry-default-signed.hap` **2026-09-12 17:06:40**，2215842 字节 |
| 产物内容 | 解 hap → `ets/modules.abc`（905968 字节）子串检索 | 含 AssignmentsPage / AssignmentDetailPage / gradeLevelOf / compareAssignmentsByUpcoming / sortAssignments / `assignments applied`；探针串 PROBE-SWITCH / evidence.textcodec / TEMP-EVIDENCE = False（"PROBE" 唯一命中是 ticket 04 常驻的 `BRIDGE_PROBE`，见 `E1`） |
| 领域纯度 | `node scripts/check-domain-purity.mjs` | PASS（17 个领域源文件） |
| 导入图 | `node scripts/check-import-graph.mjs` | PASS（131 个源文件；孤儿仅两个入口文件） |
| i18n 键 | `node scripts/check-i18n-keys.mjs` | RESULT: OK（267 键 / 84 个被引用键全部解析） |
| 生成物新鲜 | `node scripts/check-generated-fresh.mjs` | PASS |
| 探针残留 | `git show <commit>:…AssignmentEvidence.ets` 与 `10-probe.patch` 对拍 | 开关 = `false`（单测 `evidenceFixtureCoversTheUpcomingFormAndIsOffAtCommit` 也在守） |

#### 4. 未验证项 / 未交付项（**不要当成全绿**）

1. **验收第 5 条真机截图**：转 ticket 18（模拟器口径已完成）。
2. ~~**"未完成"筛选片的空态截图**：未单独抓~~ → **补做轮已关闭**（`F1/F2`）。
3. ~~**"优秀作业"（excellentHomeworkList）未交付**~~ → **统筹裁定为缺口，补做轮已交付**（见文末"补做"一节）。
4. **描述含公式**：真实 57 条里**没有**一条描述带 KaTeX 公式（`B5` 的描述是纯文本），
   所以"公式渲染"这一半是**夹具**证据（`C3`），走的与公告详情同一条 `HtmlWebView`/`getWebViewTemplate` 链路。
5. **附件 id 为空**：真实提交/作业附件的下载地址是路径形态，`Attachment.id` 取不到 ⇒ 传空串
   （ticket 11 需兜底，已在 ticket 11 写边界说明）。
6. **跨 tab 的抓取代价**：作业 tab 与课程 tab 各建一个 `CourseListStore` ⇒ 两个 tab 都访问时
   **各自抓一次**（覆盖态各 135 请求 / ~4s）。本轮按"复用课程线的取数实现、不复制学期优先级逻辑"
   的要求选择这条最简路径；若要合并成单例 store，属跨 ticket 改造（会动 ticket 12 的 `CoursesPage`）。

#### 5. 取样代价

| 轮次 | 命令 | 代价（实测） |
| --- | --- | --- |
| 秋季（无覆盖） | `aa start` → 点作业 tab | `data.assignments fetched courses=2 items=0 requests=6 elapsedMs=161` |
| 春季（`--ps lohSemester 2025-2026-2`） | 同上 | `courses=7 items=57 requests=135 failures=0 elapsedMs=4090`（+通知/文件域，整轮 ≈4.5s） |
| 夹具态 | 同秋季 | 开关 false/true 各一次构建（18–26s 增量）+ 装机 |

设备窗口共 4 轮（install → 启动 → 点 tab → 截图/布局/hilog），每轮 1–2 分钟；**没有**在同一轮里反复重抓。

#### 6. 有意偏离（都已在 `docs/reference-quirks.md` 或此处登记）

- **截止时间那句的相对措辞**：参考实现用 dayjs humanize（"5个月前截止" / "还剩 3 天"）。
  平台侧 `Intl.RelativeTimeFormat` 给不出同样的前后缀（只有 "5个月前"/"3天后"），
  所以卡片与详情显示**站点原文 `YYYY-MM-DD HH:mm` + 状态标记（未到期/已截止）**，
  相对措辞仅作为详情页的第二行（ICU 措辞，不带参考实现的前后缀）。
  这是**措辞层**差异，语义与可核对性不变（截图里两头都能看到）。
- **筛选**：参考实现 FilterList 有 all/unfinished/finished/fav/archived/hidden 六个视图（下拉）；
  本轮交付前三个（收藏/归档/屏蔽属 ticket 14），并把下拉换成同屏三个筛选片。行为（切视图）一致。
- **完成方式 / 提交方式**：参考实现比较数字枚举；夹具里是中文标签、真实数据是数字代码
  ⇒ 新实现**两种形状都认**，见台账第 20 条。
- **作业详情不再有占位页**：ticket 12 的 `AssignmentDetailPlaceholderPage` 已删除，
  路由名与参数收敛到 `features/assignments/AssignmentRoutes.ets`（参数从扁平子集改成完整 `Assignment`）。
  ticket 12 验收第 4 条"能从作业标签页进入详情"**仍然成立且更强**（进去的是真身）。

#### 7. 在真实数据上发现并修掉的两条缺陷（详见 `.scratch/assignments/evidence/README.md` 第 7 节）

1. 已过期段没有排序（少了参考实现排序的第一步）——台账第 19 条；边界说明已写进 **ticket 05**。
2. `scsj`/`pysj`/`bjjzsj` 三个时间字段没有规范化（详情页出现 `提交于 1780143131000`）——
   边界说明已写进 **ticket 05**。
### 统筹验收（2026-09-12，**模拟器** Pura 90 / HarmonyOS 6.1.0(23)）→ Status: verified-partial

**结论：五条验收标准里第 1–4 条我独立复验通过**（不是采信转述）；第 5 条（真机）按 AGENTS.md 转 ticket 18。
另外我裁定「优秀作业」**构成缺口**（工单 What-to-build 有它，参考实现的**卡片**也依赖它），已派同一 agent 补做
⇒ **补做落地前本 ticket 不置 `verified`**（见第 4 节）。

#### 1. 我独立重跑的（在 `0d69fc0` / 工作区干净上）

| 检查 | 我跑的命令 | 我读到的结果 |
| --- | --- | --- |
| 全量单测 | 删 `entry/.test` 后 `hvigorw … test --no-incremental` | `Tests run: 294, Failure: 0, Error: 0, Pass: 294, Ignore: 0`（我自己跑，日志 `.dsh/logs/t10-coord-test.log`） |
| 四脚本 | `check-domain-purity / -import-graph / -i18n-keys / -generated-fresh` | `PASS`（17 领域源文件）/ `PASS`（131 源文件，孤儿仅两个入口）/ `RESULT: OK`（267 键）/ `PASS`；跑完 `git status` 干净 ⇒ 生成物无漂移 |
| 产物级符号 | 我自己把 `entry-default-signed.hap`（2,215,842 B，17:06:40）当 zip 解开 | `ets/modules.abc` = 905,968 B；命中 `AssignmentsPage / AssignmentDetailPage / AssignmentFilter / AssignmentText / gradeLevelOf / compareAssignmentsByUpcoming / sortAssignments / assignments applied / normalizeDeadline`；`PROBE-SWITCH` / `TEMP-EVIDENCE` 为 False |
| **我自己的冷启动 + 覆盖 + 点两个 tab** | `aa force-stop` → `aa start … --ps lohSemester 2025-2026-2` → `devecocli ui click … 924 2682`（课程）→ `… 396 2682`（作业）→ `hilog -x` 全量拉回本地筛 | `effective semester=2025-2026-2 source=override` → `data.assignments fetched courses=7 items=57 elapsedMs=3878 requests=135 failures=0 nonStringDeadlines=57` → `features.assignments assignments applied: reason=initial semester=2025-2026-2 source=override siteCurrent=2026-2027-1 items=57 visible=57 filter=all unfinished=0 finished=57 pastDue=57`（原始输出 `.scratch/assignments/evidence/coord/`） |
| 我自己截图核对排序 | 同上，作业 tab 截图 | 顶部 `2026-06-28 23:59 → 06-20 → 06-15 → 06-14 → 06-11`，全部「已截止」，筛选片 `全部 57 / 未完成 0 / 已完成 57`，头部「当前学期 2025-2026 学年春季学期 + 取证覆盖生效」 |
| 交付证据抽看 | A1（秋季空态）/ B5（真实详情）/ C3（公式夹具）逐张看过 | A1 = `暂无作业` + 0/0/0、不白屏不报错；B5 = 独立完成/在线提交、截止+「2个月前」、作业附件、已提交+我的提交附件+提交于、成绩 10+批改于、作业内容正文；C3 = `$$E=mc^2$$` 渲染成**行间公式**（KaTeX 链路） |

**第 3 条（附件可点）我认账的部分**：四类附件行都渲染且都推 `ROUTE_FILE_DETAIL`；实际点击过的 kind = main / submitted / answer，
`grade` 未单独点（同一 handler / 同一路由，参数不同）—— 这一条属于**替代验收**（布局树证明该行存在且标了"批改附件"），
我接受，但记在这里：它**不是**"四类各点一次"的直接证据。

#### 2. 我核对过的参考语义（判断"是不是真缺陷"）

- **排序（台账第 19 条）**：参考实现确实是两步 —— 每门课先 `sort(deadline 降序, id 降序)`（`actions/assignments.ts:49-53`），
  全局那条在 processor 里排完再切（`:122-128`）。**ticket 05 只搬了切分那一步**，所以已过期段是接口顺序 ——
  这是真缺陷，`compareAssignmentsByUpcoming(sortAssignments(collected), now)` 与参考行为等价。**判定：认可。**
- **数字时间字段（`scsj`/`pysj`/`bjjzsj`）**：与 ticket 12 的 `jzsj` 同源；`bjjzsj` 那条 `.length > 0` 判空在数字形态下永不赋值，属**真 bug**。**判定：认可**，
  且 ticket 05 已在两处（ticket 12 带入的那段 + 本轮追加）留有"原证据成立范围"的说明。
- **`completionType/submissionType` 数字枚举（台账第 20 条）**：参考实现比较的就是数字（`AssignmentDetail.tsx:153,158`），
  而它自己的**夹具**里是中文标签 ⇒ 两种形状都认是正确的收口方式。**判定：认可**（这正是"反推夹具与真实形状不一致"的典型）。

#### 3. 一处我第一手观察到的**代价**（不是缺陷，但要记住）

作业 tab 与课程 tab **各建一个 store**，都访问时**各抓一次**：我的 hilog 里两次完整抓取分别是
`17:18:24`–`17:18:29` 与 `17:18:51`–`17:18:56`（各 135 请求 / ~4 s）。交付方已在未验证项第 6 条写明；
我确认属实。合并成单例 store 属跨 ticket 改造（会动 ticket 12 的 `CoursesPage`），本轮**不做**，
留给"性能/架构"那一类收尾 ticket 判断。

#### 4. 我这一轮的裁定（补做项）

1. **「优秀作业」算缺口，已派原 agent 补做**（探针优先：先对春季 7 门课 + 秋季 2 门课 POST `yxzylist`，逐课记 `status/bytes/aaData.length`；
   全空则停下回报，非空则按参考语义补完取数/解析/卡片 medal/详情段/单测并用真实数据出证据）。
   理由：不只是详情页少一段 —— 参考实现的**作业卡片**在 `excellentHomeworkList.length > 0` 时显示黄色 medal（`AssignmentCard.tsx:84-91`），
   属**卡片保真**缺口。补做会动 ticket 05 已验收的 `AssignmentsFetcher`（加字段 + 每门课多一次 POST），
   已要求同一次编辑内更新 `DataFetch.test.ets` 的请求计数断言，并在 ticket 05 追加边界说明。
2. **"未完成视图空态"的界面证据**（交付方自己列的未验证项第 2 条）一并补：春季下点"未完成"筛选片 → 截图 + 布局。
3. **`.scratch/.gitignore` 的来历（已澄清）**：ticket 10 期间（16:57）该文件被改成 `**/evidence`，交付方报告"不是它改的"，
   一度被我怀疑是并行 agent 所为 —— **账号所有者确认：是他本人人工改的**（不是任何 agent，也没有并行会话）。
   该改动已核验语义后单独收编（提交 `238b211`）：已跟踪的 4 个 `evidence/README.md` 仍被跟踪，
   只有未跟踪的证据文件被忽略 —— 与"证据本地保留、不入库"的约定一致。**若将来要提交新证据文件需 `git add -f`。**
   （教训：工作区里出现不明改动时，先问账号所有者，再怀疑并发；本次唯一损失是我在提交信息里写了一句多余的"来源不明"。）

#### 5. 未验证 / 转出（与交付第 4 节一致，我逐条认账）

真机截图 → ticket 18；"描述含公式"的真实样本仍缺（真实 57 条无一条带 KaTeX，公式那一半是夹具证据，走的是与公告详情同一条 `HtmlWebView` 链路）；
**附件 `id` 为空**（真实提交附件是路径形态）⇒ 已写进 ticket 11 要求兜底；跨 tab 重复抓取见第 3 节；"优秀作业"与"未完成空态截图"见第 4 节。

#### 6. 我这一轮的取样代价

1 次全量单测（38 s 构建 + 测试）、1 次冷启动 + 2 次 ui 点击 + 1 次全量 hilog + 1 次截图（约 2.5 分钟设备窗口）、1 次 hap 解包。
**设备锁与构建锁均已释放**（补做轮已把两把锁交回原 agent）。


### ticket 10 补做交付（2026-09-12，模拟器 Pura 90 / 127.0.0.1:5555 / HarmonyOS 6.1.0(23)）

**实现提交**：`7a3f38c`（探针 + 优秀作业取数/解析/卡片/详情 + 单测）。
本节写的是**补做后**的数字 —— 上面第 3 节的 294 / 17:06:40 是**补做前**的。**Status 仍留给统筹改**。

#### 1. 探针（先探针、再决定）—— 逐课原始计数

做法：临时文件 `data/remote/ExcellentProbe.ets` + `AssignmentsFetcher.fetch` 末尾一行调用
（补丁 `.dsh/logs/10b-probe.patch`，**用后已删**，源码里查不到）；逐门课 POST `yxzylist`
（表单复用 `postForm({url, courseId})`），打印 `status / bytes / result / aaData`，
把**最大那一条原始响应**按 1500 字符分块打进 hilog **并**落到应用 files 目录后 `hdc file recv`。

| 学期 | 课程 id | status | bytes | result | aaData |
| --- | --- | --- | --- | --- | --- |
| 2025-2026-2 | 2025-2026-2151368314 | 200 | 172 | success | 0 |
| 2025-2026-2 | 2025-2026-2151368509 | 200 | 172 | success | 0 |
| 2025-2026-2 | 2025-2026-2151369202 | 200 | 172 | success | 0 |
| 2025-2026-2 | **2025-2026-2151370719** | 200 | **7013** | success | **18** |
| 2025-2026-2 | 2025-2026-2151370727 | 200 | 172 | success | 0 |
| 2025-2026-2 | 2025-2026-2151371077 | 200 | 172 | success | 0 |
| 2025-2026-2 | **2025-2026-2151371080** | 200 | **2451** | success | **6** |
| 2026-2027-1 | 2026-2027-1152226210 | 200 | 172 | success | 0 |
| 2026-2027-1 | 2026-2027-1152227978 | 200 | 172 | success | 0 |

⇒ **春季 24 条非空 ⇒ 按裁定补做**（18 条落在 12 个 `zyid`、6 条落在 3 个 `zyid`；**24/24 全部匿名**）。
证据：`P1-excellent-probe-spring.txt`、`P2-excellent-probe-autumn.txt`（`hdc file recv` 的原始文件）、
`P3-hilog-spring-probe-full.txt`、`P4-hilog-autumn-probe-full.txt`（逐课行 + raw 分块）。
可重跑：`aa start … --ps lohSemester 2025-2026-2` → `devecocli ui click --device 127.0.0.1:5555 396 2682`
→ `hdc … file recv /data/app/el2/100/base/com.koracan.learnOH/haps/entry/files/excellent-probe.txt …`。
（过程记录：秋季第一次启动 5 秒后被系统杀掉、应用侧零日志（`P4` 里只有 `onCreate`），**重试后成功** —— 当初那份 `P4` 已用重试版覆盖。）

#### 2. 落地清单（补做轮）

| 文件 | 变化 |
| --- | --- |
| `domain/model/ContentItem.ets` | 新增 `ExcellentHomework`；`Assignment.excellentHomeworkList?: ExcellentHomework[]` |
| `domain/parse/AssignmentParser.ets` | 新增 `RawExcellent` / `excellentHomeworkPageUrl` / `parseExcellentHomework` / `excellentDisplayAttachment` / `attachExcellentHomework`（文件末尾一节） |
| `data/remote/AssignmentsFetcher.ets` | `ASSIGNMENT_EXCELLENT_LIST_PATH` / `extractExcellentRows` / `fetchExcellent`（每门课 +1 POST、每条 +1 GET）；汇总行 `excellent=`；消费点自证行 `excellent: course=… zyid=… items=… anonymous=… named=…` |
| `features/assignments/AssignmentFilter.ets` | `hasExcellentHomework`（卡片 medal 判据） |
| `features/assignments/AssignmentsPage.ets` | 卡片右上角 🏅（`yellow500`，排在 📎/✓/🎓/🔑 之后，照 AssignmentCard.tsx:84-91） |
| `features/assignments/AssignmentDetailPage.ets` | "优秀作业"段（medal + `gradeAttachment || submittedAttachment` 可点 → `ROUTE_FILE_DETAIL` + "X的优秀作业"）；`assignment detail appear` 增 `excellent=<n>` |
| `features/assignments/AssignmentEvidence.ets` | 夹具加 2 条优秀作业（1 匿名 + 1 具名）—— 真实数据取不到具名那一支 |
| i18n | `ui_assignment_excellent` / `ui_assignment_excellent_by` / `ui_assignment_excellent_mark_label`（270 键） |
| 单测 | 新文件 `ExcellentHomework.test.ets`（7 条）+ `DataFetch` 新增 1 条 + 既有两个计数断言同步（post 9 → 10） |

#### 3. 逐条证据（每条结论配**独立**证物）

- **真实数据取数**（春季 7 门课）：`G4-hilog-spring-excellent-full.txt` 里
  `assignments fetched courses=7 items=57 … requests=166 failures=0 nonStringDeadlines=57 excellent=24`
  （166 = 135 + 7 次列表 + 24 次详情页）+ 15 行 `excellent: course=… zyid=… items=… anonymous=N named=0`。
- **卡片 medal（真实）**：`G1-assignments-spring-excellent-list-final.png`（列表顶）、
  `G1b-assignments-spring-excellent-medals-final.png` + `G2c-layout-spring-excellent-scroll2.json`
  （布局树里两处 `MEDAL @[1194,765…]` / `@[1194,1479…]`）。
- **详情"优秀作业"段（真实）**：`G5b-assignments-spring-excellent-section-final.png` +
  `G6b-layout-spring-excellent-section-final.json`（`🏅 优秀作业` / `🏅 9.pdf` / `匿名的优秀作业`）+ `G7`（`excellent=1`）。
- **附件可点（真实，优秀作业这一路）**：`G8/G9/G10`（`attachment tapped: kind=excellent name=9.pdf` →
  FileDetail 参数逐项；注意优秀作业的下载地址是 `/b/wlxt/kczy/zy/student/downloadFileyx/…`，
  **与作业附件的 `downloadFile` 不同**，ticket 11 需按 URL 原样用）。
- **夹具：具名作者那一支**（真实 24/24 全匿名）：`H1`（列表 🏅）、`H5`（`mock=true … excellent=2`）、
  `H6`（`assignment detail appear … excellent=2`）、`H3/H4`（`匿名的优秀作业` + `夹具同学的优秀作业`）、
  `H7/H8/H9`（`kind=excellent name=夹具优秀作业-提交.pdf id=mock-exc-att-submitted`）。
- **秋季 0 条**：`P2` + `P4`（2 门课均 `bytes=172 aaData=0`）。
- **未完成视图空态（裁定 2）**：`F1-assignments-spring-unfinished-empty-final.png` + `F2` 布局树
  （筛选片"未完成 0"高亮、空态"没有未完成的作业"）。
- **提交态复验 + 产物检索**：`I1`（真实 57 条）+ `I2-hilog-commit-state-full.txt`
  （`assignments evidence: mock=false … excellent=2`、`excellent=24 requests=166 failures=0`）；
  `E2-hap-modules-abc-symbols.txt`（`yxzylist`/`viewYxzy`/`ExcellentHomework`/`parseExcellentHomework`/
  `attachExcellentHomework`/`excellentHomeworkPageUrl` = True；`ExcellentProbe`/`excellent-probe`/
  `PROBE-SWITCH`/`evidence.textcodec`/`TEMP-EVIDENCE` = False）。

#### 4. 门禁（补做后，真跑）

| 检查 | 结果 |
| --- | --- |
| 全量单测 | 删 `entry/.test` + `--no-incremental` → **Tests run: 302, Failure: 0, Error: 0, Pass: 302**（基线 294，+8） |
| 构建 | `devecocli build` BUILD SUCCESSFUL，产物 **2026-09-12 18:04:40**，2242094 字节 |
| 产物内容 | `ets/modules.abc` = 924768 字节；见 `E2`（含优秀作业符号、无任何探针串） |
| 四脚本 | domain-purity PASS（17）/ import-graph PASS（131）/ i18n **RESULT: OK**（270 键、84 引用全解析）/ generated-fresh PASS |
| 探针残留 | 源码无 `ExcellentProbe`；产物检索同上；补丁留档 `.dsh/logs/10b-probe.patch` + `10b-mock-switch.patch`（含 `.keep`/`.on`） |

#### 5. 偏离（已登记在 `docs/reference-quirks.md` 第 21 条）

1. **不取 `getHomeworkDetail(baseId)`**（参考实现对每条优秀作业再 POST 一次描述接口）：该作业描述同一次 fetch 已取到，
   优秀作业段也不显示它 ⇒ **请求数减少**（24 次），界面可观察量不变。
2. **失败粒度更细**：参考实现 `Promise.all` 一条详情页失败丢整门课；这里单条失败 ⇒ 保留该条（无附件）+ warn。
   整条列表失败 ⇒ warn + 作业列表/次序不受影响（参考实现原语义）。
3. 卡片/详情用 🏅 emoji 代替 MaterialCommunityIcons 的 medal（同第 16 条的判断）。
4. 请求数如实增加（135 → 166）并进汇总行；ticket 05 的边界说明已追加"追加之二"。

#### 6. 仍未验证 / 转出

- **具名作者（非匿名）**这一支在真实数据上取不到（春季 24/24 `sfzm='是'`）⇒ 只有夹具证据（H3/H4）。
- 优秀作业附件只到"名字 + 下载地址 + 参数逐项"这一层；真身（下载/预览/分享）仍归 ticket 11。
- 真机截图仍转 ticket 18（本轮全部为**模拟器**口径）。
- **取样代价**：探针 2 轮（春季 7 门课、秋季 2 门课）+ 补做后 2 轮（真实春季、夹具）+ 提交态 1 轮；
  每次全量抓取春季 `requests=166 / elapsedMs≈5.2–6.7s`。
### 统筹验收（补做轮 · 2026-09-12，**模拟器** Pura 90 / HarmonyOS 6.1.0(23)）→ **Status: verified（模拟器口径；真机转 ticket 18）**

**结论：「优秀作业」补做通过，第 4 节那条"缺口"关闭；五条验收标准第 1–4 条 + 补做项全部我独立复验通过。**
（第 5 条真机截图按 AGENTS.md / spec 第 8 节转 ticket 18；本 ticket 至此在模拟器口径上全绿。）

#### 1. 我独立重跑的（在 `ccee783` / 工作区干净上）

| 检查 | 我跑的命令 | 我读到的结果 |
| --- | --- | --- |
| 全量单测 | 删 `entry/.test` 后 `hvigorw … test --no-incremental` | `Tests run: 302, Failure: 0, Error: 0, Pass: 302, Ignore: 0`（基线 294，+8；日志 `.dsh/logs/t10b-coord-test.log`） |
| 四脚本 | 四个 `check-*.mjs` | `PASS`（17 领域）/ `PASS`（132 源文件）/ `RESULT: OK`（270 键）/ `PASS`；`git status` 干净 |
| 产物级符号 | 我自己解 `entry-default-signed.hap`（2,242,094 B，18:04:40） | `ets/modules.abc` = 924,768 B；命中 `yxzylist / viewYxzy / ExcellentHomework / parseExcellentHomework / attachExcellentHomework / excellentHomeworkPageUrl / excellent=`；`ExcellentProbe / excellent-probe / PROBE-SWITCH / TEMP-EVIDENCE` 全 False |
| **探针原始响应（我不看结论，看 bytes）** | 直接读 `.scratch/assignments/evidence/P1-excellent-probe-spring.txt` / `P2-…-autumn.txt` | 春季：`…719` = 200 / 7013 B / `aaData` 18 条、`…1080` = 200 / 2451 B / 6 条、其余 5 门 = 200 / 172 B / 0；`"zyid"` 出现 **24** 次、`"sfzm":"是"` **24** 次 ⇒ **真实存在 24 条、且 24/24 匿名**是站点原始响应说的，不是我们代码的分类。秋季 2 门 = 200 / 172 B / 0 |
| **我自己的冷启动 + 覆盖 + 作业 tab** | `aa force-stop` → `aa start … --ps lohSemester 2025-2026-2` → `devecocli ui click … 396 2682` → `hilog -x` 全量拉回本地筛 | `effective semester=2025-2026-2 source=override` → **15 行** `data.assignments excellent: course=… zyid=… items=… anonymous=… named=0` → `data.assignments fetched courses=7 items=57 elapsedMs=6198 requests=166 failures=0 nonStringDeadlines=57 excellent=24` → `assignments applied: … items=57 … pastDue=57` |
| **卡片 🏅（我自己滚动取证）** | `devecocli ui fling --device 127.0.0.1:5555 660 2200 660 700` ×6 → 两帧截图 | 第二帧：**离散数学方法 / 作业（10）与 作业（9）** 的图标行是 `📎 ✓ 🎓 🏅`（四枚齐、位置一致），而同一屏里没有优秀作业的条目**没有** 🏅 ⇒ 图标与数据是对应的，不是画死的 |
| 交付证据抽看 | `G5b`（详情优秀作业段）/ `F1`（未完成视图空态） | G5b：`🏅 优秀作业` + `🏅 9.pdf` + `匿名的优秀作业`（同一张详情里"批改附件"与"优秀作业附件"是两段、两条不同的下载地址）；F1：筛选片"未完成 0"高亮 + 居中 `没有未完成的作业`（与秋季的 `暂无作业` **不同句**） |

#### 2. 我对三条偏离的裁定（都登记在台账第 21 条）

1. **不取 `getHomeworkDetail(baseId)`**：我读了参考实现的渲染（`AssignmentDetail.tsx:327-363`）——优秀作业段只显示 **附件名 + "X的优秀作业"**，
   `description` 根本不参与渲染，而那个 `baseId` 的作业描述在同一次 fetch 里已经取过。**判定：接受**（请求 −24，可观察量不变）。
2. **失败粒度比参考实现细一档**（单条失败保留该条 + warn，而不是整门课一起丢）：这是**更宽容**的偏离，且写了替代验收标准与单测（那次 404 就是第一条路径）。
   **判定：接受**，但记一句：将来若有人"照抄参考实现"，要连这条一起改回去，别只改一半。
3. **卡片/详情用 🏅 emoji 代替 MaterialCommunityIcons 的 medal**：沿用台账第 16 条的判断（替代验收标准 = 截图上的颜色/位置）。
   我第一手看了：四枚图标在同一条状态位上、颜色可区分。**判定：接受。**

#### 3. 我第一手测到的代价变化（记在案）

| | 补做前（我 17:18 那次） | 补做后（我 18:14 那次） |
| --- | --- | --- |
| 请求数 | 135 | **166**（+7 列表 +24 详情页） |
| 抓取耗时 | 3,878 / 3,979 ms | **6,198 ms** |

⇒ 优秀作业让春季那次全量抓取**多了约 2.2 s**。这是"移植 fidelity"换来的成本，我接受；但它叠在"课程/作业两个 tab 各抓一次"之上时，
一次冷启动两次全量抓取 ≈ 12 s ⇒ **性能收尾那一类 ticket 值得把"单例 store + 优秀作业是否懒加载"列进去**（本轮不做）。

#### 4. 仍未验证（不影响本 ticket 定级，但记明）

- **具名作者（非匿名）那一支**：春季真实数据 24/24 全匿名 ⇒ 只有**夹具**证据（`H3/H4`）。这是账号/数据门控，不是实现缺口。
- **优秀作业附件的真身**（下载/预览/分享、以及它用的 `downloadFileyx` 路径与提交附件 `downloadFile` 不同）仍归 **ticket 11**（边界说明已在 ticket 11 里）。
- 真机截图 → **ticket 18**。

#### 5. 我这一轮的取样代价

1 次全量单测（38 s 构建 + 测试）、1 次冷启动 + 1 次点击 + 6 次 fling + 2 帧截图 + 1 次全量 hilog（约 3 分钟设备窗口）、1 次 hap 解包。


### 边界说明（2026-09-12，由 ticket 11.5 带入）—— 作业页头不再显示学期；状态标记换矢量图标

- **变了什么**：
  1. 作业页头从「`当前学期 <学期>` + `取证覆盖生效` / `更新于 HH:mm:ss` + `未完成 n`」四项
     收敛为「**作业 + 刚刚更新**」一行（第 24 条，账号所有者点名）；
  2. 卡片五枚状态标记由 emoji（📎 ✓ 🎓 🔑 🏅）改为同源矢量图标
     （MCI `attachment` / `check` / `key-variant` / `medal` + MaterialIcons `grade`），
     顺序与颜色（orange/green/red/blue/yellow）以及无障碍文案一字未改；
  3. 底色 `#FFFBFF` → `#FFFFFF`（第 25 条）。
- **你的证据还成立到哪一步**：ticket 10 关于**取数/排序/两条接口/优秀作业/计数**的所有结论不受影响；
  受影响的只有两条**界面**表述：
  - "界面显示 `2025-2026 学年春季学期`" —— **作业页头不再显示学期**，同一句仍在**课程页头**（ticket 12 的那条）；
    复核 ticket 10 的学期证据时改看课程页头，或看 hilog 的消费点行
    `assignments applied: … semester=2025-2026-2 source=override …`（**这一行仍然在**，是更强的那条证据）；
  - 旧截图里的 emoji 形状与浅底色不再是基准（形状判据升级见第 16 条改判）。
- **可观察量转移到哪里**：ticket 11.5 的逐屏对照证据与"作业页头无学期/无徽标/无未完成计数"的**证伪截图**。

### 边界说明（2026-09-13，由 ticket 14 带入）—— 过滤视图收敛到 features/marks；作业默认视图改判为「未完成」

- **变了什么**：
  1. **过滤视图的实现位置**：`features/assignments/AssignmentFilter.ets` 里的
     `AssignmentFilter` 枚举与 `matchesFilter` / `filterAssignments` / `countAssignments`
     三个函数**已删除**，七个视图（all / unread / fav / archived / hidden / unfinished / finished）
     统一到 `features/marks/FilteredContent.ets`（逐行对齐参考实现 `data/selectors/filteredData.ts`）——
     参考实现里这三种视图与收藏 / 归档 / 屏蔽本来就是同一套 selector。
     `AssignmentFilter.ets` 现在只留"单条作业怎么看"的规则（过期判定 / 答案 / 优秀作业 / 空态）。
  2. **作业 tab 的默认过滤视图**：从 `全部` 改为 `未完成`。依据是参考实现
     `data/reducers/settings.ts:24-29` 的 `tabFilterSelections.assignment = 'unfinished'`，
     且该选择经 redux-persist 落盘（`data/reducers/root.ts:61-65`）。ticket 14 引入"按 tab 记住过滤选择"，
     默认值就取参考实现那一份。
  3. `AssignmentText.emptyStateKey` 的入参类型从 `AssignmentFilter` 换成 `ContentFilter`：
     ALL / UNFINISHED / FINISHED 三档返回原来的键（一字未改），新增的三档（fav / archived / hidden）
     返回参考实现 `Empty` 组件那句 `loh_empty`。
- **你的证据还成立到哪一步**：ticket 10 关于**取数 / 排序 / 两份接口 / 优秀作业 / 计数 / 空态**的所有结论
  **不受影响**；`AssignmentList.test.ets` 的断言**期望值一字未改**，只有 9 处调用点换成了新的等价实现
  （外加三条"新视图空态键"的断言）。受影响的只有一条**界面**表述：
  "冷启动时高亮的是`全部 57`" —— 现在冷启动高亮`未完成 0`（B1/B3 那张截图的状态仍然可达：点一下`全部`片）。
  `F1-assignments-spring-unfinished-empty-final.png`（未完成视图空态）**反而更贴近提交态**（默认就是它）。
- **可观察量转移到哪里**：ticket 14 交付的作业 tab 筛选条证据（六片、各自计数、默认高亮`未完成`）。




