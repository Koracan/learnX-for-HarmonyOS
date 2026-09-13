# ticket 11.5 取证（UI 保真两项：图标同源 + 页头/底色）

**口径**：模拟器 **Pura 90**（`127.0.0.1:5555`，HarmonyOS **6.1.0(23)**）—— 与工程声明的 `compatibleSdkVersion` 同版本；
真机（MatePad Air / API 24）不在本轮，截图一律按"模拟器"标注。
**源码版本**：`git rev-parse HEAD` = `ea57659ea611f8f455595210a4c846ef2593f824`，**工作区脏**（本轮未提交的改动即本 ticket 的内容），
故本目录的截图对应"HEAD + 本 ticket 的工作区"这一状态；提交后可在提交点上复核（源码侧判据不依赖截图）。

---

## 1. 结论（三句话）

1. **Part A（图标）**：全应用图标已换成**与参考实现同源**的字体图标 —— 内嵌
   `react-native-vector-icons@10.2.0` 打包的那两份 TTF（MCI + MaterialIcons），
   运行时 `font.registerFont` 注册，字形来自**同一批码位**（表见 `entry/src/main/ets/ui/icons/IconCatalog.ets`）。
   设备截图里**字形真的出来了**（不是 PUA 空格），emoji/字符替代品在 `.ets` 源码里**已清零**（§5）。
2. **Part B（页头）**：作业页头只剩「标题 + 刚刚更新」；课程页头 = 「标题 + 学期 + 刚刚更新」；
   通知 / 文件页头同原则但**保留**了 `未读 n` / 文件条数；**学期只在课程页头**出现。
3. **Part B-2（底色）**：浅色底色取色 **255,255,255**（改前 **255,251,255**），深色 **28,28,28**（R=G=B）；
   品牌强调色（tab 选中态 / 筛选片粉底）未动。

---

## 2. 逐屏对照（一屏一对文件）

**改前** = 本机上一版（ticket 11 交付的构建）的截图，`B0-*`；**改后** = 本轮构建，`A2-*`（浅色）/ `D1-*`、`D2-*`（深色）。
参考实现只有两张真截图（账号所有者提供）：课程列表 `06beaa…`、作业详情 `66afb1…`；其余屏的"与参考一致"用**源码里的图标名 + 颜色**对照（见 §4 清单表）。

| # | 屏 | 改前 | 改后 | 该屏的图标（源码 file:line） |
| --- | --- | --- | --- | --- |
| 1 | 公告列表 | `B0-01-notices.png`（🚩 + 蓝点 + 品红底） | `A2-01-notices.png`（MCI flag + checkbox-blank-circle） | `NoticesPage.ets:182-208` |
| 2 | 作业列表（春季 57 条） | `B0-02b-assignments-spring.png`（📎 ✓ 🎓 + 四行页头） | `A2-02-assignments-spring.png`（五枚矢量图标 + 一行页头） | `AssignmentsPage.ets:300-333` |
| 3 | 作业详情 | `B0-03b-assignment-detail-spring.png`（📄 ✓ 🎓 📝） | `A2-03-assignment-detail-spring.png`（MCI attachment / check / **MI grade** / 无图标的"作业内容"） | `AssignmentDetailPage.ets:210-214,326-331,524-548` |
| 4 | 文件列表 | `B0-04-files.png`（● 紫点 + 学期行） | `A2-04-files.png`（MCI checkbox-blank-circle + 一行页头） | `FilesPage.ets:153-186,207-215` |
| 5 | 课程列表 | `B0-05-courses.png`（🔔 📅 🗂 + 裸数字 2） | `A2-05-courses.png`（**MI** notifications / event / folder + 学期 + 刚刚更新） | `CoursesPage.ets:159-195,204-232` |
| 6 | 学期切换 | `B0-06b-semester-picker.png`（U+2713 字符） | `A2-06-semester-picker.png`（MCI check） | `SemesterSelectionPage.ets:135-143` |
| 7 | 设置（占位） | `B0-07-settings.png`（底部圆点 tab 栏） | `A2-07-settings.png`（底部矢量图标 tab 栏） | `ShellTabs.ets:52-84` |
| 8 | 公告详情 | `B0-08-notice-detail.png`（U+2039 返回） | `A2-08-notice-detail.png`（MI arrow-back；本账号公告无附件 ⇒ 附件行不出现） | `NoticeDetailPage.ets:212-226,262-273` |
| 9 | 空态（秋季无作业） | `B0-02-assignments.png`（自绘圆环） | `A2-09-assignments-empty.png`（MI check-circle 实心勾） | `EmptyState.ets:20-27` |

