# ticket 21 证据：深色模式下系统栏（状态栏 / 导航条）配色跟随应用底色

**一个文件一条主论断**。图片只留本地（`.scratch/.gitignore` 忽略 `**/evidence`）；本文件是文字证据。

## 环境与产物指纹（同一棵树内可比，见 `docs/agents/gates.md`）

| 项 | 值 |
| --- | --- |
| 设备 | `127.0.0.1:5555`，`hdc` 实测 `const.product.devicetype=phone`、`const.ohos.apiversion=23` |
| 屏幕 | 1320 × 2856 px（状态栏高 136px、底部导航条区高 98px、应用内容区 y∈[136,2758]） |
| 树 | `D:/Koracan/source/harmony/learnOH`，基线 `b7a27dc`（仅 `AGENTS.md` 有他人未提交改动） |
| 修前产物 | `ets/modules.abc` 1,845,372 B `A50EB3C057441D23161BC1906695C7DC19B9941C05D56ADF6C3FAD1E63D6848C` |
| 修后产物（深色取证态，`FORCE_DARK_FOR_EVIDENCE=true`） | 1,850,732 B `E45B77AC50B03D2140669741BDD0BE737039B497796611690C15E6EA4E24F86A` |
| **提交态产物**（`FORCE_DARK_FOR_EVIDENCE=false`） | 1,850,732 B `5F8CD5834297586D48224CE40F6A07F1E649A0555F484C450AF7C120D411CABA` |

两份产物同尺寸、只有那一个布尔不同（内容级检索：两份 `modules.abc` 里都有本次新增串
`apply system bar colors` / `system bar theme` / `windowBackgroundOk`）。

## 逐文件论断表

| 文件 | 主论断 | 原始数字（x=200 整列扫描） |
| --- | --- | --- |
| `before-dark-shell.png` | **修前**深色态：状态栏与底部导航条区是**平台默认纯黑**，与应用底色不同 | 状态栏 `y=0..135 #000000`；内容 `y=136.. #1C1C1C`；`y=2758.. #000000` |
| `after-dark-shell.png` | **修后**深色态：两处都等于应用底色（整列**没有任何过渡**） | `y=0 -> #1C1C1C`，其后整列直到 2855 只有控件自身的颜色，导航条区不再出现 `#000000` |
| `after-light-shell.png` | **提交态**：应用是浅色（说明取证开关已关），两个栏 = `#FFFFFF` = 应用底色，浅色模式无回归 | `y=0 -> #FFFFFF`；`y=2565.. #FFFFFF`（导航条区同色） |

三张帧都是公告 tab 的空态主页（同一台设备、同一账号状态），只有深/浅与修前/修后不同。

## hilog 消费点自证（`FORCE_DARK_FOR_EVIDENCE` 为**取证态**那一次，20:25:12–13）

    20:25:13.001 core.window.systembar: apply system bar colors: bar=#FFFFFF content=#1C1C1C barPropertiesOk=true windowBackgroundOk=true ... fullyAppliedCount=1
    20:25:13.111 core.window.systembar: apply system bar colors: bar=#FFFFFF content=#1C1C1C barPropertiesOk=true windowBackgroundOk=true ... fullyAppliedCount=2
    20:25:13.111 core.window.immersive:   apply immersive: requested=false layoutFullScreenOk=true systemBarEnableOk=true ...
    20:25:13.413 features.notices.provider: evidence switches: FORCE_DARK_FOR_EVIDENCE=true FORCE_ENGLISH_FOR_EVIDENCE=false
    20:25:13.414 entry.ability:            configuration updated: colorMode=0 ...
    20:25:13.419 core.window.systembar: apply system bar colors: bar=#1C1C1C content=#E6E6E6 barPropertiesOk=true windowBackgroundOk=true ... fullyAppliedCount=3

读法：① 窗口就绪后先按当时的浅色刷一次；② 沉浸式恢复（栏重新出现）**紧跟一次重放**（`fullyAppliedCount=2`，
证明"关沉浸式要重放"这条真的执行了）；③ 深色配置一到，两个调用**都成功**地刷成 `#1C1C1C`。

**提交态那一次**（20:27:24–27）：

    20:27:25.192 core.window.systembar: apply system bar colors: bar=#FFFFFF ... windowBackgroundOk=true ... fullyAppliedCount=1
    20:27:25.915 core.window.systembar: apply system bar colors: bar=#FFFFFF ... windowBackgroundOk=true ... fullyAppliedCount=2
    20:27:27.269 features.notices.provider: evidence switches: FORCE_DARK_FOR_EVIDENCE=false FORCE_ENGLISH_FOR_EVIDENCE=false

## 机制证据（WMS 窗口表，`logs/t21/wms-dump.txt`）

    SCBStatusBar18      [ 0    0    1320 136  ]
    SCBGestureNavBar16  [ 0    2758 1320 98   ]
    learnOH0            [ 0    0    1320 2856 ]

应用窗口本身是**整屏**的，两个系统栏是 SystemUI 的独立窗口叠在上面；手势导航下底部那个窗口是**透明**的
（桌面帧 `logs/t21/home.png` 里底部露出的是壁纸），所以露出来的是**应用窗口底色** —— 这就是"只设
`navigationBarColor` 修不掉底部那条"的原因（平台文档：该属性配的是**三键导航栏**）。

## 门禁（提交态，同一棵树）

| 项 | 结果 |
| --- | --- |
| 单测（先删 `entry/.test` + `--no-incremental`） | `Tests run: 455, Failure: 0, Error: 0, Pass: 455`；`test_result.txt` mtime 2026/9/13 20:26:10（基线 454，+1 = 本次新增） |
| 打包 `assembleHap --no-incremental` | `BUILD SUCCESSFUL`；`ERROR` 0、`ErrorCode` 0、`COMPILE RESULT` 0 |
| 四脚本 | domain-purity `PASS` / import-graph `PASS`（两条 WARN 是已知入口文件）/ i18n-keys `RESULT: OK` / generated-fresh `PASS` |

## 未做到 / 边界（如实登记）

1. **系统级深色没有单独取证**：深色帧走的是应用级 `setColorMode(DARK)`（`FORCE_DARK_FOR_EVIDENCE`），
   系统本身停在浅色。两者进的是**同一条路径**（`onConfigurationUpdate` → `applySystemBarTheme(newConfig.colorMode)`），
   但没有一张"设备设置里切深色"的帧。
2. **真机 / 平板 / 三键导航未取证**：本机模拟器只有手势导航；账号所有者截图那台是平板。
   三键导航栏那条由 `navigationBarColor` 覆盖（平台文档口径），本轮无设备可验。
3. **启动闪屏底色未改**：`dark/element/color.json` 的 `start_window_background` 仍是 `#000000`，
   与应用底色 `#1C1C1C` 不同（冷启动一瞬间的黑色闪屏）。属同一族的相邻项，不在本次反馈范围内，未动。
4. 过程帧 `logs/t21/after-locked-blackframe.png` 是**锁屏黑帧**（取证时设备自己灭了屏），
   只作过程记录，不支撑任何论断。
