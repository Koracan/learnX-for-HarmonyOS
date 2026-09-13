# ticket 06：提交入口被拦下时给出原因 —— 设备取证

设备：模拟器 **Pura 90**（`127.0.0.1:5557`）。`hdc -t 127.0.0.1:5557 shell param get const.product.devicetype` → `phone`，
`const.ohos.apiversion` → `23`，`const.product.model` → `emulator`。窗口 1320×2856 px。
**真实会话**（公告 / 作业 / 文件 / 课程都是站点数据；设置页没有 Mock 自证行）。全程只碰这一台设备。

**没有发出任何真实提交请求**：见"没有请求"那一节的负对照计数。

## 溯源

| 项 | 值 |
| --- | --- |
| `git rev-parse HEAD` | `0fc0a6ddb5eb9edc3aee2f75d37f9259a5c4839a` |
| 工作区（取证期间） | 只有一个未跟踪目录 `?? .scratch/ui-optimize/logs/`；`git diff --stat` 为空 |
| 产物指纹（提交态）`entry-default-signed.hap` | `6F269CE9CD0F4C1CCAFD98A6260F57E4F2FF82CF2209493CD2A6609298B49B38` |
| 产物指纹（提交态，解包后）`ets/modules.abc` | `E79140069F7C62BAF33398098D7FF5CA913A91840994A06F888B0680A9966C0E` |
| 产物指纹（取证态 = 夹具构建）`entry-default-signed.hap` | `F7AE12347E9686B31F0127D6BBFB435A3C50EA59F418D2EAC42B96324BCD4B9E` |
| 装回提交态后的 `ets/modules.abc` | `E7914006…996C0E`（**与提交态那份逐字节相同**） |

装机后设备上跑的是提交态产物，两处消费点自证：
`assignments evidence: mock=false count=4 unfinished=2 past=2 hasDisplayMath=true excellent=2` 与
`assignments applied: … items=57 visible=45 … pastDue=57`（真实学期 2025-2026-2）。

## 逐文件论断表

| 文件 | 用途（一条主论断） |
| --- | --- |
| `t06-real-pastdeadline-toast.png` | 真实会话、**已截止**作业详情：点页头提交图标后，屏幕底部出现 toast「作业已截止」 |
| `t06-fixture-submit-blocked-toast.png` | **夹具构建**下的提交页：不填正文、不选附件点「提交」，出现「请先填写正文或选择附件，再提交」；**没有**出现二次确认弹窗 |
| `logs/t06-layout-sustained.json` | 上一条 toast 的节点原文（type / text / visible / bounds） |
| `logs/t06-layout-control.json` | 对照：不点击时同一页面**没有**任何 `"type":"Toast"` 节点 |
| `logs/t06-submit-layout.json` | 夹具提交页那次 toast 的节点原文 |
| `logs/t06-fixture-hilog-*.txt`、`logs/t06-sweep*-hilog-*.txt`、`logs/t06-restored-hilog.txt` | 原始 hilog 拉取（未入库） |
| `logs/t06-sweep3-*.txt`、`logs/t06-sweep4-*.txt` | 9 个学期的 `assignments applied` 原始 dump（未入库） |

## 一、真实会话：已截止时点提交入口，提示出现了

复现路径：作业 tab → 学期 2025-2026-2 → 第一条「第十二次作业」（截止 2026-06-15 23:59，页面标「已截止」）
→ 页头右上角提交图标（`Stack [1180,137,1320,276]`，中心 1250,206）。

**hilog**（原始行）：

    features.assignments.detail: submission entry blocked: reason=past_deadline deadline=2026-06-15 23:59
    AceOverlay: [(100000:100000:scope)] Toast node mount to root node
    AceOverlay: [(100000:100000:scope)] open toast animation enter, containerId:100000
    AceOverlay: [(100000:100000:scope)] pop toast enter
    AceOverlay: [(100000:100000:scope)] toast remove from root

**layout dump**（`uitest dumpLayout -m true`，合并窗口；toast 是独立窗口里的一个节点）：

    "text":"作业已截止"  "type":"Toast"  "visible":"true"  "bounds":"[481,2352][839,2478]"  "hostWindowId":"36"

**对照**：同一页面、不点击时 `"type":"Toast"` 出现 0 次、「作业已截止」出现 0 次；
点击那一次 `"type":"Toast"` 恰好 1 次。

⇒ **本 ticket 的前提在这一支被证伪**：这个入口在真实会话下**不是静默的** —— 点它会出现含「截止」的提示。
它被写成"无反应"（`migration/issues/18:256`）与源码不符；ticket 13 自己的取证也写了"toast 未抓到"。
本轮 `toast failed:` 出现 **0 次**（`AssignmentDetailPage.toast()` 的 catch 分支未被触发），
所以也**不是** toast 传递层的缺陷。2 秒的窗口用单次 `devecocli ui screenshot`（十几秒）抓不到；
本轮的抓法：设备端连续点击保持提示常驻，再用 `uitest screenCap` 截图。

