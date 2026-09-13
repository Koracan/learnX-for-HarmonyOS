# 17: 学期切换必须驱动四个列表 + 切换过程与结果要可见

**What to build:** 账号所有者第三轮反馈（2026-09-13，按重要性第 1、2 条）：

1. **（严重）切了学期以后，公告 / 作业 / 文件 / 课程都不会自动刷新。** 其中**作业与课程**手动下拉刷新**有效**，
   **公告与文件**手动下拉刷新**也无效**。
2. **切换后学期页立刻返回。** 希望**不返回**，并在切换时给出**加载**与**成功 / 失败提示**。
   账号所有者自己给的修法建议：**切换时弹出一个加载页面，由它完成刷新与提示**。

这一条同时改到"数据从哪来"（四条取数路径的学期口径）与"切换这个动作长什么样"（加载 + 结果 + 不自动返回）。
两件事**必须一起做**：只改数据口径，用户仍然看不到刷新发生在哪；只加加载页，四个列表照样是旧的。

**Blocked by:** None（可立即开始）

**Status:** verified（统筹者独立复现：门禁 441 绿 + 分栏态 A/B（加载 / 不返回 / 结果提示 / 四列表 7-57-17-95）+ 失败注入 partial + 产物指纹逐字一致；见文末 2026-09-13 统筹者验收）

**判据（每条都要设备证据或单测，不能只写看起来好了）**

A. 先诊断，再动手
- [ ] 「不自动刷新」按页面拆开，四个 tab 各给**机制证据**（file:line + 因果链）。不要用"可能只是慢"糊过去。
      至少回答：① 公告与文件这两条取数路径**到底认不认**学期选择（不认的话，它们的有效学期由什么决定）；
      ② 课程与作业共用的那份 store 在切换后**有没有**真的完成一次重取、耗时多少（hilog 毫秒），
      以及"界面没变"是**没取**、**没取到**、还是**取到了但没重绘**。
- [ ] 下面「派单情报」一律当作**待证伪的线索**：那是统筹者自己读代码读出来的，结论你自己复核；
      其中有不止一条是**猜测**（会明确标注）。猜错了就照实改判。

B. 修复
- [ ] **学期选择是进程级共享状态**：一处选择，**四条**取数路径都消费它（课程 / 作业共用的课程快照、公告、文件）。
- [ ] 有效学期的优先级保持 **脚本覆盖 > 界面选择 > 站点当前学期**，且这三档的判定**只有一处实现**
      （现在至少散在两处、公告侧还有第三套口径）；不要复制三份。
- [ ] **手动下拉刷新**在四个 tab 都跟随选择：公告与文件的下拉刷新必须带上选中学期
      （这是账号所有者点名的缺陷，用请求 URL 或 hilog 行证明）。
- [ ] **切换 = 一次编排**：点一行 → 进入"切换中"（加载遮罩；**遮罩期间不可重复点击、不可返回**，
      否则提示会落在已经返回的页面上）→ 等**全部域**落地 → 给结果。**不自动返回**：学期页留在栈顶，由用户自己按返回。
- [ ] **成功 / 失败提示**：全部成功 → 成功提示（带上目标学期）；任一域失败 → 失败或**部分失败**提示
      （说清哪个域失败、原因要点）。**不得假装切换成功**。课程域失败时沿用既有"保留旧数据 + errorMessage"的显式降级，不清空列表。
- [ ] 既有取证入口不能被破坏：`aa start --ps lohSemester <id>` 的运行期覆盖仍然**优先于**界面选择（别人的取证工具依赖它）。
- [ ] **状态复原**：取证结束后把设备学期切回 **2026-2027 学年秋季学期**，并记录复原动作。

C. 证据
- [ ] **切换中的一帧**（加载可见）+ **切换后的成功提示帧**（提示文案能在帧或 dump 里读到）
      + **没有自动返回**的证据（学期页仍在栈顶：学期列表还在，或返回栈层数 / 路由名）。
