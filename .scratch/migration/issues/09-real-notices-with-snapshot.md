# 09: 公告切真实数据 + 快照

**What to build:** 公告列表与详情改用真实抓取数据；抓取成功后保存带抓取时间与结构版本的内容快照，启动时先展示上次快照再后台刷新。

**Blocked by:** 08（保持登录 + 自动重登 + 降级）

**Status:** ready-for-agent

> **承接的临时技术债（来自 ticket 03）**：`entry/src/main/ets/features/notices/repository/` 下的 `NoticeRepository` 接口与 `MockNoticeRepository` 是**过渡位置**——ticket 03 开工时 `data/` 正被 ticket 05 占用，故接口暂寄在 features 下。本 ticket 落地时必须把接口与真实实现移到 `data/notices/`，并修改 `NoticeRepositoryProvider` 这一处工厂注入点；**界面不得改动**（这正是当初把接口与 Mock 分开放的目的）。迁移后删除 features 下的过渡文件。

> **公告卡片的保真项（来自 ticket 03 的验收，尚未实现）**：ticket 03 的卡片是 tracer bullet 的简化版。与参考实现 `src/components/NoticeCard.tsx` 相比缺三样，换真实数据时必须补齐（mock 数据里看不出差别，真实数据里这些都会显形）：
> 1. **标题与正文都要过 `removeTags` 等价物**（去注释 / 去标签 / `he.decode` 全实体集 / 折叠空白）。参考实现见 `NoticeCard.tsx:42,72`；目前 `NoticesPage` 直接渲染原始 `title`，且**正文根本没有渲染**。契约是两层的，见 `docs/reference-quirks.md` 第 4 条。
> 2. **正文预览**：`removeTags(content)`，`numberOfLines={2}`。
> 3. **两个状态图标**：`attachment`（橙）与 `markedImportant`（红），见 `NoticeCard.tsx:46-61`。
>
> 另有一处是**新增**而非缺失：参考实现的未读只用蓝色圆点（`NoticeCard.tsx:62-68`），ticket 03 额外加了「未读」文字。本 ticket 要么去掉文字改回纯圆点，要么在 `docs/reference-quirks.md` 登记为已批准的偏离。

- [ ] 公告卡片补齐参考实现的保真项（`removeTags` 标题与正文、正文 2 行预览、附件与重要图标；未读标记保持纯圆点或登记偏离）
- [ ] 真机显示的真实公告与网页端数量、顺序一致
- [ ] **把 NoticeRepository 接口与 MockNoticeRepository 从 features/ 迁到 data/notices/**（见上方技术债说明），界面零改动
- [ ] 抓取成功后写入带抓取时间与结构版本的快照
- [ ] 冷启动先用快照渲染（无空白与闪跳），随后刷新并更新
- [ ] 快照结构版本变化时能识别旧版本并丢弃重建，不崩溃
- [ ] 界面能看出数据的陈旧程度（时间或提示）
- [ ] 真机截图

## Comments
