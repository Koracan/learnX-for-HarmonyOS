# 15: 搜索

**What to build:** 全局搜索公告、作业与文件，中英混排能命中明显匹配，结果可跳转到对应详情。

**Blocked by:** 14（收藏 / 归档 / 隐藏课程）

**Status:** verified-partial（模拟器口径；真机截图与旋转下的运行期迁移转 ticket 18）

- [ ] 搜索覆盖三个域，结果标注类型与所属课程
- [ ] 大小写不敏感；标题或课程名的精确与前缀匹配必定命中（保留参考实现中的精确匹配合并层）
- [ ] 结果可跳转到对应详情，返回后保留查询与结果
- [ ] 空查询与无结果有明确表现
- [ ] 隐藏课程的内容不出现
- [ ] 真机截图

### 边界说明（2026-09-13，由 ticket 14 带入）—— 验收第 5 条「隐藏课程的内容不出现」现在**由你闭合**

- **变了什么**：ticket 14（收藏 / 归档 / 隐藏课程）已交付并验收为 `verified-partial`。它的验收第 3 条原本同时要求「从三个**列表**与**搜索结果**中消失」，但本 ticket（15）当时尚未开工、代码里**零搜索实现**（`grep -rn "search" entry/src/main/ets` 无命中），所以那半**在本 ticket 内不可验**，被显式记为未验证并转到这里。
- **你的证据成立到哪一步**：ticket 14 已交付的是一份**共用纯过滤实现** `entry/src/main/ets/features/marks/FilteredContent.ets`（三个 selector：`selectFilteredNotices` / `selectFilteredAssignments` / `selectFilteredFiles`，逐行对齐参考实现 `src/data/selectors/filteredData.ts`）。
  **你必须复用它，不要另写一套过滤**——否则「隐藏课程后内容从列表消失」与「从搜索消失」会由两份实现分别承担，两边一旦漂移，本条的验收就不再可比对。
- **三条别「顺手统一」的语义**（`FilteredContent.ets` 顶部注释已逐条写明，照抄即可）：① `fav ⊆ all`（已归档 / 被屏蔽课程的条目不进收藏夹）；② `archived` 与 `hidden` 两个视图用**原始 items**（归档视图里能看到被屏蔽课程的条目，反之亦然）；③ **四个列表都有「屏蔽」视图**（不只是课程页；依据 `components/Filter.tsx:211-218` 与四个屏幕各自传 `hidden`）。台账第 30 条是这三条的正式出处。
- **可观察量转移到这里**：ticket 14 验收第 3 条的**搜索那一半**（工单第 13 行：`隐藏课程的内容不出现`）由本 ticket 的验收承担，证据需要一张**屏蔽课程后其内容不在搜索结果里**的截图；ticket 14 那边只保留列表那半的证据（`E15`/`E17`/`E19`）。
- 另注：搜索结果也要尊重 `archived`（归档项是否进搜索，按参考实现的行为判——先读 `src/screens/Search.tsx` 与 `filteredData.ts` 确认它用的是哪个分组，**不要凭直觉**）。

## Comments

---

### ticket 15 交付（2026-09-13）

**Status 留给账号所有者**（本节只写交付）。

**证据索引**：`.scratch/search/evidence/README.md`（逐文件论断表；全部来自**模拟器**）。

#### 1. 结论表（逐条验收）