- [ ] **不做任何手动刷新**，四条线各给一次**判别性**证据：
      - 课程 tab：学期文案 + 课程列表内容跟着换（至少一条课程标题变化，或条数变化）；
      - 作业 tab：作业列表**内容或条数**变化（**不要**只给"页头相对时间变了"）；
      - 公告 tab：公告条数 / 内容变化，**并且** hilog 里公告那条链的课程列表请求带上了选中学期；
      - 文件 tab：文件条数 / 内容变化，**并且**有 `data.files effective semester=<选中学期> source=selection`（或等价的一行）。
      - 判别性的前提：所选学期与站点当前学期的数据**必须不同**（本账号 2026-2027-1 与 2025-2026-2 在课程与作业上都不同）。
- [ ] **负对照 / 排除解释**：证明没有第二条"按站点当前学期取数"的路径在覆盖结果
      （例：切到 A 之后，相关请求 URL 里的学期段都是 A，而站点当前学期是 B）。
- [ ] **失败路径**：至少用**单测**钉住编排的三种结果（全成功 / 部分失败 / 全失败）与提示选择。
      设备侧尽力而为（建议的注入方式见下），做不到就如实写"没做到"——**不许**拿"看起来有提示"当证据。
- [ ] **单测**（沿用既有注入式缝，不新造平台依赖）：优先级纯函数；选择写进进程级状态后四条路径都读到它；编排的结果分类。
      沿用 `entry/src/test/CourseData.test.ets`（`CourseListStore` 三条）、`DataFetch.test.ets`、`NoticeRepository.test.ets`、`FileDownload.test.ets` 的缝。
      **注意**：进程级全局状态会在用例之间串味 —— 每个用例开始前清空选择，并确认既有 427 条不是靠运气过的。
- [ ] **门禁**：单测 + `assembleHap` + 四个脚本，**全部在你这棵树里跑**（见文末"构建 / 门禁环境"）。

**派单情报（统筹者初查；标了【猜】的是猜测，其余是读到的字面事实）**

- 公告侧**没有**界面选择这一档：`data/notices/NoticeFetchSource.ets:38` 调 `this.courses.fetch(session)`（**无学期参数**）
  ⇒ 由站点当前学期决定。【读到的】
- 文件侧**显式**声明没有选择这一档：`data/files/FileFetchSource.ets:5-8`（文件头注释）与 `:69`
  （`effective = override ?? siteCurrent`）。【读到的】
- 课程 / 作业共用**进程内单例**：`features/courses/CourseListStoreProvider.ets:24`；四个页面读它：
  `CoursesPage.ets:108`、`AssignmentsPage.ets:115`、`SettingsPage.ets:186`、`SearchPage.ets:112`。【读到的】
- 切换页 `features/courses/SemesterSelectionPage.ets:81-93`：`store.selectSemester(id)` 之后**立刻** `this.stack.pop()`
  —— 第 2 条症状的落点就是这里。【读到的】
- `CourseListStore.selectSemester`（`features/courses/CourseListStore.ets:128-134`）= 同步记选择 + 后台 `refresh()`；
  选择存在 store 的 `selectedSemesterId`（`:51`），**只在课程这条链上被消费**（`:100`）。【读到的】
- 公告与文件两个 store **不是**单例：`NoticesPage.ets:101`、`FilesPage.ets:101`（页面 `aboutToAppear` 里 new）。【读到的】
- 优先级判定现在散在 `data/courses/CourseFetchSource.ets:107-119` 与 `data/files/FileFetchSource.ets:69-74`；公告侧没有。【读到的】
- `ui/components/Toast.ets` 是**应用内自绘**的 Toast（能被 dump / 截图看到），`TOAST_MILLIS_FOR_EVIDENCE` 是既有取证开关
  （提交态必须回 0，有单测守着）。取证用它可以，但**提交态的构建必须与门禁数字同源**，并写清哪几张帧来自哪次构建。【读到的】
- 【猜】课程 / 作业"不自动刷新"的原因：一次重取实测 5–7 s（见 ticket 14 的 7017 ms / 6557 ms），切换后**没有任何进度指示**，
  用户很可能在重取结束前就看过去了。**这只是猜测**：请用 hilog 时间戳回答"取没取、多久、界面何时变"，
  如果是"取到了但没重绘"，那是另一个缺陷（ArkUI 依赖登记），修法完全不同。

