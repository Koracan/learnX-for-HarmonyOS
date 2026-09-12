# 14: 收藏 / 归档 / 隐藏课程

**What to build:** 三个内容列表支持收藏与归档，课程可整体隐藏；隐藏后该课程的全部内容项从信息流与搜索结果中同时消失；误操作可撤销。

**Blocked by:** 10（作业列表 + 详情）、11（文件列表 + 详情 + 下载 + 预览 + 分享）、12（课程列表 + 详情 + 学期选择）

**Status:** verified-partial（模拟器口径；搜索那半转 ticket 15，真机转 ticket 18）

> **与 ticket 03 的自造页头对账（实现时必须处理）**：ticket 03 在公告页头自造了「更新于 HH:mm:ss · 未读 N」两行，而参考实现**没有**这两行——未读数是筛选条上的角标，见 `src/components/FilterList.tsx:246` 与 `src/components/Filter.tsx:181-187`。本 ticket 落地筛选条时，要么删掉自造页头、由筛选条承担未读数，要么明确保留并写明理由，**避免同一信息在两处重复显示**。

- [ ] 收藏与归档状态持久化，重启后保持
- [ ] 三个列表都可按收藏 / 归档筛选
- [ ] 隐藏课程后其公告、作业、文件从三个列表与搜索结果中同时消失
- [ ] 撤销可恢复，且提示留足可操作时长
- [ ] 滑动操作与点击不冲突（滑动时不会误入详情）
- [ ] 真机截图

## Comments
### ticket 14 交付（2026-09-13，**模拟器**口径：Pura 90 `127.0.0.1:5555` / MatePad Pro 13 `127.0.0.1:5557`）

**Status 留给统筹**（本轮不自行置 `verified`）。**未提交 git**。

**源码版本**：`git rev-parse HEAD` = `0456055a2a61eb4a22ec538d329117515cf1c1c6`（工作区脏，含并行 ticket 16 的改动）；
取证时 `git status --porcelain` 的 sha256 = `D7B51A92C5F118A3104BDD25D504A2B2081ECEAA7B750514132B9399AEDC8086`。
证据目录 `.scratch/favorites/evidence/`（逐文件论断表见其中的 `README.md`）。

---

#### 1. **先说两条前提更正**（按开工纪律，先说明再按源码事实做）

1. **「只有课程页有 hidden 视图」与源码不符 —— 四个列表都有「屏蔽」视图。**
   您给的前提是"隐藏课程的内容项在三域里是被直接剔除的，不显示成「隐藏」分组"，但逐字读源码：
   `components/Filter.tsx:211-218` **无条件**渲染 hidden 那一项；四个屏幕都把它传进来
   （`screens/Notices.tsx:58`、`Assignments.tsx:60`、`Files.tsx:59`、`Courses.tsx:52`）；
   `selectFilteredNotices`/`Assignments`/`Files` 的返回对象里都有 `hidden: items.filter(i => hidden.includes(i.courseId))`
   （`data/selectors/filteredData.ts:85/:120/:155`）。**ticket 10 的交付节也写着**"参考实现 FilterList 有
   all/unfinished/finished/fav/archived/hidden 六个视图"。
   ⇒ 本实现按**参考实现**落地：三域内容"从 `all` 里被剔除"（工单验收第 3 条成立），**同时**保留「屏蔽」视图
   （与参考实现一致，也是找回误屏蔽的入口）。这一条同时写进 `docs/reference-quirks.md` 第 30 条。
2. **「从搜索结果中消失」这半在本 ticket 内不可能验证**：搜索是 **ticket 15**（它 Blocked by 14），
   当前代码里**没有任何搜索实现**（`grep -rn "search" entry/src/main/ets` 无命中）。
   ⇒ 本 ticket 交付三域共用的纯过滤实现（`features/marks/FilteredContent`），**ticket 15 必须复用它**；
   该验收的一半记为未验证（见第 5 节）。

---

#### 2. 逐条验收（每条：结论 + **独立**证据文件）

