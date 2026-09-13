# ticket 14（收藏 / 归档 / 隐藏课程）证据

**取证设备**（一律**模拟器**，不是真机）：

| 实例 | 串口 | 形态 / 视口 | 用途 |
| --- | --- | --- | --- |
| Pura 90 | `127.0.0.1:5555` | phone，1320×2856 px | 主证据（E*） |
| MatePad Pro 13 | `127.0.0.1:5557` | tablet，2880×1920 = **1440×960 vp** | 大屏单栏拉伸基线（T1） |

**源码版本**：`git rev-parse HEAD` = `0456055a2a61eb4a22ec538d329117515cf1c1c6`（**未提交**）。
工作区脏（含并行 ticket 16 的改动），`git status --porcelain` 的 sha256：
**`D7B51A92C5F118A3104BDD25D504A2B2081ECEAA7B750514132B9399AEDC8086`**（取证时的快照；期间工作区被其他 agent 动过就不再对应任何提交，只能算过程证据）。

**两个构建态的区分（很重要）**：

| 构建 | `ui/components/Toast.ets` 的 `TOAST_MILLIS_FOR_EVIDENCE` | 用途 |
| --- | --- | --- |
| **取证构建** | `120000`（2 分钟） | E1–E20：`devecocli ui` 单次调用要 15–35 s，参考实现的 3 s 撤销窗口**必然抓不到**（AGENTS.md：时间敏感的证据要把延迟直接改大） |
| **提交态构建** | **`0`**（= 不覆盖，用参考实现的 3000 ms） | E22：`toast shown: millis=3000` 的消费点自证 + 8 秒后 toast 已消失的截图 |

- 该开关的**实际生效值**由 `ToastController.show()` 打进 hilog（消费点，不是设置点）：
  取证构建里是 `millis=120000`（见 `E18-hilog-session-pura90.txt`），提交态构建里是 `millis=3000`（见 `E22-hilog-commit-state.txt`）。
- 提交态还由单测 `evidenceToastDurationOverrideIsOffAtCommit`（`Favorites.test.ets`）程序化守住。

**数据前提（账号事实，非本 ticket 造成）**：公告域取的是**站点当前学期**（2026-2027 秋季，2 条），
课程 / 作业 / 文件三域受 `--ps lohSemester` 影响。因此 E1–E17 的那一轮用
`aa start … --ps lohSemester 2025-2026-2`（春季：7 门课 / 57 作业 / 95 文件），
E19/E20 那一轮**不带**覆盖（秋季：2 门课 / 2 公告），为的是让"隐藏课程 → 该课程的公告从列表消失"可观察
（春季课程与秋季公告的 `courseId` 不同，覆盖态下这两件事碰不到一起）。

---

## 逐文件论断表（**一个文件只承担一条主论断**）

### 与 ticket 03 自造页头的对账（工单第 9 行）+ 过滤条落地

| 文件 | 主论断 |
| --- | --- |
| `E1-notices-header-and-filter-row.png` / `E1-layout-notices-header-and-filter-row.json` | 公告页头只剩「公告 + 刚刚更新」（**没有** `未读 n`），未读数改由筛选条的「未读 2」片承担；五片齐备：全部 2 / 未读 2 / 收藏 0 / 归档 0 / 屏蔽 0（布局树里五片的 text 逐条可读） |
| `T1-tablet-notices-filter-row.png` / `T1-layout-tablet-notices.json` / `T1-hilog-tablet.txt` | **平板（MatePad Pro 13，1440 vp）**：同一页在 750 vp 断点之上仍是**单栏拉伸**（列表宽 2880 px、五片排成一行），即 ticket 16 分栏落地前的基线 |

### 验收 2：三个列表都可按收藏 / 归档筛选

