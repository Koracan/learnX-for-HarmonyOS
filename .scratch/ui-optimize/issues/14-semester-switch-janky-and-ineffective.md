# 14: 设置页的学期切换卡顿且无效

**What to build:** 账号所有者第二轮反馈（2026-09-13，按重要性排第一）：在 设置 → 学期选择（与课程 tab 头部的学期切换是**同一个页面**）里切换学期时，
界面**卡顿**，而且**切了不生效**。要求先把这两条各自到底是什么、为什么诊断清楚，再修；修完用设备证据证明「不卡」且「真的切了」。

**Blocked by:** None（可立即开始）

**Status:** verified（统筹者独立复现：同毫秒生效 + 课程 tab 换 7 门课 + 产物指纹 `42DD5D30…` 对得上 + 主树门禁 427/427；见 2026-09-13 第三条 Comment）

**判据（每条都要设备证据或单测，不能只写看起来好了）**
- [ ] **现象被拆开**：分别给出「卡顿」的**可测定义与数值**（例：点一下到勾选标记移动/列表重绘之间的时延 ms，取自 hilog 时间戳；或滚动一屏的卡顿证据），
      以及「无效」的**确切含义**（勾选没动？勾动了但课程列表没换？换了但退出重进又回去？）。诊断结论里写清是哪一种，并附一次复现的帧/dump。
- [ ] **根因落到代码**：file:line + 因果链（哪个调用在 UI 线程上做了什么；选择在哪一步被丢掉/没被消费）。
- [ ] **修完不卡**：用**同一套手势与同一口径**重测，给出前后对比（时间戳来自 hilog，不写感觉快了）。
- [ ] **修完有效**：选另一个学期后，**学期文案与课程列表内容真的跟着换**；给**判别性**证据（切换前后各一次 layout dump + 帧，至少一条课程标题同时变化，并排除其实没换的解释）。
- [ ] **单测**：把「选择 → 生效」这条纯逻辑钉住（输入：选择的 semesterId + 抓取结果；输出：生效的 semesterId / 课程集合）。有现成的 store/override 测试缝就沿用，不硬造。
- [ ] **状态复原**：取证结束后把学期切回 **2026-2027 学年秋季学期**（原值）并记录复原动作。不要留下一个只改了设备状态的修复。
- [ ] **门禁**：单测 + assembleHap + 四个脚本（见下）。

**派单情报（统筹者初查，供起点，不是结论）**
- 页面 `entry/src/main/ets/features/courses/SemesterSelectionPage.ets`；状态链候选：`features/courses/CourseListStore.ets`、`data/courses/SemesterOverride.ets`、`data/courses/CourseListFetcher.ets`、`features/settings/SettingsRoutes.ets`（设置栈复用它）。
- `data/courses/SemesterOverride.ets` 的注释写着「界面选择 → 本进程（界面在 refresh 时把它作为选择传入）」——**无效很可能就在这条链上**（选择没被 refresh 消费，或消费了但没重取）。**自己复核，不要采信这句话。**
- 代码里有一族 `*_FOR_EVIDENCE` 开关（含 `SEMESTER_OVERRIDE_FOR_EVIDENCE`）：提交态**应当**全是 `false`，先确认，别把取证开关当产品行为。
- 参考帧（账号所有者原始报告图，只读，**只是症状参考、不是证据**）：`C:\Users\korac\.dsh\attachments\v1\objects\14\14b06e95bbf4a87124158308766202efb8ece313cc1dd7cebc0167cec3aad861`
  （画面：学期切换页，2026-2027 学年秋季学期带勾）。

**你的资源（独占，别人不得碰）**
- worktree：`D:\Koracan\source\harmony\learnOH-wt\t14`（分支 `wt/t14`，基于 main `68e488e`）。**只在你这棵树里改与构建，主树不要动。**
- 设备：`127.0.0.1:5555`（实测 `devicetype=phone`；`devecocli device list` 会把它报成 Mate X7/foldable，别信那列）。

**硬禁止（会毁掉不可恢复的东西）**：不真的提交作业；不在真机上点「退出登录」；不改设备级永久设置（语言/分辨率/密度/时区）；
不动 `.scratch/migration/**`；**不提交图片**（帧/dump/日志只留本地）；不把文档编号写进代码注释。

