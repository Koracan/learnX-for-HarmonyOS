# ticket 17 过程证据：学期切换驱动四条列表 + 切换过程可见

设备：`127.0.0.1:5555`（`hdc` 实测 `const.product.devicetype=phone`、`apiversion=23`，模拟器）。
worktree：`D:/Koracan/source/harmony/learnOH-wt/t17`（分支 `wt/t17`，基线 `63af17b`），每次构建/取证前都 `git rev-parse --show-toplevel` 自证过。

图片与原始 hilog / layout dump 在 `evidence/` 与 `evidence/logs/`（**不入库**，见 `.scratch/.gitignore`）。
本文件是文字证据，入库。

## 0. 结论先行

| # | 论断 | 一个证据 |
| --- | --- | --- |
| 1 | 四条取数路径此前**只有课程/作业**认学期选择 | 代码：`NoticeFetchSource:38` 调 `courses.fetch(session)`（无学期）、`FileFetchSource:69` 只认 `override ?? siteCurrent` |
| 2 | 所以公告/文件**手动刷新也无效**：刷新发生且成功，但刷的是站点当前学期 | `evidence/logs/t17-hilog-partial2.txt`：切换后 `data.files effective semester=2025-2026-2 source=selection`（修后）；修前同一条是 `source=site-current`（统筹者 5559 的基线） |
| 3 | 修后**四条链都消费进程级选择** | `logs/t17-hilog-switch.txt`：`data.courses` / `data.notices.source` / `data.files` 三条都打出 `semester=2025-2026-2 source=selection siteCurrent=2026-2027-1` |
| 4 | 切换**不自动返回** | `evidence/17-01-switch-success-toast.png`：提示已出、学期列表仍在栈顶 |
| 5 | 切换中有**加载遮罩** | `logs/t17-04-switching.json`：`正在切换学期…` 居中（bounds `[952,1153,1259,1204]`，屏宽 2210 ⇒ 中心 1105） |
| 6 | 全部成功 → 成功提示（带目标学期） | `evidence/17-01-switch-success-toast.png` + `logs/t17-05-after-switch.json`：`已切换到2025-2026 学年春季学期` |
| 7 | 任一域失败 → **部分失败**提示，不假装成功 | `evidence/17-02-partial-failure-toast.png` + `logs/t17-13-partial-failure.json`：`已切换到2025-2026 学年春季学期，但公告刷新失败：notice refresh aborted by evidence switch` |
| 8 | 没有第二条「按站点当前学期取数」的路径在覆盖结果 | 负对照见 §5：三个域的课程列表请求 URL 学期段全是 `2025-2026-2`，而站点当前学期是 `2026-2027-1` |
| 9 | 进程级选择**不是**靠运气：新单测钉住优先级与四条路径 | `Tests run: 440, Failure: 0, Error: 0`（基线 427） |
| 10 | 取证结束设备学期已复原 | `logs/t17-14-restored-final.json`：勾选回到 `2026-2027 学年秋季学期` |

## 1. 诊断：为什么公告与文件连手动刷新都无效（四条症状里最硬的一条）

### 1.1 有效学期的判定散在三处，且公告/文件都缺「界面选择」这一档

| 路径 | 入口 | 修前的有效学期 |
| --- | --- | --- |
| 课程 + 作业（同一次抓取） | `CourseListStore`（进程内单例）→ `RealCourseRepository.refresh(selected)` → `CourseFetchSource.fetchWithSession(session, selected)` | 覆盖 > **界面选择** > 站点当前 ✅ |
| 公告 | `NoticesPage` → `NoticeListStore` → `RealNoticeRepository` → `HttpNoticeFetchSource.fetchWithSession(session)` | **只有站点当前学期** ❌ |
| 文件 | `FilesPage` → `FileListStore` → `RealFileRepository` → `HttpFileFetchSource.fetchWithSession(session)` | 覆盖 > 站点当前（无选择档）❌ |

因果链（公告，修前 `data/notices/NoticeFetchSource.ets:37-38`）：