## 二、夹具构建：提交页被拦下时给出了说法

真实会话**进不去提交页**（理由见第三节），所以这一支用本仓既有的取证通道
`MOCK_ASSIGNMENTS_FOR_EVIDENCE`（`features/assignments/AssignmentEvidence.ets:33`）单独构建一份取证产物：

- 取证态构建：该常量置 `true` → `assembleHap --no-incremental`（ERROR=0 / ErrorCode=0 / COMPILE RESULT=0，
  BUILD SUCCESSFUL in 28 s 417 ms）→ 装机；设备自证 `assignments evidence: mock=true count=4 …`，
  列表变成 4 条夹具（未完成 2 / 已完成 2 / 全部 4）。
- **本节的每一帧都来自这份夹具构建**，不是提交态产物。

路径：作业 tab → 第一条「夹具·未到期（含公式）」（截止 2026-09-15 14:19、标「未到期」）
→ 页头提交图标 → 提交页 → **不填正文、不选附件** → 点「提交」（`Text [1152,201,1264,267] "提交" clickable`）。

**hilog**（每次点击一行，共 14 行 = 14 次点击）：

    features.assignments.submission: submission blocked: reason=nothing_to_submit xszyid=mock-upcoming-1 deadline=2026-09-15 14:19

**layout dump**：

    "text":"请先填写正文或选择附件，再提交"  "type":"Toast"  "visible":"true"  "bounds":"[236,2352][1084,2478]"

### 「没有请求」的负对照

同一份 hilog 里：

| 串 | 次数 |
| --- | ---: |
| `data.assignments.submit` | **0** |
| `sending` | **0** |
| `fileupload` | **0** |
| `tjzy`（提交端点末段） | **0** |
| `toast failed` | **0** |
| 二次确认弹窗的「确定」/「取消」（layout dump） | **不存在** |

⇒ 被拦下的那一支**一个请求都没发**，也没有走到二次确认。

## 三、真实会话里没有「未截止」作业：已搜索、不存在

判据不是列表上的「未完成」计数 —— 那个视图是 `all.filter(i => !i.submitted)`（`features/marks/FilteredContent.ets:15`），
**不含截止项**：2025-2026-1 显示「未完成 26」，而那 26 条**全部已截止**。
真正的判据是 `AssignmentsPage` 打的 `assignments applied: … items=N … pastDue=M`（`countPastDue` 按 deadline 算）。

搜索动作：对站点 `queryxnxq` 给的 9 个学期逐个 `aa force-stop` → `aa start --ps lohSemester <学期>`
（每次启动都自证 `semester override: … effective="<学期>" source=runtime-want-param`）→ 打开作业 tab → 拉全量 hilog → 抽 `assignments applied` 行。

| 学期 | items | 未提交(unfinished) | pastDue |
| --- | ---: | ---: | ---: |
| 2026-2027-1 | 0 | 0 | 0 |
| 2025-2026-2 | 57 | 0 | **57** |
| 2025-2026-1 | 108 | 26 | **108** |
| 2024-2025-3 | 0 | 0 | 0 |
| 2024-2025-2 | 87 | 10 | **87** |
| 2024-2025-1 | 66 | 2 | **66** |
| 2023-2024-3 | 7 | 2 | **7** |
| 2023-2024-2 | 163 | 75 | **163** |
| 2023-2024-1 | 58 | 1 | **58** |
| **合计** | **546** | 116 | **546** |

⇒ 每个学期都 `pastDue == items`，合计 **546 条全部已截止** ⇒ 真实会话里**不存在**能进提交页的作业。
（与 `migration/issues/18` 那份学期扫描的数字逐个相同，互为独立复核。）

## 四、收尾

- 夹具开关已还原为 `false`（`git show HEAD:entry/src/main/ets/features/assignments/AssignmentEvidence.ets`
  打印 `boolean = false`；`git diff --stat` 为空），重新 `assembleHap --no-incremental` 并装回设备；
  还原后的 `ets/modules.abc` 与提交态那一份 **SHA256 相同**（`E7914006…996C0E`），
  所以设备上现在跑的就是交付报告里那份「单测 409 / 打包绿」的产物。
- 没有清应用缓存、没有点「退出登录」、没有改任何设备级设置、没有点任何真实提交。
- 过程文件（原始 hilog 拉取、layout dump、过程截图）在 `logs/`；图片证据只留本地、未入库。
