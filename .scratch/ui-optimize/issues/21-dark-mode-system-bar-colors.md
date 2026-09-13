# 21: 深色模式下系统栏（状态栏 / 导航条）配色不跟随应用底色

**What to build:** 账号所有者反馈（2026-09-13，原话）：

> 目前深色模式下应用不能联动系统状态栏和导航条背景色，检修这个问题

（附截图：界面底色是深灰 `#1C1C1C`，而屏幕顶部状态栏与底部导航条各是一条**纯黑** `#000000` 的带子。）

**Status:** implemented（本轮的取证与门禁结果见文末 Comments）

**Blocked by:** None

## 现象与机制（先复现，再改）

本机 1320×2856 phone 模拟器，深色态整屏列扫描（过程帧 `.scratch/ui-optimize/logs/t21/`）：

| 位置 | 修前 | 修后 |
| --- | --- | --- |
| 状态栏 y∈[0,135] | `#000000` | `#1C1C1C` |
| 应用内容 y≥136 | `#1C1C1C` | `#1C1C1C` |
| 导航条区 y∈[2758,2855] | `#000000` | `#1C1C1C` |

**为什么只有深色看得出来**：浅色模式平台默认给的是白 `#FFFFFF`，恰好等于应用底色；深色模式平台默认给的是纯黑，与应用底色 `#1C1C1C` 不同。

**为什么两个栏是两件事**（WMS 实测，`.scratch/ui-optimize/logs/t21/wms-dump.txt`）：

- 应用窗口本身就是整屏：`learnOH0 [0,0,1320,2856]`；ArkUI 内容按安全区收边（上 136px、下 98px）。
- 顶部是 SystemUI 的 `SCBStatusBar [0,0,1320,136]`，底部是 `SCBGestureNavBar [0,2758,1320,98]`。
- 手势导航下底部那条窗口是**透明**的（在桌面帧上能看到壁纸透出来）⇒ 露出来的是**应用窗口自己的底色**。
  平台文档写明 `navigationBarColor` 配的是**三键导航栏**，所以只设它动不了这一条 —— 底部要靠
  `setWindowBackgroundColor` 才填得上。

## 改了什么

1. 新增 `entry/src/main/ets/core/window/SystemBarTheme.ets`：把"应用底色"交给平台，两个调用
   `setWindowSystemBarProperties({statusBarColor, statusBarContentColor, navigationBarColor,
   navigationBarContentColor})` + `setWindowBackgroundColor`；**消费点自证**（请求值 / 两个调用是否成功 /
   累计次数）打进 hilog；记住最近一次**请求**的配色供重放。
2. `ui/theme/Tokens.ets`：新增 `systemBarColors(isDark)` —— 栏底色 = 应用 `background`、
   栏内容色 = `onBackground`（**不新增色值**，仍然只有 `resolveTheme` 一处取色）。
3. `entryability/EntryAbility.ets`：窗口就绪（`loadContent` 回调里，见下）与
   `onConfigurationUpdate`（深浅色变化）两条时机各刷一次。**用 `newConfig.colorMode`**：
   实测回调里 `this.context.config.colorMode` 还是旧值（深色已生效时读回 1=浅色，栏会被刷成白色）。
4. `core/window/ImmersiveWindow.ets`：关闭沉浸式（栏重新出现）时重放一次配色，否则栏带着平台默认色回来。
5. `entry/src/test/Tokens.test.ets`：+1 条单测钉住"栏底色 = 应用底色、栏内容色 = 底色之上的前景色"。

**踩到并记下的两个坑**

- `setWindowBackgroundColor` 在 `loadContent` 完成前会报 `This window state is abnormal`（实测），
  所以首次应用挪到 `loadContent` 的回调里；否则冷启动那条路只会设上状态栏、底部仍是黑的。
- "最近一次配色"按**请求**记而不是按"成功"记：否则一次半成功（上面那个错误）会让后来的"重放"无事可做。

## 判据

- [x] 深色态：状态栏与导航条区的像素 = 应用底色 `#1C1C1C`（整列扫描无过渡）。
- [x] 深色态：栏内图标/文字仍可读（`onBackground #E6E6E6`，帧上时间、电量、手势条清楚）。
- [x] 浅色态不回归：提交态（`FORCE_DARK_FOR_EVIDENCE=false`）帧里应用是浅色、两个栏 = `#FFFFFF`。
- [x] 沉浸式开关不回归：`apply immersive` 之后紧跟着一次成功的重放（hilog 同秒两条）。
- [x] 单测 455 条全绿（基线 454，+1 是本次新增）；四脚本 PASS/OK；`assembleHap` 零 ERROR。

## Comments
### 2026-09-13 · 实现 + 自验（同一会话、同一棵树）汇报

**结论先行**：深色模式下状态栏与导航条区已跟随应用底色（`#1C1C1C`），浅色模式无回归。
两个栏**要两个不同的平台调用**才都盖上：`setWindowSystemBarProperties`（栏属性；状态栏那条靠它）
+ `setWindowBackgroundColor`（栏下露出的是**应用窗口底色**，底部那条靠它）。

**关键数字（设备 127.0.0.1:5555 = phone，1320×2856px，x=200 整列扫描）**

| 位置 | 修前 | 修后 |
| --- | --- | --- |
| 状态栏 y∈[0,135] | `#000000` | `#1C1C1C` |
| 应用内容 y≥136 | `#1C1C1C` | `#1C1C1C` |
| 导航条区 y∈[2758,2855] | `#000000` | `#1C1C1C` |
| 提交态（浅色）两栏 | — | `#FFFFFF` = 应用底色（帧 `after-light-shell.png`） |

**三个坑（写进代码注释，不写台账编号）**
1. `this.context.config.colorMode` 在 `onConfigurationUpdate` 里是**旧值**（深色已生效时读回 1=浅色）
   ⇒ 第一次实现把系统栏刷成了**白色**（帧 `logs/t21/intermediate-white-statusbar.png`），改用 `newConfig.colorMode`。
2. `setWindowBackgroundColor` 在 `loadContent` 完成前报 `This window state is abnormal`（hilog 实测）
   ⇒ 首次应用挪进 `loadContent` 回调；否则冷启动那条路只设得上状态栏。
3. "最近一次配色"按**请求**记而不是按"成功"记：否则半成功一次会让后来的沉浸式重放无事可做。

**门禁**（提交态）：单测 `Tests run: 455, Failure: 0, Error: 0, Pass: 455`（mtime 20:26:10；基线 454，+1 为本次新增）；
`assembleHap --no-incremental` 零 ERROR；四脚本 PASS / PASS / `RESULT: OK` / PASS。
产物指纹：修前 `A50EB3C0…`(1,845,372 B) → 修后 `E45B77AC…`(1,850,732 B，取证态) / `5F8CD583…`(同尺寸，提交态)。

**证据**：`.scratch/ui-optimize/evidence/t21/README.md`（逐文件论断表 + hilog 摘录 + WMS 窗口表 + 未做到项）；
过程帧与 hilog 在 `.scratch/ui-optimize/logs/t21/`（只留本地）。

**未做到（如实）**：系统级深色（设备设置里切）没有单独取证（深色帧走应用级 `setColorMode`，进的是同一个回调）；
真机 / 平板 / 三键导航未取证（本机只有手势导航）；冷启动闪屏 `start_window_background` 深色仍是 `#000000`，本轮未动。