| 验收项 | 结论 | 证据（`.scratch/favorites/evidence/`） |
| --- | --- | --- |
| 收藏与归档状态持久化，重启后保持 | **达成** | `E-P1-notices-after-restart-fav1.png`（重启后筛选条仍"收藏 1"）+ `E-P1-layout-notices-after-restart.json`；机制：`E18-hilog-session-pura90.txt` 的 `collection flags applied: source=stored favorites=notice:1,…` 与 `prefs/learnoh_collection_flags`（设备上 `hdc file recv` 的原始字节） |
| 三个列表都可按收藏 / 归档筛选 | **达成** | 公告：`E5-notices-fav-view.png`、`E7-notices-archived-view.png`；作业：`E8-assignments-filter-row.png`（六片计数 + 默认「未完成」）、`E9-assignments-archived-view.png`；文件：`E10-files-filter-row.png`、`E11-files-fav-view.png`（各配同名 `*-layout-*.json`） |
| 隐藏课程后其公告、作业、文件从三个列表与搜索结果中同时消失 | **列表那一半达成；搜索那一半无法验证（ticket 15）** | 作业域：`E15-assignments-after-hide.png`（全部 56→53、屏蔽 3）；文件域：`E17-files-after-hide2.png`（全部 95→87、屏蔽 8）；公告域：`E19-notices-autumn-after-hide.png`（全部 2→0、屏蔽 1）+ `E20-notices-hidden-view.png`；课程侧入口：`E12/E13/E14`。三域同一条实现由单测 `hidingACourseRemovesItsItemsFromAllThreeDomainsAndFromSearchInputs` 一次断言 |
| 撤销可恢复，且提示留足可操作时长 | **达成** | 收藏方向：`E3-notices-fav-toast-undo.png`（「已添加到收藏 + 撤销」两个 text 节点）→ `E4-notices-undo-restored.png`（「已从收藏移除」、收藏回到 0）；屏蔽方向：`E14-courses-after-hide.png`（「已屏蔽 + 撤销」）。提交态的时长 = 参考实现的 **3000 ms**：`E22-hilog-commit-state.txt` 的 `toast shown: millis=3000` + `E22-notices-commit-state-toast-gone.png`（动作后 8 秒 toast 已消失） |
| 滑动操作与点击不冲突（滑动时不会误入详情） | **达成** | `E2-notices-swipe-actions-open.png` + `E2-layout-notices-swipe-actions.json`（滑动后右侧露出收藏/归档按钮，页面仍是列表：布局树是 `ListItem` + 底部 tab 栏，无 `NavDestination`） |
| 真机截图 | **未完成 → 转 ticket 18**（按 AGENTS.md/spec 第 8 节；本轮全部为**模拟器**口径） | 平板（模拟器）另有 `T1-tablet-notices-filter-row.png` 作为大屏单栏基线 |

**与 ticket 03 自造页头的对账（工单第 9 行）：取方案 ①——删掉自造页头，未读数由筛选条承担。**
依据：参考实现的公告未读数本来就是筛选条上的角标（`components/FilterList.tsx:246`、`components/Filter.tsx:181-187`），
页头（`HeaderTitle`）里没有这个元素；本 ticket 落地筛选条后会出现同一信息两处显示。
**相对更新时间那一行（ticket 11.5 已批准）一字未动。**
由于 `docs/accepted-deviations.md` 第 24 条的替代验收标准第 4 项写着"公告页头仍有 `未读 n`"，
已在该条末尾**就地追记**（编号不变）：说明变了什么、原证据成立到哪一步、可观察量转移到 ticket 14 的哪张图。
证据：`E1-notices-header-and-filter-row.png`（页头只有「公告 + 刚刚更新」，筛选条上是「未读 2」）。

---

#### 3. 落地清单

**新增**

