# ticket 15（搜索）证据清单

**来源**：全部来自**模拟器**（不要读成"真机"）。设备与版本：

| 实例 | 串口 | 形态 | 分辨率（px） | 系统 |
| --- | --- | --- | --- | --- |
| Pura 90 | `127.0.0.1:5555` | phone | 1320×2856 | HarmonyOS 6.1.0(23) |
| MatePad Pro 13 | `127.0.0.1:5557` | tablet | 2880×1920（1440×960 vp） | HarmonyOS 6.1.0(23) |

**构建**：HEAD `39a650e` + 工作区改动（见工单交付节的 porcelain 哈希）。两台设备装的是
`entry/build/default/outputs/default/entry-default-signed.hap` 的 **03:32:48 那次构建**；
之后 04:56:54 为**一处注释**（`SearchCore.ets` 文件头）重构建过一次 —— 见下面的 abc 哈希：两者逐字节相同。

编译产物 `ets/modules.abc` 的 SHA256 = `870CE9FEE871A5F147C4B840CCAC52E66F6E2131DC7F66348C217793667B992A`：
它同时也是"截图对应的就是当前代码"这一条的判据 —— 取证之后只改过**一处注释**（`SearchCore.ets` 文件头），
而那处改动前后该 abc **逐字节相同**。（另外做过 `ets/modules.abc` 的内容检索，确认 `closeSearch ignored` /
`search closed` / `search result tapped` / `search applied` / `learnoh-search-input` 都在产物里 ——
只看 "BUILD SUCCESSFUL" 不够，见 AGENTS.md 的陈旧产物教训。）

**两个语料**：手机上有两轮，因为站点的"当前学期"只有 1 门可见课：
- **秋季语料**（站点当前学期 `2026-2027-1`，2 门课、1 条可见公告、0 作业、4 个文件（都在被屏蔽的课里））→ `E*` / `P*`；
- **春季语料**（`aa start --ps lohSemester 2025-2026-2`，7 门课、大量公告/作业/文件）→ `S*`。
  这一轮结束后已用一次**不带参数**的启动复原（运行时覆盖只在进程内生效）。

---

## 一、手机（Pura 90）

### 1. 入口与"哪些页面有"

| 文件 | 论断 | 画面/树里看到什么 |
| --- | --- | --- |
| `E1-phone-notices-header-search.png` + `E1-phone-layout.json` | 搜索入口是**页头右侧的图标**（不是底部 tab） | 公告页头右侧有放大镜；layout 树里它是一个 `clickable` 的 `Row`（bounds ≈ [1124,192,1264,332]）—— 底栏五个 tab 之外没有第六个搜索 tab |
| `P0-phone-courses-baseline.png` + `.json` | 取证开始前的基线：课程页 `全部 1` / `屏蔽 1`（`形式语言与自动机` 可见、`英语听说交流（A）` 被屏蔽） | 课程页两个筛选片与课程行 |
| `S3-phone-spring-course-query-sections-1-top.png` + `S3-phone-layout.json` | 课程页也有页头搜索入口（同一颗按钮；四个内容 tab 都有，设置页没有） | 见 `S1`/`S3` 的页头区域 |

### 2. 空查询 / 无结果 / 命中

| 文件 | 论断 | 关键内容 |
| --- | --- | --- |
| `E2-phone-search-empty-query.png` + `.json` | **空查询 = 可见全量**（参考实现 `String.includes('')` 的后果），且**被屏蔽课程的内容不在里面** | 查到 1 条公告（`形式语言与自动机` / `课程信息和微信群`）；被屏蔽的 `英语听说交流（A）` 那条一条都不在 |
| `E3-phone-search-prefix-cjk-query.png` + `.json` | 查询 `课程` 命中标题 `课程信息和微信群`（**标题前缀**） | layout 树里：`公告`（段头）→ `形式语言与自动机`（所属课程）→ `课程信息和微信群`（标题） |
| `E4-phone-search-content-only-cjk-query.png` + `.json` | 查询 `欢迎` 只出现在**正文**里也能命中（② 层按字段打分） | 同上那条公告被召回；标题与课程名都不含"欢迎" |
| `E4b-phone-search-case-insensitive-ascii.png` + `.json` | **大小写不敏感**（ASCII）：查询 `ppt` 命中正文里的 `PPT` | 同一条公告；hilog 里 `query="ppt" hits=1/0/0` |
| `E5-phone-search-no-result-empty-state.png` + `.json` | **无结果有明确表现** | 查询 `zzzz` → 空态 `无内容`（`EmptyState`，与参考实现 `Empty` 同形同源图标） |

