# 12: 课程列表 + 详情 + 学期选择

**What to build:** 课程 tab 显示本学期课程与未读公告、未完成作业、新文件计数；详情按标签页聚合同一课程的公告、作业与文件；可切换当前学期。

**Blocked by:** 09（公告切真实数据 + 快照）

**Status:** verified（模拟器口径；真机与平板横向转 ticket 16/18）

- [x] 列表显示课程名、教师与三类计数
- [x] 详情三个标签页各自列出该课程的内容，且能从任一标签页进入对应详情（公告 → ticket 04 的真详情；作业/文件 → 各自详情路由的**占位页**，真身在 ticket 10/11）
- [x] 学期选择列出可选学期并切换当前学期，切换后课程列表随之更新（另有脚本入口，见 Comments 第 2 节）
- [x] 该学期无课程时显示正确空态（站点当前学期为空仍是**失败信号**，见 Comments 第 3 节）
- [x] **模拟器**截图（真机截图转 ticket 18；平板横向无法在手机上验证，转 ticket 16/18）

## Comments

### 统筹提示（2026-09-12，**用户提供的事实**）—— 本 ticket 是多条线的**取数前提**

用户账号 **2026-2027 学年秋季学期没有作业**（本学期刚开学/无作业），而 **2025-2026 学年春季学期的作业已全部截止**。
⇒ **任何按学期取数的真实数据验证（ticket 10 作业 / 11 文件 / 13 提交 / 14 收藏归档）都依赖"能切到 2025-2026 学年春季学期"。**
本 ticket 的学期选择因此不只是界面功能，而是**别人的取证工具**：

- 切换学期必须能被**取证脚本在没有界面交互的情况下驱动**（或提供一个**开关守卫**的学期覆盖，并把**实际生效值**打进 hilog）——否则 ticket 10/11/13/14 在模拟器上永远拿不到真实数据。
- 学期排序沿用参考实现（见 `docs/reference-quirks.md` 第 3 条），**不要顺手"修好"**。
- 建议本 ticket 与 ticket 10 同轮或排在它之前落地；派单顺序由统筹决定。

### 统筹补充（2026-09-12，**用户提供的事实**）—— 课程本学期**非空**；学期切换只为"作业"服务

- 用户账号 **2026-2027 学年秋季学期**：**公告、文件、课程都有非空数据**；**只有作业为空**。
- ⇒ 本 ticket 的**课程列表 / 详情可以直接用真实数据验收**（空结果 = 失败信号）；"学期选择"这条能力的取证价值集中在**让作业线（ticket 10/13）能拿到 2025-2026 春季学期的（已全部截止的）作业**。
- 因此上面那条"学期切换必须可被取证脚本驱动"仍然成立，但它**不再是 ticket 09 / 11 的前提**，只服务作业线；上面第 3 行那句"10/11/13/14 都依赖学期切换"应读作"**只有作业相关的 10/13 依赖**"。

### ticket 12 交付（2026-09-12，**模拟器** Pura 90 / HarmonyOS 6.1.0(23)）

**Status 留给统筹复验时改**（本 ticket 不自行改）。证据目录 `.scratch/courses/evidence/`（本地保留、不入库）。
取证期 HEAD = `fee817f`，工作区脏（含本 ticket 改动），`git status --porcelain` 的 sha256 =
`e755449678c714d90fd2b7e6eef38e859090122255891cf96bad084c019e37e6`。

#### 1. 落地了什么