```
async fetchWithSession(session: Session): Promise<Notice[]> {
  const courseList: CourseListResult = await this.courses.fetch(session);   // ← 不带学期
```

`CourseListSource.fetch(session, semesterId?)` 的 `semesterId` 为空时会自己去问站点当前学期
（`data/courses/CourseListFetcher.ets:209-214`）⇒ 公告的课程表永远是**站点当前学期**的课程表，
与界面选了什么无关。文件同理（`data/files/FileFetchSource.ets:69`：`override.length > 0 ? override : resolution.currentSemesterId`）。

⇒ **下拉刷新确实发生、也确实成功**，但它刷的是另一个学期，所以看起来「无效」。
这解释了为什么它比课程/作业更难被用户理解为「慢」：课程/作业至少会在 8 秒后自己变。

### 1.2 课程 / 作业这条链：不是「没取」，也不是「没重绘」，是「8 秒内没有任何反馈」

统筹者在 5559（main `63af17b` 产物）复现：点一行 → 2 ms 内 pop，8.4 s 后 `course list applied`。
我在 5555 用修后的构建量到同一条链的耗时：`elapsedMs=34207`（含 25 s 取证注入延时）、
真实取数段 `17:51:19.98 → 17:51:28.98` ≈ **9.0 s**（`courses` 域含三域串行）。

⇒ 「界面没变」是**没等**：切换在途期间界面**没有任何进度指示**，而学期页已经在 2 ms 内返回。
这正是 ticket 第 2 条要求的「加载 + 结果 + 不自动返回」要解决的。
**我复现不出「课程/作业修前完全不刷新」**（与统筹者一致）：在 5555 上课程与作业都在 ~9 s 后跟上了。
我按用户口径的可行解释是「切完立刻看，8 秒内没有任何反馈」，如实记录为**未复现**，不算已证伪。

### 1.3 我自己在实现中踩到并修掉的一个缺陷（如实记录）

第一版编排用 `Promise.allSettled` 的 settle 状态判成败。但三条 store 的 `refresh()`
都把异常**吞进自己的 `errorMessage`** 并 resolve（既有「失败一律显式降级」口径），
所以 settle 永远是 `fulfilled` ⇒ **每一次失败都会被报成成功**。
第二版改读 `store.errorMessage`，仍然不可靠：同一实例上并发的另一次取数（页面 mount 的 `loadOnce`）
成功后会把 `errorMessage` 清空 —— 设备上实测到一次误报 `notices=ok(2)`。

最终版：`refresh()` 返回 `Promise<boolean>`，编排**只看这一次调用自己的返回值**。
单测 `treats a domain that reports failure as failed even though its promise resolved` 钉住这一条。

## 2. 实现（唯一优先级 + 编排）

- 生效学期的**唯一**判定：`data/courses/SemesterOverride.ets` 的 `resolveEffectiveSemester()`
  （覆盖 > 界面选择 > 站点当前），四条路径都调用它，不再各抄一份 if 链。
- 进程级界面选择：同文件的 `setSelectedSemesterId()/selectedSemesterForFetch()`；
  `CourseListStore.selectSemester()` 在选择发生时写进去。
- 编排：`features/courses/SemesterSwitch.ets` 的 `switchSemester()` —— 同步写选择 →
  `allSettled` 等三个域 → `classifySwitchResult()`（纯函数）给 success/partial/failed。
- 公告 store 与文件 store 改为**进程内单例**（`NoticeListStoreProvider` / `FileListStoreProvider`），
  否则编排拿不到页面自己 new 的那一份，公告/文件就永远停在旧数据。
- 学期页：加载遮罩（拦截点击）+ 结果 Toast + **不 pop**；宿主页 `NavDestination.onBackPressed`
  在途时消费返回手势。

## 3. 切换中的一帧（加载可见）

- 帧：`evidence/logs/t17-04-switching.json`（取证构建，开关 `SWITCH_DELAY_FOR_EVIDENCE=25000`）
- dump 里同时能读到：`正在切换学期…`（居中）**与**目标学期 `2025-2026 学年春季学期`；
  学期列表整列仍在（页面没被 pop）。
