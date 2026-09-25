# 设备、构建与运行环境

本文件只回答两类问题：**① 我手上有哪些设备、怎么确认它就是它**；**② 在本地构建或上机之前必须先做什么**。
"跑哪些命令、怎么判通过"在 `docs/agents/gates.md`。

## 设备清单

| 实例 | 形态 | 视口 | 用途 / 备注 |
| --- | --- | --- | --- |
| `Pura 90` | phone | 电话 | 基准机；未启动则 `devecocli emulator start "Pura 90"` |
| `MatePad Pro 13` | tablet | **1440 × 960 vp** | 验分栏/大屏用它。 |
| `Mate X7` | foldable | 折叠 345.6 / 展开约 1008 vp | 复用 phone 镜像，实例已铺开；折叠态低于断点 ⇒ 单栏 |
| `MateBook Pro` | 2in1 | — | **起不来**：缺 `pc_all_x86` 镜像 |
| 真机 `3FYBB25407201890` | tablet | 1244 × 818 vp | HUAWEI MatePad Air，**API 24**，型号 `BKY-W20`。可能未连接 |

每种设备可以启动一个实例，可用不同设备实现并行。**多设备时必须显式传设备**：`devecocli install/run/ui/log --device <SERIAL>`、`hdc -t <SERIAL> …`。

### 隐私模式误判

模拟器默认 6 GiB 数据空间会踩中 ArkWeb 的隐私模式误判（配额 < 2×堆上限 ⇒ 判成隐私模式 ⇒ 二次验证页**不渲染**「信任该浏览器」）。如果发现这种情况，要用以下方法调大数据空间（以 MatePad Pro 13 为例）

- 真正被 qemu 读的是 `…\Emulator\deployed\MatePad Pro 13\hardware-qemu.ini` 里的 `disk.dataPartition.size`（默认 `6g`）；
  **`config.ini` 里的 `hw.dataPartitionSize` 只是记录，改它不生效**。
- 步骤：① 停实例；② 把 `disk.dataPartition.size` 改成 `16g`；③ **删掉 `userdata.img.qcow2`**（不删就继续按旧的 6g 续用）；④ 启动。
- 代价与判据：会重建 userdata ⇒ **应用要重装、凭据要重来**；启动后 `hdc -t <serial> shell df /data` 应显示约 15G。

## 判设备身份以 `hdc` 实测为准

**串口不能当身份**：只跑一台时它可能拿到 `5555`，而 `devecocli emulator list` 的串口列会张冠李戴。
每次取证前先确认（以 `hdc` 实测为准，`devecocli device list` 交叉核对）：

    hdc -t <serial> shell param get const.product.devicetype    # 期望回 phone / tablet
    hdc -t <serial> shell param get const.ohos.apiversion       # 23 = 模拟器，24 = 真机

## 改不了视口与电源态

`devecocli emulator` 的 rotate / fold / power / volume / battery / sensor / geolocation / shake
一律返回 `Emulator scene control commands require Emulator 7.0 or later. Current Emulator version is 6.1.1.300.`
真机也没有 `wm`、WMS 只有只读 dump ⇒ **真机旋转只能靠人物理转**。

想改视口只有三条路：换机型（tablet 1440vp）、升 Emulator 到 ≥7.0、或用 DevEco 模拟器窗口上的旋转按钮（GUI，CLI 碰不到）。

## 构建前置

**每次构建前先设 SDK 路径**，否则 hvigor 一旦重建守护进程就会失败、**一条测试都不跑**：

    $env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'

症状：日志里只有 `00303217 Configuration Error: Invalid value of 'DEVECO_SDK_HOME' …` 与 `BUILD FAILED`，**没有 `Tests run`**
（守护进程因 `isNodeEnvChanged` 被重建时必现；之前几次能跑，只是因为恰好还有一个带正确环境的老守护进程活着）。

hvigor 入口：`C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat`。

### 新 worktree 的一次性准备

`git worktree add` 出来的树**不是**开箱可构建的：

1. **必须 `ohpm install`**（在树根跑）：否则 `test` **真的**失败（`Failed to resolve OhmUrl @ohos/hypium`）—— 这是真红，不是假红。
2. 每棵树有自己的 `entry/build` 与 hvigor 守护进程（并行构建互不覆盖）。
3. **签名材料不用复制**：`build-profile.json5` 的 `signingConfigs` 指向**用户级** `~/.ohos/config/` 下的绝对路径，新树天然能读到。

## 装机：`devecocli run` 的三条坑

1. **必须作为后台作业运行**：应用启动后它仍保持运行，直到应用退出才返回——前台调用会一直挂住。
2. **可能在 `BUILD SUCCESSFUL` 之后长时间不进安装**（实测一次 6 分钟无输出）。
   处置：`devecocli run --skip-build` 部署已有 hap，或直接 `hdc install` + `aa start`。
3. **杀掉 run 之后必须显式清掉残留的 hvigor / deveco 子进程**，否则下一次构建会卡在 `Another build is already running`。

## 截图会骗人

设备锁屏时 `devecocli ui screenshot` 可能给**竖屏尺寸的黑帧**——别读成"设备转到竖屏了"。
先 `hdc -t <SERIAL> shell power-shell wakeup`，上滑解锁后重拍。

## 签名

**默认不管签名**：装机用 debug 配置（`build-profile.json5` 的 `products[0].signingConfig` 现为 `default`）；
**不要**把 `signingConfig` 改成 `release`，不要动 `keys/` 与 ACL——发布与上架由账号所有者处理。
**仅当用户明确要求协助签名问题时**，按 `docs/sign.md` 处理。