**参考实现的两张真截图对照**（只对得起这两屏）：
- 课程列表：参考图标 = `notifications` / `event` / `folder`（`CourseCard.tsx:37,41,47`）——与 `A2-05` 上的三个字形**同形同色（outline）**；
- 作业详情：参考的段图标 = MCI `attachment` / `check` / MaterialIcons `grade`（`AssignmentDetail.tsx:196,215,256`）——与 `A2-03` 逐段对应；
  参考页头右上角的"上传"按钮**本工程不渲染**（ticket 10 的硬红线：提交归 ticket 13），故 `A2-03` 上没有它。

**没有"改前"的屏**：通知详情 / 文件详情 / 课程详情 / 嵌入 WebView 的渲染页 —— 本轮**未在改动前逐屏留图**，
只能给改后（`A2-08`、`D2-01` 等）。按规矩记为**未抓到**，不用其他屏的图顶替。

**`A3-01-notices-commitstate.png` 的归属（ticket 11.5 复验第 ③ 条）**：这张图拍的是 **`f4af731` 提交态构建**
（`FORCE_DARK/EVIDENCE=false`、字体就绪）在设备上跑起来的**公告列表**，时间 2026-09-12 21:50，
与它同批的 hilog 自证行见 §6-A（`icon font ready: … ready=true` + `evidence switches: …=false=false`）。
它与 `A2-01-notices.png` 的画布内容**逐像素同构、只差状态栏时钟**（09:11 → 09:50）；
两者的分工是：**`A2-01` 是"改前 vs 改后"那一对里的"改后"**（支撑 §2 第 1 行与 Part A/B 的界面论断），
**`A3-01` 只用来支撑"提交态构建的界面与取证构建一致"**（即"提交态不是某个探针态"），
**不**再拿它去支撑 §2 的逐屏对照（避免一份证据担两个论断）。

---

## 3. 分论断的独立证据（不复用同一份）

| 论断 | 独立证据 |
| --- | --- |
| 字形真的渲染出来了（PUA 码位没落空） | `A2-01-notices.png`（MCI flag + 圆点）、`A2-02-assignments-spring.png`（MCI check / key-variant / medal + MI grade）、`A2-09-assignments-empty.png`（MI check-circle） |
| 底部 tab 栏是**参考那五个图标** | `A2-07-settings.png`（五个 tab 同屏：bell / calendar / folder / apps / gear） |
| 注册失败时**有 hilog + 可读回退**（不是豆腐块） | `F0-fallback-notices.png` + `rawfile 缺失` 的 error 行（§6 原始输出）。失败是**故意制造**的：把 `resources/rawfile/fonts/*.ttf` 临时移走再构建 |
| 浅色底色 = 纯白（R=G=B 且 ≥254） | §4 取色表（`A2-01…A2-09`），9 个采样点/屏全为 `255,255,255` |
| 改前底色是品红偏色 | §4 取色表里 `B0-01` / `B0-05` = `255,251,255`（**另一批文件**，与上面的"改后"不是同一份证据） |
| 深色底色 = 中性深灰（R=G=B 且 <60） | `D1-01/D1-02/D1-03/D1-04/D1-05` 与 `D2-01/D2-02`，取色 `28,28,28`（§4） |
| 深色是**应用内开关**切过去的（不是系统深浅色） | §6 的 `force dark for evidence: setColorMode(DARK)` 行 + 该轮构建的 `evidence switches: FORCE_DARK_FOR_EVIDENCE=true`；提交态复原后同一行显示 `false` |
| 提交态产物里**没有**探针、**有**本轮新符号 | §7 的 `ets/modules.abc` 检索 |
| 提交态构建（`FORCE_*=false`）的界面与取证构建一致 | `A3-01-notices-commitstate.png`（**只作这一条用**，见下面的归属说明） |
| 相对时间两档真的按 `fetchedAt` 分档 | §6b 的 `T1-01-notices-fresh.png`（刚刚更新）与 `T1-02-notices-injected-1min.png`（1 分钟前更新）——**两张、同一屏、只差 fetchedAt** |
| 页头"学期只在课程页" | `A2-02`（作业页头**无**学期/无徽标/无未完成计数）与 `A2-05`（课程页头**有**学期）—— 两张不同的图 |

