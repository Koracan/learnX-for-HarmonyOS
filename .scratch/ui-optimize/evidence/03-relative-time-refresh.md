# 页头相对时间不再冻结：设备取证清单

设备：**MatePad Pro 13（tablet）**，串口 `127.0.0.1:5559`（`hdc -t 127.0.0.1:5559 shell param get const.product.devicetype` 回 `tablet`，
`const.ohos.apiversion` 回 `23`，`const.product.model` 回 `emulator`）。窗口 2880×1920 px，密度 2（1vp = 2px）；
双栏判据 `active=true`（`split view decision: active=true measured=1440x893 fallback=1440x960 breakpoint=750 masterWidth=393`），主栏 786px。

> 这台机是**真实登录会话**，冷启动走纯 HTTP 静默重登（hilog `restore: session rebuilt via pure HTTP (no webview)`、
> `login: success status=200 csrfChars=36`）。全程**没有点「退出登录」**、没有点任何提交 / 上传入口、
> 没有改设备级设置（语言 / 分辨率 / 密度 / **时钟**）、**没有清应用缓存**。
> 动过的设备状态只有：装了一次本工作区构建的 hap（`hdc install -r`，升级安装，应用数据保留）、一次冷启动、
> 底部 tab（公告 → 作业 → 公告）、一次 HOME 键把应用压到后台、`aa start` 把它拉回前台。

## 契约：一个可命名的动作 + **只有一处实现**

| 项 | 位置 | 说明 |
| --- | --- | --- |
| AppStorage 键 | `features/shell/PageShown.ets:40` `PAGE_SHOWN_AT_KEY = 'lohPageShownAtMillis'` | 值是**最近一次"页面被显示"的时刻**（毫秒） |
| 动作（唯一实现） | `features/shell/PageShown.ets:56` `markPageShown(source)` | 全仓**唯一**写这个键的地方：`AppStorage.setOrCreate(PAGE_SHOWN_AT_KEY, …)` 在 main 树里只出现 1 次 |
| 页头文本（唯一实现） | `features/shell/PageShown.ets:82` `pageHeaderUpdatedText(fetchedAtMillis, pageShownAtMillis)` | 四个列表页各自只把这两个数传进来 |
| 订阅方 | `@StorageProp(PAGE_SHOWN_AT_KEY) pageShownAtMillis` 各一处（公告 / 作业 / 课程 / 文件） | 读发生在**产出那一行文本的表达式里**（`updatedText()`），不是 `@Watch` 回调、也不是 build 里的分支 |

两个触发源都汇进同一个动作：

| 触发源 | 调用点 | 设备上的日志串 |
| --- | --- | --- |
| 切 tab（底栏点击） | `ShellTabs.switchTo` → `markPageShown('tab-switch:' + index)` | `page shown: source=tab-switch:0 at=…` |
| 切 tab（Tabs 自己的回调，含程序化 `changeIndex`） | `ShellTabs` 的 `.onChange` → `markPageShown('tab-change:' + index)` | `page shown: source=tab-change:0 at=…` |
| 回到前台 | `EntryAbility.onForeground` → `markPageShown('ability-foreground')` | `page shown: source=ability-foreground at=…` |
| 壳层首次显示 | `ShellTabs.aboutToAppear` → `markPageShown('shell-appear')` | `page shown: source=shell-appear at=…` |

`onPageShow` 在四个列表页上**不存在**（它们是 shell 里的子组件），信号只能从上往下发；
壳层自己重绘也**不等于**子页面重绘（`TabContent` 的子组件实例持久、`build()` 不因切 tab 重跑）——
所以是"订阅 + 重算"，不是"在 onChange 里改个 state"。

## 溯源

| 项 | 值 |
| --- | --- |
| `git rev-parse HEAD`（本工作区分支基点） | `94f39bdfd9cb02ccac81620f464bb61b159e1e7f` |
| 产物 `entry-default-signed.hap` | 5078277 字节，SHA256 = `D1F33B5E5E8F96052F6D8524678F8AECF4D7060FC85CD9B6256569AC285C3592` |
| 产物（解包后）`ets/modules.abc` | 1791648 字节，SHA256 = `2E2788FEA39079B6607CCD8D96256C0B37021E5A7BB66097D4347FBAB2B4632A` |

产物内容级检查（`docs/agents/gates.md` 的"陈旧产物"判据；在**解包出来**的 `ets/modules.abc` 里逐字节搜，不是对 zip 搜）：

