# 设备、构建与运行环境

> 本文件由 `AGENTS.md` 指向：**要构建、装机、跑设备命令，或需要知道有哪些模拟器/真机时读这里。**

## 设备清单

| 实例 | 形态 | 视口 | 用途 / 备注 |
| --- | --- | --- | --- |
| `Pura 90` | phone | 电话 | 基准机；未启动则 `devecocli emulator start "Pura 90"` |
| `MatePad Pro 13` | tablet | **1440 × 960 vp** | 验分栏/大屏用它。**跑登录前必须先放大数据分区**（`docs/reference-quirks.md` 第 28 条） |
| `Mate X7` | foldable | 折叠 345.6 / 展开约 1008 vp | 复用 phone 镜像，实例已铺开；折叠态低于断点 ⇒ 单栏 |
| `MateBook Pro` | 2in1 | — | **起不来**：缺 `pc_all_x86` 镜像 |
| 真机 `3FYBB25407201890` | tablet | 1244 × 818 vp | HUAWEI MatePad Air，**API 24**，型号 `BKY-W20`。2026-09-13 已完成一次性复验（ticket 18） |

**多设备时必须显式传设备**：`devecocli install/run/ui/log --device `SERIAL``、`hdc -t SERIAL …`。

### 判设备身份以 `hdc` 实测为准

**串口会被复用**：只跑一台时它可能拿到 `5555` ⇒ 「`5555` 就是 Pura 90」**不成立**。
而 `devecocli emulator list` 的串口列**会张冠李戴**（实测把 `MatePad Pro 13` 报成 `5555`、`Pura 90` 报成 `5557`）。

每次取证前先确认身份（`devecocli device list` 的列与它一致，但以 hdc 实测为准）：

    hdc -t 127.0.0.1:5555 shell param get const.product.devicetype    # 期望回 phone / tablet
    hdc -t <serial> shell param get const.ohos.apiversion   # 23 = 模拟器，24 = 真机

### 模拟器的 scene 组命令全部不可用

`devecocli emulator` 的 rotate / fold / power / volume / battery / sensor / geolocation / shake
一律返回 `Emulator scene control commands require Emulator 7.0 or later. Current Emulator version is 6.1.1.300.`
⇒ **模拟器上无法旋转、折叠、缩放窗口、灭亮屏**。
真机也没有 `wm`、WMS 只有只读 dump ⇒ **真机旋转只能靠人物理转**。
想改视口只有三条路：换机型（tablet 1440vp）、升 Emulator 到 ≥7.0、或用 DevEco 模拟器窗口上的旋转按钮（GUI，CLI 碰不到）。

**一个会骗人的现象**：设备锁屏时 `devecocli ui screenshot` 可能给**竖屏尺寸的黑帧**，
别读成「设备转到竖屏了」——先 `hdc -t SERIAL shell power-shell wakeup`，上滑解锁后重拍。

## 构建

**每次构建前先设 SDK 路径**，否则 hvigor 一旦重建守护进程就会失败、**一条测试都不跑**：

    $env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'

症状：日志里只有 `00303217 Configuration Error: Invalid value of 'DEVECO_SDK_HOME' in the system environment path`
与 `BUILD FAILED`，**没有 `Tests run`**。实测：不设它、且守护进程因 `isNodeEnvChanged` 被重建时必现
（之前几次能跑，只是因为恰好还有一个带正确环境的老守护进程活着）。

hvigor 入口：``C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat`。

**构建耗时以分钟计**（实测 45s–1m30）：不要用会阻塞的短超时前台调用——把输出重定向到 ``.dsh/logs/``，或作为**后台作业**运行。
用管道（`| Select-Object`）转发 devecocli 的 stdout 会丢失 hvigor 的失败信息、并让命令迟迟不返回。

具体要跑哪些命令、以及"构建/测试假绿"的几种陷阱，见 `docs/agents/gates.md`。

### 新 worktree 的一次性准备（2026-09-13 两条线各踩一次）

`git worktree add` 出来的树**不是**开箱可构建的，两样都要补，否则会得到看起来很吓人的"红"，但那不是代码问题：

1. **必须 `ohpm install`**（在树根跑）：否则 `test` **真的**失败（`Failed to resolve OhmUrl @ohos/hypium`）—— 这是真红，不是假红。
2. 每棵树有自己的 `entry/build` 与 hvigor 守护进程（并行构建互不覆盖）；删树前先按 `concurrency.md` 停掉该树的守护进程。

## `devecocli run` 的三条坑

1. **必须作为后台作业运行**：应用启动后它仍保持运行，直到应用退出才返回——前台调用会一直挂住。
2. **可能在 `BUILD SUCCESSFUL` 之后长时间不进安装**（实测一次 6 分钟无输出）。
   处置：`devecocli run --skip-build` 部署已有 hap，或直接 `hdc install` + `aa start`。
3. **杀掉 run 之后必须显式清掉残留的 hvigor / deveco 子进程**，否则下一次构建会卡在 `Another build is already running`。

## 签名

签名材料、两条签名配置的用途、**怎么解 p7b 看真实字段**、以及**上架前必须满足的 ACL 一致性**，全部在 `docs/sign.md`（那里有可复现的解码命令与实测表格）。

**结论：本文件（以及任何文档）里关于签名的论断，动手前先自己解一遍 p7b 复核**，命令见 `docs/sign.md`。

**怎么自己判**（一条命令，不碰设备、不碰网络）：

    node scripts/check-release-profile.mjs                       # 检查 build-profile.json5 里 release 配置所指的 Profile
    node scripts/check-release-profile.mjs --profile <某.p7b>     # 检查刚下载、还没写进 build-profile 的那一份

它硬校验 `type=release` / `app_gallery` / `bundle-name` / 内嵌证书与 `material.certpath` 一致，
并把 `module.json5` 的请求权限与 `acls.allowed-acls` 逐条对照：受限权限缺一条就 `RESULT: FAIL`。
