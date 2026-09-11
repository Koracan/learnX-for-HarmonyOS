# 状态层与持久化格式全部更换

弃用 `redux` / `react-redux` / `redux-persist` / `redux-thunk` / `typesafe-actions`，改为领域 store（`@ObservedV2`/`@Trace`）+ 无 UI 依赖的 Repository；持久化改为 asset store（凭据）+ preferences（设置、收藏、归档、隐藏课程、当前学期、内容快照），不再有 redux-persist 的 `persist:` 键前缀与 rehydrate 时机，**会话 cookie 不落盘**。旧数据不迁移，首次启动清理遗留并要求重新登录一次。

理由：`react-redux` 依赖 React 运行时，必须换；而参考实现的持久化是 8 份不同配置、3 种后端、跨 slice 重置与全局 mock 白名单交织在一起的，语义只在运行时可观察。与其翻译它，不如按领域模型重建——代价是必须重新推导行为契约（例如会话过期判定、收藏/归档/隐藏的过滤语义、Mock 模式），收益是持久化边界变得可枚举。

**Consequences**：内容快照带 `fetchedAt` 与 `schemaVersion`，采用"先展示旧快照再后台刷新"，取代旧版"全量持久化 + 隐式陈旧"。这是有意的：旧版"数据陈旧"与"半登录态"是最难诊断的一类 bug。