| # | 验收 | 结论 | 判据与证据 |
| --- | --- | --- | --- |
| 1 | 搜索覆盖三个域，结果标注类型与所属课程 | **通过** | 段头 = 类型（公告 / 作业 / 文件），每行首行 = 所属课程；春季语料三张（`S1` 公告段、`S2` 作业段、`S4` 文件段）+ `S3`（按课程名查询命中作业域，行内带课程 + 教师 + 截止时间）；layout dump 里有精确的 `"text": "公告/作业/文件"` 段头与课程名。单测：`searches the extra reference fields of all three domains` |
| 2 | 大小写不敏感；标题或课程名的精确与前缀匹配必定命中（保留精确匹配合并层） | **通过** | 手工合并层与参考实现**逐字同判据**（`upperTitle/upperCourseName.includes(query.trim().toUpperCase())`，quirks 第 5 条）：`E3`（查询 `课程` → 标题 `课程信息和微信群`）、`E4b`（查询 `ppt` → 正文 `PPT`，大小写不敏感）、`E4`（查询 `欢迎`，标题/课程名都不含它，只有正文有）。单测 `matches titles and course names case-insensitively…`、`puts manual title/course hits first and deduplicates by id`、`tiers a field match…` |
| 3 | 结果可跳转到对应详情，返回后保留查询与结果 | **通过** | `E6`（点结果 → 公告详情）、`E7`（返回后查询 `课程` 与结果仍在）；跳转走 `pushDetailFromMaster`（单栏压本页栈、分栏压右栏，见 `T2`/`T3`） |
| 4 | 空查询与无结果有明确表现 | **通过** | 空查询 = **可见全量**（参考实现 `String.includes('')` 的后果，`E2` + 单测 `lists everything… for an empty query`）；无结果 = 明确的空态「无内容」（`E5` 查询 `zzzz`；`E10` 屏蔽课程后同一查询） |
| 5 | 隐藏课程的内容不出现 | **通过** | `E10`（屏蔽 `形式语言与自动机` 后查 `课程` → 空态）与 `E11`（取消屏蔽 → 同一查询立刻命中）构成因果对，`P1`/`P2` 给出中间状态与复原；hilog `search applied: query="课程" candidates=1/0/0 hits=1/0/0 hiddenCourses=3` ↔ `candidates=0/0/0 hits=0/0/0 hiddenCourses=4`。过滤**复用** `features/marks/FilteredContent` 的三个 `*ExcludingHiddenCourses`（判据来自同一份 selector 的 hidden 分组），没有另写一套 |
| 6 | 真机截图 | **未完成（如实）** | 本 ticket 的证据**全部来自模拟器**（Pura 90 / MatePad Pro 13）。真机（MatePad Air，API 24）按 `AGENTS.md` 的约定只在 **ticket 18 之前**做一次性复验；复现条件见下面「未验证项与复现条件」第 3 条 |

#### 2. 库选型结论（先实验，再决定）

- **实验**：`ohpm install @ohos/flexsearch@2.0.1` → 写只 import 并调用一次的模块 `features/search/FlexSearchProbe.ets`，由 `entry/src/test/FlexSearchProbe.test.ets` import（**可达路径**）→ 删 `entry/.test` 后 `hvigorw test --no-incremental`。
- **结论：该包以发布态不可用**。编译期失败（原文见 `.scratch/search/evidence/15-flexsearch-smoke-failure.txt`）：
  ```
  ErrorCode: 00507015
  Description: the requested module '&@ohos/flexsearch/src/flexsearch&2.0.1'
  does not provide an export name 'Document' which imported by '&entry/src/main/ets/features/search/FlexSearchProbe&'
  ```
  根因（解包读源码）：`index.d.ts` 声明了一批**具名**导出（`Document` / `Index` / `create` …），而真实入口 `src/flexsearch.js` **只有** `export default FlexSearch`（该文件末行）。
  顺带修正评估文档里那条未验证项：`main` 指向的 `.js` 入口**能**被解析（错误信息里的模块名就是它）——失败在**导出形状**上，而这个包把两者发成了不一致的样子。
- **选择：兜底方案（自写加权评分）**，并且**连 `fastest-levenshtein` 也没有引**：编辑距离内核是自写的带上界早退两行 DP（`withinEditDistance`，约 30 行）。
  ⇒ 本次交付**没有新增任何 ohpm 依赖**：`entry/oh-package.json5` 与 HEAD 逐字节一致（实验用的依赖已 `ohpm uninstall` 并 `git checkout` 复原）。
- **降级边界（不要读成与 fuse 等价）**：② 层的召回 = 字段的**大小写不敏感子串** + **ASCII 词**的 ≤1（词长 3–7）/ ≤2（≥8）编辑距离；
  CJK 只有子串/前缀（与 `.scratch/migration/search-package-eval.md` 第 3 条一致，**不支持拼音/同音字**）。
  参考实现 fuse 的**排序细节**（score 降序、`ignoreLocation` 与各阈值默认）没有逐值复刻：我们的排序是「加权分降序 + 同分保持输入顺序」。
- **未验证**：`import FlexSearch from '@ohos/flexsearch'`（default 导入，与真实 `.js` 一致但与 `.d.ts` 冲突）这条路**没有试**——按工单"不在这上面耗超过一轮构建"的约定停在第一轮。
- 评估文档 `.scratch/migration/search-package-eval.md` 已就地更新（把"待验证"改成结论 + 证据）。