| 项 | 落点 |
| --- | --- |
| 学期解析（当前 + 全部可选） | `data/courses/SemesterFetcher.ets` |
| 课程列表（完整条目） | `data/courses/CourseListFetcher.ets`——课程这条线的**唯一取数实现**；`data/notices/CourseListFetcher.ets` 改成**转发层**，ticket 09 的导出名与 `names` 口径一字不变 |
| 三类计数（纯逻辑） | `domain/courses/CourseCounts.ets`（逐条对齐参考实现 `selectCoursesWithCounts`） |
| 一次抓取聚合三域 | `data/courses/CourseFetchSource.ets`（复用 ticket 05 的 Notices/Assignments/FilesFetcher，**不复制取数逻辑**） |
| 数据路径 | `data/courses/RealCourseRepository.ets` 走 `AuthedTaskRunner`（**没有自造重登/重试/降级**） |
| 学期覆盖（脚本入口） | `data/courses/SemesterOverride.ets` + `entryability/EntryAbility.ets` 的 `applySemesterOverride` |
| 界面 | `features/courses/`（CoursesPage / CourseDetailPage / SemesterSelectionPage / CourseDetailPlaceholder / CourseListStore / repository/CourseRepositoryProvider） |
| 壳 | `features/shell/ShellTabs.ets` 的课程 TabContent 换成 `CoursesPage` |
| i18n | `scripts/i18n-ui-strings.mjs` 新增 8 个 `ui_` 键（生成器已重跑，`check-generated-fresh` PASS） |
| 台账 | `docs/reference-quirks.md` **新增第 18 条**（四处有意偏离 + 替代验收）；**第 17 条追加更正**（见第 5 节） |

门禁：单测 **279 通过 / 0 失败**（基线 256，本 ticket +23）；`devecocli build` 全量重建（删 `entry/build`）成功，
产物 15:05:16；hap 解开后 `ets/modules.abc`（791840 字节）含 RealCourseRepository / SemesterOverride /
CourseListStore / CoursesPage / SemesterSelectionPage / HttpCourseFetchSource / buildCourseRecords /
normalizeDeadline / lohSemester / ui_courses_override_badge，且**不含**探针串 `PROBE asg`；
四脚本 PASS / PASS / RESULT: OK / PASS。

#### 2. 脚本可驱动的学期切换（硬约束 2）

    hdc -t 127.0.0.1:5555 shell "aa force-stop com.koracan.learnOH"
    hdc -t 127.0.0.1:5555 shell "aa start -a EntryAbility -b com.koracan.learnOH --ps lohSemester 2025-2026-2"

- **自证生效**（每次课程刷新都打一行）：

      entry.ability: semester override: want parameter "lohSemester"="2025-2026-2" accepted=true;
        semester override: constant="" runtime="2025-2026-2" effective="2025-2026-2" source=runtime-want-param
      data.courses.source: data.courses effective semester=2025-2026-2 source=override
      data.courses.source: data.courses override active: siteCurrent=2026-2027-1 effective=2025-2026-2

- **切过去以后看得到的东西（ticket 10/13 的前提）**：

      data.courses resolved semester=2025-2026-2 requested=2025-2026-2 lang=zh_CN courses=7 bytes=6288
      snapshot semester=2025-2026-2 source=override courses=7 notices=17 assignments=57 files=95
                 semesters=9 semestersAvailable=true

  界面：当前学期 = **2025-2026 学年春季学期**，右上角"取证覆盖生效"，列表 **7 门课**
  （西方音乐史/康啸 … 软件分析与验证/贺飞）；学期切换页勾选的也是春季学期。
- 为什么不走沙箱文件：实测 `hdc file send` 写应用沙箱**被拒**（`[Fail]Error opening file: permission denied`；
  反向 `hdc file recv` 可以），而 `aa start --ps` 可用且**无需重建**。构建期常量
  `SEMESTER_OVERRIDE_FOR_EVIDENCE` 作为次要入口保留（提交态为空）。
- 覆盖只在**进程内存**里 ⇒ 脚本必须先 `force-stop` 再 `--ps` 启动。优先级
  `override > 界面选择 > 站点当前学期`（有截图证明覆盖会压住界面点选）。

#### 3. 实测结论（每条都有独立证据文件；详见 evidence/README.md）