**失败注入（建议，允许换更好的）**
- 本机模拟器 `svc` / `ip` 都不可用、shell 不是 root（统筹者实测：`/bin/sh: svc: inaccessible or not found`）
  ⇒ **hdc 侧关不掉网**。别在这上面烧时间。
- 一个**不需要动网络**的真失败：切到**没有选课**的学期时，公告取数会因为 `courseIds` 为空而抛
  `no courses for the current semester`（`data/notices/NoticeFetchSource.ets:40-44`），而课程域同时是**合法空态**
  ⇒ 天然的**部分失败**。能复现就是一次真注入；复现不了照实写。

**你的资源（独占，别人不得碰）**
- worktree：`D:\Koracan\source\harmony\learnOH-wt\t17`（分支 `wt/t17`，基于 main `63af17b`）。
  `ohpm install` 与 `reference/` 目录联接**已由统筹者做好**。**只在这棵树里改与构建，主树不要动。**
  开工前、每次构建前、每次取证前都 `git rev-parse --show-toplevel` 自证你在哪棵树。
- 设备：`127.0.0.1:5555`（`hdc` 实测 `devicetype=phone`，**这台只有你用**）。
  `devecocli device list` 会把它报成 Mate X7 / foldable —— 别信那列。
- i18n 说明：本轮另有一条线（ticket 18）也可能改 i18n 生成物的输入
  （`scripts/i18n-ui-strings.mjs` / `scripts/generate-i18n-resources.mjs`）。你**照常改、照常提交生成物**，
  合并时的冲突由统筹者用"取一侧 + 重跑两个生成器"收敛。你新增的提示文案请走 `scripts/i18n-ui-strings.mjs`。

**硬禁止（会毁掉不可恢复的东西）**：不真的提交作业（本账号 9 个学期 546 条作业全部已截止，提交不可撤回）；
不在真机上点「退出登录」；不改设备级永久设置（语言 / 分辨率 / 密度 / 时区）；不动 `.scratch/migration/**`；
**不提交图片**（帧 / dump / 日志只留本地）；不把台账或 ticket 编号写进代码注释。

**构建 / 门禁环境（照做，别自创）**
1. `$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'`（不设会出现
   `Configuration Error: Invalid value of 'DEVECO_SDK_HOME'` 且**一条测试都不跑**）。
2. hvigor 入口：`C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat`（不在 PATH 上）。
   构建以分钟计，用**后台作业**跑并把输出重定向到 `.dsh/logs/`。
3. 单测：先删 `entry/.test`，再 `test --no-incremental`；判据是
   `entry/.test/default/intermediates/test/coverage_data/test_result.txt` 里的 `Tests run:` 行 **+ 该文件的时间戳是本轮的**
   （只看 BUILD SUCCESSFUL 或退出码会被假绿骗）。
4. 打包：`assembleHap --no-incremental`，然后在日志里**搜** `ERROR` / `ErrorCode` / `COMPILE RESULT`，
   不能只看 BUILD SUCCESSFUL。
5. 四个脚本：`node scripts/check-domain-purity.mjs`、`check-import-graph.mjs`、`check-i18n-keys.mjs`、`check-generated-fresh.mjs`
   （最后一个在新树首跑可能假红，判据是 `git diff` 对那 6 个生成物为空）。
6. 指纹：**不要用 hap 文件 SHA256 当"装的是哪一笔"的判据**（容器不可复现）。要比就解包比 `ets/modules.abc` 的 SHA256，
   或用内容级检索。
7. 设备身份以 `hdc -t SERIAL shell param get const.product.devicetype` 实测为准。本机模拟器**不能**旋转 / 缩放 / 折叠。

**报告要求**：结论先行；每条论断配**一个**证据（file:line、dump 的 px、帧、或 hilog 时间戳）；
做不到的如实写"没做到 / 存疑"，**没抓到不等于不存在**；在 `.scratch/ui-optimize/issues/17-semester-switch-drives-all-lists.md` 追加 Comment，
过程证据写进 `.scratch/ui-optimize/evidence/17-<slug>.md`（可提交），图片留在 `.scratch/ui-optimize/evidence/` 且**不入库**。
收尾必须回报「**窗口关闭**」并说明设备与工作区状态（进程 / 画面 / 是否留了脏文件）。
## Comments