---

## 4. 取色（空白底色像素）

采样方式：`System.Drawing.Bitmap.GetPixel`，每屏取 9 个点（左/中/右 × 上/中/下，避开文字与卡片）：
`(10,600) (20,600) (1300,600) (10,1500) (20,1500) (1300,1500) (10,2400) (20,2400) (1300,2400)`。

| 组 | 文件 | 全部采样点 | 判据 |
| --- | --- | --- | --- |
| 改前（浅） | `B0-01`、`B0-05` | `255,251,255` | R≠G ⇒ **品红偏色**（正是账号所有者量到的 254,250,254 那一族） |
| 改后（浅） | `A2-01`…`A2-09` | `255,255,255` | R=G=B 且 ≥254 ✔ |
| 改后（深） | `D1-01`…`D1-05`、`D2-01`、`D2-02` | `28,28,28` | R=G=B 且 <60 ✔ |

**切换深色的方式**：应用内**构建期开关** `FORCE_DARK_FOR_EVIDENCE`（`features/notices/repository/NoticeRepositoryProvider.ets:39`）
→ `ShellTabs.applyEvidenceOverrides()` → `getApplicationContext().setColorMode(COLOR_MODE_DARK)`（只作用于本应用，不动设备全局设置）。
探针补丁另存 `.dsh/logs/11.5-dark-switch.patch`（+ `.keep`）；提交态已复原为 `false`，并有**运行期自证**（§6 末行）。
深色下的**课程列表**没有抓到（该 tab 的栈顶当时是课程详情，`D2-01` 拍到的仍是详情页）——**如实记为未抓到**；
深色证据覆盖了公告 / 作业 / 作业详情 / 文件 / 课程详情（`D0-05`）/ 学期切换（`D2-02`）。

---

## 5. 源码侧判据（可 grep 复核）

- **emoji / 字符替代品清零**（`.ets` 源码，排除 HTML 实体表 `domain/parse/Text.ets` 的 `♠♣♥♦` 与 U+2039/U+203A 实体）：
  对 `{📎,🚩,📄,🎓,🔑,🏅,📝,🔔,📅,📁,●,✓,‹,›}` 在 `entry/src/main/ets` 下检索 **0 命中**；
- **令牌字面量**：`LIGHT_COLORS.background === '#FFFFFF'`、`DARK_COLORS.background === '#1C1C1C'`（`ui/theme/Tokens.ets`，单测钉住）；
- **闭集**：图标只有 `ui/icons/IconCatalog.ets` 的 `AppIcon`（15 个成员），渲染只有一个 `ui/icons/IconGlyph.ets`；
- **学期只在课程页**：`grep -n "ui_courses_semester_label" entry/src/main/ets/features` 只剩 `CoursesPage.ets` 与
  `SemesterSelectionPage.ets`（后者的用法是**选中项的 accessibilityText**，不是页头）。

---