- 自证：`logs/t17-hilog-switch.txt` 的 `switch delay override active: SWITCH_DELAY_FOR_EVIDENCE=25000 ms`。
- **说明**：这张帧来自**取证构建**（注入延时把 5–7 s 的窗口拉大到可拍），提交态该常量为 0；
  这不是「加载遮罩只在取证时才有」——遮罩由 `switching` 状态驱动，与注入无关。

## 4. 成功提示帧 + 没有自动返回

- 帧：`evidence/17-01-switch-success-toast.png`（1958×2141，取证构建）
- 同一帧里三件事同时可核：① 底部 Toast `已切换到2025-2026 学年春季学期`；
  ② 标题 `学期切换` 与整列学期仍在（**没有自动返回**）；③ 勾选 `✔` 已从秋季行移到春季行。
- dump 佐证：`evidence/logs/t17-05-after-switch.json`（同一文本可在树里读到）。
- 自证时长开关：`logs/t17-hilog-switch.txt` 的 `semester switch toast: millis=60000`。

## 5. 四条线各一次判别性证据（**不做任何手动刷新**）

切换目标 `2025-2026-2`；站点当前学期 `2026-2027-1`；两者数据确实不同。

| tab | 站点当前学期（2026-2027-1） | 选中学期（2025-2026-2） | 证据 |
| --- | --- | --- | --- |
| 课程 | 页头 `2026-2027 学年秋季学期`；`全部 2`（英语听说交流（A）/ 形式语言与自动机） | 页头 `2025-2026 学年春季学期`；`全部 7`（西方音乐史 / 高技术战争 / 三年级男生台球 / 离散数学方法 / 偏微分方程 / 算法分析与设计基础 / 软件分析与验证） | `logs/t17-09-fall-courses.json` ↔ `logs/t17-10-spring-courses.json` |
| 作业 | `全部 0` | `全部 57`、`已完成 57` | `logs/t17-09-fall-assignments.json` ↔ `logs/t17-06-spring-assignments.json` |
| 公告 | `全部 2`、未读 0、内容=「课程信息和微信群」/「Welcome message from the professor」 | `全部 17`、未读 7、内容=「高技术期末开卷考试信息」/「离散数学方法 考试安排」/「期末考试安排」 | `logs/t17-09-fall-notices.json` ↔ `logs/t17-06-spring-notices.json` |
| 文件 | `全部 4`、未读 0、全为 ZIP（Listening 1–3-2） | `全部 95`、未读 4、内容=「期末复习」/「期末考试样卷」/「课件26/27」 | `logs/t17-09-fall-files.json` ↔ `logs/t17-06-spring-files.json` |

公告那条链的**请求级**证据（ticket 明确要求「hilog 里公告那条链的课程列表请求带上了选中学期」）：

```
# logs/t17-hilog-switch.txt
17:51:19.831 data.notices.source semester override: ... effective="" source=none
17:51:21.153 data.notices.source effective semester=2025-2026-2 source=selection siteCurrent=2026-2027-1 courses=7
17:51:21.241 data.notices.repository notices refresh done: items=17 elapsedMs=1424
```

文件那条链（ticket 要求 `data.files effective semester=<选中学期> source=selection` 或等价一行）：

```
17:51:19.983 data.files effective semester=2025-2026-2 source=selection siteCurrent=2026-2027-1
17:51:20.434 data.files snapshot semester=2025-2026-2 source=selection courses=7 files=95
```

课程 + 作业（同一次抓取，`CourseSnapshot.assignments`）：

```
17:51:28.980 data.courses snapshot semester=2025-2026-2 source=selection courses=7 notices=17 assignments=57 files=95
```

### 负对照：没有第二条「按站点当前学期取数」的路径在覆盖结果

三个域发起的课程列表请求 URL 学期段**全是选中学期**，站点当前学期是 `2026-2027-1`：