#### 3. 门禁数字（真跑，原始值）

| 门禁 | 命令 | 原始结果 |
| --- | --- | --- |
| 单测 | 删 `entry/.test` → `hvigorw --mode module -p module=entry@default -p product=default test --no-incremental` | `Tests run: 377, Failure: 0, Error: 0, Pass: 377, Ignore: 0`；`test_result.txt` 时间戳 **2026-09-13 04:15:34**（基线 367 ⇒ +10 条，全部是本次新增的 `Search.test.ets`） |
| 构建 | 后台 `hvigorw … assembleHap --no-incremental`（最后一次 04:56:54） | `BUILD SUCCESSFUL`；产物 `entry-default-signed.hap` = 4,744,811 B；**内容级复核**：解开 hap 后在 `ets/modules.abc` 里检索到 `closeSearch ignored` / `search closed` / `search result tapped` / `search applied` / `learnoh-search-input`（只看"BUILD SUCCESSFUL"不够，见 AGENTS.md 的陈旧产物教训） |
| 领域纯净 | `node scripts/check-domain-purity.mjs` | `PASS domain 不依赖平台与应用层`（扫描 24 个领域源文件） |
| 导入图 | `node scripts/check-import-graph.mjs` | `PASS 所有相对 import 均可解析`（扫描 182 个源文件）；孤儿只有两个**入口**文件（`pages/Index.ets`、`entrybackupability/EntryBackupAbility.ets`）—— 新增的 `features/search/*`、`ui/components/SearchButton.ets` **不在**孤儿列表里（可达性成立） |
| i18n | `node scripts/check-i18n-keys.mjs` | `RESULT: OK`（157 个源码键全部可解析；未新造键，用的是既有的 `loh_search` / `loh_search_placeholder`） |
| 生成物新鲜 | `node scripts/check-generated-fresh.mjs` | `PASS 生成物与其生成器输入一致`（6 个生成物 / 2 个生成器） |

**版本可追溯**：`HEAD=39a650ed7d8fa267bc45815d653468a57d3c10fd`；工作区脏（17 条：14 个改动 + 3 个新增路径）。
`git status --porcelain | git hash-object --stdin` = **`843db91d34a9133bd0d1872782bbfe8cfcd53b98`**（计算于最后一次文字更新前一刻）。
写下这一行会再改一次工作区，所以该哈希严格对应「除本节文字与一处**注释**外」的树 —— 那处注释改动（`SearchCore.ets` 文件头把选型写成最终结论）**不改变编译产物**：改动前后 `ets/modules.abc` 的 SHA256 都是 `870CE9FEE871A5F147C4B840CCAC52E66F6E2131DC7F66348C217793667B992A`（逐字节相同）。
⇒ **设备上的证据对应的就是当前代码**（该 abc 由本次构建产出）。

#### 4. 未验证项与复现条件

1. **`@ohos/flexsearch` 的 default 导入没试**（见第 2 节）。复现实验：`ohpm install @ohos/flexsearch@2.0.1`，把探针里的 `import { Document } …` 换成 `import FlexSearch from '@ohos/flexsearch'`，删 `entry/.test` 后跑一次 `test --no-incremental`。
2. **模糊召回质量**：本工程 ② 层的**实际能力**是"子串 + ASCII 词编辑距离"，**不支持**拼音/同音字/中文近形字（评估文档已把这条写成 CJK 的平台事实）。要拼音检索需另加拼音索引字段（`@ohos/pinyin4js` / `@nutpi/pinyin`），不在本 ticket 范围。
3. **真机（验收第 6 条）**：未做。复现条件：在真机（MatePad Air，`3FYBB25407201890`，API 24）上装同一 hap → 公告页头右侧放大镜 → 输入 `课程`（应命中标题 `课程信息和微信群`）；屏蔽该课程后同一查询应落空态；点结果应进公告详情、返回后查询仍在。时点按 `AGENTS.md` 卡在 ticket 18 之前。
4. **分栏下的右栏起始内容**：本工程搜索页自成一左一右，右栏**起始为空态**；参考实现会沿用"进搜索页之前那个右栏详情"（偏离登记在 `docs/accepted-deviations.md` 第 29 条）。
5. **旋转/缩放窗口下的迁移**：本机模拟器 scene 命令不可用（quirks 第 31 条），所以"搜索页在旋转时详情不丢"只由 `SplitView.test.ets` 的纯判据单测保证，**未在设备上取到运行期证据**（与 ticket 16 同一未验证项）。
6. **首轮增量构建的一个现象**：本轮第一次 `assembleHap` 只用了 8–16 s 且退出 0 —— 已按 AGENTS.md 用「产物时间戳 + `ets/modules.abc` 内容检索」双重确认不是陈旧产物（见门禁表）。