### wt/t17（实现 agent）— 2026-09-13

**结论先行：四条链现在都消费同一份进程级学期选择；切换做成一次编排（加载 → 结果 → 不自动返回）。**

分支 `wt/t17`；设备 `127.0.0.1:5555`（`hdc` 实测 phone / API 23，独占）。
过程证据（文字，已入库）：`.scratch/ui-optimize/evidence/17-semester-switch-drives-all-lists.md`。

#### 诊断（先诊断再动手）

- **公告连手动刷新都无效**：`data/notices/NoticeFetchSource.ets:38` 调 `this.courses.fetch(session)`
  ——**不带学期**；`CourseListSource.fetch` 在学期为空时会自己去问站点当前学期
  （`data/courses/CourseListFetcher.ets:209-214`）⇒ 公告的课程表永远是站点当前学期的。
  文件同理：`data/files/FileFetchSource.ets:69` 是 `override ?? siteCurrent`，**根本没有选择这一档**。
  ⇒ 下拉刷新确实发生、也确实成功，但刷的是另一个学期 —— 这就是「无效」的机制。
- **课程/作业**：不是没取、也不是取到了不重绘。修后实测这一轮取数 `17:51:19.98 → 17:51:28.98` ≈ **9.0 s**
  （`logs/t17-hilog-switch.txt`）。**「切完不刷新」我在 5555 上没复现**（课程与作业都在 ~9 s 后自己跟上了，
  与统筹者在 5559 的结论一致）。按用户口径的可行解释是「8 秒内没有任何反馈」，如实记为**未复现**、不算已证伪。
- 优先级判定修前散在 `CourseFetchSource:107-119` 与 `FileFetchSource:69-74` 两处，公告侧没有第三套
  （它干脆没有选择档）—— 现收敛为一处 `resolveEffectiveSemester()`。

#### 修复

- 唯一优先级：`data/courses/SemesterOverride.ets` 的 `resolveEffectiveSemester()`（覆盖 > 界面选择 > 站点当前），
  课程/作业、公告、文件**三条路径都调它**。
- 界面选择进**进程级**状态（`setSelectedSemesterId` / `selectedSemesterForFetch`），
  `CourseListStore.selectSemester()` 在选择发生时写入。
- 公告 store 与文件 store 改成**进程内单例**（新增 `NoticeListStoreProvider` / `FileListStoreProvider`）——
  否则编排拿不到页面自己 new 的那一份。
- 编排 `features/courses/SemesterSwitch.ets`：同步写选择 → `allSettled` 等三个域 → 纯函数分类 success/partial/failed。
- 学期页：加载遮罩（拦截点击、在途时返回失效，宿主页 `NavDestination.onBackPressed` 消费系统返回）
  + 结果 Toast + **不 pop**。新增 4 条 i18n 文案（走 `scripts/i18n-ui-strings.mjs`，生成物已重跑并入库）。
- 既有取证入口未破坏：`aa start --ps lohSemester <id>` 仍是最高优先级（`overrides` 档，有单测）。

#### 我在实现中踩到并修掉的缺陷（如实记录）

第一版编排按 `Promise.allSettled` 的 settle 状态判成败。但三条 store 的 `refresh()` 都把异常**吞进自己的
`errorMessage`** 并 resolve（既有降级口径）⇒ settle 永远 fulfilled ⇒ **每次失败都会被报成成功**。
第二版改读 `store.errorMessage`，设备上仍误报过一次 `notices=ok(2)`：同一实例上并发的 `loadOnce` 成功后
把 `errorMessage` 清空了。**最终版让 `refresh()` 返回 `Promise<boolean>`，只看这一次调用自己的返回值**；
单测 `treats a domain that reports failure as failed even though its promise resolved` 钉住。

#### 证据（每条论断一个证据）