| # | 结论 | 证据 |
| --- | --- | --- |
| 1 | 本学期课程 **2 门**，条数与顺序与站点 `resultList` 一致（英语听说交流（A）/英语听说交流（A） …） | A1/A2 截图+布局、A5/A5b hilog（含 raw preview） |
| 2 | 三类计数与三域原始响应一致：🔔1/🔔1（notices=2）、📅0/📅0（assignments=0）、📁4/📁0（files=4，站点 jxkjs=4/0） | A1/A2、A5b |
| 3 | 学期集合接口可用：**9 个学期**，最新在前，页面上第 2 项就是 **2025-2026 学年春季学期** | A3/A4 |
| 4 | 脚本切学期生效 → 春季 **7 门课**、assignments=57（ticket 10/13 的真实作业集合） | B0–B4、B7/B8 |
| 5 | **界面**切学期同样生效：点"2023-2024 学年夏季学期"→ 列表变 1 门课 | C1/C2 |
| 6 | 覆盖优先于界面选择（覆盖态下点"2023-2024 夏季"被压住） | G1/G2 |
| 7 | 空态：站点对 `2010-2011-1` 返回 200 + 空 resultList → 居中"暂无课程"；**站点当前学期**为空则抛错（单测钉住） | D0/D1、D3/D4 |
| 8 | 详情三标签 + 三个详情入口：通知 2 条、作业 3 条（截止时间已正常显示）、文件（西方音乐史空 / 离散数学方法 9 条）；点公告 → 真详情，点作业/文件 → 各自占位详情 | E1–E15 |
| 9 | **真实数据缺陷**：`jzsj` 是 epoch 毫秒**数字**（57/57 条），曾让整页失败；已修（见第 4 节） | P1（崩溃栈）、B7/B8（修复后） |

**作业为空**这条账号事实在本轮**再次确认**：2026-2027 秋季 `assignments=0` 且 `failures=0`
（不是取数失败：课程/公告/文件都非空）。春季学期 `assignments=57`，但**未完成计数 0**——
它们**全部已截止**（账号事实正是如此），而参考实现的"未完成"= 未提交**且未截止**，所以 📅0 是正确结果。
作业**条目**非空：课程详情的作业标签页列出 3 条（全部已提交）。

#### 4. 真实数据缺陷：站点把作业截止时间下发成**数字**（已在本 ticket 修好）

**现象**（切到春季学期时整页失败）：

    features.courses.store: course refresh failed: undefined is not callable
    stack= at parseTimestamp (domain/parse/Text.ets:364)
           at compareAssignmentsByUpcoming (domain/parse/AssignmentParser.ets:204)
           at fetch (data/remote/AssignmentsFetcher.ets:191)

**真因**：站点把每条作业的 `jzsj` 下发成 **epoch 毫秒的数字**（实测 57/57；例 `1780243140000` =
2026-05-31 23:59 本地时间）。ticket 05 的 `parseTimestamp` 直接对入参调用 `raw.trim()`，数字走到 `trim`
上抛 `undefined is not callable`。参考实现在**渲染层**用 `dayjs(deadline)` 处理，而 dayjs 对数字按毫秒解释
（`AssignmentCard.tsx:103-108`）——所以这不是"站点异常"，是**我们的移植在真实数据上缺了一格**。

**修法**（两处，都对 dayjs 对齐，**字符串入参的行为一字不变**）：

1. `domain/parse/Text.parseTimestamp` 接受数字（有限数字按 epoch 毫秒返回；其它非字符串视为不可解析 =
   dayjs 的 Invalid Date ⇒ `isAfter` 恒 false）；签名与 `compareTimeDesc` / `compareByTimeThenIdDesc` 一并放宽。
2. `domain/parse/AssignmentParser` 新增 `normalizeDeadline`：非字符串的 `jzsj` 按本地时间格式化成
   `YYYY-MM-DD HH:mm`（`Assignment.deadline` 的既定形状）；字符串原样保留。

**取证**：`P1-hilog-probe-and-crash-simulator.txt`（探针 + 栈 + 逐行计数）、
`B8-hilog-final-spring-datacourses.txt`（`nonStringDeadlines=57`）、E3/E4（界面上截止时间已正常）、
单测 `AssignmentParser.test.ets`（数字 → 既定形状）与 `CourseCounts.test.ets`（`parseTimestamp` 接受数字）。