```
# logs/t17-hilog-switch.txt（同一轮切换，17:51:19.98–17:51:19.99）
network request #35 ... loadCourseBySemesterId/2025-2026-2/zh_CN   ← 文件域
network request #36 ... loadCourseBySemesterId/2025-2026-2/zh_CN   ← 公告域
network request #37 ... loadCourseBySemesterId/2025-2026-2/zh_CN   ← 课程域
```

对照：`data.courses semesters resolved current=2026-2027-1` —— 站点报的当前学期确实是 `2026-2027-1`，
而三条路径都没有按它取数。

## 6. 失败路径设备证据（部分失败，真注入）

注入方式沿用仓库既有开关 `data/notices/RealNoticeRepository.ets:62` 的
`NOTICES_REFRESH_FAILURE_FOR_EVIDENCE`（消费点 `:220` 自证），**没有动网络**。

```
# logs/t17-hilog-partial2.txt
18:09:40.014 data.notices.repository notices refresh switch: NOTICES_REFRESH_FAILURE_FOR_EVIDENCE=true
18:09:40.021 features.notices.store ERROR refresh failed: notice refresh aborted by evidence switch
18:09:47.744 features.courses.switch semester switch finished: target=2025-2026-2 result=partial \
              domains=[courses=ok(7) notices=fail(2) files=ok(95)] elapsedMs=32741
18:09:47.744 features.courses.switch WARN semester switch incomplete: failedDomains=[notices] \
              firstReason=notice refresh aborted by evidence switch
18:09:47.746 result presented: ... message=已切换到2025-2026 学年春季学期，但公告刷新失败：notice refresh aborted by evidence switch
```

- 帧：`evidence/17-02-partial-failure-toast.png` + `logs/t17-13-partial-failure.json`。
- 同轮里课程域与文件域**照常成功**（`courses=ok(7) files=ok(95)`）⇒ 这是「部分失败」而不是「整个切换崩了」。
- **全失败档**没有设备注入（没有第二个可用的免网络注入点：模拟器 `svc`/`ip` 不可用、shell 非 root）；
  它由单测 `classifies all success, partial failure and total failure` 钉住。**如实记为设备侧未做**。

## 7. 单测（提交态）

新增 `entry/src/test/SemesterSwitch.test.ets`（13 条）覆盖：

1. 优先级纯函数 `resolveEffectiveSemester` 的四档（override > selection > site-current > none）；
2. 非法学期值**不生效**（不把打字错误当成「切过去了」）；
3. `CourseListStore.selectSemester` 把选择写进**进程级**状态；
4. 课程 / 公告 / 文件**三条路径**在只有进程级选择时都用选中学期（并断言**请求 URL 的学期段**）；
5. 什么都不选时三条路径回落到站点当前学期（正对照）；
6. 编排结果分类三档 + 「任一域失败绝不落 success」的负对照；
7. 「store 报失败但 promise resolved」必须算失败（就是我踩到的那个缺陷）；
8. 失败原因要点单行化与截断；
9. 两个取证时长开关在提交态都是 0。

## 8. 门禁原始数字（全部在 `wt/t17` 这棵树里跑）

| 门禁 | 原始输出 |
| --- | --- |
| 单测 | `Tests run: 440, Failure: 0, Error: 0, Pass: 440, Ignore: 0`（`entry/.test/default/intermediates/test/coverage_data/test_result.txt`，mtime `2026-09-13T18:12:23`，本轮） |
| 单测基线 | 本轮开工时（未改代码）同法测得 `Tests run: 427, Failure: 0, Error: 0, Pass: 427, Ignore: 0`（`logs` 见 `.dsh/logs/t17-baseline-test.log`） |
| 打包 | `assembleHap --no-incremental`：`BUILD SUCCESSFUL in 12 s 104 ms`；关键字扫描 `ERROR|ErrorCode|COMPILE RESULT` **0 命中** |
| 脚本 1 | `check-domain-purity.mjs` → `PASS domain 不依赖平台与应用层` |
| 脚本 2 | `check-import-graph.mjs` → `PASS 所有相对 import 均可解析`（WARN 两个孤儿：`pages/Index.ets` 入口属正常、`EntryBackupAbility.ets` 与基线一致） |
| 脚本 3 | `check-i18n-keys.mjs` → `RESULT: OK`（manifest 313；base/zh_CN/en_US 各 missing=0 empty=0 extra=0；source 引用 186 个键全部解析） |
| 脚本 4 | `check-generated-fresh.mjs` → `PASS 生成物与其生成器输入一致`（新树首跑也未假红） |

