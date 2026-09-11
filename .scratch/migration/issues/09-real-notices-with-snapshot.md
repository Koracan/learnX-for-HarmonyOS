# 09: 公告切真实数据 + 快照

**What to build:** 公告列表与详情改用真实抓取数据；抓取成功后保存带抓取时间与结构版本的内容快照，启动时先展示上次快照再后台刷新。

**Blocked by:** 08（保持登录 + 自动重登 + 降级）

**Status:** ready-for-agent

> **承接的临时技术债（来自 ticket 03）**：`entry/src/main/ets/features/notices/repository/` 下的 `NoticeRepository` 接口与 `MockNoticeRepository` 是**过渡位置**——ticket 03 开工时 `data/` 正被 ticket 05 占用，故接口暂寄在 features 下。本 ticket 落地时必须把接口与真实实现移到 `data/notices/`，并修改 `NoticeRepositoryProvider` 这一处工厂注入点；**界面不得改动**（这正是当初把接口与 Mock 分开放的目的）。迁移后删除 features 下的过渡文件。

- [ ] 真机显示的真实公告与网页端数量、顺序一致
- [ ] **把 NoticeRepository 接口与 MockNoticeRepository 从 features/ 迁到 data/notices/**（见上方技术债说明），界面零改动
- [ ] 抓取成功后写入带抓取时间与结构版本的快照
- [ ] 冷启动先用快照渲染（无空白与闪跳），随后刷新并更新
- [ ] 快照结构版本变化时能识别旧版本并丢弃重建，不崩溃
- [ ] 界面能看出数据的陈旧程度（时间或提示）
- [ ] 真机截图

## Comments