## 6. 原始输出（hilog，逐字）

**A. 正常路径（提交态构建 `f4af731`，2026-09-12 21:50；`A3-01-notices-commitstate.png` 就是这一批的界面）**

    I A04c4f/ui.icons.font: … INFO  [ui.icons.font] icon font ready: attempted=true ready=true mci=learnOHMaterialCommunityIcons material=learnOHMaterialIcons mciSrc=fonts/MaterialCommunityIcons.ttf materialSrc=fonts/MaterialIcons.ttf receipt=[learnOHMaterialCommunityIcons=undefined learnOHMaterialIcons=undefined]
    I A04c4f/features.shell: … INFO  [features.shell] shell ready: tabs=notices,assignments,files,courses,settings locale=zh-Hans
    I A04c4f/features.notices.provider: … INFO  [features.notices.provider] evidence switches: FORCE_DARK_FOR_EVIDENCE=false FORCE_ENGLISH_FOR_EVIDENCE=false

> `receipt=…=undefined` 是**平台事实**：本模拟器上 `font.getFontByName` 对**应用自己注册**的字体返回 undefined
> （它只对系统字体有效）。**它不能当就绪判据** —— 第一版实现拿它判定，结果所有图标都退化成了文字
> （见 2026-09-12 21:07:36 的 `icon font getFontByName FAILED: Cannot read property path of undefined`，
> 界面截图就是 `A1-*` 那一批，即"可读回退"证据的另一种形态）。
> 现在的判据是**先确认 rawfile 在包里**（`resourceManager.getRawFdSync`）+ `registerFont` 不抛错。

**B. 失败路径（故意把两份 TTF 移出 rawfile 后构建，2026-09-12 21:18）**

    E A04c4f/ui.icons.font: … ERROR [ui.icons.font] rawfile unavailable: fonts/MaterialCommunityIcons.ttf（Invalid relative path）
    E A04c4f/ui.icons.font: … ERROR [ui.icons.font] rawfile unavailable: fonts/MaterialIcons.ttf（Invalid relative path）
    E A04c4f/ui.icons.font: … ERROR [ui.icons.font] 图标字体未注册：rawfile 缺失（mci=false material=false）；界面回退为可读文本。attempted=true ready=false …

界面（`F0-fallback-notices.png`）：卡片右上角是 **`重要公告 [new]`** 这样的**可读文本**，tab 栏是标签文本 ——
**既不是空白，也不是豆腐块，而且有 error 日志**。

**C. 深色开关（取证轮）**

    I A04c4f/features.notices.provider: … INFO  [features.notices.provider] evidence switches: FORCE_DARK_FOR_EVIDENCE=true FORCE_ENGLISH_FOR_EVIDENCE=false
    I A04c4f/features.shell: … INFO  [features.shell] force dark for evidence: setColorMode(DARK)


---

## 6b. 相对时间两帧（"注入 fetchedAt" 取证，ticket 11.5 复验第 ④ 条）

台账第 24 条替代验收标准第 3 条要求：`<1 分钟 → 刚刚更新` 与 `N 分钟前更新` **两帧设备证据**，且
"用**注入快照时间戳**（改 `fetchedAtMillis`，不靠手速）"。本轮的做法与逐字步骤如下。

### 机制（谁覆盖谁的 fetchedAt，以及怎么让它不覆盖）

页头的相对时间 = `updatedTimeText(store.fetchedAtMillis, Date.now())`。`fetchedAtMillis` 有**两个**来源：

| 来源 | 何时 | 会不会覆盖注入值 |
| --- | --- | --- |
| `NoticeSnapshot.apply()`（读 preferences 里落盘的快照） | `NoticesPage.loadOnce()` **第一步** | 注入值在这里生效 |
| `notice refresh done: … fetchedAt=<now>`（抓取成功后落盘并回填） | `loadOnce()` **第二步**（≈300–500ms 后） | **会**——这就是"启动即刷新、窗口 <1s"的那条路径 |