**构建 / 门禁环境（照做，别自创）**
1. `$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'`（不设会出现 `Configuration Error: Invalid value of 'DEVECO_SDK_HOME'` 且**一条测试都不跑**）。
2. hvigor 入口：`C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat`（不在 PATH 上）。构建以分钟计，用**后台作业**跑并把输出重定向到 `.dsh/logs/`。
3. 单测：先删 `entry/.test`，再 `test --no-incremental`；判据是 `entry/.test/default/intermediates/test/coverage_data/test_result.txt` 里的 `Tests run:` 行 + **该文件的时间戳是本轮的**（只看 BUILD SUCCESSFUL 或退出码会被假绿骗）。
4. 打包：`assembleHap --no-incremental`，然后在日志里**搜** `ERROR` / `ErrorCode` / `COMPILE RESULT`，不能只看 BUILD SUCCESSFUL。
5. 四个脚本：`node scripts/check-domain-purity.mjs`、`check-import-graph.mjs`、`check-i18n-keys.mjs`、`check-generated-fresh.mjs`（最后一个在新 worktree 首跑可能假红，判据是 `git diff` 对那 6 个生成物为空）。
6. 指纹：**不要用 hap 文件 SHA256 当「装的是哪一笔」的判据**（容器不可复现）。要比就解包比 `ets/modules.abc` 的 SHA256，或用内容级检索。
7. 设备身份以 `hdc -t SERIAL shell param get const.product.devicetype` 实测为准（`devecocli device list` 的机型列会张冠李戴）。本机模拟器**不能**旋转/缩放/折叠。

**报告要求**：结论先行；每条论断配**一个**证据（file:line、dump 的 px、帧、或 hilog 时间戳）；
做不到的如实写「没做到/存疑」，**没抓到不等于不存在**；在 `.scratch/ui-optimize/issues/你的ticket文件.md` 追加 Comment，
过程证据写进 `.scratch/ui-optimize/evidence/NN-slug.md`（可提交），图片留在 `.scratch/ui-optimize/evidence/` 且**不入库**。
收尾必须回报「**窗口关闭**」并说明设备与工作区状态（进程/画面/是否留了脏文件）。

## Comments

### 2026-09-13 · 统筹者派单
- 现象按账号所有者原话：「设置页的学期切换卡顿且无效」。**先把「无效」定义清楚再动手**；若诊断发现它其实是另一处机制（例如页面根本没消费选择、或列表缓存没失效），
  照实改判并在 Comment 里写明**前提如何被修正**。若修法要动到别人已验收证据所依赖的前提（学期覆盖开关、课程列表抓取口径），先停下来报告，不要悄悄改。

### 2026-09-13 · 实现与自证

**结论先行**：两条症状是**同一个根因的两面** —— 学期选择既不是共享状态（每个页面各自 `new` 一份 `CourseListStore`），又被绑在一整轮重取数上（点击 await 到取数结束才写状态、才 pop）。
修复 = 进程内单例 `courseListStore()` + `selectSemester` 同步记录 + 整轮取数移出点击关键路径。
「卡顿」7017 ms → **≤1 ms**；「无效」已变成「设置里选春季，课程 tab 直接是春季 7 门课，且没有新取数」。

**前提修正（派单情报被证伪的一条）**：派单说「无效很可能在 `SemesterOverride` 这条链上（选择没被 refresh 消费）」。
**这条不成立**：`CourseFetchSource` 确实消费了选择（实测 `effective semester=2025-2026-2 source=selection`），
`SemesterOverride` 的优先级（覆盖 > 选择 > 站点当前）原样可用。真正的断点是**选择的宿主**：写进了设置页自己那一份 store，课程 tab 那一份看不到。
参照系是参考实现：`SemesterSelection.tsx:38-40` 的选择是**纯全局状态写入**，重取由消费方 `Courses.tsx:20-32` 监听后发起。

逐条打勾：

- [x] **现象被拆开**：「卡顿」= 点击一行到选择被采纳的时延，基线 **7017 ms**（tap `16:01:21.938` → `course list applied` `16:01:28.955`，取自 hilog 毫秒）；
      「无效」的确切含义是**勾动了、设置页也换了，但课程 tab 不受影响**（不是「勾选没动」，也不是「退出重进又回去」）。
      证据：`evidence/frames-t14/baseline/h02-aftertap-28s.txt` 与 `c03-courses-layout.json`（课程 tab 仍是「2026-2027 学年秋季学期」/`全部 2`）。
