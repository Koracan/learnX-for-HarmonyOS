# t04 · 单栏态底栏帧（设备证据）

**结论（一句话）**：在设备 `127.0.0.1:5555`（Mate X7，**实测 `const.product.devicetype = phone`**、API 23、模拟器）上，
单栏态的底栏 **5 个命中区合计 x∈[0,2210]，等于整屏宽 2210px** ⇒ 工单 04 的"单栏态仍＝整屏宽"这一半 **成立**。
另一条必须同时读的话：**本轮装的 hap 不是统筹者给的那个指纹**（见下方"产物指纹不符"），所以"装的是哪一笔源码"这一环**我下不了结论**。

取证时间：2026-09-13 15:26–15:30（+08:00）。工作区：`git rev-parse HEAD` = `2a433f62d9030bf73ab8ecaff1bc743561f0ed43`，`git status --porcelain` = **CLEAN**（`E3B0C442…` 空串哈希）。

---

## 0. 有问题先说：产物 SHA256 与统筹者给的期望值不符

| 项 | 值 |
| --- | --- |
| hap 路径 | `entry/build/default/outputs/default/entry-default-signed.hap`（主树，未换路径） |
| 大小 | **5065647 B**（与期望**一致**） |
| mtime | 2026-09-13T15:23:17+08:00 |
| **实测 SHA256** | `48E1655E62F1ED32DC78E7C517A0D2700F8D377308C0DFA2082DD04DA8618262` |
| **统筹者给的期望** | 开头 `CDE9A6D4…` |
| **统筹者复查（见 §9）** | **已闭合**：容器哈希不可复现；21/21 entry payload 与冻结 main 逐一同值 ⇒ 装的就是 main 的代码 |
| 产物内指纹 | 解包后 `ets/modules.abc` SHA256 = `13524BE3EF1382FA9FD57D3D693D4D583FEB8559389BF9D8D70B99D2B84549B2`（1,783,796 B） |

- **对不上**。我**没有**改路径、**没有**构建、**没有**换产物，仍然如实报出来。
- 两处独立复算都得到 `48E1655E…`：`Get-FileHash` 与 .NET `SHA256.Create()` 直接读流，**一致** ⇒ 不是算错。
- 全仓（含 `.scratch/`）grep `CDE9A6D4` **零命中** ⇒ 这个期望值在仓库里没有留痕，我无法追溯它出自哪次构建。
- 该 hap 的 mtime（15:23:17）**早于** HEAD 提交时间（`2a433f6` = 15:24:12）⇒ 它编于**工作区脏**的时刻（很可能是 ticket 11 那轮的构建产物，ticket 11 只动注释）。
- **后果**：本帧能证明"设备上跑的那份产物行为正确"，但**不能**把"这份产物 = 冻结后的 main"当成已成立。
  若要闭合"装的是哪一笔"，需要一个指纹能对上的产物重装一次（**我没有重装候选，也没构建**）。

## 1. 装的是什么（设备侧确认）

- 命令：`hdc -t 127.0.0.1:5555 install -r <hap>` ⇒ `install bundle successfully`，`EXIT=0`（**未清数据/未清缓存**）。
- `bm dump -n com.koracan.learnOH`（装后）：`versionName=2.0.0`、`versionCode=2000000`、
  `fingerprint=C9B76CD0FD1BAB637DD67774E46D16CF8E130F7B2859DABC6CC2A29A9B3D5336`、
  `installTime=1789248795265`（≈2026-09-13 15:03:15，**首装时间，本轮未变**）、
  `updateTime=1789284380020`（≈**15:26:20**，与本轮安装时刻 `uptime` 15:26:21 对得上 ⇒ 装进去的确实是本轮的包）。
- 设备侧 `fingerprint` 与产物内指纹**没有**做等价比对（`/data/app/el1/bundle/public/…` 权限不足，见 §6 未做到项）。

## 2. 为什么认定这是"单栏"（不能只凭一张截图）

三条相互独立，指向同一结论；**关键是第 1 条：dump 里根本不存在分栏结构**。

1. **dump 几何**：整棵 93 个不同 bounds 的树里，`[786,`、`[788,`、`[393,`、`,788]`、`1752`、`,266]` 的命中数**全部为 0**（`tools/scan-geometry.ps1` 输出）。
   **更正（统筹者 2026-09-13 复核）**：`,786]` 这条子串实测**命中 2 处**，不是 0 —— 两处都是列表文本节点的 **y 最大值** `[50,727][2160,786]`（`bounds` 与 `origBounds` 各一次），与分隔条无关。
   ⇒ 该子串**本身不可靠**（y 坐标会撞上同一个串）；判「有没有右栏」应以 `[786,` / `[788,` 为准 —— 两者都是 0，**结论不变**。见 §9。
   对照分栏态基线：主栏 `Refresh [0,266,786,1752]`、分隔条在 x=786/787 ⇒ 这三个坐标是分栏态的**指纹**，这里一个都没有。
   所有容器都是整屏宽：`[0,0][2210,2416]`、`[0,122][2210,2154]`、`[0,122][2210,2329]`、`[0,2154][2210,2329]`。