所以"注入"= ① 让注入值走快照那条路；② **掐掉第二次覆盖**。
本模拟器上**不能直接改 preferences 里的字节**：`shell` 域对该文件没有写权限
（实测 `/bin/sh: can't create /data/app/el2/100/base/com.koracan.learnOH/haps/entry/preferences/learnoh_notice_snapshot: Permission denied`，
即使该目录权限是 777；`su` 也不存在），所以改用**构建期开关** `NOTICES_REFRESH_FAILURE_FOR_EVIDENCE`
（`data/notices/RealNoticeRepository.ets`，提交态 `false`）在请求发出前中止刷新 —— 这样"注入值"就等于
**上一次成功刷新落盘的 `fetchedAtMillis = T0`**，而**启动时刻由我们选**（`hdc shell date +%s` 可读、差值可算），
把 `now − T0` 定在 ~90s 即可，**不是赌手速**。

### 逐字命令（可重跑）

    $d='127.0.0.1:5555'; $ev='.scratch/icons/evidence'
    # 0) 材料：两个 hap —— F = 提交态（开关 false）、S = 本开关为 true 的构建
    #    （构建期开关的提交态自证见 §6-C；两个 hap 的 SHA/时间戳见 §7）

    # 1) 用 F 启动一次：它成功刷新并落盘 T0（这一帧就是"刚刚更新"）
    hdc -t $d shell aa force-stop com.koracan.learnOH
    hdc -t $d install -r .dsh/logs/11.5r-hap-F2.hap
    hdc -t $d shell aa start -a EntryAbility -b com.koracan.learnOH
    hdc -t $d shell hilog -x -D 0x4C4F | Select-String 'notices refresh done'   # => fetchedAt=T0
    devecocli ui screenshot --device $d --path $ev/T1-01-notices-fresh.png

    # 2) 换成 S（刷新被中止），把启动时刻对准 T0 + 90s
    hdc -t $d shell aa force-stop com.koracan.learnOH
    hdc -t $d install -r .dsh/logs/11.5r-hap-S.hap
    $now = [int64](hdc -t $d shell date +%s).Trim()
    $T0  = 1789225651257                                   # ← 上一步 hilog 里的 fetchedAt
    $wait = [Math]::Max(0, [int](90 - ($now*1000 - $T0)/1000)); Start-Sleep -Seconds $wait
    hdc -t $d shell aa start -a EntryAbility -b com.koracan.learnOH
    devecocli ui screenshot --device $d --path $ev/T1-02-notices-injected-1min.png

    # 3) 复原：装回 F（提交态）并正常启动一次 —— 成功刷新会把快照改回"新鲜"的值
    hdc -t $d shell aa force-stop com.koracan.learnOH
    hdc -t $d install -r .dsh/logs/11.5r-hap-F2.hap
    hdc -t $d shell aa start -a EntryAbility -b com.koracan.learnOH

### 注入值 → 画面文本（2026-09-12 实测）

| 帧 | 文件 | 生效的 `fetchedAtMillis` | 启动/拍摄时刻的 `now − fetchedAt` | 页头文本 | 对应 hilog |
| --- | --- | --- | --- | --- | --- |
| 新鲜 | `T1-01-notices-fresh.png` | `1789225651257`（本次刷新写入） | ≈ 0（同一次刷新） | **刚刚更新** | `notices refresh switch: …=false` + `notices refresh done: … fetchedAt=1789225651257` |
| 注入 | `T1-02-notices-injected-1min.png` | `1789225651257`（**上一次**刷新的值，被开关保住） | **99,743 ms**（启动时 90,743 ms，拍摄时 99,743 ms） | **1 分钟前更新** | `snapshot applied: items=2 fetchedAt=1789225651257` + `notices refresh switch: …=true` + `notice refresh aborted before any request` + `refresh failed: notice refresh aborted by evidence switch` |

