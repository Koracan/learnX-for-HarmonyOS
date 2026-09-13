# 14: 设置页的学期切换卡顿且无效

**What to build:** 账号所有者第二轮反馈（2026-09-13，按重要性排第一）：在 设置 → 学期选择（与课程 tab 头部的学期切换是**同一个页面**）里切换学期时，
界面**卡顿**，而且**切了不生效**。要求先把这两条各自到底是什么、为什么诊断清楚，再修；修完用设备证据证明「不卡」且「真的切了」。

**Blocked by:** None（可立即开始）

**Status:** ready-for-agent

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