### 3. 跳详情 / 返回保留 / 关闭

| 文件 | 论断 | 关键内容 |
| --- | --- | --- |
| `E6-phone-detail-from-search-result.png` + `E6-phone-detail-layout.json` | 结果**可跳转到对应详情** | 点结果后是公告详情（`公告` / `课程信息和微信群` / `赵乙宁` / 日期），hilog `search result tapped: type=notice id=… split=false` |
| `E7-phone-back-keeps-query-and-results.png` + `.json` | **返回后保留查询与结果** | 返回后查询框仍是 `课程`、结果行仍在；hilog `search navbar visibility: true` |
| `E8-phone-search-closed-back-to-shell.png` + `.json` | 页头关闭按钮回到主壳（**根栈**） | 画面是公告 tab + 底部五个 tab；hilog `search closed` |

### 4. 归档 vs 屏蔽（搜索的数据口径）

| 文件 | 论断 | 关键内容 |
| --- | --- | --- |
| `E9-phone-notices-archived-view.png` + `.json` | 那条公告**处于「归档」状态** | 公告页 `归档 1` 视图里就是 `课程信息和微信群`（带归档旗标），而 `全部 0` |
| `E3`（同上） | **归档项仍会被搜到**（参考实现喂的是原始 `items`，不是 `all`） | 同一条公告在搜索里出现 ⇒ 搜索口径 = 原始条目，只排除被屏蔽课程（工单要求照做） |
| `E10-phone-search-hidden-course-empty.png` + `.json` | **屏蔽课程后其内容不在搜索结果里**（验收第 5 条） | `P1` 之后查 `课程` → 空态 `无内容`；hilog `search applied: query="课程" candidates=0/0/0 hits=0/0/0 hiddenCourses=4` |
| `E11-phone-search-after-unhide-hit.png` + `.json` | **取消屏蔽后同一查询立刻命中**（因果闭合 + 状态复原） | 同一条公告回来了；hilog `candidates=1/0/0 hits=1/0/0 hiddenCourses=3` |
| `P1-phone-courses-after-hide.png` + `.json` / `P2-phone-courses-restored.png` + `.json` | 中间状态与复原 | P1：课程页 `全部 0` / `屏蔽 2`；P2：`全部 1` / `屏蔽 1`（与 `P0` 同态） |

### 5. 三域覆盖（春季语料，7 门课、真实作业与文件）

| 文件 | 论断 | 关键内容 |
| --- | --- | --- |
| `S1-phone-spring-empty-query-three-sections-top.png` + `S1-phone-layout.json` | **公告段**：段头 = 类型，行内首行 = 所属课程 | layout 树里有精确的 `"text": "公告"` 段头 + `离散数学方法`/`软件分析与验证` 等课程名 |
| `S2-phone-spring-empty-query-assignments-section.png` + `S2-phone-layout.json` | **作业段**（空查询往下滚一屏） | layout 树里有精确的 `"text": "作业"` 段头 |
| `S3-phone-spring-course-query-sections-1-top.png` + `S3-phone-layout.json` | 按**课程名**查询（`离散数学方法`）命中**作业域**，行内带课程 + 教师 + 截止时间 | `离散数学方法` / `作业（7）` / `陆玫 · 2026-04-16 23:59` 等 |
| `S4-phone-spring-file-title-query-files-section.png` + `S4-phone-layout.json` | **文件段**：段头 + 行内 `TYPE SIZE` | layout 树里有精确的 `"text": "文件"` 段头 |

### 6. 日志与选型实验