| 文件 | 作用 |
| --- | --- |
| `domain/marks/ContentFilter.ets` | 七个过滤视图的取值域与解析（取值逐字对齐参考实现 `Filter.tsx:14-21`，因为要持久化） |
| `domain/marks/CollectionFlags.ets` | 收藏 / 归档 / 屏蔽的状态形状与迁移规则；四个 tab 的默认过滤选择（照抄 `settings.ts:24-29`，**assignment 默认 unfinished**） |
| `domain/marks/CollectionFlagsCodec.ets` | 落盘 JSON 的编解码（纯函数；损坏 = 丢弃 + 原因，绝不抛） |
| `features/marks/FilteredContent.ets` | 三域的分组 / 计数 / 取视图 / 单行状态判定，逐行对齐 `data/selectors/filteredData.ts` |
| `features/marks/CollectionFlagsProvider.ets` | **进程内单例**组装点（屏蔽一门课要同时影响三个列表，必须共享） |
| `data/marks/CollectionFlagsStore.ets` | `@ObservedV2/@Trace` 状态 store + 持久化端口 + 内存替身 |
| `data/marks/PreferencesCollectionFlags.ets` | 设备侧 preferences 实现（一个 JSON 键；**不引入 redux-persist，不自造第二套存储**） |
| `ui/components/FilterChip.ets` | 筛选片（名称 + 计数；ticket 10 起的同屏版式） |
| `ui/components/Toast.ets` | Toast（含撤销动作，默认 3000 ms；含**提交态为 0** 的取证开关与消费点自证） |
| `ui/components/SwipeActions.ets` | 滑动操作按钮（收藏/归档、屏蔽两套；宽度 80、图标与底色逐项照 `CardWrapper.tsx`） |
| `entry/src/test/Favorites.test.ets` | 14 条单测（状态迁移 / 三域过滤语义 / 编解码与损坏丢弃 / store 跨实例恢复 / 取证开关守卫） |

**改动**

| 文件 | 变化 |
| --- | --- |
| `features/notices/NoticesPage.ets` | 五片筛选条 + 滑动收藏/归档 + 长按菜单 + Toast；**移除页头的 `未读 n`** |
| `features/assignments/AssignmentsPage.ets` | 六片筛选条（顺序与计数口径照 `Filter.tsx:153-218`）+ 滑动 + 长按 + Toast；默认视图 unfinished |
| `features/files/FilesPage.ets` | 五片筛选条 + 滑动 + 长按 + Toast |
| `features/courses/CoursesPage.ets` | 两片（全部/屏蔽）+ 滑动屏蔽 + 长按 + Toast |
| `features/assignments/AssignmentFilter.ets` | 删掉 `AssignmentFilter` 枚举与 `matchesFilter`/`filterAssignments`/`countAssignments`（实现收敛到 `features/marks/FilteredContent`），只留"单条作业怎么看"的规则 |
| `features/assignments/AssignmentText.ets` | `emptyStateKey` 入参改 `ContentFilter`；前三个视图的键一字未改，新三视图用 `loh_empty` |
| `ui/icons/IconCatalog.ets`(+单测) | 新增 6 个码位：MCI `heart`/`heart-off`/`archive-arrow-down`/`archive-arrow-up`、MaterialIcons `visibility`/`visibility-off`（逐条抄自参考实现的 glyphmap） |
| `entry/src/test/AssignmentList.test.ets` | 9 处调用点迁到新等价实现（**期望值一字未改**），另加 3 条新视图空态键断言 |
| `entry/src/test/I18n.test.ets` | `UI_STRING_COUNT` 116→119、`TOTAL_KEY_COUNT` 302→305 |
| `scripts/i18n-ui-strings.mjs` + 4 个生成物 | 3 条新 `ui_` 文案：`ui_remove_favorite` / `ui_unarchive` / `ui_unhide_course`（参考实现的滑动按钮只有图标、没有文字，这三条供无障碍文案与长按菜单用） |
| `docs/reference-quirks.md` | **新增第 30 条（锁定）**：三个视图口径不对称（fav ⊆ all；archived/hidden 用原始 items；置真 append 不去重）+ 四个列表都有 hidden 视图 |
| `docs/accepted-deviations.md` | 第 24 条**就地追记**：公告页头的 `未读 n` 已移除（编号不变，写明原判据作废与可观察量转移） |
| `.scratch/migration/issues/10-assignments-list-and-detail.md` | **边界说明**（由 ticket 14 带入）：过滤视图收敛、作业默认视图由「全部」改判为「未完成」、`emptyStateKey` 类型变化，以及 ticket 10 原证据成立到哪一步 |