两帧**同一屏、同一批数据（items=2）、只差页头那一行**；分档函数（`updatedTimeParts`）的四条边界另有单测
（`entry/src/test/UpdatedTime.test.ets`：59s / 60s / 59min / 60min / 23h / 24h）。

### 提交态复原（已做，且有运行期自证）

- 设备重新装回**提交态** hap 并正常启动：`T1-03-notices-restored.png`；hilog 同一实例里有
  `notices refresh switch: NOTICES_REFRESH_FAILURE_FOR_EVIDENCE=false` 与
  `notices refresh done: items=2 elapsedMs=345 fetchedAt=1789225798234`；
- `aa start` **不带 `--ps`**：`semester override: want parameter "lohSemester" absent; … effective="" source=none`；
- preferences 里的快照被应用自己的成功刷新**改回新鲜值**：`fetchedAtMillis=1789225798234`
  （与上面那行 `refresh done` 完全一致，读取时刻 1789225823 ⇒ 25s 前）⇒ **注入值不残留**；
- 构建期开关的**产物级**说明：布尔常量的值不进 `modules.abc` 的字符串表（搜 `=true`/`=false` 无意义），
  所以提交态自证由**两层**承担：`git show HEAD:<file>` 里的 `boolean = false`（源码层）+ 上面那行
  **运行期** `notices refresh switch: …=false`（消费点层）。

---

## 7. 产物级核对（hap）

    entry/build/default/outputs/default/entry-default-signed.hap   4,113,217 B   @2026/09/12 21:49:36
    └─ ets/modules.abc                                            1,134,768 B
    └─ resources/rawfile/fonts/MaterialCommunityIcons.ttf         1,147,844 B（**stored**，未压缩）
    └─ resources/rawfile/fonts/MaterialIcons.ttf                    356,840 B（**stored**）
    └─ resources/rawfile/fonts/LICENSE-*.txt                         30,903 B

在 `ets/modules.abc` 里**命中**：`IconGlyph` / `IconCatalog` / `IconFont` / `registerIconFonts` /
`learnOHMaterialCommunityIcons` / `learnOHMaterialIcons` / `rawFilePresent` / `getRawFdSync` /
`MaterialCommunityIcons.ttf` / `ui_updated_just_now` / `ui_updated_minutes_ago` / `ui_updated_hours_ago` /
`ui_updated_days_ago` / `updatedTimeParts`；
**未命中**：`RealNoticesProbe` / `DiagLog` / `runNoticesProbe` / `W12Probe` / `SLOW_MOCK_FOR_EVIDENCE` / `FORCE_DARK_FOR_EVIDENCE=true`。
（`ui_courses_override_badge` 会命中：它是**仍然声明但已无人引用**的 i18n 字符串，和其余 300 条字符串一样被打进资源；
源码引用数为 0，见 §5。它不是开关、也不是探针。）

---

## 8. 可重跑命令

    # 1) 字体改动后的构建 + 装机（构建锁 + 设备锁）
    $env:DEVECO_SDK_HOME='C:Program FilesHuaweiDevEco Studiosdk'
    devecocli build
    hdc -t 127.0.0.1:5555 shell aa force-stop com.koracan.learnOH
    hdc -t 127.0.0.1:5555 install -r entry/build/default/outputs/default/entry-default-signed.hap
    hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b com.koracan.learnOH --ps lohSemester 2025-2026-2

    # 2) 逐屏截图（每屏一张；注意：devecocli ui screenshot **不覆盖**已存在的文件，换名或先删）
    devecocli ui screenshot --device 127.0.0.1:5555 --path .scratch/icons/evidence/<name>.png

    # 3) 取色（空白底色像素）
    Add-Type -AssemblyName System.Drawing
    $b = [System.Drawing.Bitmap]::FromFile((Resolve-Path '.scratch/icons/evidence/A2-05-courses.png'))
    $c = $b.GetPixel(20,1500); "$($c.R),$($c.G),$($c.B)"   # => 255,255,255

    # 4) 回退证据（故意制造失败）：移走 rawfile 里的两份 TTF → build → install → 截图 + hilog
    # 5) 运行期自证（提交态）：重启后 hilog 里应有
    #    evidence switches: FORCE_DARK_FOR_EVIDENCE=false FORCE_ENGLISH_FOR_EVIDENCE=false
    #    icon font ready: attempted=true ready=true …
    hdc -t 127.0.0.1:5555 shell hilog -x -D 0x4C4F | Select-String 'icon font|evidence switches'

    # 6) 产物检索
    Copy-Item entry/build/default/outputs/default/entry-default-signed.hap .dsh/logs/x.zip
    Expand-Archive .dsh/logs/x.zip .dsh/logs/x -Force
    #    在 .dsh/logs/x/ets/modules.abc 里检索 §7 的两组符号