| 判据 | 证据 |
| --- | --- |
| 切换中一帧（加载可见） | `logs/t17-04-switching.json`：`正在切换学期…` bounds `[952,1153,1259,1204]`（屏宽 2210 ⇒ 居中），下面一行是目标学期 |
| 成功提示帧 + **不自动返回** | `17-01-switch-success-toast.png`：一帧里同时有 Toast `已切换到2025-2026 学年春季学期`、标题 `学期切换` 与整列学期仍在、`✔` 已移到春季行 |
| 课程（**不做手动刷新**） | 页头 `2026-2027 学年秋季学期`/`全部 2` → `2025-2026 学年春季学期`/`全部 7`（`t17-09-fall-courses.json` ↔ `t17-10-spring-courses.json`） |
| 作业 | `全部 0` → `全部 57`（`t17-09-fall-assignments.json` ↔ `t17-06-spring-assignments.json`） |
| 公告 | `全部 2`/未读 0 → `全部 17`/未读 7，内容换成「高技术战争/离散数学方法/软件分析与验证」（`t17-09-fall-notices.json` ↔ `t17-06-spring-notices.json`）；**且** hilog 公告链的课程列表请求带上了选中学期 |
| 文件 | `全部 4` → `全部 95`（`t17-09-fall-files.json` ↔ `t17-06-spring-files.json`） |
| 文件链有效学期 | `data.files effective semester=2025-2026-2 source=selection siteCurrent=2026-2027-1`（17:51:19.983） |
| 负对照（没有第二条按站点当前学期取数的路径） | 三个域的请求 URL 学期段全是 `2025-2026-2`（`network request #35/#36/#37`），而 `semesters resolved current=2026-2027-1` |
| 部分失败提示 | `17-02-partial-failure-toast.png` + `t17-13-partial-failure.json`：`已切换到2025-2026 学年春季学期，但公告刷新失败：notice refresh aborted by evidence switch`；`result=partial domains=[courses=ok(7) notices=fail(2) files=ok(95)]` |
| 状态复原 | `t17-14-restored-final.json`：`✔` 回到 `2026-2027 学年秋季学期`；hilog `target=2026-2027-1 result=success domains=[courses=ok(2) notices=ok(2) files=ok(4)]` |

#### 门禁（全部在 `wt/t17` 里跑）

- 单测 **`Tests run: 440, Failure: 0, Error: 0, Pass: 440, Ignore: 0`**（本树基线本轮实测 `427 / 0 / 0 / 427`；
  result 文件 mtime `2026-09-13T18:12:23`，是本轮的）。新增 13 条在 `entry/src/test/SemesterSwitch.test.ets`。
- 打包 `assembleHap --no-incremental`：`BUILD SUCCESSFUL in 12 s 104 ms`；日志搜 `ERROR|ErrorCode|COMPILE RESULT` **0 命中**。
- 四脚本：`check-domain-purity` PASS / `check-import-graph` PASS（WARN 两个孤儿与基线同）/
  `check-i18n-keys` RESULT: OK（manifest 313，三语言 missing=0 empty=0 extra=0，186 个源码引用全解析）/
  `check-generated-fresh` PASS。
- 提交态 `ets/modules.abc` SHA256 `99A18C5337136091412B76EA3BDCDA9A3ADC12A422BE3542EE59D0CDCA3DE0BC`（1821828 B）。
  取证构建的指纹见证据文档 §9（含一次**未记录**的失败注入构建，已如实标注）。

#### 没做到 / 存疑

1. 「课程/作业修前完全不刷新」**未复现**（5555 上 ~9 s 后自己跟上）——见上。
2. **设备侧「全失败」档没做**（只做了部分失败）：仓库里只有一个免网络注入点（公告），
   模拟器 `svc`/`ip` 不可用、shell 非 root。全失败档由单测覆盖。
3. 失败注入构建（`18:07:57`）的 abc 指纹**未记录**，事后被提交态构建覆盖。
4. 加载帧的 25 s 窗口靠 `SWITCH_DELAY_FOR_EVIDENCE` 注入放大（真实窗口 5–9 s，`devecocli ui layout` 单次就要 10–35 s）；
   遮罩本身的触发与注入无关。提交态该常量为 0。
