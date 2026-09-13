# 07: 打开公告后未读蓝点消失并持久化

**What to build:** 打开过的公告立刻不再显示未读蓝点；已读状态随快照一起持久化，重开应用后不会「又变回未读」。

**Blocked by:** None（可立即开始）

**Status:** verified（机制 `9b77857` + 判别性冷启动帧 `4c18db3`；两条断言齐）

- [x] 打开公告详情后返回列表，该条目的未读标记消失；未读数相应减少
- [x] 已读集合随快照一起持久化；冷启动读回后与内容项合并
- [x] 快照损坏或版本不符时，已读集合的读取不抛异常（沿用既有的「丢弃重建、不崩溃」约定）
- [x] 单测：已读写入 → 持久化 → 读回合并（沿用既有公告仓库测试的写法）
- [x] 证据：设备上打开一条 → 返回列表截图（蓝点消失）→ 重启 → 再截图（仍消失）
      （补证轮已闭合：`t07-04` 是**判别性**帧，`t07-05` 明确标注非判别性，见下方补证轮复核）

## Comments

### 2026-09-13 · 统筹者验收：verified-partial（机制成立；持久化那一帧被退回重做）

**我独立复核过的东西**：
- **主树四门禁**（在合并后的 `9b77857` 上复跑）：domain-purity PASS / import-graph PASS / i18n-keys OK / generated-fresh PASS。
- **单测**：`entry/.test/.../test_result.txt` 时间戳 `2026/9/13 13:33:58`、`Tests run: 399, Failure: 0, Error: 0, Pass: 399`（分支基线 392 ⇒ 净增 7）。核对的**是那份文件本身**，不是回报里的转述。
- **改动的 10 个文件**与工单一一对应；**无 i18n 生成物、无图片入库**（该分支没有碰 i18n 输入，所以与 ticket 13 的生成物不冲突）。
- **两帧截图我亲眼看过**（`t07-01` / `t07-03`）：蓝点在 + 未读 1 → 蓝点消失 + 未读 0，红标保留、两条内容不变。**"打开即已读"这条成立**。
- **接线复核**：`NoticesPage.openDetail` 在压栈处调 `store.markRead`；`NoticeListStore.markRead` 换新记录后整表赋回 `@Trace` 字段（就地改元素属性不通知视图 —— 这条注释里写的实测结论是对的）；`RealNoticeRepository.markRead` 立刻重写快照，且**抓取时间沿用最近一次抓取**（页头"N 分钟前更新"说的是数据新鲜度，与本地读没读过无关）。

**为什么只算 partial：第 2 条（持久化）原来的证据是过定的**
交付里写"「重启后仍消失」只能由本地集合持久化解释"，但：
1. **`t07-04` 用的是交付构建（取证开关 false）**，而站点那条公告**本来就是已读** ⇒ 蓝点在这帧里不在，与本地集合是否持久化**无关**。
2. **换成取证构建也拿不到判别性证据**：`applyEvidenceUnreadOverride` 跑在 `mergeNoticeReadState` **之后**，把 `items[0].hasRead` 硬改成 false、**盖掉了本地集合的结果** ⇒ 取证构建冷启动时蓝点会重新出现（那是开关干的）。

已退回，要求把取证覆盖**移到合并之前**（= 模拟"站点说这条未读"），于是冷启动那一帧里"站点侧说未读、本地集合说已读、界面显示已读"→ **只有本地持久化能解释**。写侧（落盘信封含 `readNoticeIds`）与读侧（冷启动后蓝点不在且站点侧被报未读）要分成两条证据写。