- [x] **根因落到代码**：`features/settings/SettingsPage.ets:87,186,469` 造并交出自己的一份 store；`features/courses/CoursesPage.ets:107` 另造一份；
      选择存在私有字段 `features/courses/CourseListStore.ets:44 selectedSemesterId`；卡顿侧是 `SemesterSelectionPage.ets:72` 的 await 挂在 `CourseListStore.ets:107` 的整轮 refresh 上，`:74` 才 pop。
      证据：`git show af163b4:...` 的上述行号（提交 `d677f05` 里已改）。
- [x] **修完不卡**：同一套手势、同一口径（hilog 毫秒）—— tap / `semester selection applied` / `semester selection dismissed` **同在 `16:12:47.086`**；
      整轮取数仍在跑，但已在关键路径之外（`course list applied` @ `16:12:53.643`，+6557 ms，与基线的 7017 ms 同量级，说明活儿没被删掉）。
      证据：`evidence/frames-t14/after/h11-aftertap-early.txt`、`h12-aftertap-late.txt`。
- [x] **修完有效**：同一次点击后课程 tab 页头变 `2025-2026 学年春季学期`、计数 `全部 7`、七门课标题全换（西方音乐史／高技术战争／三年级男生台球／离散数学方法／偏微分方程／算法分析与设计基础／软件分析与验证）。
      **判别性**：进课程 tab **没有**新的 `effective semester=`/`course list applied` 行 ⇒ 换学期只能来自共享状态，排除「课程 tab 自己又按站点当前学期取了一次」。
      证据：`evidence/frames-t14/after/a02-courses-tab/screenshot-1789287226814.png` + `a02-courses-layout.json` + `h13-courses-tab.txt`。
- [x] **单测**：沿用既有 `CourseRepository` 缝注入假仓储，在 `entry/src/test/CourseData.test.ets` 新增 `data.courses.CourseListStore` 三条 ——
      输入「选择的 semesterId + 抓取结果」，输出「生效的 semesterId / 课程集合」，并钉住「同步记录」与「失败不清空旧值、不留在途标记」。
      证据：干净树 `Tests run: 427, Failure: 0, Error: 0`（`test_result.txt` mtime `2026-09-13 16:09:54`）。
- [x] **状态复原**：在同一台设备点回 `2026-2027 学年秋季学期`（`16:15:13.493` tap → `16:15:14.331` applied，courses=2），
      切换页勾选回到秋季（check bounds `[2110,435,2160,485]`），课程 tab 回到秋季 / `全部 2`。
      证据：`after/a03-semester-page-restored.json`、`after/a04-final-courses.json`。
- [x] **门禁**（**全部在干净树 `learnOH-wt/t14-clean` = `d677f05` 里重跑**，不是在被占用的 t14 里）：单测 427/427；
      `assembleHap --no-incremental` 搜 `ERROR`/`ErrorCode`/`COMPILE RESULT` 零命中；四脚本 domain-purity PASS / import-graph PASS / i18n `RESULT: OK` / generated-fresh PASS。
      产物指纹（解包 `ets/modules.abc`，1,785,004 B）= `42DD5D30C25B84EEB0EB7682FB5D1BDD01E63873502BD1074CD21A7076D2CD47`；负对照 `evidenceTransitionDelegate` 命中 0（不含别的 ticket 的代码）。

**没做到 / 存疑**：
1. 基线产物的 `ets/modules.abc` 指纹**拿不到**：基线 hap 被同一棵树里另一次构建覆盖（该树当时被另一条 ticket 占用，其 `updateTime` 显示它的产物从未装到本设备）。
   基线一侧的同一性判据只能是「装机 `updateTime` = `15:58:06.832`（我的基线产物 mtime 15:57:22）+ 基线源码 `af163b4` + hilog」。
2. 「不卡」只量化到「点击 → 选择被采纳」，**没有**量化后台取数期间渲染线程是否掉帧（HTML/JSON 解析仍在 UI 线程）。**没抓到**不等于不存在。

