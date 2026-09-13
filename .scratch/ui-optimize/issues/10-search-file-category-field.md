# 10: 搜索按文件分类召回（条件 ticket）

**What to build:** 如果文件模型能取到文件的分类，就把分类文本纳入搜索召回；取不到就不做。这是一个条件 ticket：先查证，再决定做或关掉。

**Blocked by:** None（可立即开始）

**Status:** closed-wontfix（条件不成立：数据模型取不到 category；而站点真实存在的分类文本 fileType 已在召回范围内）

- [x] 查证文件抓取链路是否拿得到分类字段（能不能取到，必须在 ticket 的执行记录里给出可复核的判据）
- [ ] 若取得到：分类文本纳入字段表，单测断言字段表包含它且权重与参考口径一致
- [x] 若取不到：**关掉本 ticket**，写明原因（数据模型缺口），不留下半个改动

## Comments

### 2026-09-13 · 统筹：条件不成立，关闭本 ticket（无代码改动）

**结论**：文件抓取链路**取不到**分类字段 `category.title`；而流水线里真实存在的"分类 / 类型"文本 `wjlx` → `fileType` **已经在**搜索字段表里、权重与参考口径一致。所以本 ticket **不产生任何代码改动**。

**可复核判据**（每条都能自己重跑）：

1. **字段表已经带分类文本**：`entry/src/main/ets/features/search/SearchCore.ets` 的 `FILE_SEARCH_FIELDS` 含 `{ name: 'fileType', weight: 2 }`，`fileHaystack()` 也把它填进摘要。
   单测已钉住这张表：`entry/src/test/Search.test.ets:99` 断言 `['courseName:1','courseTeacherName:1','title:2','description:2','fileType:2']`。
2. **`fileType` 的来源就是站点给的 `wjlx`**：`entry/src/main/ets/domain/parse/FileParser.ets` 的字段映射 `wjlx → fileType`；参考实现同一处也是 `fileType: f.wjlx`（`reference/learnOH-old/harmony/oh_modules/.ohpm/learn-oh-data-processor@.../src/main/ets/DataProcessorModule.ts:432`）。
3. **参考实现多出来的那个键 `category.title` 在参考实现里自身也是死键**：`thu-learn-lib` 的 `File.category?: FileCategory`（`reference/learnOH-old/node_modules/thu-learn-lib/lib/typescript/types.d.ts:104-116`）只由**另一条**接口 `getFileListByCategory(courseID, categoryId)`（同包 `lib/typescript/index.d.ts:54`）填充；参考实现的文件列表动作走的是 `dataSource.getFileList(courseId)`（`reference/learnOH-old/src/data/actions/files.ts:39`），**从不调用**按分类取列表那条 ⇒ `category` 恒为 `undefined`，`useSearch.ts:40` 的 `{ name: 'category.title', weight: 2 }` 在参考实现里也永远不命中。
4. **本工程的数据模型缺口已如实登记**：`SearchCore.ets` 的 `MODEL_MISSING_KEYS = ['category.title']`；`Search.test.ets:118-120` 断言它仍在表里，并注明"参考实现能命中 / 本工程数据模型没有来源"。
5. **原始记录形状里没有 category**：列表接口一条原始记录只有 `kjxxid / wjid / bt / ms / fileSize / scsj / wjlx / isNew`（`FileParser.ets` 的 `RawCourseFile`），站点这条列表接口本就不下发 category；真要拿它得再发一次 `getFileListByCategory`，那是**新增一条数据链路**，不是本 ticket 的范围。

**为什么不做"多发一条请求取 category"**：spec 的关键决策第 9 条是"只有确认文件模型能拿到分类时才做；取不到就不做，并在执行记录里写明原因"。新增按分类抓取的链路属于数据层扩张，且参考实现自己都没用它 —— 留作候选，不在本轮。

**遗留**：无。本 ticket 不留半个改动。