5. **未取双栏（tablet）**下的切换表现：本 ticket 的设备是 phone。

#### 设备与工作区状态

- 设备学期已复原为 **2026-2027 学年秋季学期**（站点当前学期），运行期覆盖 `lohSemester` 全程为空 ⇒ 无进程外残留。
- 装了**提交态**构建的 HAP（取证期间那两次带注入的构建已换掉，不留给下一个人）；
  应用冷启动后在跑（pid 22862），画面停在**课程 tab**：页头 `2026-2027 学年秋季学期`、`全部 2`，
  hilog `effective semester=2026-2027-1 source=site-current`（`logs/t17-16-final-courses-state.json`、
  `evidence/17-03-final-device-state.png`）。
- 工作区 `wt/t17`：**干净**（`git status --porcelain` 为空），提交 `de9d454`；
  图片 / dump / hilog 只在本地 `.scratch/ui-optimize/evidence/**`（不入库），文字证据已 `git add -f` 入库。
- 该树仍有一个 hvigor 守护进程（pid 85420）。
- **窗口关闭**。
- 一处需统筹者知晓：`17-…md` 这个 ticket 文件只存在于主树（未跟踪），worktree 里没有它的副本；
  本 Comment 是直接追加到主树那份上的（除它之外主树未被我改动）。

### wt/t17（实现 agent）— 2026-09-13 补充轮：设置入口的返回守卫 + 取证开关单测

**统筹者独立验收打回一条，已修并重新取证。**

#### 打回的那条

返回守卫只做在课程入口：`grep -rn 'ROUTE_SEMESTER_SELECTION'` 的两个 push 点是
`CoursesPage:270` 与 `SettingsPage:191`，而只有 `CoursesPage` 的 NavDestination 传了 `onSwitchInFlight`
并挂了 `onBackPressed`。后果：从**设置**进学期页 → 点一行（切换 ~7 s）→ 期间按系统返回 ⇒ 页面先 pop、
编排仍在后台跑完，成功/失败提示落在**已被销毁**的页面上，用户看不到 —— 正是这条判据要防的事。

#### 修法

`features/settings/SettingsPage.ets`：新增字段 `semesterSwitchInFlight`；`routeTo` 的
`ROUTE_SEMESTER_SELECTION` 分支传 `onSwitchInFlight` 并挂
`.onBackPressed((): boolean => this.semesterSwitchInFlight)`。
**分栏态一并覆盖**：`routeTo` 被 `masterDestination` 与 `detailDestination` 共用，单栏（主栈）与
分栏（右栏 `detailStack`）构造的是同一个带守卫的 `NavDestination`。
（分栏那条路径**只有结构性论据、没有设备观察**：本 ticket 的设备是 phone，模拟器不能旋转/改视口 —— 如实登记。）

#### A/B 设备证据（同一台 5555，同一序列：设置 → 学期子页 → 点一行 → 0.6 s 后发一次系统 Back）

| 时点 | 构建 | Back 之后观察到什么 |
| --- | --- | --- |
| 修前 | 上一轮提交态产物（`99A18C53…`） | 学期页**被 pop**（dump 是设置页），hilog 仍打出 `toast shown: … 已切换到2025-2026 学年春季学期` —— 提示落在已销毁页面上（`logs/t17-19-…json`） |
| 修后 | 取证构建（`F3B6D863…`，`SWITCH_DELAY_FOR_EVIDENCE=25000`） | 学期页**仍在** + 遮罩 `正在切换学期…` 在（`logs/t17-21-…json`）；切换结束后 `evidence/17-04-back-guard-toast-still-visible.png`：提示**可见**、`✔` 已移行，且底部高亮的是**设置** tab ⇒ 确实是设置入口 |

时间线（设备时钟）：`18:36:07.664 switch started` + `delay override active: …25000 ms` →
（Back 在 tap 后 0.56 s 发出，落在窗口内）→ `18:36:41.097 switch finished: result=success` +
`toast shown: millis=60000 … 已切换到2025-2026 学年春季学期`。

