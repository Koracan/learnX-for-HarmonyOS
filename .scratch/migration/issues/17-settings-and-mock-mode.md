# 17: 设置与子页 + Mock 正式化

**What to build:** 设置页及其子页（文件设置、关于、帮助、沉浸式、退出登录、日志导出），覆盖参考实现中存在的全部设置项；以 guest/guest 登录进入 Mock 模式。

**Blocked by:** 11（文件列表 + 详情 + 下载 + 预览 + 分享）、14（收藏 / 归档 / 隐藏课程）

**Status:** ready-for-agent

- [ ] 设置页覆盖参考实现中存在的所有设置项，逐项可操作且持久化
- [ ] 文件设置生效；关于页显示版本与构建号；帮助与隐私链接可打开
- [ ] 沉浸式开关即时生效，重启后保持
- [ ] 退出登录后凭据被清除并回到登录页
- [ ] 以 guest/guest 登录进入 Mock 模式：界面可用、数据为样例、不发起真实网络请求
- [ ] 真机截图

## Comments


### 边界说明（2026-09-12，由 ticket 11 带入）—— 文件设置：值与语义在 ticket 11，界面入口归你

ticket 11 落地了参考实现 `screens/FileSettings.tsx` 的两个设置项与"清理缓存"：

- **值 / 语义 / 持久化在 `entry/src/main/ets/data/settings/`**：
  - `FileSettings.ets`：`FileSettings`（`useDocumentDir` / `omitCourseName`，默认值照 `data/reducers/settings.ts:22` 都是 `false`）、
    `FileSettingsStore`（`load()` / `set()` / `current()` / `stored()`）、持久化端口 `FileSettingsPort`、内存实现，
    以及**取证用的运行时覆盖**（`--ps lohFileUseDocumentDir` / `lohFileOmitCourseName`，`describeFileSettingsOverride()` 自证）；
  - `PreferencesFileSettings.ets`：`@ohos.data.preferences` 实现（独立的 preferences 文件 `learnoh_file_settings`）；
  - 组装点 / 进程内单例：`features/files/repository/FileRepositoryProvider.ets` 的 `fileSettingsStore()`。
- **消费点**：`data/files/FileDownloader`（落盘根目录 = 文档 / 缓存；文件名 = `课程名-文件名` / `文件名`）、
  `FileDownloader.clearCache()`（删整个 `learnX-files` 根，对应参考实现 `removeFileDir()`）。

**归属**：**值、语义、生效逻辑归 ticket 11**；**全局设置页的入口与外观归 ticket 17**。
ticket 11 另有一个**文件 tab 自己**的设置入口页（`features/files/FileSettingsPage.ets`，两个开关 + 清理缓存），
那是文件功能的入口、不是全局设置页。你要在设置 tab 里复用，直接
`import { fileSettingsStore } from '../files/repository/FileRepositoryProvider'` 与 `FileSettingsPage` 即可 ——
**不要另造一套设置存储**。
**合并时注意**：`ShellTabs.ets` 的"文件 tab"内容已换成 `FilesPage`；设置 tab 仍是 `PlaceholderTab`（归你）。