| 文件 | 论断 |
| --- | --- |
| `15-phone-hilog-search.txt` | 消费点自证：`search opened` / `search applied`（query、三域候选数、三域命中数、hiddenCourses、items）/ `search input focused` / `search result tapped` / `search navbar visibility` / `search closed` / `courses applied`。**同一份文件同时支撑多个论断**——每条论断引用的是其中**不同**的行（不重复使用同一行） |
| `15-flexsearch-smoke-failure.txt` | 库选型实验：`@ohos/flexsearch@2.0.1` 具名导入在编译期失败 `00507015 … does not provide an export name 'Document'` |

---

## 二、平板（MatePad Pro 13，1440×960 vp，分栏已实现）

平板自己的状态：已登录（ticket 16 铺好的），**屏蔽 0**（手机上是 屏蔽 1）—— 所以它比手机多一条可见公告、4 个可见文件，
正好用来演示「两条结果轮流进右栏」。装的是**同一个 hap**。

| 文件 | 论断 | 画面/树里看到什么 |
| --- | --- | --- |
| `T0-tablet-shell-split.png` | 取证前的分栏主壳（左栏 = 列表、右栏 = 空态 `无内容`） | 底栏横跨整屏；左栏 393vp |
| `T1-tablet-search-split-left-and-right.png` + `T1-tablet-search-split-layout.json` | **搜索页在分栏下自成一左一右**：左栏 = 搜索框 + 结果（393vp），右栏 = 详情位（此刻是空态） | 树里有精确的 `"text": "无内容"`（右栏空态）与左栏的 `公告` 段头、`形式语言与自动机`、`课程信息和微信群`；1280px 处一条竖分隔线把 786px（= 393vp × 2）与右栏分开 |
| `T2-tablet-result-detail-in-right-pane.png` + `T2-tablet-result-detail-layout.json` | **点搜索结果 → 详情落在右栏**，左栏保留结果列表且该行**高亮** | 左栏：搜索页（`Welcome message…` 那一行灰底高亮）；右栏：公告详情（`Welcome message from the professor` / `张为民` / 正文）；`无内容` 在 T2 的树里**消失**（右栏不再是空态） |
| `T3-tablet-left-keeps-query-and-highlight.png` + `T3-tablet-left-keeps-query-highlight-layout.json` | 再点**另一条**结果：右栏换成新详情、左栏**高亮跟着移动**（列表与查询保留） | 右栏变成文件详情（`Listening 3-2 (Extra Listening)` / `类型 ZIP` / `大小 212.87 MB` / `课程 英语听说交流（A）`）；左栏高亮现在在 `Listening 3-2` 那一行、`Welcome` 那行已恢复常态 |
| `15-tablet-hilog-search.txt` | 消费点自证（平板侧） | `search opened` / `search applied: … candidates=…/hits=… hiddenCourses=…` / `search result tapped: … split=true` / `split view enter/exit: tab=search moved=…` |

---

## 三、取证过程中发现的两个**运行期**缺陷（都已修，且都有注释）

首轮 `assembleHap` 与 377 条单测**全绿**，但设备上一跑就暴露两个纯运行期缺陷。它们没有「修复前」的截图留档，
证据是修复后上表里那些画面 + 当时的日志行（`search closed` 之后界面仍是搜索页那一类）：

| 缺陷 | 现象 | 根因 | 修法 |
| --- | --- | --- | --- |
| 关闭按钮关不掉搜索页 | 日志打了 `search closed`，界面**仍是搜索页**（而搜索页整屏盖住底栏 ⇒ 用户出不去） | 关闭动作弹的是**页内详情栈**（详情已返回时它是空的，`pop()` 无事发生） | `SearchEntry.closeSearch()` 改成弹**根栈** |
| 输入后列表不刷新 | hilog 里命中数跟着查询变，**界面一直停在进页面那一刻的结果** | 三个结果缓存是**普通字段**，`results()` 依赖它们却未被观察 | 三个字段改 `@State` |

**另外一个取证环境教训**：`devecocli log --from 30m` **不保证拿得到 30 分钟的行** —— 详情页的 ArkWeb/chromium 日志会很快把缓冲区顶掉
（实测：30m 窗口只回来最近几分钟，手机侧 `E3/E4/E4b/E5/E6/E7` 那一轮的行第一次没抓到）。
处置：**每个论断拍完就立刻拉一次日志**（`15-phone-hilog-search.txt` 就是按这个办法逐轮累积、再去重排序的）。