课程入口回归 + 顺带复原设备：`logs/t17-24-…json`（Back 后学期页仍在 + 遮罩在）、
`logs/t17-25-…json` + `evidence/17-05-courses-back-restore.png`（提示 `已切换到2026-2027 学年秋季学期`、
`✔` 回到秋季行、`domains=[courses=ok(2) notices=ok(2) files=ok(4)]`）⇒ **设备已复原到秋季**。

#### 顺手补的取证开关单测

`SWITCH_DELAY_FOR_EVIDENCE` 此前没有 OffAtCommit 断言。已在 `SemesterSwitch.test.ets` 补
`evidenceSwitchDelayOverrideIsOffAtCommit`（与 `evidenceToastDurationOverrideIsOffAtCommit` /
`evidenceUnreadOverrideIsOffAtCommit` 同一口径）。

#### 本轮门禁（提交态，全在 `wt/t17`）

- 单测 **`Tests run: 441, Failure: 0, Error: 0, Pass: 441, Ignore: 0`**（mtime `2026-09-13T18:41:02`，本轮；440 → 441 就是补的那条）。
- 打包 `assembleHap --no-incremental`：`BUILD SUCCESSFUL in 9 s 750 ms`；搜 `ERROR|ErrorCode|COMPILE RESULT` **0 命中**。
- 四脚本：purity PASS / import-graph PASS / i18n `RESULT: OK` / generated-fresh PASS。
- 提交态 `ets/modules.abc` SHA256 `69E480AE85F5A90EFC805CDF7CD8707CE570DE9EB3C6907F8E4895169396D087`（1822596 B）；
  取证构建 `F3B6D863F2F50A57506E160F6AE5878B2D94EE5795AAA08381B1AC6E9E898CA4`；
  上一轮提交态 `99A18C53…`（即本轮的「修前」基线）。
- 两个开关提交态复原（`git show HEAD` 可核）：`SWITCH_DELAY_FOR_EVIDENCE=0`、
  `SEMESTER_SWITCH_TOAST_MILLIS_FOR_EVIDENCE=0`。

#### 本轮没做到 / 存疑

1. **分栏（右栏 detailStack）的守卫没有设备观察**（phone 设备 + 模拟器不能改视口），只有结构性论据。
2. 修前对照是**同设备换装上一轮提交态产物**做的（不是同一次构建内翻开关），两次代码差异只有这一处守卫。

#### 设备与工作区状态（窗口关闭）

- 设备学期 = **2026-2027 学年秋季学期**（站点当前学期），运行期覆盖为空。
- 已换回**提交态** HAP；`wt/t17` 工作区干净；文字证据入库，图片/dump/hilog 只在本地。
- **窗口关闭**。

### 2026-09-13 · 统筹者验收：**verified**（门禁我自己重跑 + 在**另一台设备**上重做 A/B + 分栏与失败路径我自己补了设备观察）

**A. 产物同一性（我自己编）**：补充轮前（`de9d454`）解包 `ets/modules.abc` = `99A18C53…` / 1,821,828 B；补充轮后（`483dcce`）= `69E480AE…` / 1,822,596 B —— 两次都与实现方报的**逐字符相同**。

**B. 门禁（我自己在 `wt/t17` 里重跑）**：补充轮后删 `entry/.test` + `test --no-incremental` ⇒ `Tests run: 441, Failure: 0, Error: 0, Pass: 441, Ignore: 0`（`test_result.txt` mtime **18:44:18**）；`assembleHap --no-incremental` 搜 `ERROR`/`ErrorCode`/`COMPILE RESULT` 各 0；四脚本 PASS / PASS / `RESULT: OK` / PASS，且跑完生成器后 `git status` 为空。

