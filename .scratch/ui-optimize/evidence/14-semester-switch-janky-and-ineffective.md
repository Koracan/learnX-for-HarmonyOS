# 学期切换「卡顿」与「无效」：诊断、修复与同口径前后对比

设备 `127.0.0.1:5555`（`const.product.devicetype` 实测回 `phone`，`const.ohos.apiversion` = 23，窗口 2210×2416 px）。
应用 `com.koracan.learnOH`，真实会话（设置页显示账号 `han-wang23`）。全程没有点「退出登录」、没有提交任何作业。

## 0. 结论先行

| 判据 | 结论 |
| --- | --- |
| 卡顿的可测定义 | 点一行学期到「选择被记录且页面返回」的时延。**基线 7017 ms**（tap 16:01:21.938 → course list applied 16:01:28.955）；**修复后 ≤1 ms**（tap / applied / dismissed 同在 16:12:47.086） |
| 无效的确切含义 | 在设置里选中的学期**不影响课程 tab**：设置侧 `source=selection` 拿到 7 门课，课程 tab 相同时刻仍以 `source=site-current` 取 2 门课，页头写「2026-2027 学年秋季学期」 |
| 同一个根因 | 学期选择既**不是共享状态**（每页各 new 一份 store 的私有字段），又被**绑在一整轮重取数上**（点击 await 到取数结束才写状态、才 pop） |
| 修复 | `courseListStore()` 进程内单例 + `selectSemester` 同步记录（新增 `pendingSemesterId`）+ 整轮取数移出点击关键路径 |

## 1. 溯源与产物指纹

| 项 | 值 |
| --- | --- |
| 修复提交 | `wt/t14` = `d677f05012ad09c79d66e653df8ff8bd4dfd0e1d`（父 `af163b4`） |
| 构建树（干净） | `learnOH-wt/t14-clean`，detached 在 `d677f05`，`git status --porcelain` 为空 |
| 构建命令 / 时刻 | `hvigorw assembleHap --no-incremental`，产物 mtime **16:10:44** |
| hap 大小 | 5,064,447 B（**仅作记录，不作指纹**） |
| 产物指纹（解包 `ets/modules.abc`） | 1,785,004 B，SHA256 `42DD5D30C25B84EEB0EB7682FB5D1BDD01E63873502BD1074CD21A7076D2CD47` |
| 装机时刻 | 设备 `bm dump` 的 `updateTime` = 1789287085672 = **16:11:25.672**（统筹者复核时换算更正：原写 16:11:16.672 少了 9 秒；「此后没有第二次安装」这个结论不受影响） |

产物**内容级**检查（在解包出来的 `ets/modules.abc` 里逐字节搜，`iso-8859-1` 解码后 `IndexOf`）：

| 串 | 命中 | 说明 |
| --- | ---: | --- |
| `semester selection applied` | 1 | 本次新增的同步生效点 |
| `semester selection dismissed` | 1 | 本次新增的「已 pop」点 |
| `course list store wired` | 1 | 本次新增的单例组装点 |
| `pendingSemesterId` | 1 | 本次新增字段 |
| `semester row tapped` | 2 | **正对照**：既有串，证明这次字节搜索找得到存在的串 |
| `evidenceTransitionDelegate` | 0 | **负对照**：另一条 ticket 的取证代码不在本产物里 |
| `SLOW_TRANSITION_FOR_EVIDENCE` | 0 | 同上 |

## 2. 「卡顿」的可测定义与基线数值

**定义**：从点击某一行学期（hilog `semester row tapped`）到**该选择被界面采纳**（勾选标记可移动 / 页面返回）之间的毫秒数。
取的是**应用自己写进 hilog 的 epoch 毫秒**（`LogFormat.formatRecord` 的时间戳），不写「感觉快了」。

**基线（装的是未修产物；见 6.1 的时间线核对）**

```
16:01:21.938 [features.courses.semesters] semester row tapped: 2025-2026-2
16:01:21.939 [features.courses.store]     semester selected: 2025-2026-2
16:01:28.955 [features.courses.store]     course list applied: semester=2025-2026-2 source=selection siteCurrent=2026-2027-1 courses=7
```

⇒ **7017 ms**。在这 7 秒里勾选标记不动、页面也不返回：`select()` 走的是
`SemesterSelectionPage.ets:72` 的 `await store.selectSemester(...)` → `CourseListStore.ets:107` 的 `await this.refresh()`，
而 `CourseFetchSource.fetchWithSession` 要串行取「学期集合 + 课程列表 + 三域内容」（`:107-128`）。