| 串 | 结果 |
| --- | --- |
| `lohPageShownAtMillis`（本次新增的键） | **FOUND @451499** |
| `page shown: source=`（本次新增的日志串） | **FOUND @451432** |
| `lohSplitViewActive`（对照组：既有键） | FOUND @452450 |
| `ui_updated_minutes_ago`（对照组：既有的档位键） | FOUND @60319 |
| `lohPageShownTick`（一个**不存在**的串，反证搜索确实按字面走） | NOT FOUND |

⇒ 装了的那一份**确实是本工作区的构建**：证据不是"install 退出码 0"，而是产物里有本次改动、且**设备 hilog 里打出了只有这次改动才会有的行**
（`page shown: source=…`），两者互证。

## 两帧设备证据（判别性）

### 帧的定义

| 帧 | 做了什么 | 画面里的页头行 | 设备状态栏 |
| --- | --- | --- | --- |
| **帧 1** | `hdc install -r` → `aa force-stop` → `aa start`（冷启动；静默重登 + 一次真实抓取） | `刚刚更新` | 02:04 |
| **帧 2** | 点底栏「作业」（切走）→ 等真实的两分钟 → 点底栏「公告」（切回） | `3 分钟前更新` | 02:07 |
| **帧 3** | 按 HOME（进后台）→ `aa start`（回前台） | `6 分钟前更新` | 02:10 |

帧 1 与帧 2 间隔 2 分 49 秒（状态栏 02:04 → 02:07，hilog 14:04:2x → 14:07:2x）；
帧 2 与帧 3 间隔约 2 分 50 秒 —— 两对都 **≥2 分钟**，**没有改设备时钟**。

### 算术：文本与时间戳逐位对上

四个档位由既有纯函数 `updatedTimeParts` 分档（`ui/components/UpdatedTime.ets`，边界由 `UpdatedTime.test.ets` 钉住）。
本次改动只把"时间基准"从上一次求值那一刻换成**本页最近一次被显示的时刻**，所以每一帧的文本都可以用 hilog 里的两个数重算出来：

快照抓取时刻（`data.notices.repository notices refresh done` 自己打出来的）**全程只有一个**：
`fetchedAt=1789279440209`（14:04:00.209）。

| 帧 | 时间基准 = `page shown … at=` | 基准 − fetchedAt | `floor(差 / 60000)` | 画面文本 |
| --- | --- | --- | ---: | --- |
| 帧 1 | `1789279439714`（`source=shell-appear`） | **−495 ms** | 负数 ⇒ JUST_NOW | 「刚刚更新」✔ |
| 帧 2 | `1789279635375`（`source=tab-change:0`） | **195166 ms** | **3** | 「3 分钟前更新」✔ |
| 帧 3 | `1789279802140`（`source=ability-foreground`） | **361931 ms** | **6** | 「6 分钟前更新」✔ |

同一份快照、同一份列表、同一个 Text 节点，三帧三个不同的文本 —— 这就是"不再冻结"。
（改动前那一版在同样路径上只会一直显示构建那一刻算出来的「刚刚更新」。）

### 为什么这次变化**不是"应用又抓了一次"**

判"没有新抓取"所依据的日志串（都是应用自己打的，消费点自证）：

| 串 | 出处 | 含义 |
| --- | --- | --- |
| `features.notices.store refresh done: count=… unread=…` | 公告列表 store | 公告这一次抓取**结束**（只有它会写这个 store 的 `fetchedAtMillis`） |
| `data.notices.repository notices refresh done: … fetchedAt=…` | 公告仓库 | 网络抓取成功并落盘，**并把 fetchedAt 打进日志** |
| `data.notices.source notice fetch source done: …` / `data.notices fetched …` | 公告抓取源 | 真的发出了 4 个公告请求 |
| `data.notices.snapshot snapshot load:` / `snapshot save ok:` | 公告快照 | 本地快照读 / 写 |

**这些串在全场会话里的最后一次出现是 14:04:00.258**（`refresh done: count=2 unread=0`）。
帧 2 与帧 3 之间的**全部**应用日志（14:07:15.376 → 14:10:02.140，逐条，无省略）：