2. **判据算术**：`hidumper -s DisplayManagerService -a '-a'` ⇒ `Width: 2210 / Height: 2416 / Rotation: 0 / Density: 3.125`。
   ⇒ 视口宽 = 2210 ÷ 3.125 = **707.2 vp**；`SPLIT_VIEW_BREAKPOINT_VP = 750`（`SplitView.ets:36`），且竖屏（非 landscape）
   ⇒ `resolveSplitViewActive()`（`SplitView.ets:96-104`）**两条都不满足** ⇒ 单栏。
3. **像素**：y=1300 行 x∈[780,795] 与 x∈[0,4] **全为纯白 255,255,255**（无分隔条、无左沿残条）；
   截图无"主栏 2210 → 右栏"过渡。

> 密度说明：`wm`/`wm density` 在该镜像不可用；`hidumper` 的 `Density: 3.125` 是设备自报值，
> `VirtualWidth 773`（展开态）/ 本帧用 2210÷3.125=707.2vp —— 两者都 < 750vp，不影响单栏判定。

## 3. 底栏命中区（`uitest dumpLayout -m true` 原始行）

**屏幕**：`SCREEN_BOUNDS=[0,0][2210,2416]` ⇒ 宽 **2210px**，高 2416px，密度 **3.125**。

**5 个命中区**（`type=Column`, `clickable=true`）：

```
[0,2157][442,2329]      442x172
[442,2157][884,2329]    442x172
[884,2157][1326,2329]   442x172
[1326,2157][1768,2329]  442x172
[1768,2157][2210,2329]  442x172
```

**合计 x 区间 = [0, 2210]**，合计宽度 = **2210px = 整屏宽**（5 × 442 = 2210，2210 ÷ 3.125 = 707.2vp = 整屏 vp）。
底栏容器（`type=Row`, 父链 `… > NavBarContent > Column > Row`）：`[0,2154][2210,2329]` = 2210×175，也是整屏宽。

**对照期望**：期望"底栏合计宽度 ≈ 整屏宽（参考 2210）" ⇒ **实测正好 2210，成立**；
期望"明显小于整屏就是真问题" ⇒ **不成立/未出现**。

**像素同向佐证**（`f01-single-column-bottombar-pixelscan.txt`）：
底栏顶边框 `y=2154/2155/2156` 每行 `minX=0, maxX=2209`（横跨整屏；分栏态基线此处是 `nonWhite maxX=787`）。

## 4. 底栏 5 个图标的字形码位与 y 区间

| # | tab | 图标节点 bounds | 图标 y 区间 | 图标码位 | 标签码位 |
| --- | --- | --- | --- | --- | --- |
| 1 | 公告 | `[184,2178][259,2253]` 75×75 | **2178–2253** | `U+E7F4` | `U+516C U+544A` |
| 2 | 作业 | `[626,2178][701,2253]` 75×75 | **2178–2253** | `U+E878` | `U+4F5C U+4E1A` |
| 3 | 文件 | `[1068,2178][1143,2253]` 75×75 | **2178–2253** | `U+E2C7` | `U+6587 U+4EF6` |
| 4 | 课程 | `[1510,2178][1585,2253]` 75×75 | **2178–2253** | `U+E5C3` | `U+8BFE U+7A0B` |
| 5 | 设置 | `[1952,2178][2027,2253]` 75×75 | **2178–2253** | `U+E8B8` | `U+8BBE U+7F6E` |

标签文字 y 区间 `[2265,2309]`（5 个一致）。图标中心 x 依次 221 / 663 / 1105 / 1547 / 1989（= 442 的等分中心）。

**关于"字形码位"的口径**：dump 的 `text` 字段给的是图标字体的**私用区码点**（`U+E7F4` 等），**不是** Material 字形名
（Active/Inactive 两态在 dump 里可能同值）⇒ 这里报的是**渲染出的字符码位**，不做"哪个是激活字形"的推断。
本帧"文件 tab 处于激活态"由**截图**佐证（文件图标为紫色 `rgb=200,135,211`，落在 x=1105），**不由码位佐证**。

## 5. 产物清单（均在 `.scratch/ui-optimize/evidence/frames-t02-t04/`，**只留本地**）