**过程与边界**：
- 证据文档：`evidence/14-semester-switch-janky-and-ineffective.md`（图片/hilog/dump 只留本地，md 用 `git add -f` 入库）。
- 未触碰 `.scratch/migration/**`；未清应用数据、未退出登录、未提交作业、未改设备级永久设置；未动 `SEMESTER_OVERRIDE_FOR_EVIDENCE` 语义与课程列表抓取口径。
- `*_FOR_EVIDENCE` 族在提交态仍全为 `false`/空串（`SEMESTER_OVERRIDE_FOR_EVIDENCE=''`），本次没有为取证临时打开任何开关。

### 2026-09-13 · 统筹者验收：**verified**（我自己复现了一遍，不只看自述）

**A. 产物同一性（本 ticket 最容易出错的一环，我用自己的构建对了一遍）**
- 我在 `learnOH-wt/t14`（`a8ed8bb`）里自己跑 `assembleHap --no-incremental`：解包 `ets/modules.abc` = **1,785,004 B**，SHA256 **`42DD5D30C25B84EEB0EB7682FB5D1BDD01E63873502BD1074CD21A7076D2CD47`** —— 与实现方报的**逐字符相同**。
- 我自己在 abc 里做内容级检索，正/负对照都复现：`semester selection applied` / `semester selection dismissed` / `course list store wired` / `pendingSemesterId` / `semester row tapped` 命中；另一条 ticket 的 `evidenceTransitionDelegate` 与 `SLOW_TRANSITION_FOR_EVIDENCE` **不存在（-1）** ⇒ 这份产物里没有别人的代码。

**B. 我自己在设备 5555 上复现（不是读它的日志）**
- 我抓 hilog、自己点 `2025-2026 学年春季学期`：`semester row tapped` / `semester selected` / `semester selection applied` / `semester selection dismissed` **同在 `16:22:38.512`**，而 `course list applied … courses=7` 在 **`16:22:45.439`（+6.93 s）** ⇒ 「点击不卡」与「活儿没被删掉」两条都成立，量级与它的基线（7017 ms）一致。
- 同一次操作后课程 tab 页头变 **`2025-2026 学年春季学期`**、计数 **`全部 7`**、七门课标题全换（西方音乐史 / 高技术战争 / 三年级男生台球 / 离散数学方法 / 偏微分方程 / 算法分析与设计基础 / 软件分析与验证）—— dump 是我自己的脚本解析的。
- 我随后把学期**复原**回 `2026-2027 学年秋季学期` 并复核：页头回到秋季、`全部 2`、两门原课程；应用存活 pid 31601。

**C. 门禁（我在 t14 树里重跑，不采信它跑完就删掉的那棵临时树）**
- 单测：`Tests run: 427, Failure: 0, Error: 0, Pass: 427, Ignore: 0`（`test_result.txt` mtime **2026-09-13 16:21:55**，是本轮的）。
- `assembleHap --no-incremental`：exit 0，`BUILD SUCCESSFUL` 1 次，搜 `ERROR:` / `ErrorCode` / `COMPILE RESULT` **各 0**。
- 四脚本：domain-purity `PASS` / import-graph `PASS` / i18n `RESULT: OK` / generated-fresh `PASS`（exit 全 0）。
- 卫生：`git grep FOR_EVIDENCE` 只剩既有开关且提交态全 `false`/空串（本次没有为取证打开任何开关）；改动文件里**没有** ticket/台账编号引用；未触碰 `.scratch/migration/**`；两个提交里**没有图片**。

**D. 我改了一处它写错的数字**：证据文档把装机时刻写成 `16:11:16.672`，`updateTime` 的 epoch 换算实际是 **`16:11:25.672`**（差 9 秒）。已在文档里就地更正并标注。

**E. 我认下的两条缺口（它如实报了，我也确认补不了）**：① 基线产物的 `modules.abc` 指纹拿不到（基线 hap 被同树里另一次构建覆盖），基线一侧只有 `updateTime` + `af163b4` 源码 + hilog；② 「不卡」只量化到「点击 → 选择被采纳」，**没有**渲染线程掉帧的测量。两条都不阻塞本 ticket 的判据。

**F. 派单情报被证伪的一条（记下来）**：我原先猜「无效」出在 `SemesterOverride` 链上；实测该链正常消费了选择（`source=selection`），真正的断点是**选择的宿主**是每页各自 `new` 的 store。参照实现把选择放在全局 state、重取由消费方发起，这条参照把定性做得很干净。