复现帧 / dump：`.scratch/ui-optimize/evidence/frames-t14/baseline/c02*`（切换页与勾选态）、`c03*`（课程 tab 仍为秋季）。

## 3. 「无效」的确切含义与基线证据

**确切含义**：不是「勾选没动」，也不是「退出重进又回去」，而是**勾动了、列表也换了，但换的是设置页自己那一份**——
课程 tab 不受影响。（同一个 `CourseListStore` 的两个实例各持一个 `selectedSemesterId`。）

判别性证据（同一次运行、同一个进程 25649）：

```
16:01:28.955 [features.courses.store] course list applied: semester=2025-2026-2 source=selection siteCurrent=2026-2027-1 courses=7   <- 设置页那一份
16:02:15.486 [data.courses.source]    effective semester=2026-2027-1 source=site-current                                              <- 课程 tab 另一份，仍按站点当前学期
16:02:16.004 [features.courses.store] course list applied: semester=2026-2027-1 source=site-current ... courses=2
```

同状态 layout dump（课程 tab）：`frames-t14/baseline/c03-courses-layout.json` —— 页头 `2026-2027 学年秋季学期`、`全部 2`、
课程是 `英语听说交流（A）` 与 `形式语言与自动机`。两份 store 在同一次运行里**互相矛盾**，这就是「无效」。

## 4. 根因落到代码

因果链（基线 `af163b4`）：

1. `features/settings/SettingsPage.ets:87` 持有 `private courseStore: CourseListStore | null`，`:186` 用 `new CourseListStore(createCourseRepository())` 造**自己的一份**，`:469` 把它交给学期页。
2. `features/courses/CoursesPage.ets:107` 同样 `new` 出**另一份**。`createCourseRepository()` 每次调用都新建整条取数链（`DataFetch`），两份 store 互不知情。
3. 学期选择存在 store 的**私有字段** `CourseListStore.ets:44 selectedSemesterId` —— 写的是哪一份，就只有哪一份按它取数。
4. 参考实现把这件事放在**全局 state**：`reference/learnOH-old/src/screens/SemesterSelection.tsx:38-40` 的 `handleSelect` 只 `dispatch(setCurrentSemester(id))`（纯状态写入，不取数）；
   由消费方 `src/screens/Courses.tsx:20-32` 监听 `state.semesters.current` 变化后再 `dispatch(getCoursesForSemester(...))`。
   本工程把它拆成了「每页一份 store + 页内 await 重取」，两条症状都由此而来。
5. 卡顿的因果：`SemesterSelectionPage.ets:72` 的 await 直到整轮取数结束（`:74` 才 pop），期间不改任何可观察状态；
   而学期页本身**只需要学期集合**（`semesterIds()` / `activeSemesterId()` 读 `store.semesters` / `store.semesterId`），三域内容与它无关。

## 5. 修复

| 文件 | 改动 |
| --- | --- |
| `features/courses/CourseListStoreProvider.ets`（新增，`:24-30`） | `courseListStore()` 进程内单例（与既有 `collectionFlagsStore()` 同模式） |
| `features/courses/CourseListStore.ets:52-57` | 新增 `@Trace pendingSemesterId`：在途选择与已生效值分开 |
| `features/courses/CourseListStore.ets:128-134` | `selectSemester` 变**同步**：记选择 + 打在途标记 + 打 `semester selection applied`，再返回后台 `refresh()` |
| `features/courses/CourseListStore.ets:110-114` | `refresh()` 的 `finally` 清在途标记（成功/失败都不留在途） |
| `features/courses/SemesterSelectionPage.ets:58-64` | 勾选行改读 `pendingSemesterId || semesterId`（选择一到就移动，不等取数） |
| `features/courses/SemesterSelectionPage.ets:81-93` | `select()` 变同步：不 await 取数，记下选择后立刻 pop |
| `CoursesPage.ets:108` / `AssignmentsPage.ets:115` / `SearchPage.ets:112` / `SettingsPage.ets:186` | 四处改成 `courseListStore()`，共用同一份 |

**没有动的**：`SEMESTER_OVERRIDE_FOR_EVIDENCE` 的语义与优先级（覆盖 > 选择 > 站点当前，`CourseFetchSource.ets:107-119` 原样）、
课程列表抓取口径（`CourseListFetcher` 的路径/字段映射原样）、`EntryAbility` 的 want 参数入口。

## 6. 修完不卡：同口径前后对比

### 6.1 先核对「基线测的确实是未修产物」