> **边界说明（给 ticket 05 / 10 的读者）**：我改了 ticket 05 已验收的两个资产
> （`domain/parse/Text.ets` 的 `parseTimestamp`、`domain/parse/AssignmentParser.ets` 的 deadline 映射）。
> 按本仓库规矩，本该在被影响方也写一句；但 ticket 05/10 的文件不在本 ticket 的改动边界内，
> **请统筹把下面这句抄进 ticket 05（并在 ticket 10 开工时知会）**：
> "ticket 12 在真实数据上发现 `jzsj` 可能是 epoch 毫秒数字，`parseTimestamp` 与 `Assignment.deadline`
> 已按 dayjs 对齐修正（字符串行为不变）。ticket 05 的夹具都是字符串，所以当时看不出；作业卡片要显示
> 截止时间时直接读 `Assignment.deadline` 即可（已是 `YYYY-MM-DD HH:mm` 字符串）。"

#### 5. 台账第 17 条的更正：`queryxnxq` **不再** 403

ticket 09 的 A3/A4 探针记着"带不带 `_csrf` 都 403"。本轮用**同一个** `authedGet`（带 `?_csrf=`）实测：
`GET status=200 bytes=127 ok=true`、`semesters resolved current=2026-2027-1 list=9 listOk=true`，
学期切换页因此列出了 9 个学期。**那条子结论未能复现**，已在台账第 17 条追加更正段
（"不要据此认定该接口坏掉"）；第 17 条其余部分（裸请求会拿到站点 403 报错页、生产一律带 `_csrf`）不变。
本轮**没有**解释差异原因，只记录观察。

#### 6. 未验证项 / 转出项

1. **平板横向**：手机上无法验证 ⇒ **转 ticket 16**（分屏/断点）+ ticket 18 的真机复验。
2. **真机（MatePad Air / API 24）**：未连接 ⇒ 按 AGENTS.md 转 **ticket 18** 的一次性复验。
3. **作业为空**：本轮再次确认是**账号事实**（见第 3 节末），不是缺数据。
4. **附件的真实样本**：仍未取得（同 ticket 09 的未验证项）。
5. **课程上课时间地点**（参考实现的 `LEARN_COURSE_TIME_LOCATION`）**没做**：本 ticket 验收不需要，
   每门课要多一次请求；已在 `data/courses/CourseListFetcher.ets` 文件头写明。
6. **一次 appfreeze（未复现）**：15:18 那次冷启动，系统给了主线程卡顿转储
   （AppRecovery / AbilityTransaction，bundle = com.koracan.learnOH），随后应用退后台、系统浏览器被带起；
   **紧接着重跑同一命令即正常**，之后 6 次冷启动（含覆盖态）全部正常。本轮**未能定位到我们代码里的原因**，
   按"观察到但未复现"记录（`.dsh/logs/12-crash.log`）。

**取样代价**：一轮"单测 → 构建 → 装机 → 点按/截图/布局 → 拉 hilog" ≈ 3–5 分钟设备窗口；
本轮 9 次装机（2 次探针构建 + 1 次全量重建）、约 30 次 ui 操作（单次 15–30s），设备窗口合计约 40 分钟，
另有 1 次 appfreeze 使该轮作废。完整清单与可重跑命令见 `.scratch/courses/evidence/README.md`。
### 统筹验收（2026-09-12，**模拟器** Pura 90 / HarmonyOS 6.1.0(23)）→ Status: verified

**结论：5 条验收项全部通过（模拟器口径）。** 交付里的主要论断我都自己重跑或自己读了原始 artifact，未采信转述。
另有**两条边界必须写进下游 ticket**（见下），它们不影响本 ticket 的验收结论。

#### 1. 我独立重跑的（在 `2a776d2` 上；工作区只有未跟踪的 `.scratch/*/evidence/`）