```
14:09:17.830 A04c4f/entry.ability        Ability onBackground
14:10:02.084 A04c4f/entry.ability        Ability onNewWant
14:10:02.086 A04c4f/entry.ability        semester override: want parameter "lohSemester" absent; … source=none
14:10:02.086 A04c4f/entry.ability        file settings override: want parameters absent; … source=none
14:10:02.140 A04c4f/features.shell.pageshown  page shown: source=ability-foreground at=1789279802140 previousAt=1789279635375
14:10:02.140 A04c4f/entry.ability        Ability onForeground
```

⇒ 这 2 分 47 秒里 **一条 `data.*`、一条 `network request #N`、一条 `refresh done`、一条 `page appear` 都没有**。
两帧之间唯一的产生方事件就是 `markPageShown('ability-foreground')`。**帧 2 → 帧 3 是严格无抓取的一对**，
所以它单独就足以把"文本变了"归因到**重算**，而不是"数据刷新"。

**帧 1 → 帧 2 这一对要如实说明一处**：工单原文的路径是"切走再切回"，而**切到「作业」页确实触发了一次抓取** ——
但那一次是**作业页自己的 `CourseListStore`**（`data.courses.source` / `data.courses.repository`，
14:05:29.069–14:05:29.677，把公告 / 作业 / 文件三域一起取），它**不写**公告列表 store 的 `fetchedAtMillis`。
两条独立依据：

1. 上面那张表里，公告那四个串在 14:04:00.258 之后再没出现；
2. **算术证伪**：若公告 store 在切走那一刻（14:05:29.019）被抓过，帧 2 的基准差就只有
   `1789279635375 − 1789279529019 = 106356 ms ⇒ 1`，画面该是「1 分钟前更新」；若在切回那一刻被抓，该是「刚刚更新」。
   实际是 **3**，只与冷启动那次 `fetchedAt=1789279440209` 相符。

### 只变了一行：帧 2 与帧 3 的**文本节点逐条 diff**

两份 `--mode full` 的 layout dump 差集**只有一条记录**（同一坐标、同一元素）：

```
<= 3 分钟前更新 [145,164,274,190]
=> 6 分钟前更新 [145,164,274,190]
```

公告列表的每一条（课程名 / 标题 / 正文预览 / 发布人 / 相对发布时间）、五个筛选片计数（`全部 2`…）、
底栏五个 tab —— 两帧**逐字节相同**。

原始节点（帧 2 / 帧 3 同一位置）：

```json
{ "type": "Text", "text": "3 分钟前更新", "bounds": [145, 164, 274, 190], "children": [] }   // 帧 2
{ "type": "Text", "text": "6 分钟前更新", "bounds": [145, 164, 274, 190], "children": [] }   // 帧 3
```

帧 1 的同一节点：`Text "刚刚更新" bounds=[145,164,234,190]`（左边界同为 145；右边界随字数变化）。

## 逐文件论断表

| 文件 | 字节 | SHA256(前16) | 用途（一条主论断） |
| --- | ---: | --- | --- |
| `t03-frame1-coldstart-just-now.png` | 224853 | 223152B33F7468F4 | 冷启动后公告页页头 = **「刚刚更新」**（JUST_NOW 档） |
| `t03-frame2-after-tabswitch-3min.png` | 226231 | E8F05BECDAF91585 | 切到作业再切回公告后，同一页头 = **「3 分钟前更新」**（MINUTES 档） |
| `t03-frame3-after-foreground-6min.png` | 226431 | 20271FD8ED93E580 | HOME 压后台再回前台后，同一页头 = **「6 分钟前更新」**（MINUTES 档，换了一个数） |
| `t03-frame1-layout.json` | 71130 | 57D5F8B26A657A7C | 帧 1 的原始 layout dump（`Text "刚刚更新" [145,164,234,190]`） |
| `t03-frame2-layout.json` | 71135 | DDD1EC87727A6D79 | 帧 2 的原始 layout dump（`Text "3 分钟前更新" [145,164,274,190]`） |
| `t03-frame3-layout.json` | 71135 | 56BE90AC5DEE23D6 | 帧 3 的原始 layout dump（`Text "6 分钟前更新" [145,164,274,190]`） |
| `logs/t03-hilog-full-session.txt` | 32548 | FE38FC0C11A15265 | 全场会话 hilog（14:03:58 → 14:10:02）：**唯一**的 `fetchedAt`、三次 `page shown`、帧 2→帧 3 之间零抓取 |
| `logs/t03-hilog-window.txt` | 32022 | 653DFADA9AE28B14 | 同上窗口的另一次拉取（用于交叉核对行数与内容一致） |
| `logs/t03-hilog-coldstart.txt` | 18726 | 58A35AF1E9572788 | 冷启动窗口（证明运行的是本次构建：`shell-appear` / `ability-foreground` 两行） |

