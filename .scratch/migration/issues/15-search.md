# 15: 搜索

**What to build:** 全局搜索公告、作业与文件，中英混排能命中明显匹配，结果可跳转到对应详情。

**Blocked by:** 14（收藏 / 归档 / 隐藏课程）

**Status:** ready-for-agent

- [ ] 搜索覆盖三个域，结果标注类型与所属课程
- [ ] 大小写不敏感；标题或课程名的精确与前缀匹配必定命中（保留参考实现中的精确匹配合并层）
- [ ] 结果可跳转到对应详情，返回后保留查询与结果
- [ ] 空查询与无结果有明确表现
- [ ] 隐藏课程的内容不出现
- [ ] 真机截图

### 边界说明（2026-09-13，由 ticket 14 带入）—— 验收第 5 条「隐藏课程的内容不出现」现在**由你闭合**

- **变了什么**：ticket 14（收藏 / 归档 / 隐藏课程）已交付并验收为 `verified-partial`。它的验收第 3 条原本同时要求「从三个**列表**与**搜索结果**中消失」，但本 ticket（15）当时尚未开工、代码里**零搜索实现**（`grep -rn "search" entry/src/main/ets` 无命中），所以那半**在本 ticket 内不可验**，被显式记为未验证并转到这里。
- **你的证据成立到哪一步**：ticket 14 已交付的是一份**共用纯过滤实现** `entry/src/main/ets/features/marks/FilteredContent.ets`（三个 selector：`selectFilteredNotices` / `selectFilteredAssignments` / `selectFilteredFiles`，逐行对齐参考实现 `src/data/selectors/filteredData.ts`）。
  **你必须复用它，不要另写一套过滤**——否则「隐藏课程后内容从列表消失」与「从搜索消失」会由两份实现分别承担，两边一旦漂移，本条的验收就不再可比对。
- **三条别「顺手统一」的语义**（`FilteredContent.ets` 顶部注释已逐条写明，照抄即可）：① `fav ⊆ all`（已归档 / 被屏蔽课程的条目不进收藏夹）；② `archived` 与 `hidden` 两个视图用**原始 items**（归档视图里能看到被屏蔽课程的条目，反之亦然）；③ **四个列表都有「屏蔽」视图**（不只是课程页；依据 `components/Filter.tsx:211-218` 与四个屏幕各自传 `hidden`）。台账第 30 条是这三条的正式出处。
- **可观察量转移到这里**：ticket 14 验收第 3 条的**搜索那一半**（工单第 13 行：`隐藏课程的内容不出现`）由本 ticket 的验收承担，证据需要一张**屏蔽课程后其内容不在搜索结果里**的截图；ticket 14 那边只保留列表那半的证据（`E15`/`E17`/`E19`）。
- 另注：搜索结果也要尊重 `archived`（归档项是否进搜索，按参考实现的行为判——先读 `src/screens/Search.tsx` 与 `filteredData.ts` 确认它用的是哪个分组，**不要凭直觉**）。

## Comments