| 文件 | 主论断 |
| --- | --- |
| `E5-notices-fav-view.png` / `E5-layout-notices-fav-view.json` | 公告：点「收藏」片后只剩那一条（收藏 1），列表由 2 条变 1 条 |
| `E7-notices-archived-view.png` / `E7-layout-notices-archived-view.json` | 公告：「归档」片下能看到被归档的那一条（归档 1） |
| `E6-notices-archived-counts.png` / `E6-layout-notices-archived-counts.json` | 归档一条之后：全部 2→1、**收藏 1→0**、归档 0→1 —— 设备侧复现了参考实现"**fav ⊆ all**"（已归档项不出现在收藏夹，filteredData.ts:83） |
| `E8-assignments-filter-row.png` / `E8-layout-assignments-filter-row.json` | 作业：六片与计数（未完成 0 / 已完成 57 / 全部 57 / 收藏 0 / 归档 0 / 屏蔽 0），**默认高亮「未完成」**（参考实现 settings.ts:26 的默认值），且空态文案是那句专用的「没有未完成的作业」 |
| `E9-assignments-archived-view.png` / `E9-layout-assignments-archived-view.json` | 作业：归档一条后 已完成 57→56 / 全部 57→56 / 归档 1，且归档视图里就是那一条 |
| `E10-files-filter-row.png` / `E10-layout-files-filter-row.json` | 文件：五片与计数（全部 95 / 未读 4 / 收藏 0 / 归档 0 / 屏蔽 0） |
| `E11-files-fav-view.png` / `E11-layout-files-fav-view.json` | 文件：收藏一条后 收藏 1，收藏视图里就是那一条 |

### 验收 3：隐藏课程后其内容从列表消失

| 文件 | 主论断 |
| --- | --- |
| `E12-courses-filter-row.png` / `E12-layout-courses-filter-row.json` | 课程页：全部 7 / 屏蔽 0（春季 7 门课），页头是「课程 + 2025-2026 学年春季学期 + 刚刚更新」 |
| `E13-courses-swipe-hide-action.png` / `E13-layout-courses-swipe-hidden-action.json` | 课程行**滑动**露出右侧「屏蔽」按钮（单个按钮，参考实现 CardWrapper.tsx:63-79） |
| `E14-courses-after-hide.png` / `E14-layout-courses-after-hide.json` | 屏蔽一门课：全部 7→6 / 屏蔽 0→1，列表少一条，提示「已屏蔽 + 撤销」 |
| `E15-assignments-after-hide.png` / `E15-layout-assignments-after-hide.json` | **作业域**：该课（`…314`）的 3 条作业从"全部"消失（56→53），并在作业页的「屏蔽 3」里可见 |
| `E17-files-after-hide2.png` / `E17-layout-files-after-hide2.json` | **文件域**：再屏蔽一门课（`…509`，有 8 个文件）后 全部 95→87、屏蔽 0→8 |
| `E16-files-after-hide.png` / `E16-layout-files-after-hide.json` | （过程证据）只屏蔽 `…314` 时文件域 全部 95 / 屏蔽 0 ⇒ **那门课没有文件**，不是过滤没生效 —— 这也是后来再屏蔽一门课的原因 |
| `E19a-layout-courses-autumn-before-hide.json` | （秋季起点）课程页 全部 2 / 屏蔽 0，2 门课 |
| `E19-notices-autumn-after-hide.png` / `E19-layout-notices-autumn-after-hide.json` | **公告域**（秋季，不带学期覆盖）：屏蔽该秋季课程后 全部 2→**0**、屏蔽 0→**1**；注意此帧的列表视图是**归档**（上一次会话记住的过滤选择，本身也印证"按 tab 记住选择"） |
| `E20-notices-hidden-view.png` / `E20-layout-notices-hidden-view.json` | 公告的「屏蔽」视图里能看到被屏蔽课程的那条公告（参考实现四个列表都有 hidden 视图，filteredData.ts:85 / Filter.tsx:211-218） |

> **交叉域说明**：公告域与另外两域用的是同一条实现（`features/marks/FilteredContent` 的三个 selector + 同一个 `hiddenCourseIds`），
> 单测 `hidingACourseRemovesItsItemsFromAllThreeDomainsAndFromSearchInputs` 一次断言三域；设备侧因两域学期不同而分两轮取证（上面已分组标注）。

### 验收 4：撤销可恢复 + 提示可操作