台账编号：**quirks 新增 30**（动手前已 grep 确认当时最大为 29）；**accepted-deviations 未新增条目**（27→仍 27，只改了第 24 条）。

---

#### 4. 门禁（**真跑**的原始数字，2026-09-13）

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| 全量单测 | 删 `entry/.test` 后 `hvigorw --mode module -p module=entry@default -p product=default test --no-incremental` | `test_result.txt` 末行 **`Tests run: 362, Failure: 0, Error: 0, Pass: 362, Ignore: 0`**（文件 mtime 2026/9/13 1:37:58；**基线 348 → +14**） |
| 构建 | `hvigorw … assembleHap --no-incremental` | **BUILD SUCCESSFUL**；`entry-default-signed.hap` **4,506,911 字节 / 2026-09-13 1:38:10** |
| 领域纯度 | `node scripts/check-domain-purity.mjs` | **PASS**（24 个领域源文件） |
| 导入图 | `node scripts/check-import-graph.mjs` | **PASS**（174 个源文件；孤儿只有两个入口文件） |
| i18n 键 | `node scripts/check-i18n-keys.mjs` | **RESULT: OK**（305 键；153 个被引用键全解析） |
| 生成物新鲜 | `node scripts/check-generated-fresh.mjs` | **PASS**（生成物与生成器输入一致） |
| 取证开关复原 | 源码 + 单测 | `TOAST_MILLIS_FOR_EVIDENCE = 0`；单测 `evidenceToastDurationOverrideIsOffAtCommit` 守着；提交态设备侧 `toast shown: millis=3000` |

**关于"是否真跑了测试"**：删 `entry/.test` + `--no-incremental`，并且读了 `test_result.txt` 的 `Tests run` 行与文件时间戳（不是只看退出码）。
**关于产物是否是新的**：hap 时间戳 1:38:10 晚于本轮最后一次源码编辑；并另有一路"产物级/视觉级"的复原证据（第 4 节最后一行）。

---

#### 5. 未验证项 / 未交付项（**不要当成全绿**）

1. **搜索那一半（工单验收第 3 条）**：`ticket 15` 未落地，代码里没有搜索 ⇒ **无法验证**。
   复现条件：ticket 15 交付后，屏蔽一门课再搜它的标题，结果集里不应出现（ticket 15 必须复用 `features/marks/FilteredContent` 的 `all`/分组口径，而不是自己再写一套过滤）。
2. **真机截图（验收第 6 条）**：转 ticket 18；本 ticket 全部为**模拟器**口径。
3. **归档方向的撤销提示**没有独立的截帧（只在 `E9` 里附带可见）；收藏方向（E3/E4）与屏蔽方向（E14）各有独立证物。三条走的是同一个组件、同一段 flag 语义。
4. **长按菜单**（`bindContextMenu`，用来承载参考实现"长按展开操作区" CardWrapper.tsx:161-166 的等价入口）只由编译与代码保证，设备上**没有单独点过**。
5. **深色 / 英文**下这三处界面未单独截图。
6. **平板只取了 1 张**（公告页筛选条 + 布局树）：用于说明 1440 vp 下仍是单栏拉伸（ticket 16 之前的基线），**不代表**平板上的收藏/归档/屏蔽全流程都验过。
7. **取证期间应用被环境事件终止过数次**（01:07 / 01:14 / 01:40；01:15 那次日志留痕 `reason=LIFECYCLE_TIMEOUT`，`[ARR1101]terminate EntryAbility`）。
   `hilog -x` 里检索 `FIX THIS APPLICATION ERROR` / `jscrash` / `onAbilityDied` **均无命中**，重启后重复同一串操作**不复现**；
   同一时段宿主上还有并行 agent 的构建和另一台模拟器。**记为未定因的环境事件**，留档 `X1`/`X2`，不作为缺陷结论，也不排除并行操作。