| 检查 | 我跑的命令 | 我读到的结果 |
| --- | --- | --- |
| 全量单测 | 删 `entry/.test` 后 `hvigorw --mode module -p module=entry@default -p product=default test --no-incremental` | `entry/.test/…/test_result.txt` 末行 `Tests run: 279, Failure: 0, Error: 0, Pass: 279, Ignore: 0`（我自己的运行，非转述；日志 `.dsh/logs/t12-coord-test.log`，BUILD SUCCESSFUL in 38 s） |
| 四脚本 | `check-domain-purity` / `check-import-graph` / `check-i18n-keys` / `check-generated-fresh` | `PASS` / `PASS`（仅 WARN 两个入口文件为孤儿：`pages/Index.ets`、`entrybackupability/EntryBackupAbility.ets`，属正常）/ `RESULT: OK`（245 键，en_US 唯一 untranslated = `ui_app_name`）/ `PASS 生成物与其生成器输入一致`；跑完 `git status --porcelain` 仍只有未跟踪证据目录 ⇒ **生成物无漂移** |
| 产物级符号 | 我自己把 `entry-default-signed.hap`（2,051,450 B，15:05:16）当 zip 解开 | `ets/modules.abc` = 791,840 B；`IndexOf` 命中 `RealCourseRepository / SemesterOverride / CourseListStore / CoursesPage / SemesterSelectionPage / HttpCourseFetchSource / buildCourseRecords / normalizeDeadline / lohSemester / ui_courses_override_badge` 全为 True，`PROBE asg` 为 False |
| **学期覆盖（我自己重跑）** | `aa force-stop` → `aa start -a EntryAbility -b com.koracan.learnOH --ps lohSemester 2025-2026-2` → `devecocli ui click --device 127.0.0.1:5555 924 2682`（课程 tab）→ `hilog -r` 后全量拉、本地筛 | `semester override: … effective="2025-2026-2" source=runtime-want-param` → `data.courses effective semester=2025-2026-2 source=override` → `override active: siteCurrent=2026-2027-1 effective=2025-2026-2` → `resolved semester=2025-2026-2 requested=2025-2026-2 courses=7 bytes=6288` → `assignments fetched courses=7 items=57 elapsedMs=4548 requests=135 failures=0 nonStringDeadlines=57` → `snapshot semester=2025-2026-2 source=override courses=7 notices=17 assignments=57 files=95 semesters=9 semestersAvailable=true`（原始输出存 `.scratch/courses/evidence/coord/`） |
| ticket 09 行为未回归 | 同上那次冷启动（未点课程 tab 的第一次） | `data.notices fetched courses=2 items=2 elapsedMs=168 requests=4 failures=0` —— 与 ticket 09 验收时的同一行一致 ⇒ 公告线未被本轮改动破坏 |
| 界面 | A1 / A3 / B0 / B1 / C1 / D0 / E3 / E14 / G1 逐张看过 | 与第 3 节逐条对得上（详见下） |

**截图逐张核对**：A1 = 秋季 2 门（张为民/英语听说交流（A）🔔1📅0📁4、高跃/形式语言与自动机 🔔1📅0📁0，右上计数 2）；
A3 = 学期切换页 9 项、最新在前、秋季打勾、**第 2 项正是 2025-2026 学年春季学期**；B1 = 春季 7 门 +「取证覆盖生效」标记 + 计数 7；
C1 = **界面**切到 2023-2024 夏季 → 1 门（穆太江/C++程序设计实践，无覆盖标记，确系界面路径）；D0 = 2010-2011 秋季居中「暂无课程」+ 计数 0；
E3 = 课程详情「作业」页 3 条且**截止时间正常显示**（2026-05-31 23:59 等，全部 ✓ 已提交）⇒ 第 4 节那条修复在界面上可见；
E14 = 从课程 tab 的「通知」进入的是 ticket 04 的**真详情**（陆玫 / 2026年6月9日 / 正文）；G1 = 覆盖态下点夏季被压住，仍 7 门。
`domain/courses/CourseCounts.ets` 与参考 `filteredData.ts:24-49` 我逐条件对过：未读公告 / **未提交且未截止** / `isNew`，一致。

#### 2. 边界一（**必须写进 ticket 10**）：学期覆盖只到「课程这条线」，不是全局开关

我在冷启动时**不点课程 tab**，日志里覆盖自证那行照样出现：

    entry.ability: semester override: want parameter "lohSemester"="2025-2026-2" accepted=true;
      semester override: constant="" runtime="2025-2026-2" effective="2025-2026-2" source=runtime-want-param
    data.courses: data.courses resolved semester=2026-2027-1 requested= lang=zh_CN courses=2 bytes=1837   ← 仍是站点当前学期