#### 5. 代价 / 已知成本

- **打开搜索页 = 多一次抓取**：本工程没有一个全局内容 store（每个 tab 各持一份，见 ticket 10/12）。搜索页复用 `CourseListStore` 的同一次 refresh（课程 + 三域内容 + 学期集合），代价与"进两个 tab = 两次抓取"同级。**没有**为此新造第二条取数路径。
- **两处只有设备上才暴露的缺陷**（首轮编译与单测全绿、跑起来才发现；都写进了代码注释，避免后人重踩）：
  1. 关闭按钮弹的是**页内详情栈**（空栈），搜索页关不掉、而它整屏盖住底栏 —— 改为弹根栈（`SearchEntry.closeSearch`）；
  2. 检索结果缓存最初是**普通字段**，输入后列表不刷新（hilog 的命中数变了、界面不变）—— 改成 `@State`（`SearchPage.noticeHits/assignmentHits/fileHits`）。
- **数据口径**：搜索结果 = **原始条目 - 被屏蔽课程**（参考实现用原始 `items`，故**归档项仍会被搜到**；工单要求"屏蔽课程不出现"，这一条是对参考实现的**有意偏离**，登记在台账第 29 条）。
- **未引依赖**、**未新造 i18n 键**；新增 4 个源文件（`features/search/{SearchCore,SearchPage,SearchRoutes,SearchEntry}.ets`）+ 1 个组件（`ui/components/SearchButton.ets`），并给四个 tab 页头各加一颗按钮、给 `ShellTabs` 加一层根 `Navigation`（搜索是**根级**屏幕，不是第六个 tab）。

---

### 统筹验收（2026-09-13，**模拟器**口径：Pura 90 `127.0.0.1:5555` / MatePad Pro 13 `127.0.0.1:5557`）→ Status: verified-partial

**我逐项自己重跑/重读**：

| 检查 | 我的独立结果 |
| --- | --- |
| HEAD | `39a650e`（工作区脏） |
| **设备证据对应当前代码** | 它报的 `ets/modules.abc` SHA256 是 `870CE9FE…92A`；我把 `entry/build/.../entry-default-signed.hap` 解开重算 `ets/modules.abc` 的 SHA256 = **`870CE9FE…92A`，逐字符相同** ⇒ 证据与当前代码同源。（它报的 porcelain 哈希与我此刻重算的不同——那是 git 索引/快照元数据，不影响证据效力；这一点我按产物指纹判，不按 porcelain 判。） |
| 单测 | **Tests run: 377, Failure: 0, Error: 0, Pass: 377, Ignore: 0**（删 `entry/.test` + `--no-incremental`；`test_result.txt` mtime **04:58:51** 为新写入）⇒ 基线 367 +10 |
| 四项门禁 | domain-purity PASS(24) / import-graph PASS(182，孤儿仅两个入口) / i18n `RESULT: OK`(157 引用键) / generated-fresh PASS |
| 依赖面已复原 | 根 `oh-package.json5` 与 `entry/oh-package.json5` 里**没有** `@ohos/flexsearch`；无新增 ohpm 依赖 |
| flexsearch 冒烟失败 | `.scratch/search/evidence/15-flexsearch-smoke-failure.txt` 实读：`ErrorCode: 00507015 … does not provide an export name 'Document'` —— 属实 |
| 平板落右栏 | `T2-tablet-result-detail-layout.json` 解出：左栏节点 `w=786`px（=**393vp**），右栏从 `x=788` 起有正文 `paragraph` 节点 ⇒ 双栏成立、详情在右栏 |
| 屏蔽课程 | `E10`（106,721 B，空态）↔ `E11`（164,236 B，命中列表）大小差异自洽；两帧文件名与状态词一致 |
| 两个运行期缺陷已修 | `SearchPage.ets:125-129` 有注释说明「最初写成普通字段时结果从不重建」且三个命中数组现为 `@State`；`SearchEntry.ets:40-56` 说明关闭必须弹**根栈**（内部栈已空时 `pop()` 是空操作、搜索页盖住底栏会**让用户出不去**） |
| 四个 tab 入口 | `NoticesPage:308` / `AssignmentsPage:327` / `FilesPage:330` / `CoursesPage:330` 均接入 `SearchButton`；设置页未接（与参考实现 `getScreenOptions(t('settings'), true)` 一致） |
| 交付方 Status | **未动** |