8. **撤销的页面回调没有单测**：`Toast → handleFav(item, true)`（以及归档 / 屏蔽的两个同形回调）写在 ArkUI struct 里，
   host 单测不实例化组件 ⇒ 这一段由设备证据（`E3`→`E4`）覆盖；**store 侧**的置假迁移
   （`setFavorite(..., false)` / `setHidden(..., false)` 并从持久层读回）有单测。
9. **撤销窗口的"留足时长"取的是参考值 3000 ms**：验收原文写"提示留足可操作时长"，参考实现 success 档就是
   `Toast.tsx:51-54` 的 3000 ms。若账号所有者认为要更长（例如 5000 ms），那是一条**新增偏离**，需要单独定义验收标准并登记，本轮**没有**擅自改。

#### 6. 代价与已知偏离

- **代价**：四个页面每次重建都会重算三域分组与计数（`filtered()` 在 chips / 列表 / 每行的滑动状态里各调用一次，
  规模是 95 文件 / 57 作业 / 17 公告）。实测未造成可见卡顿，但**没有**做缓存/记忆化；若 ticket 15/16 之后感觉到卡，
  第一刀应该是"把分组算一次放进 store"而不是改语义。
- **界面版式（沿用 ticket 10 的选择）**：参考实现的筛选入口是页头图标弹出的下拉列表，这里是**同屏筛选片**；
  **顺序与计数口径照 `Filter.tsx:153-218`**（作业没有 unread 片，因为参考实现没给作业传 `unread`）。
- **长按**：参考实现长按是"展开右侧操作区"，ArkUI 的 `swipeAction` 没有编程式展开的 API，这里改成**同一动作集的菜单**（等价入口）。
- **过滤选择落盘位置**：参考实现放在 `settings.tabFilterSelections`（redux-persist），本工程放在
  `data/marks` 的同一个 JSON 里（**本仓库没有 redux-persist**，按既有 preferences 快照模式办）；行为（按 tab 记住）一致。
- **隐藏视图**：四个列表都有（与参考实现一致，见第 1 节的前提更正与台账第 30 条）。
- **不新增依赖**：没有引入任何第三方搜索/存储库。

---

### 统筹验收（2026-09-13，**模拟器**口径：Pura 90 `127.0.0.1:5555` / MatePad Pro 13 `127.0.0.1:5557`）→ Status: verified-partial

**我没信交付表，逐项自己重跑/重读**（构建锁与设备锁此时均空，我独立跑的）：

| 检查 | 我的独立结果 |
| --- | --- |
| HEAD / 工作区 | `0456055`；交付方报的 `git status --porcelain` sha256 `D7B51A92…` 与之自洽 |
| 单测 | **Tests run: 362, Failure: 0, Error: 0, Pass: 362, Ignore: 0**（删 `entry/.test` + `--no-incremental`；`test_result.txt` mtime 01:46:36 为**新写入**）⇒ 基线 348 +14，**数字与交付一致** |
| 四项门禁 | domain-purity PASS(24) / import-graph PASS(174，孤儿仅两个入口) / i18n `RESULT: OK`(305 键) / generated-fresh PASS |
| 提交态开关 | `E22-hilog-commit-state.txt` 实读为 `toast shown: millis=3000 hasAction=true text=已添加到收藏` ⇒ **消费点自证**已复原（取证态是 120000） |
| 页头对账方案① | `E1-layout-notices-header-and-filter-row.json` 里页头**只有** `刚刚更新`，**无** `未读 n`；筛选条五片 未读 2 / 收藏 0 / 归档 0 / 屏蔽 0 ⇒ 未读数已移到筛选条，**没有两处重复** |
| 隐藏课程计数 | `E15-layout-assignments-after-hide.json` 实读 已完成 53 / 全部 53 / **屏蔽 3** ⇒ 56→53 算式自洽 |
| 台账编号 | quirks **第 30 条在 651 行**，28/29/30 顺连无撞号；accepted-deviations **未新增**（27 仍 27，只改 24） |
| ticket 10 边界说明 | 该工单 401 行确有新增小节（过滤视图收敛 / 作业默认视图改判「未完成」） |
| 交付方 Status | **未动**，仍是 `ready-for-agent` ⇒ 未自行置 verified |