## 9. 构建溯源（哪张帧来自哪次构建）

| 构建 | 内容 | `ets/modules.abc` SHA256 | 大小 |
| --- | --- | --- | --- |
| A：取证构建（切换/成功/四条线/加载帧） | `SWITCH_DELAY_FOR_EVIDENCE=25000`、`SEMESTER_SWITCH_TOAST_MILLIS_FOR_EVIDENCE=60000`，其余提交态 | `D223B35B7BC820782920509255763D118173DB98AB5DFD36C64066BB9D2068EE` | 1820948 |
| B：失败注入构建（部分失败帧） | 在 A 之上再置 `NOTICES_REFRESH_FAILURE_FOR_EVIDENCE=true`，构建时刻 `18:07:57` | **未记录（存疑）** | — |
| C：提交态构建（门禁数字来源） | 六个取证开关全部复原 | `99A18C5337136091412B76EA3BDCDA9A3ADC12A422BE3542EE59D0CDCA3DE0BC` | 1821828 |

- A 与 C 的指纹不同，符合预期（A 带两个取证常量，C 不带）。
- **B 的 abc 指纹我没记**（当时直接装上去了，事后被 C 覆盖）。如实记为存疑；
  但 B 这次运行的自证在**它自己的 hilog 与 dump 里**：`NOTICES_REFRESH_FAILURE_FOR_EVIDENCE=true`、
  `result=partial domains=[... notices=fail(2) ...]`、以及帧上的部分失败文案。
- 三个取证开关在**提交态**的值（`git show HEAD` 可复核）：
  `SWITCH_DELAY_FOR_EVIDENCE=0`、`SEMESTER_SWITCH_TOAST_MILLIS_FOR_EVIDENCE=0`、
  `NOTICES_REFRESH_FAILURE_FOR_EVIDENCE=false`；`SEMESTER_OVERRIDE_FOR_EVIDENCE=''`、
  `TOAST_MILLIS_FOR_EVIDENCE=0`、`FORCE_NOTICE_UNREAD_FOR_EVIDENCE=false` 未被本轮改动。

## 10. 状态复原

- 学期页仍留在栈顶时点 `2026-2027 学年秋季学期` 行；
- `logs/t17-14-restored-final.json`：勾选 `✔` 在 `2026-2027 学年秋季学期` 行上；
- hilog 自证（`logs/t17-hilog-restore.txt`）：
  `18:00:06.062 semester row tapped: 2026-2027-1` →
  `18:00:32.289 semester switch finished: target=2026-2027-1 result=success domains=[courses=ok(2) notices=ok(2) files=ok(4)]`，
  与切换前的站点当前学期数据一致（courses=2 / notices=2 / assignments=0 / files=4）。
- 第二次切换（部分失败取证之后）同样复原：`18:10:42` 点秋季行，dump `t17-14` 勾选回到秋季。
- 运行期覆盖 `lohSemester` 全程**未设置**（`semester override: runtime="" effective="" source=none`），
  所以设备没有留下任何进程外状态；冷启动即回到站点当前学期。
- **最后一步把设备换回提交态构建**（取证期间装的是带注入的构建，不能留给别人）：
  `18:16` 重装提交态 HAP 并冷启动，`logs/t17-16-final-courses-state.json` 与
  `evidence/17-03-final-device-state.png`：课程页头 `2026-2027 学年秋季学期`、`全部 2`、
  两门秋季课程；hilog `effective semester=2026-2027-1 source=site-current`。
  这是「无选择 + 站点当前学期」的干净状态。

## 11. 没做到 / 存疑（如实列出）

1. **「课程/作业修前完全不刷新」我没复现**：在 5555 上它们 ~9 s 后自己跟上了（与统筹者一致）。
   我把它记为「8 秒内无任何反馈」，没有当成已证伪。