设备 `bm dump -n com.koracan.learnOH` 的 `updateTime` = 1789286286832 = **15:58:06.832**（我的基线装机），
此后到我 16:11:25 装干净产物之前**没有第二次安装**。我的基线构建产物 mtime 是 15:57:22，
基线那轮测量是 16:00:23 与 16:01:21 ⇒ **测的就是我自己的未修产物**。
（另一条 ticket 15:59:51 起改过源码并在同一棵树里构建过，但其 `updateTime` 未变 ⇒ 它的产物从未装到本设备。）

### 6.2 前后对比（同一套手势：设置 → 学期切换 → 点 `2025-2026 学年春季学期`；同一口径：hilog 毫秒）

| | 基线 | 修复后 |
| --- | --- | --- |
| tap 时刻 | 16:01:21.938 | 16:12:47.086 |
| 选择被记录 | 无此行（只能等取数） | `semester selection applied` **16:12:47.086** |
| 页面返回 | 取数结束后才 pop（≈16:01:28.955） | `semester selection dismissed` **16:12:47.086** |
| **点击 → 生效（可观察）** | **7017 ms** | **≤1 ms（同一条 hilog 毫秒内）** |
| 整轮取数 | 就在关键路径上 | 仍在跑，但**已移出关键路径**：`course list applied ... courses=7` @ 16:12:53.643（+6557 ms） |

修复后完整四行（`frames-t14/after/h11-aftertap-early.txt`）：

```
16:12:47.086 [features.courses.semesters] semester row tapped: 2025-2026-2
16:12:47.086 [features.courses.store]     semester selected: 2025-2026-2
16:12:47.086 [features.courses.store]     semester selection applied: 2025-2026-2
16:12:47.086 [features.courses.semesters] semester selection dismissed: 2025-2026-2
16:12:53.643 [features.courses.store]     course list applied: semester=2025-2026-2 source=selection ... courses=7
```

⇒ 取数时长**没有变**（6557 ms vs 7017 ms，同一量级），变的是它**不再挡在点击前面**。这不是「把活儿删了」。

另附一帧 `after/a01-after-tap/`：点击之后回到设置页（页面确实被 pop 掉）。
注：`devecocli ui click` 自身进程启动要 ~10 s，所以这一帧只能证明「页面已返回」，瞬时性由上表的 hilog 同行毫秒证明。

## 7. 修完有效：判别性证据

同一套操作（设置里点 `2025-2026 学年春季学期`）后进课程 tab：

| | 基线 | 修复后 |
| --- | --- | --- |
| 页头学期文案 | `2026-2027 学年秋季学期` | **`2025-2026 学年春季学期`** |
| 计数 | `全部 2` | **`全部 7`** |
| 课程标题 | 英语听说交流（A）／形式语言与自动机 | **西方音乐史／高技术战争／三年级男生台球／离散数学方法／偏微分方程／算法分析与设计基础／软件分析与验证** |
| 进课程 tab 是否又取一次数 | 是，`effective semester=2026-2027-1 source=site-current`（16:02:15.486） | **否**：`h13-courses-tab.txt` 里最后一条 `effective/applied` 仍是设置侧那次（16:12:47.199 / 16:12:53.643） |

最后一行是关键：「没有新取数却换了学期与课程集合」只可能来自**共享状态**，排除了「其实是课程 tab 自己重新按站点当前学期取了一次」这种解释。

证据：`after/a02-courses-tab/screenshot-1789287226814.png` + `after/a02-courses-layout.json`（页头、`全部 7`、七门课标题的 bounds 都在同一份 dump 里）。

## 8. 状态复原

取证结束后在**同一台设备**上点回 `2026-2027 学年秋季学期`（切换页第一行，bounds `[50,430,2110,489]`，中心 1105,459）：

```
16:15:13.493 [features.courses.semesters] semester row tapped: 2026-2027-1
16:15:13.494 [features.courses.store]     semester selection applied: 2026-2027-1
16:15:14.331 [features.courses.store]     course list applied: semester=2026-2027-1 source=selection ... courses=2
```

复原后核对：切换页勾选在 `2026-2027 学年秋季学期`（`after/a03-semester-page-restored.json`，check 图标 bounds `[2110,435,2160,485]`）；
课程 tab 页头回到 `2026-2027 学年秋季学期`、`全部 2`（`after/a04-final-courses.json` + `a04-final/`）。
应用进程存活（`pidof` = 31601），未清数据、未退出登录、未改设备级设置。

## 9. 门禁（全部在干净树 `t14-clean` = `d677f05` 里跑）