| 文件 | 字节 | SHA256 | 承载的论断 |
| --- | --- | --- | --- |
| `d01-single-column-files-tab-layout.json` | 83784 | `009AB086023AD3FC95CB62D00666CDE04F506513DEF60FFF2029142EE9049FEF` | 单栏几何（公告 tab 时；底栏整宽、无分栏指纹） |
| `d02-single-column-files-tab-layout.json` | 85065 | `B7558FB34BE79166D456F7995847CA2A7F75D2FC7B02E7C7B2663C0C513F7B83` | **文件 tab** 时的单栏几何 + 底栏 5 命中区（§3 原始行出处） |
| `41-single-column-files-tab-active.png` | 256336 | `8C6F72EE3FC20CA0F448912429F84E8EDF45CD1B24DDDECA11617958575A2DAD` | 文件 tab 单栏一帧（图标/标签/紫色激活态 + 底栏整宽） |
| `f01-single-column-bottombar-pixelscan.txt` | 2453 | `D55C1BA52EF978B01EB4EB689B1F22E7ED4983C193A2F428D51C0A9BB97BE111` | 底栏顶边框横跨 x∈[0,2209]（像素级同向佐证） |
| `42-single-column-files-tab-window-close.png` | 256756 | `A1BC7E0A3E36EA0DFF577D6EC6605633B671C84D1AA5019501C455EC985D1108` | 收尾时的可用状态（文件 tab 仍在） |
| `probes/40-proc-after-install-notices-tab.png` | 323487 | `08C53DCACCC7E49DB85E5EFD9A1A506EE4AA3235E86EF627C63C1E93B2FC0FD2` | **过程帧**：装后首帧（当时停在**公告** tab），仅作过程留痕 |

- 40 与 41 **不是同一论断的证据**：40 是"装后应用已自动恢复且为单栏"，41 才是"**文件 tab** 单栏底栏整宽"。
- **`40` 原名里的 "files-tab" 名不符实**（画面是公告 tab）：按证据纪律**已改名挪进 `probes/`**（`40-proc-after-install-notices-tab.png`），不留在交付证据层；收尾帧用 42 承担"文件 tab"。

## 6. 如实报："没做到 / 存疑"

1. **产物指纹不符（最重要）**：实测 `48E1655E…` ≠ 期望 `CDE9A6D4…`，见 §0。**已闭合（见 §9）** —— 两者 payload 完全相同，差异只在容器元数据。
2. **没取到设备侧产物指纹**：`/data/app/el1/bundle/public/com.koracan.learnOH/entry.hap` 未在取证范围内可比对（权限/镜像限制）；
   只有 `bm dump` 的版本+安装时间。⇒ "装的就是这个 SHA256 的包"依赖 `install` 的 `EXIT=0` 与 `updateTime` 吻合，**不是**字节级。
3. **没做分栏↔单栏的直接对照**：平板恒横屏、模拟器不能旋转，本机（phone 形态）取不到分栏态；
   分栏态那一半沿用既有帧（`11-split-filedetail.png` 等），**本轮未重取**。两侧证据不同设备，只能各自成立。
4. **读图 41 的过程瑕疵（已消除）**：第一次对 41 取哈希得到 `08C53DCA…`（03:28:51 的中间态写入），
   随后文件才定型为 `8C6F72EE…`。**已在稳定后重跑像素扫描，结果与原扫描逐行一致**（顶边框 `0/2209`、`DENSE_COLS=685-688`、`PX x=1105 rgb=200,135,211`）
   ⇒ 数值结论未受影响；此处记录以免后人对着两个哈希困惑。后续复核以 `8C6F72EE…` 为准。
5. **未改动任何设备级/应用内设置**：没有点退出登录、没有提交/上传、没有动沉浸式开关或学期选择；**没有清应用数据/缓存**。
6. **截图上应用内时钟显示 03:29 而设备时间是 15:29**：应用内时钟与壁钟差 12h（疑 12/24 小时制或时区显示），
   **与本 ticket 无关、未归因**，仅记录以免被当成"帧是旧的"。

## 7. 复现命令（逐条）

```powershell
hdc -t 127.0.0.1:5555 shell param get const.product.devicetype          # -> phone
Get-FileHash -Algorithm SHA256 'entry\build\default\outputs\default\entry-default-signed.hap'
hdc -t 127.0.0.1:5555 install -r 'entry\build\default\outputs\default\entry-default-signed.hap'
hdc -t 127.0.0.1:5555 shell aa force-stop com.koracan.learnOH
hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b com.koracan.learnOH
hdc -t 127.0.0.1:5555 shell bm dump -n com.koracan.learnOH              # versionName/installTime/updateTime
hdc -t 127.0.0.1:5555 shell hidumper -s DisplayManagerService -a '-a'   # Width/Height/Rotation/Density
devecocli ui click --device 127.0.0.1:5555 1105 2200                    # 文件 tab（坐标取自 dump）
hdc -t 127.0.0.1:5555 shell uitest dumpLayout -m true
hdc -t 127.0.0.1:5555 file recv /data/local/tmp/layout_<id>.json <local>
devecocli ui screenshot --device 127.0.0.1:5555 --path <local>.png
& .\tools\analyze-dump.ps1 -Path <local>.json                          # 底栏命中区 + 码位
& .\tools\scan-geometry.ps1 -Path <local>.json                         # 分栏指纹命中数
```

