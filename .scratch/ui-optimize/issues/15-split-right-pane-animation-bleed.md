# 15: 分栏态右栏的进入/退出动画侵入左栏

**What to build:** 横屏分栏态下，右栏（详情）在**进入**（列表点进详情）与**退出**（返回）的动画过程中，内容会画到左栏（主栏）上。
要求动画被**裁剪在右栏自己的范围内**：动画期间任何一帧，分栏线以左（x 小于主栏宽）的区域都不应出现右栏内容。

**Blocked by:** None（可立即开始）

**Status:** ready-for-agent

**判据**
- [ ] **先复现并留帧**：分栏态下触发进入与退出，在动画**中间**各截至少一帧，帧里能看到越过分栏线的内容；同时记录分栏线位置（主栏宽 px）。
- [ ] **定位**：给出转场/动画配置与容器层级的 file:line，说明为什么越界（容器未裁剪？动画位移把内容带出父容器？动画挂错层级？）。
- [ ] **修完可自证**：同样的进入/退出各取**动画中间帧至少 3 帧**，逐帧做**像素扫描**，统计分栏线以左出现右栏内容的命中数；
      必须给出修前（命中）与修后（不命中）的**同口径**对照 + 扫描脚本。别只给一张看起来正常的静态帧。
- [ ] **几何不变**：主栏 786px、分隔条 2px、右栏取余量**一字不改**（dump 对照）。
- [ ] **单测**：动画逻辑里若有可测的纯判断（如是否需要裁剪 / 是否分栏）就加断言；没有可测缝就**说明为什么没有**，不硬造。
- [ ] **门禁**：单测 + assembleHap + 四个脚本（见下）。

**派单情报（统筹者初查，供起点，不是结论）**
- 相关：`features/shell/SplitView.ets`、`features/shell/ShellTabs.ets`，以及各详情页的进/退栈路径。上一轮在这里验证过「全屏（主栏隐藏）时隐藏底栏」与「分栏态底栏收敛到主栏宽」。
- 参考帧（账号所有者原始报告图，只读，**只是症状参考、不是证据**）：`C:\Users\korac\.dsh\attachments\v1\objects\84\849fa8406ddff5bdb471ed0fc3ab0859d14cbdbd96193ef38468eec80ae9ef4c`
  —— 画面是平板分栏：左栏（课程列表）右侧能见到一块**灰色矩形**盖进左栏，即报告说的动画侵入左栏。
- 已知的相邻现象（**不是本 ticket**，别顺手改）：全屏态最左残留 2px 分隔条（`Divider().visibility` 未跟 `masterHidden`）；`#191919` 空色带未归因。

**你的资源（独占，别人不得碰）**
- worktree：`D:\Koracan\source\harmony\learnOH-wt\t15`（分支 `wt/t15`，基于 main `68e488e`）。只在你这棵树里改与构建。
- 设备：`127.0.0.1:5559`（tablet，1440×960vp）。模拟器**不能**旋转/缩放，分栏态只能在这里取。

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
- 「动画中间帧」是本 ticket 的核心难点：`uitest dumpLayout` 抓的是稳定态，动画帧只能靠**连拍截图**或**录屏抽帧**。
  自己选一条可靠路径并在 Comment 里写明**抓帧方法**与**它可能漏掉哪一帧**（抓不到就说抓不到，不要用稳定态帧替代动画帧）。