2. **设备侧「全失败」档没做**（只做了部分失败）：需要一个能同时打掉三个域的免网络注入点，仓库里只有一个（公告）。
   全失败档由单测覆盖。
3. **构建 B 的 abc 指纹未记录**（见 §9 表）。
4. 加载帧的 25 s 窗口是**注入**出来的（`SWITCH_DELAY_FOR_EVIDENCE`）；
   真实窗口是 5–9 s，`devecocli ui layout` 单次 10–35 s，不注入抓不稳。遮罩本身的触发与注入无关。
5. 未验证**分栏（tablet）**下的切换表现：本 ticket 的设备是 phone，双栏路径本轮没取。
6. `ui click` 的坐标取自 layout dump 的 px（未按截图目测），但 dump 的坐标是屏幕物理 px、
   而点击也按物理 px 传参 —— 两次点击都命中预期节点（dump 前后文本变化可证）。
---

## 12. 补充轮（统筹者验收打回的一条：设置入口的返回守卫）

统筹者独立验收发现：返回守卫只做在**课程入口**（`CoursesPage` 的 ROUTE_SEMESTER_SELECTION），
**设置入口**（`SettingsPage` 同一路由）既没传 `onSwitchInFlight` 也没挂 `onBackPressed`。
后果：从设置进学期页 → 点一行（切换 ~7 s）→ 期间按系统返回 ⇒ 页面先 pop、编排仍在后台跑完，
结果提示落在**已被销毁**的页面上，用户看不到。

### 12.1 修复

`features/settings/SettingsPage.ets`：

- 新增字段 `semesterSwitchInFlight`；
- `routeTo` 的 `ROUTE_SEMESTER_SELECTION` 分支传 `onSwitchInFlight` 并挂
  `.onBackPressed((): boolean => this.semesterSwitchInFlight)`。
- **分栏态也覆盖**：`routeTo` 被 `masterDestination`(:481) 与 `detailDestination`(:487) **共用**，
  所以单栏（主栈）与分栏（右栏 `detailStack`）构造的是同一个带守卫的 `NavDestination`。
  **但本 ticket 的设备是 phone（单栏），分栏那条路径我只给了结构性论据、没有设备观察**（如实登记）。

`grep -rn 'ROUTE_SEMESTER_SELECTION'` 的全部 push 点只有两处（`CoursesPage:270`、`SettingsPage:191`），
两个宿主现在都有守卫。

### 12.2 A/B 设备证据（同一台 5555，同一操作序列）

操作序列：设置 tab → 学期切换子页 → 点 `2025-2026 学年春季学期` 行 → **0.6 s 后**发一次
`hdc -t 127.0.0.1:5555 shell uitest uiInput keyEvent Back`。

| | 构建 | Back 之后那一帧 | 结果 |
| --- | --- | --- | --- |
| **修前** | 提交态 `de9d454` 的产物（`99A18C53…`，无设置入口守卫） | `logs/t17-19-before-back-during-switch.json` | 学期页**被 pop**，dump 里是设置页（`设置/退出登录/沉浸式模式/学期切换/文件/…`）；hilog 仍打出 `toast shown: … text=已切换到2025-2026 学年春季学期`（18:33:48.184）——提示落在已销毁的页面上 |
| **修后** | 取证构建 `F3B6D863…`（`SWITCH_DELAY_FOR_EVIDENCE=25000`） | `logs/t17-21-after-back-during-switch.json` | 学期页**仍在**（`学期切换` + 整列学期）**且**遮罩 `正在切换学期…` 在（bounds `[952,1153,1259,1204]`，居中） |
| **修后（切换结束）** | 同上 | `logs/t17-22-after-switch-toast.json` + `evidence/17-04-back-guard-toast-still-visible.png` | 学期页仍在、`✔` 已移到春季行、提示 `已切换到2025-2026 学年春季学期` **可见**（截图底部一栏，且底部高亮的是**设置** tab ⇒ 确实是设置入口） |

时间线（设备时钟，`logs/t17-hilog-after-back.txt`）：