| 门禁 | 结果 |
| --- | --- |
| 单测 | `Tests run: 427, Failure: 0, Error: 0, Pass: 427, Ignore: 0`；`entry/.test/.../test_result.txt` mtime **2026-09-13 16:09:54**（本轮） |
| assembleHap | 日志 170 行 `BUILD SUCCESSFUL in 26 s 949 ms`；搜 `ERROR` / `ErrorCode` / `COMPILE RESULT` **零命中**；产物 mtime 16:10:44 |
| check-domain-purity | PASS（25 个领域源文件） |
| check-import-graph | PASS（206 个源文件；WARN 孤儿是 `EntryBackupAbility.ets` 与 `pages/Index.ets` 两个入口文件，属正常） |
| check-i18n-keys | `RESULT: OK`（manifest 309 / reference 178 / 182 个源码引用全部解析） |
| check-generated-fresh | PASS（6 个生成物、2 个生成器）；随后 `git status --porcelain` 为空 |

单测新增 3 条（`entry/src/test/CourseData.test.ets` 的 `data.courses.CourseListStore`）：选择被真的传给取数、生效学期与课程集合跟着换、
失败时保留旧值且不留在途标记、后续刷新继续跟随选择。用既有的 `CourseRepository` 缝注入假仓储，没新造接口。

## 10. 证据清单

| 文件 | 主论断 |
| --- | --- |
| `frames-t14/baseline/c02-semester-layout.json` | 基线切换页：`2026-2027 学年秋季学期` 带勾，九行学期 |
| `frames-t14/baseline/c03-courses-layout.json` | 基线「无效」：设置里选春季后，课程 tab 仍是 `2026-2027 学年秋季学期` / `全部 2` |
| `frames-t14/baseline/h01/h02-aftertap-*.txt` | 基线 7017 ms（tap→applied） |
| `frames-t14/after/a00-semester-layout.json` | 修复后切换页初始态（秋季带勾，与基线同状态可比） |
| `frames-t14/after/h11-aftertap-early.txt` | 修复后 tap/applied/dismissed 同在 16:12:47.086 |
| `frames-t14/after/h12-aftertap-late.txt` | 后台 `course list applied` @ 16:12:53.643（+6557 ms，已不在关键路径） |
| `frames-t14/after/a02-courses-layout.json` + `a02-courses-tab/*.png` | 修复后「有效」：春季 + `全部 7` + 七门课标题 |
| `frames-t14/after/h13-courses-tab.txt` | 进课程 tab **没有**新的 `effective semester=`/`applied` 行 |
| `frames-t14/after/a03-semester-page-restored.json` | 复原：勾选回到 `2026-2027 学年秋季学期` |
| `frames-t14/after/a04-final-courses.json` | 复原后课程 tab：秋季 + `全部 2` |

图片与 hilog/dump 原始拉取**只留本地**（`.scratch/.gitignore` 忽略 `**/evidence/**`）；本 md 用 `git add -f` 显式入库。

## 11. 未做到 / 存疑

1. **基线产物的 `ets/modules.abc` 指纹拿不到了**：基线 hap 被同一棵树里另一次构建覆盖（该树当时被另一条 ticket 占用），
   `entry/build/default/outputs/default/entry-default-signed.hap` 现 mtime 16:06:08。
   ⇒ 基线那一侧我用的是「装机 `updateTime` = 15:58:06.832 + 基线源码 `af163b4` + hilog」，没有可复算的基线产物指纹。修复后那一侧有完整指纹。
2. **「卡顿」只量化到「点击 → 选择被采纳」**，没有量化后台那一轮取数本身是否阻塞渲染线程（HTML/JSON 解析仍在 UI 线程）。
   我**没有抓到**「后台取数期间滚动课程列表掉帧」的证据，因此**不主张**它不存在。这条留给后续。
3. 设备时钟比宿主机快 ≈30.2 s（基线 30.4 s / 修复后 30.1 s）。所有对比只用**同一次运行内的差值**，不受该偏移影响。
4. `semesterIds()` 的 `ForEach` key 含 `activeSemesterId()`，选择改变会让整个列表重建；九个学期下没有可观察代价，未改。

## 12. 环境注记（新 worktree 必读）

`learnOH-wt/t14` 与 `t14-clean` 都是新 worktree，第一次跑门禁会踩两个坑（都不是代码问题）：

1. **缺 `oh_modules`** ⇒ `hvigorw test` 报 `Failed to resolve OhmUrl ... @ohos/hypium`，`test_result.txt` 根本不生成。
   修法：`ohpm install`（一次 ~30 s）。
2. **缺 `reference/`** ⇒ `check-i18n-keys.mjs` 必红（`reference dictionary keys: 0`）、`check-generated-fresh.mjs` 直接 exit 2。
   修法：在新树里建 `reference/learnOH-old` 链接指向 `D:\Koracan\source\harmony\learnOH-old`（该目录已 gitignore，不入库）。