| 文件 | 主论断 |
| --- | --- |
| `E3-notices-fav-toast-undo.png` / `E3-layout-notices-fav-toast.json` | 收藏一条后弹出「已添加到收藏」+「撤销」（布局树里 `已添加到收藏` 与可点的 `撤销` 两个 text 节点逐字可读），同时 收藏 0→1 |
| `E4-notices-undo-restored.png` / `E4-layout-notices-undo.json` | 点「撤销」后回到收藏 0，并弹出「已从收藏移除」（参考实现：这一支**没有**撤销按钮，逐字一致） |
| `E22-notices-commit-state-toast-gone.png` + `E22-hilog-commit-state.txt` | **提交态**：`toast shown: millis=3000`（消费点自证开关已复原）；同一张图是"收藏动作发生 8 秒后"拍的，**toast 已消失** ⇒ 撤销窗口回到参考实现的 3 秒 |
| `E18-hilog-session-pura90.txt` | 取证构建里的同一行是 `millis=120000`；并含每一次动作的消费点自证：`favorite set` / `archive set` / `hide course set` / `notices applied: … fav=… archived=… hidden=…` / `files applied: … hidden=…` / `collection flags save ok: reason=…` |

> E9/E11/E14 的画面里也各自带着当时那次动作的 toast（已归档 / 已添加到收藏 / 已屏蔽 + 撤销）——
> 那是**附带可见**，主论断仍按上表分配（一个文件一条主论断）。

### 验收 1：重启后保持

| 文件 | 主论断 |
| --- | --- |
| `E-P1-notices-after-restart-fav1.png` / `E-P1-layout-notices-after-restart.json` | `force-stop` → 重新 `aa start` 之后，公告筛选条仍是 **收藏 1**（重启前在 E3 里收藏的那条） |
| `E18-hilog-session-pura90.txt` | 同一轮里还有 `collection flags applied: source=stored favorites=notice:1,…`（启动时从持久层读回，**消费点**自证） |
| `prefs/learnoh_collection_flags` | 设备上 preferences 落盘的原始字节（`hdc file recv`）：一段 JSON，含 `noticeFavorites` / `noticeArchived` / `hiddenCourseIds` 与四个 `tabFilters` |
| `E19-notices-autumn-after-hide.png` | 附带：重启后公告页仍停在上一轮记住的「归档」视图 ⇒ 过滤选择也是按 tab 持久化的（参考实现 settings.tabFilterSelections 的行为） |

### 验收 5：滑动与点击不冲突

| 文件 | 主论断 |
| --- | --- |
| `E2-notices-swipe-actions-open.png` / `E2-layout-notices-swipe-actions.json` | 在一条公告上左滑后，右侧露出「收藏（心形）/ 归档（向下归档）」两个按钮，**页面仍停在列表**（布局树里是 `ListItem` + 底部 tab 栏，没有 `NavDestination`）⇒ 滑动没有误入详情 |

### 事件（**不是功能证据**，如实留档）

| 文件 | 说明 |
| --- | --- |
| `X1-launcher-after-app-terminated.png` | 2026-09-13 01:40 应用被系统终止后的桌面。会话期间应用被**环境事件**终止过数次（01:07、01:14、01:40），其中 01:15 那次日志留痕为 `HISYSEVENT PROCESS_KILL … reason=LIFECYCLE_TIMEOUT`（`[ARR1101]terminate EntryAbility`）。**未定位到崩溃标记**（`hilog -x` 里检索 `FIX THIS APPLICATION ERROR` / `jscrash` 均无命中），重启后重复同一串操作**不再复现**；同一时段宿主上还有并行 agent 的构建与另一台模拟器在跑。**结论：记为未定因的环境事件，不作为缺陷结论，也不排除并行操作。** |
| `X2-hilog-crash-window-0112.txt` | 事故窗口附近的整段 `hilog -x`（该缓冲已滚动，未含事故当刻） |

**未覆盖 / 未验证**（详见 ticket 14 交付节"未验证项"）：

1. **搜索结果**：搜索是 **ticket 15**（阻塞于本 ticket），当前代码里**不存在搜索**，所以"隐藏课程后内容从搜索结果消失"**无法在本 ticket 内验证**。本 ticket 交付的是三域共用的纯过滤实现（`features/marks/FilteredContent`），ticket 15 必须复用它。
2. **真机**：按 AGENTS.md / spec 第 8 节转 ticket 18；本目录全部为**模拟器**口径。
3. **归档方向的 toast/撤销**：主证物给了收藏方向（E3/E4）与屏蔽方向（E14），归档方向的 toast 只在 E9 里附带可见。
4. **长按菜单**：`bindContextMenu` 那条等价入口只由编译与代码保证，设备上没有单独点过。
5. **深色 / 英文**下这三处界面：未单独截图。