**C. 我在设备 `127.0.0.1:5559`（tablet / **分栏态**；我自己装的这份提交态产物）上重做了 1、2 两条症状的 A/B**：
- **切换中**：设备侧连拍（`snapshot_display`）抓到遮罩帧：背景压暗 + 居中卡片 `正在切换学期…` + 目标学期，且勾选标记已移到新选那一行。
- **不自动返回**：切换结束后学期页**仍在屏幕上**（右栏仍是学期列表、勾选在春季）—— 修前同一台设备上这一页会立刻 pop（我的 before 基线里右栏露出的是栈里前一个页面）。
- **结果提示**：`semester switch finished: target=2025-2026-2 result=success domains=[courses=ok(7) notices=ok(17) files=ok(95)] elapsedMs=7986`，紧跟着 `toast shown: millis=3000 … text=已切换到2025-2026 学年春季学期`。
- **四个列表都不用手动刷新**：课程 春季 / 全部 7、作业 全部 57、公告 全部 17（未读 7）、文件 全部 95；修前同设备基线是 2 / 0 / 2（站点当前学期）/ 4。
- **手动刷新也不再「无效」**：文件 `effective semester=2025-2026-2 source=selection siteCurrent=2026-2027-1`、公告 `data.notices.source effective semester=2025-2026-2 source=selection … courses=7`。
- 取证后设备复原到 `2026-2027 学年秋季学期`（课程 全部 2 / 文件 全部 4），运行期覆盖全程为空。

**D. 我打回的一条 + 我替它补上的分栏观察**：设置入口原先没有返回守卫（`SettingsPage` 的 NavDestination 既没传 `onSwitchInFlight` 也没挂 `onBackPressed`）⇒ 在途按系统返回会 pop、提示落在已销毁页面上。它在 `483dcce` 里补齐；它自己如实登记「分栏（右栏 detailStack）只有结构性论据、没有设备观察」。**我用同一序列（设置 → 学期页 → 点一行 → 0.9 s 后 `uitest uiInput keyEvent Back`）在分栏态复现**：Back 之后学期页**仍在**（右栏 dump 仍是学期列表、勾选在春季），切换在 18:46:20.377 以 success 结束并打出提示 ⇒ 该缺口由我这边补上设备观察。

**E. 失败路径（我自己编了一次注入构建）**：`NOTICES_REFRESH_FAILURE_FOR_EVIDENCE=true`（另把结果提示时长切到 60000 ms 以便 dump 得到），abc `F58FC1DE…`。分栏态切换 秋季→春季：`result=partial domains=[courses=ok(7) notices=fail(2) files=ok(95)] elapsedMs=8068`，**界面 dump 里真的读到** `已切换到2025-2026 学年春季学期，但公告刷新失败：notice refresh aborted by evidence switch`（bounds `[844,1671,2824,1704]`）⇒「某一域失败不假装成功」在设备上成立（这正是实现中修掉的 `allSettled` 永远 fulfilled ⇒ 每次失败都报成功那一类）。收尾已 `git checkout` 复原两个开关（`git show HEAD` 自证 `false` / `0`、`wt/t17` 工作区干净），并把设备换回**合并后**的提交态产物。

**F. 合并**：`wt/t17` 并入 main = `0c6351c`。唯一内容冲突在 `SettingsPage.ets`（t18 的 `exportedSummary` 与 t17 的 `semesterSwitchInFlight` 落在同一处），手工保留两者；i18n 生成物按「重跑两个生成器 + `git diff` 为空」收敛（`check-generated-fresh` PASS；`ui_exported` 的三占位符与 `loh_immersive_mode_description` 的新值都在）。合并后 main 终验：`Tests run: 441`（mtime 18:48:37）、打包 0/0/0、四脚本 PASS/OK/PASS、abc `46915DFD…` / 1,821,648 B。

**G. 我确认的缺口（与实现方一致，均不阻塞判据）**：① **「课程 / 作业修前完全不刷新」没有复现** —— 在 5559 与 5555 上都是 ~8–9 s 后自己跟上；本 ticket 真正的修法是「把这段等待变成有反馈的加载」，而不是「修好一个不存在的取数」；② 设备侧「全失败」档仍只有单测（我的注入只做到 partial）；③ 实现方那轮失败注入构建的 abc 未记录（我这轮补了 `F58FC1DE…`）；④ 本 ticket 新增了**两个**取证开关（`SWITCH_DELAY_FOR_EVIDENCE` / `SEMESTER_SWITCH_TOAST_MILLIS_FOR_EVIDENCE`），提交态都是 0 且各有 OffAtCommit 单测 —— 记下来，供以后判断取证开关面是否继续膨胀。