**前提更正：交付方对，我错。** 我给的两条前提里，第 1 条（「只有课程页有 hidden 视图」）是**错的**——我当时说「隐藏课程的内容项在三域里是被直接剔除的，不是显示成一个『隐藏』分组」。我回源码逐处核对，确认**是它按源码做对了**：

- `components/Filter.tsx:211-218` 的 hidden 项**无条件渲染**（对比 fav 的 `favCount !== undefined`、archived 的 `archivedCount !== undefined` 都带条件，**唯独 hidden 没有**）；
- 四个屏幕都传了 hidden：`Notices.tsx:58` / `Assignments.tsx:60` / `Files.tsx:59` / `Courses.tsx:52`；
- 三个内容 selector 都返回 `hidden` 分组：`filteredData.ts:85`（notices）/ `:120`（assignments）/ `:155`（files）。

⇒ **四个列表都有「屏蔽」视图**，课程页不是独有；同时三域内容确实「从 all 里被剔除」。它把这条写进 quirks 第 30 条是对的。**这条记我的错，不记它的。**

**验收判定：verified-partial**

- 第 1 / 2 / 4 / 5 条：**达成**，证据独立且一图一论断（E-P1 与 prefs 原始字节分开、E3→E4 两步各一帧、E2 用布局树证「无 NavDestination」）。
- 第 3 条：**列表那半达成**（E15/E17/E19 三域各一帧），**搜索那半按设计不可验**——搜索是 ticket 15 且阻塞于本 ticket，当前代码零搜索实现。该半的**可观察量转移**已写进 ticket 15 的注释（要求它复用 `features/marks/FilteredContent`）。
- 第 6 条真机截图：转 ticket 18，已登记进其必查清单。

**我额外确认的两处质量**（不是缺陷，是加分项，记下来供后续 ticket 参照）：

1. **它主动分了「取证构建」与「提交态构建」两个态**，并说明理由：`devecocli ui` 单次 15–35s ⇒ 参考实现的 3 秒撤销窗口必然抓不到，故取证态把 toast 改成 120000ms、提交态复原为 3000ms，且**两个态都有消费点自证**（`ToastController.show()` 打 `millis=`）。这正好落实了 AGENTS.md「时间敏感的证据要把延迟直接改大」+「开关自证要打在消费点」。
2. **`E16` 是一帧如实记录的「没生效」**：只屏蔽 `…314` 时文件域 95→95，它没把它当成功，而是查明「那门课没有文件」，再屏蔽一门有文件的课拿到 `E17`。先排除假因再下结论，这个做法对。

**仍未闭合（全部转 ticket 18）**：归档方向的撤销提示无独立截帧（只在 E9 附带可见）；长按菜单（`bindContextMenu`）设备侧未单独点过；深色/英文下三处界面未截图；平板只 1 张；撤销的**页面回调**无单测（ArkUI struct 不入 host 单测，store 侧有单测）。

**一处我要求 ticket 18 顺带观察、但明确不据此下缺陷结论的现象**：取证期间应用被环境事件终止数次（01:07 / 01:14 / 01:40；01:15 留痕 `reason=LIFECYCLE_TIMEOUT` + `[ARR1101]terminate EntryAbility`），`hilog -x` 内**无** `FIX THIS APPLICATION ERROR` / `jscrash`，重启后不复现。交付方记为**未定因环境事件**并留档 `X1`/`X2`，处置得当。我追加一条判据给 ticket 18：真机上冷启动**无并行负载**时观察是否仍出现 `LIFECYCLE_TIMEOUT` —— 仍出现 ⇒ 与本机并行构建/双模拟器无关，需单独查；不出现 ⇒ 记为负载相关。