**判定：verified-partial。** 第 1–5 条**通过**，第 6 条真机按规矩转 ticket 18。

#### 我认可的库选型结论（它先实验后决定，做对了）

它按派工要求**先跑冒烟再决定**，并且在第一轮失败后**停手转兜底**（没有在依赖上反复耗构建）：
评估文档的首选 `@ohos/flexsearch@2.0.1` **以发布态不可用** —— `index.d.ts` 声明具名导出，真实入口只 `export default`。
于是改用**自写加权评分**（`features/search/SearchCore.ets`），**未新增任何依赖**。降级边界它写得很实：CJK 只有子串/前缀、不支持拼音/同音字，**不与 fuse 等价**。

**有一条我决定不再补试（记录我的取舍）**：它未验证项里写着「`@ohos/flexsearch` 的 **default 导入**没试」。
理论上可以 `import Fuse from '@ohos/flexsearch'` + 本地类型断言（d.ts 不准就绕过它），很可能可用。
**我判定不值得**：① 工单验收第 2 条只要求「大小写不敏感 + 标题/课程名精确与前缀必中」，自写层已经满足；
② 本工程目前**零 ohpm 依赖**，为一项未被要求的检索质量引入首个第三方依赖，收益与风险不成比例；
③ 参考实现那段**手工合并层是锁定项**，无论引擎如何都要保留，所以换引擎并不会让"保真度"发生变化。
⇒ **保持自写实现**。若将来确实要拼音/更强模糊召回，那是一条**独立的增强 ticket**（评估文档第 3 条已指出：拼音要独立索引字段，不是换模糊库）。

#### 台账（我核对过编号与定性）

- `docs/reference-quirks.md` **第 32 条**：搜索字段表里 4 个恒不命中的 `*AttachmentName` 键 —— 属**锁定**（是参考实现的字段表事实）。
- `docs/accepted-deviations.md` **第 29 条**：三处偏离，我逐条认可：
  1. **引擎换自写评分** —— 平台无 fuse.js 的 ArkTS 移植，且首选包实测不可用；
  2. **结果排除被屏蔽课程** —— 这是**工单第 5 条明写的要求**（参考实现不排除，所以必须登记偏离）；**归档项仍照参考实现保留可搜**，这个区分做对了；
  3. **分栏下搜索页自成一左一右、右栏起始为空态** —— 理由是结构性的：参考实现的搜索页挂在**根容器**里、能借用"外面那个右栏"，而本工程的分栏在**每个 tab 内部**（台账第 28 条），根级搜索页没有外部右栏可用。**这是诚实且必要的偏离，不是实现让步。**

#### 仍未闭合（转 ticket 18）

① 真机截图；② **旋转/缩放窗口**下搜索页详情的运行期迁移（本机 scene 命令不可用，见 quirks 第 31 条，只有单测判据）；③ 模糊召回质量（上面已说明不与 fuse 等价，不作为缺口，只作口径）。

#### 它顺带报的三条工具教训（我已分别登记/复核）

1. **只看到 `BUILD SUCCESSFUL` 会误判编译失败**：flexsearch 冒烟的日志里 `> hvigor ERROR: ErrorCode: 00507015 …` **之后仍跟着一句 `BUILD SUCCESSFUL`**。判编译成败必须找 `ERROR`/`ErrorCode`，不能只看最后一行。
2. **`devecocli log --from <窗口>` 不保证覆盖该窗口**（ArkWeb/chromium 日志会顶掉缓冲区）⇒ 每个论断拍完**立刻**拉日志。这条与 AGENTS.md 里 `--keyword` 丢 tag 是同一族坑。
3. **`ui click` 的坐标要用 layout dump 的 px**（按截图目测会偏 100+ px）；**`ui screenshot` 不覆盖同名文件**（会报错，容易把旧图当新证据）。