```
18:36:07.664 semester switch started: target=2025-2026-2 accepted=true
18:36:07.664 switch delay override active: SWITCH_DELAY_FOR_EVIDENCE=25000 ms before any domain fetch
   ← Back 在 tap 之后 0.56 s 发出（宿主机 18:35:48.873；设备时钟约 +19.3 s）⇒ 落在 25 s 窗口内
18:36:41.097 semester switch finished: target=2025-2026-2 result=success domains=[courses=ok(7) notices=ok(17) files=ok(95)]
18:36:41.097 toast shown: millis=60000 hasAction=false text=已切换到2025-2026 学年春季学期
```

### 12.3 课程入口回归 + 顺带复原设备

同一套操作走**课程入口**（点 `2026-2027 学年秋季学期` 行 = 复原动作）：

- `logs/t17-24-courses-back-during-switch.json`：Back 之后学期页仍在 + 遮罩在（`正在切换学期…`）。
- `logs/t17-25-courses-after-switch.json` + `evidence/17-05-courses-back-restore.png`：
  提示 `已切换到2026-2027 学年秋季学期`、`✔` 回到秋季行；hilog
  `result=success domains=[courses=ok(2) notices=ok(2) files=ok(4)]` ⇒ **设备已复原到秋季**。

### 12.4 顺手补的取证开关单测

统筹者指出 `SWITCH_DELAY_FOR_EVIDENCE` 当时没有 OffAtCommit 断言。已在
`entry/src/test/SemesterSwitch.test.ets` 补 `evidenceSwitchDelayOverrideIsOffAtCommit`
（与 `evidenceToastDurationOverrideIsOffAtCommit` / `evidenceUnreadOverrideIsOffAtCommit` 同一口径）。

### 12.5 这一轮的门禁（提交态，全部在 `wt/t17`）

| 门禁 | 原始输出 |
| --- | --- |
| 单测 | `Tests run: 441, Failure: 0, Error: 0, Pass: 441, Ignore: 0`（mtime `2026-09-13T18:41:02`，本轮；上一轮 440 → 本轮 +1 就是补的那条） |
| 打包 | `assembleHap --no-incremental`：`BUILD SUCCESSFUL in 9 s 750 ms`；关键字扫描 `ERROR|ErrorCode|COMPILE RESULT` **0 命中** |
| 脚本 | purity PASS / import-graph PASS / i18n `RESULT: OK` / generated-fresh PASS |
| 提交态指纹 | `ets/modules.abc` SHA256 `69E480AE85F5A90EFC805CDF7CD8707CE570DE9EB3C6907F8E4895169396D087`（1822596 B） |

### 12.6 这一轮的构建溯源

| 构建 | 内容 | abc SHA256 | 大小 |
| --- | --- | --- | --- |
| 修前基线 | 上一轮提交态（`de9d454`），无设置入口守卫 | `99A18C5337136091412B76EA3BDCDA9A3ADC12A422BE3542EE59D0CDCA3DE0BC` | 1821828 |
| 取证构建（12.2/12.3 的帧） | `SWITCH_DELAY_FOR_EVIDENCE=25000`、`SEMESTER_SWITCH_TOAST_MILLIS_FOR_EVIDENCE=60000` | `F3B6D863F2F50A57506E160F6AE5878B2D94EE5795AAA08381B1AC6E9E898CA4` | 1822596 |
| 提交态（本轮门禁数字来源） | 全部开关复原 | `69E480AE85F5A90EFC805CDF7CD8707CE570DE9EB3C6907F8E4895169396D087` | 1822596 |

### 12.7 这一轮没做到 / 存疑

1. **分栏态（右栏 `detailStack`）的返回守卫没有设备观察**：本 ticket 的设备是 phone（单栏），
   模拟器无法旋转/改视口。只给了结构性论据（`routeTo` 被两个 destination 共用）。
2. 修前那一帧的对照是**同一台设备上换装上一轮提交态产物**做的（不是同一次构建内开关翻转），
   但两次的代码差异只有这一处守卫（`git diff` 可核）。