源码上能对上：覆盖只在 `data/courses/CourseFetchSource.fetchWithSession()` 里被读（`CourseFetchSource.ets:90`），
而公告路径的 `NoticeFetchSource.fetchWithSession(session)`（`data/notices/RealNoticeRepository.ets:44`）**连学期参数都没有**，
它经 `data/notices/CourseListFetcher` 走 `SemesterFetcher.resolve()` = 站点当前学期。

⇒ **这不是本 ticket 的缺陷**（本 ticket 的交付物是课程 tab；覆盖也确实是本轮为作业线新加的能力），
但它是一个**会被下游误读的坑**：作业 tab 若不把生效学期接进自己的取数路径，`--ps lohSemester` 下它依旧取「站点当前学期」= **空**，
而空列表恰好又是账号事实 ⇒ 两种原因会**在日志上长得一样**。已把处置写进 ticket 10 的 Comments 第 2 节。

#### 3. 边界二（证据标签）：`B0-notices-tab-spring-final.png` **名不符实**

该图拍的是**秋季**公告：未读 2、形式语言与自动机 / 英语听说交流（A）、「更新于 15:09:40」、状态栏 03:10——
**早于**本轮 B 组（B1 状态栏 03:36、更新于 15:36:13）的那次切换，而且它是公告 tab，本来就不受覆盖影响（见边界一）。
⇒ 它**不能**当「切到春季」的证据，只能当「**覆盖不影响公告 tab**」的界面侧佐证（这一点它很有用）。文件名保留但按此读；
已在 `.scratch/courses/evidence/README.md` 第 3 节就地更正，并把这条教训写进 `AGENTS.md`「取证要点」。

#### 4. 未验证 / 转出（与交付第 6 节一致，我逐条认账）

平板横向 → ticket 16；真机 API 24 → ticket 18；公告/文件**附件真实样本**仍缺；课程「上课时间地点」未取（源码已写明理由）；
一次 appfreeze 未复现——**我今日两次冷启动（15:43、15:44，含覆盖态）均正常，同样未能复现**，维持「观察到但未复现」。
两条可读性 nit（不阻塞）：`AssignmentsFetcher.ets` 与 `AssignmentParser.ets` 末尾丢了换行（No newline at end of file）；
`normalizeDeadline(value: string)` 靠 `text()` 的「类型谎」（运行时可能是数字）才能进到数字分支——单测（`jzsj` 由 `JSON.parse` 造出的数字）钉住了它，不会静默退化。

#### 5. 我这一轮的取样代价

1 次全量单测（38 s 构建 + 测试）、2 次冷启动 + 1 次 ui 点击 + 2 次全量 hilog（约 3 分钟设备窗口）、1 次 hap 解包。
**设备锁与构建锁均已释放，无后台作业在跑。**


### 边界说明（2026-09-12，由 ticket 11 带入）—— 课程详情的文件详情占位页已被真身取代

1. **`features/courses/CourseDetailPlaceholder.ets` 已删除**（ticket 10 换掉作业详情后，该文件只剩 `CourseFileDetailPlaceholderPage` 一个）；
2. `ROUTE_COURSE_FILE_DETAIL` 与 `CourseFileDetailRouteParams` **保留在 `CourseRoutes.ets` 未动**
   （`CourseDetailPage.openFile` 的构造点一行未改），只是 `CoursesPage` 的目的地渲染改为
   `FileDetailPage({ params: fileDetailParamsFromCourseFile(param as CourseFileDetailRouteParams), stack })`
   （转换函数在 `features/files/FileRoutes.ets`）；
3. 于是课程详情"文件"标签页点进去不再是"该页面将在后续迭代中实现"。

**你的证据还成立到哪一步**：ticket 12 关于课程列表 / 详情 / 学期切换的证据不受影响；
只有"文件标签页 → 占位页"这一处的截图不再可复现。
**可观察量转移到哪里**：ticket 11 的文件详情截图。