分析脚本留在同目录 `tools/`（`analyze-dump.ps1` / `scan-geometry.ps1` / `scan2.ps1` / `probe-bottombar.ps1` / `hash-check.ps1` / `final-checks.ps1`），供独立复算。

## 8. 收尾状态

- 应用进程 `com.koracan.learnOH` pid `11457`，`aa dump -a` = **FOREGROUND**；画面停在**文件 tab**、单栏可用态（`42-…window-close.png`）。
- 设备锁：本轮只碰 `127.0.0.1:5555`；5557 / 5559 **未触碰**。未跑 hvigor、未跑 `devecocli build`。
- **窗口关闭**。
## 9. 统筹者复查（2026-09-13 15:33）：产物指纹问题**已闭合**；并更正 §2 的一处统计口径

**结论：装进 5555 的那份 hap，代码内容与冻结后的 main 完全相同；`48E1655E…` 与 `CDE9A6D4…` 的差别不是代码差异，而是 hap 容器不可复现。⇒ 本帧对 ticket 04 成立。**

### 9.1 payload 级对账（我自己跑的，不是转述）

同一棵主树、同一份代码连编多次（构建台账 `.hvigor/report/`）：

| 项 | 15:22:02 | 15:23:17（**装机用的这份**） | 15:33:24（复查重编） |
| --- | --- | --- | --- |
| hap SHA256 | `CDE9A6D4…` | `48E1655E…` | `5931290B…` |
| hap 大小 (B) | 5,065,647 | 5,065,647 | 5,065,652 |
| `ets/modules.abc` SHA256 | `13524BE3…` | `13524BE3…` | `13524BE3…` |
| 21 个 entry 的 payload SHA256 + CRC | — | 与右列**逐一同值** | 21/21 与左列相同 |

- 把 15:23:17 与 15:33:24 两份解包逐 entry 比对：**21/21 payload 相同**
  （含 `resources.index`、`module.json`、`pack.info`、`sourceMaps.map`、全部 resources/rawfile 与 `ets/modules.abc`）。
- 差异**只有两处**：① 每个 entry 的 local header 偏移 10–11 的 **DOS 修改时间字段**（15:23:16 vs 15:33:24，逐 entry 命中）；
  ② 最后一个 entry 与中央目录之间的 **`<hap sign block>`**（`MII…` DER，35729 → 35734 B，中央目录随之整体位移 +5）。
- 全文件逐字节：8329 B 不同、72 段，**没有一段落在 entry payload 里**。
- ⇒ **hap 文件哈希不是「哪一笔源码」的指纹**；`ets/modules.abc` 才是（四次构建同值，且与 docs-only 提交前一致）。

### 9.2 我复核过的其余部分

- 我自己重跑 dump 解析（脚本独立于取证方的 `tools/*.ps1`）：`clickable=true` 共 18 个节点，其中底栏带 5 个 `Column`，
  各 **442×172**，`x_min=0`、`x_max=2210`、`sum_w=2210`；底栏容器 `Row [0,2154][2210,2329]` 亦 2210 宽；
  5 个图标中心 x = **221 / 663 / 1105 / 1547 / 1989**（= 442 的等分中心），标签 y 区间五个一致。
- 我读了 `41-single-column-files-tab-active.png`：底栏横跨整屏、5 项等距、文件 tab 紫色激活态 ⇒ 与 dump 同向。
- `48E1655E…` 我独立复算（`Get-FileHash` + 解包后逐 entry 哈希），与取证方一致。
- 更正 §2：`,786]` 命中 **2** 处（y=786，不是 x=786），见 §2 行内更正；对结论无影响。

### 9.3 结论对 ticket 04 的意义

- 单栏态：「底栏合计 = 整屏宽 2210px」成立，且**装的就是冻结后的 main 的代码**。
- 分栏态与全屏态：沿用平板帧（见 issue Comments 第二条），本轮未重取，仍按「过程证据」口径记账。
- 未同机对照（模拟器不能旋转/缩放）这一条**仍然成立**，两侧证据来自不同设备；这是环境限制，不是未取证。