过程文件（**不构成本 ticket 的论断**，只作工作副本）：`logs/t03-before-install.png`、`logs/t03-before-install-layout.json`
（装机**前**那一版、停在文件 tab 的过程帧）、`logs/t03-away-layout.json`（切到作业页那一帧）、
`logs/t03-after-home-layout.json`（按 HOME 后的桌面帧）、`logs/t03-hap-unpack/`（解包产物做内容级检查用）。

## 逐条验收

1. **页面重新显示时，页头时间文本按当前时间重算** —— 「切走再切回 tab」：帧 1 → 帧 2（`刚刚更新` → `3 分钟前更新`）；
   「从后台回前台」：帧 2 → 帧 3（`3 分钟前更新` → `6 分钟前更新`）。两对的间隔都 ≥2 分钟（状态栏 02:04 / 02:07 / 02:10）。
   三帧的文本都能由 hilog 里的 `page shown … at=` 与 `fetchedAt=` 逐位重算出来（见上表）。
2. **既有四档边界单测仍然全绿** —— `entry/.test/…/test_result.txt`：`Tests run: 426, Failure: 0, Error: 0, Pass: 426`
   （基线 423 → 426，新增的 3 条见下）。四档边界本身**一个字都没改**：`ui/components/UpdatedTime.ets` 与
   `entry/src/test/UpdatedTime.test.ets` 都不在本次 diff 里。
3. **一个可命名的动作，四个列表页共用同一个模式** —— 动作 = `markPageShown(source)`（`features/shell/PageShown.ets`，
   全仓唯一写 `PAGE_SHOWN_AT_KEY` 的地方，grep 计数 = 1）；四个列表页各只有一条 `@StorageProp(PAGE_SHOWN_AT_KEY)`
   与一行 `pageHeaderUpdatedText(…)` 调用；页头文本的**实现**也只有一处。
   新增单测 `entry/src/test/PageShown.test.ets`（3 条，已注册进 `List.test.ets`）：
   时间基准的取值与退回当下、`pageHeaderUpdatedText` 在四档键上的映射与"同一快照 + 不同基准 ⇒ 文本不同"、
   以及动作确实把时刻写进了 AppStorage。
4. **设备证据：同一台设备、同一状态、间隔 ≥2 分钟、切走再切回，那一行确实变了** —— 见上「两帧设备证据」：
   两帧截图 + 两份 layout dump 的同一个 `Text` 的 px 行 + 帧 2→帧 3 之间"零抓取"的 hilog 依据。

## 未做到 / 存疑（如实记录）

1. **设备帧只覆盖两档**：`JUST_NOW`（帧 1）与 `MINUTES`（帧 2 / 帧 3）。`HOURS` / `DAYS` 的措辞这一轮**没有**在设备上出现
   （要出现得有 1 小时以上的旧快照）。那两档的措辞由既有单测的键映射（`ui_updated_hours_ago` / `ui_updated_days_ago`）承担。
2. **只验了一个页面**：设备帧全部取自「公告」。四个页面共用同一处实现（grep 可复核），但没有逐页取设备帧；
   「作业」页只在切换过程中被扫到一帧（`logs/t03-away-layout.json`，那一帧页头也是「刚刚更新」，不作论断）。
3. **"从后台回前台"只验了 HOME + `aa start` 这一条路径**（模拟器上没有别的可控路径）。另外
   `source=ability-foreground` 在**冷启动**时也会触发一次（14:03:58.932，早于 `shell-appear`），这是设计使然，不是重复。
4. **没做像素级 diff**：帧 2 / 帧 3 的"只变了一行"是**文本节点层面**的逐条 diff（且 `bounds` 也相同），
   没有对两张 PNG 做逐像素比较。
5. **`test_result.txt` 的 `fetchedAt` 之外没有任何"消费点"埋点**：页头这一行本身不打日志，所以"界面确实重算了"
   只能由 layout dump / 截图承担；我没有为它加一条渲染日志（避免每次重绘都刷日志）。
   设备证据里"运行的是本次构建"由产物内容检索 + `page shown: …` 行承担。