---

## 9. 未抓到 / 未验证（如实记录）

1. **改前的逐屏截图**只有公告 / 作业 / 作业详情 / 文件 / 课程 / 学期切换 / 设置 / 公告详情这 8 屏（`B0-*`）；
   课程详情、文件详情、通知详情的"改前"没留图。`B0-03` 是**误拍**（当时作业列表为空、点了空行），
   故作业详情的改前用 `B0-03b`。
2. **深色课程列表**未抓到（栈顶是课程详情）。
3. **真机（MatePad Air / API 24）**：全部转 ticket 18（原 ticket 11.5 的最后一条 checklist 即如此）。
4. **"参考的图标都换成矢量"这一条只对本工程**用到的 15 个**成立**：
   参考实现里还有一批**我们尚未移植的功能**用的图标名（`search` / `filter-list` / `cached` / `delete` /
   `person-remove` / `loop` / `rule-folder` / `policy` / `help` / `copyright` / `fullscreen` 等），
   这些位置本工程**还没有对应的界面**（搜索页、收藏/归档、沉浸式设置、全局设置页归 ticket 14/15/17），
   所以清单表里它们是"参考有、我们未用"。
   **口径更正（2026-09-12 复验）**：本条原来接着写"其中 8 个名字在打包的 MCI 字形表里根本不存在 ⇒
   参考实现自己也拿不到字形"—— **那是错的，我把族搞混了**。那 8 个（`person-remove` / `loop` /
   `rule-folder` / `policy` / `center-focus-strong` / `drive-file-rename-outline` / `preview` / `info-outline`）
   在参考实现里**全部由 MaterialIcons 渲染**（`Settings.tsx:12`、`FileDetail.tsx:20`、`TableCell.tsx:11` 等
   都是 `import MaterialIcons from 'react-native-vector-icons/MaterialIcons'`），
   **字形都在**（person-remove=MI 0xEF66、loop=MI 0xE028、rule-folder=MI 0xF1C9、policy=MI 0xEA17、
   center-focus-strong=MI 0xE3B4、drive-file-rename-outline=MI 0xE9A2、preview=MI 0xF1C5、info-outline=MI 0xE88F；
   另补 `error`=MI 0xE000、`keyboard-arrow-right`=MI 0xE315）⇒ 内嵌的 `MaterialIcons.ttf` 将来可直接用，
   不必新增字体依赖。真正两族都没有的只有 8 个**不是图标名**的字符串（`Filter.tsx` 的 `name` prop 七个 + `<meta viewport>`）。
   **复核脚本（可重跑，自己解析 TTF cmap）**：`node .scratch/icons/evidence/check-glyphs.mjs`
   ⇒ 参考实际用到的 51 个名字 JSON 缺 0 / cmap 缺 0；cmap 码位数 MCI 6595、MI 2226（JSON 名数 6596 / 2234）。
5. `font.getFontByName` 的返回语义只在本模拟器上实测；真机上若返回值不同，`IconFont` 的**诊断行**会变，
   但**判定不受影响**（判定只看 rawfile + registerFont）。
