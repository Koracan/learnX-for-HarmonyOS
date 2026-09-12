# 10: 作业列表 + 详情

**What to build:** 作业 tab 显示真实作业（未到期在前、已过期在后），详情展示描述、附件、提交状态、成绩与优秀作业。

**Blocked by:** 09（已完成）、12（已完成）——两者均已 `verified`

**Status:** ready-for-agent

- [ ] 列表按截止时间排序（未到期在前），显示状态标记与截止时间
- [ ] 详情正确显示描述（含公式）、本地化的成绩等级、四类附件
- [ ] 附件可点，可预览或下载
- [ ] 无作业或全部已过期时显示正确空态
- [ ] 真机截图

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
- 证据：`A1/A2/A3`（秋季空态）；"未完成视图空态"的机制证据是单测
  `emptyStateDependsOnTheViewAndOnBusy` + `allSubmittedAndPastShowsTheUnfinishedEmptyState`；
  **界面截图未单独抓**（见"未验证项"）。
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
2. **"未完成"筛选片的空态截图**：未单独抓（机制有单测，界面侧未截）。
3. **"优秀作业"（excellentHomeworkList）未交付**：工单 What-to-build 里出现过它，但四条验收标准都没有它；
   参考实现那段（`AssignmentDetail.tsx:327-363`）的数据来自**另一条接口**
   （thu-learn-lib `getExcellentHomeworkListByHomework`，每门课一次 POST），而 ticket 05 已验收的
   `AssignmentsFetcher` 语义里没有它。改那条取数属于改已验收前提，且要额外请求，故本轮**只读、不取**。
   **请统筹确认这是否算缺口**；若要补，建议单列一条小 ticket（含取样代价：7 门课 +7 请求）。
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