**裁定**：
- **取证常量 `FORCE_FIRST_NOTICE_UNREAD_FOR_EVIDENCE` 留下**，但必须补一条"提交态"断言（`expect(...).assertFalse()`，本仓惯例见 `AssignmentList.test.ets:300` / `EnrollmentScript.test.ets:201` / `Favorites.test.ets:369`）。理由：它一旦被误提交成 `true`，用户会看到**假的未读蓝点**。
- **站点 `hasRead` 与本地集合的合并口径维持「或」**。依据：**参考实现没有"标记未读"这个动作、也没有本地已读集合** —— `reference/learnOH-old/src/data/types/state.ts:113-133` 的 `Notice` 只是从站点 `Notification` 里 `Pick` 出 `hasRead`（`NoticeState` 只有 favorites / archived / items），`data/selectors/filteredData.ts:82` 直接 `filter(i => i.hasRead === false)`，全仓没有写 `hasRead` 的地方 ⇒ 不存在"本地把已读改回未读"的合法路径，「或」是单调且正确的。合并点只有 `mergeNoticeReadState` 一处。
- **移植口径（一并记下）**："打开即已读 + 本地已读集合随快照持久化"是**本工程的有意增强**，不是移植参考实现 —— 参考实现里未读蓝点只随站点数据变。写清楚，免得日后有人按参考实现"改回去"。

**如实记录的其余两点**：
- 设备上**取不到真实未读样本**（站点 `sfyd` 两条都是已读，设备只有 2 条公告），所以"打开前有蓝点"这个起点是用取证构建造的；尚未宣称站点数据存在未读。
- 本 ticket 只覆盖**公告 tab** 的入口；从课程详情页进公告详情不写已读（不在本 ticket 范围内，作为已知差异记着）。

### 2026-09-13 · 补证轮复核：partial → **verified**（合并 `4c18db3`）

补证轮 commit `b53d27b`（2 文件 +79/−32）把上一节指出的问题按"判别性"重做了：
- **覆盖挪到合并之前**：`refresh()` 里 `applyEvidenceUnreadOverride(this.mapFetched())` 现在作用在**抓取记录**上，之后才是 `mergeNoticeReadState(reportedUnread, this.readIds)`（`RealNoticeRepository.ets:245-250`）。语义变成"站点说这一条未读"，于是**本地集合成了唯一能把它判成已读的东西** —— 这正是上一轮缺的那一环。我读代码确认了顺序，注释也把"顺序反了会盖掉本地集合判定"写明。
- **自证多了一条计数**：refresh 收尾日志里的 `localReadSetFlip=N`（被抓取侧报未读、最终被本地集合判成已读的条数）。冷启动那次 `reportedUnread=true` + `localReadSetFlip=1` + 界面 `未读 0` 三者同时成立 ⇒ 判别性成立。
- **开关改名**：`FORCE_FIRST_NOTICE_UNREAD_FOR_EVIDENCE` → `FORCE_NOTICE_UNREAD_FOR_EVIDENCE`（目标由 `EVIDENCE_UNREAD_INDEX` 决定，"FIRST" 已不符实义）。我 grep 过旧名**零残留**。我要求的那条提交态断言已加在 `NoticeRepository.test.ets:309`（`evidenceUnreadOverrideIsOffAtCommit`，`expect(...).assertFalse()`）。
- **写侧证据换成沙箱文件内容**：`preferences/learnoh_notice_snapshot` 里 `readNoticeIds` 两条 id、两条 item `hasRead=true`，且同一集合在**打开前 `readIds=1`、打开后 `readIds=2`**。他们如实说明"本轮抓不到 `notice marked read` 那行 hilog（工具只够到当前进程）" —— 用磁盘内容替代日志，这个替换比原方案更硬。
- **对照帧自觉标注**：交付构建冷启动 `localReadSetFlip=0 / evidenceUnreadOverride=false`，文件名与 README 都写了"**非判别性**"（站点自己也说已读）。这条自觉标注正是上一轮缺的。
- **我复核的**：`test_result.txt` 时间戳 `2026/9/13 13:48:52`、`Tests run: 400, Failure: 0, Error: 0`（399 + 新增断言）；合并后主树四门禁 PASS/OK；`t07-04` 那一帧我**亲眼看过**（未读 0、无蓝点）。

**仍然存在的限制（不因此降级，但留在这里）**：`EVIDENCE_UNREAD_INDEX=1` 是**一次性**的 —— 本轮跑完两条 id 都进了本地集合，以后再要"打开前有蓝点"必须换下标或先清沙箱快照；判别性还依赖那一次刷新成功（本轮 `elapsedMs=336`）。两条都写进了证据 README。

