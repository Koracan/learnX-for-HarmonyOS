# 03: 导航骨架 + 公告列表（Mock）

**What to build:** 底部五个 tab 的导航骨架（公告 / 作业 / 文件 / 课程 / 设置），公告 tab 显示来自 Mock 数据源的公告列表，支持下拉刷新与空态。这是 tracer bullet：从 Mock 到真机可见界面一次贯通。

**Blocked by:** 01（工程分层 + 日志门面 + 主题令牌）、02（i18n 资源化）

**Status:** ready-for-review

- [x] 五个 tab 可见，切换后各自保留浏览位置（证据来自**模拟器** Pura 90，见 Comments 第 1 节）
- [x] 公告 tab 列出 Mock 公告，按发布时间倒序（7 条，09-25 → 08-17，含 id tiebreaker）
- [x] 下拉刷新有可见反馈（spinner +「刷新」帧 + RefreshStatus 状态机）；列表为空时显示空态文案（中英各一版截图）
- [x] 列表项显示标题、课程名、时间（相对时间）与未读标记（圆点 +「未读」文字）
- [x] Mock 数据源与真实数据源实现同一接口（NoticeRepository），替换实现只改注入点一行
- [x] 截图存 .scratch/shell/evidence/03-*.png（**模拟器**，清单见该目录 README.md）
## Comments

### 03 交付记录（导航骨架 + 公告列表，tracer bullet）

**状态**：代码、单测、脚本检查与模拟器取证全部完成；构建/单测/纯度门禁均过。设备为**模拟器 Pura 90**（127.0.0.1:5555，HarmonyOS 6.1.0(23)），真机 3FYBB25407201890 未连接。

#### 1. 逐条验收与证据

| 验收项 | 结论 | 证据（命令 / 真实输出 / 文件） |
| --- | --- | --- |
| 五个 tab 可见、可切换 | 达成 | `03-shell-tabs-zh.png`；`03-layout-tabs-zh.json` 里五个底栏文案各自的真实 bounds：`公告@2658 作业@2658 文件@2658 课程@2658 设置@2658`（同 dump 里另一个 `公告@192` 是页头）。点击坐标全部来自 `devecocli ui layout` 的真实 bounds（例：tap 课程 at (924,2682) bounds=[882,2658,967,2707]），未估 |
| 切换后各自保留浏览位置 | 达成（两个方向） | D1：公告列表滚到中段 → 切到设置 → 切回公告：`03-scroll-before-switch-zh.png` 与 `03-scroll-after-switch-zh.png` 内容相同（首条为「…邮箱，以免丢失或延误)+杜春光 5年前」），两份 layout dump **逐字节相同**，脚本判定 `== D1 preserved: True ==`。D2：继续下滚 → 切到课程 → 切回：`03-scroll2-*-switch-zh.png`，`== D2 preserved: True ==` |
| 公告按发布时间倒序 | 达成 | `03-shell-tabs-zh.png`：09-25（量子与统计）→ 09-22 → 09-10 → 09-08 → 08-30 → 08-17 22:30 → 08-17 17:50。**Mock 字面量故意乱序**，且单测 `mockLiteralOrderIsNotSorted` 断言「原始数组非有序」，所以界面上的倒序只可能来自 `sortNoticesDesc` |
| 列表项：标题 / 课程名 / 时间 / 未读标记 | 达成 | 同图：课程名（量子与统计…）、标题、发布人 + 相对时间（5年前/6年前）、未读=圆点 +「未读」文字（2 处）；页头「未读 2」与 Mock 里 `hasRead=false` 的 2 条自洽（单测 `countsUnreadInTheMockSet`） |
| 下拉刷新有可见反馈 | 达成 | ① refreshing 帧：`03-pull-refresh-refreshing-zh.png` / `-2-zh.png` 可见 Refresh 的 spinner + promptText「刷新」；② 完成后 `03-pull-refresh-done-zh.png` 页头「更新于 03:07:10」（刷新前 03:06:55）；③ 框架状态机 hilog（域 0x4C4F）：`pull refresh state: 1 → 2 → 3 → 4` 夹着 `mock notices refreshed: count=7` 与 `refresh done: count=7 unread=2`（`03-refresh-hilog-refresh.txt`） |
| 空态文案（中英皆有） | 达成 | 中文 `03-empty-zh.png`（暂无公告 / 未读 0）；英文 `03-empty-en-dark.png`（No notices / unread 0，同时是深色截图） |
| Mock 与真实数据源同一接口 | 达成 | `NoticeRepository` 单接口（`loadSnapshot()` / `refresh()`），唯一注入点 `createNoticeRepository()`；界面只依赖接口。单测 `mockAndSnapshotImplementationsHonourTheSameContract` 用**两个实现**（MockNoticeRepository 与真实形状的 FakeSnapshotNoticeRepository）跑同一组契约断言 |
| 截图存证 | 达成 | `.scratch/shell/evidence/`，42 个文件 + `README.md` 清单（字节数 + SHA256 前 16 位 + 用途），清单用 `git add -f` 入库（目录被 `.scratch/.gitignore` 忽略，与 foundation/evidence 同口径） |

设备版本可信度：`hdc shell bm dump -n com.koracan.learnOH` 原始输出存 `03-bm-dump.txt`，已安装包 `versionCode=1000042 / versionName=1.1.0`（与 `AppScope/app.json5` 一致；ADR-0003 的 2.0.0/2000000 属 ticket 18）。注意 bm dump 里有多层 versionName/versionCode，前几层是空串，必须取最后一个非空值。取证时刻的源码版本见 `revision.txt`：`git rev-parse HEAD` + `git status --porcelain` 的 SHA256 + 上述版本号；**工作区当时是脏的**（本 ticket 与 05 的在途改动），故这批截图不对应任何单个 commit，属过程证据。

#### 2. 导航选型与理由（写进 `features/shell/ShellTabs.ets` 文件头）

- 内容容器用 **Tabs + TabContent**：TabContent 子树首次显示后留在组件树上，切走不销毁 ⇒ 各 tab 滚动位置天然保留（这是验收第 1 条最省事、最可靠的实现；Navigation+NavPathStack 单栈反而要自己存取滚动偏移）。
- 底栏**自绘**（`Tabs.barHeight(0)` 隐藏系统 tabBar）：系统 tabBar 用系统品牌色，拿不到 #9A25AE 这类令牌；自绘后每个按钮的颜色与尺寸逐项取 `resolveTheme()`。每个 tab 的点击区是 `.layoutWeight(1).height('100%')` 的整格，不是只有文字可点。
- 将来每个 tab 要有自己的详情栈（公告详情…）时，在各自 TabContent 内放一个 `Navigation` + 自己的 `NavPathStack` 即可（参考实现也是「每 tab 一个 stack」）；本 ticket 不预搭空栈。

#### 3. 状态层（spec 第 3 节）

`NoticeListStore` 用 `@ObservedV2` + `@Trace`（items / phase / fetchedAtMillis / fromSnapshot / errorMessage），视图直接读。实测在 V1 组件里也能驱动刷新（异步 `loadOnce()` 完成后列表正确出现，见截图）。取数时序（先 `loadSnapshot()` 再 `refresh()`）封在 store 里，ticket 09 换真实实现时不动界面。

#### 4. 与参考实现的有意偏离（统筹已挂账，本 ticket 不改代码）

参考实现 `components/NoticeCard.tsx` / `FilterList.tsx` 与本实现有 5 处差异，均为 tracer bullet 的有意简化：

1. 标题未过 `removeTags`（参考 `NoticeCard.tsx:42`）——mock 标题无标签，真实公告会显形 → **挂 ticket 09**；
2. 缺正文预览 `removeTags(content)` + maxLines=2（参考 `NoticeCard.tsx:71-75`）→ **挂 ticket 09**；
3. 缺附件图标（橙）与重要标记图标（红）（参考 `NoticeCard.tsx:46-61`）→ **挂 ticket 09**；
4. 「未读」文字是新增（参考只用蓝色圆点，`NoticeCard.tsx:62-68`）→ **挂 ticket 09**；
5. 页头「更新于 HH:mm:ss · 未读 N」是自造（参考没有这一行，未读数在筛选条角标 `Filter.tsx:181-187`）→ **挂 ticket 14**（筛选条落地时对账，避免同一信息两处显示）。

另：参考实现的实体解码在**渲染层**（`helpers/html.ts` 的 `removeTags` 里做 `he.decode`），解析层不解码（`docs/reference-quirks.md` 第 4 条）。本 ticket 未在数据层做任何实体解码，符合该契约；解码属渲染层、归 ticket 09。

#### 5. 需要统筹知悉的三件事

1. **`NoticeRepository` 的临时位置**：按分工 `data/` 归 ticket 05，故接口与 Mock 暂放 `features/notices/repository/`，文件头已写明「过渡位置：ticket 09 落地时迁往 `data/notices/` 并删除本文件，改 `createNoticeRepository()` 一行」。统筹已把这笔账钉在 ticket 09。
2. **i18n 加键**：新增 4 个 UI 文案（公告 tab 名「公告」、占位页说明、空态「暂无公告」、「更新于 {0}」），按 ticket 02 Comments 10.4 的既定工作流改 `scripts/i18n-ui-strings.mjs` 并重跑 `node scripts/generate-i18n-resources.mjs && node scripts/gen-i18n-keys.mjs`。**生成产物 `entry/src/main/ets/core/i18n/I18nKeys.ets` 被机械更新（207 → 211 键），非手改**；同步更新了我拥有的 `entry/src/test/I18n.test.ets` 键数常量（24→28 / 207→211）。`node scripts/check-i18n-keys.mjs` → `RESULT: OK`（211 键，源码引用全解析，三份 string.json missing=empty=extra=0）。
3. **四个取证开关**：`MOCK_EMPTY_FOR_EVIDENCE` / `FORCE_DARK_FOR_EVIDENCE` / `FORCE_ENGLISH_FOR_EVIDENCE` / `SLOW_MOCK_FOR_EVIDENCE`（均在 `NoticeRepositoryProvider.ets`）**提交态全部 false**；深色/英文走**应用级** `setColorMode`/`setLanguage`，不改设备全局设置（shell 无权 `param set persist.global.*`，且不干扰并行 agent）。`03-final-zh.png` 是翻回 false 后重新构建安装的界面。

#### 6. 实际跑过的命令与结果

| 命令 | 结果 |
| --- | --- |
| `hvigorw --mode module -p module=entry@default -p product=default test` | `BUILD SUCCESSFUL`；**Tests run: 101, Failure: 0, Error: 0, Pass: 101**（我的 `features.notices.*` 共 15 条全绿：NoticeOrder 8 + NoticeRepository 3 + NoticeListStore 4；分类汇总见 `03-unit-test-by-class.txt`）。注：需先设 `DEVECO_SDK_HOME`（daemon 重建时会报 Invalid value of DEVECO_SDK_HOME） |
| `devecocli build` | exit 0（final 构建 `.dsh/logs/03-build-final.log`；另有 empty-zh / empty-en-dark / refresh 三次取证构建日志） |
| `hdc install -r ...entry-default-signed.hap` + `aa start` | install bundle successfully / start ability successfully（`devecocli run` 会一直挂着且与并行 agent 抢设备，故改用 build + hdc install/start） |
| `devecocli ui layout --format json --mode full` | 所有点击/滑动坐标来源；dump 存 `03-layout-*.json` |
| `devecocli ui screenshot --device 127.0.0.1:5555 --path ...` | 截图（目标文件已存在会报错 → 脚本先删；偶发 snapshot display as jpeg failed → 脚本重试 4 次） |
| `hdc shell "hilog -x -D 0x4C4F > /data/local/tmp/x.txt"` + `hdc file recv` | 完整 hilog（域号是 `core/log/Logger.ets` 的 `LOG_DOMAIN = 0x4C4F`；**0x0A0B 是错的，实测 0 字节**） |
| `node scripts/check-domain-purity.mjs` | 扫描 9 个领域源文件 / PASS domain 不依赖平台与应用层，exit 0 |
| `node scripts/check-i18n-keys.mjs` | RESULT: OK |

#### 7. 没做到 / 未验证（如实说明）

- **全部证据来自模拟器**（Pura 90，HarmonyOS 6.1.0(23)），**没有真机证据**（3FYBB25407201890 未连接；按 AGENTS.md 归 ticket 18 前的最终一次性复验）。
- **「在另一个 tab 里滚动后切回」这一方向无法验证**：本 ticket 其余四个 tab 是占位页、没有可滚动内容。做法改为在公告列表上做两次独立方向的验证（D1 中段 / D2 更深处），切走时分别经过设置与课程两个不同 tab。等 10/11/12 落地后应补一次真正的跨 tab 滚动互不干扰。
- **深色只截了一张**（深色 + 英文 + 空态同屏），没有「深色下的公告列表」截图；深浅两套令牌的正确性另有 ticket 01 的单测与静态扫描背书。
- **英文只截了空态**（应用级 setLanguage），没有英文列表截图；切换开关已翻回 false。
- refreshing 帧能截到，是因为取证期把 Mock 延迟从 700ms 临时调到 **5000ms**（`SLOW_MOCK_FOR_EVIDENCE`，提交态 false）；正常 700ms 下 `devecocli ui` 单次调用约 15-35s，必然错过该帧。refresh 帧由设备 `snapshot_display` 的 jpeg 转 PNG（该命令只接受 .jpeg 后缀）。
- light 阶段最初两处 hilog 采集是 **0 字节**（当时误用域 0x0A0B），已删除空文件并用正确域重采（`03-hilog-refresh.txt` / `03-hilog-final.txt` 等）。
- ArkTS 编译有 WARN 未清零（我的文件里：`ShellTabs.ets` 的 `getContext` deprecated 兜底、RefreshStatus 相关的 may-throw），非 ERROR；本版本 `check lint` / `check arkts` 不可用，静态门禁这一路无证据。
- 与 05 的并发代价（已由统筹写进 AGENTS.md）：一次 `hdc install` 卡死 11 分钟、`entry-default-signed.hap` 于 02:32:35 被另一 agent 的构建覆盖；之后改为「申请设备窗口 + build 后立刻安装截图」。

#### 8. 主要交付文件

`entry/src/main/ets/pages/Index.ets`（换成壳）、`features/shell/{ShellTabs,PlaceholderTab}.ets`、`features/notices/{NoticesPage,NoticeListStore,NoticeOrder}.ets`、`features/notices/repository/{NoticeRepository,MockNoticeRepository,NoticeRepositoryProvider}.ets`、`ui/components/EmptyState.ets`、`entry/src/test/Notices.test.ets`（+ `List.test.ets` 追加一行注册）、`entry/src/main/resources/{base,zh_CN,en_US}/element/string.json`（+4 键）、`scripts/i18n-ui-strings.mjs`。

#### 9. 验收后修复（统筹复核发现：下拉刷新出现两个指示器）—— 已修

**缺陷**：`03-pull-refresh-refreshing-zh.png` 里除了 Refresh 自己的 spinner + promptText「刷新」，列表正中还叠了一个居中 LoadingProgress，两个指示器同转。
**根因**：`NoticesPage.listBody()` 用 `store.isBusy()`（= LOADING **或** REFRESHING）决定是否盖居中指示器；下拉刷新（REFRESHING）因此也叠了一层。
**修法**（`NoticeListStore` + `NoticesPage` 各一处）：

- 新增 `isInitialLoading()` = `phase === LOADING && items.length === 0`，居中指示器只用它；
- `isEmpty()` 里用 `isBusy()` 抑制空态闪烁的逻辑保持原样（那是独立且正确的）。

**修复后的证据**（设备：模拟器 Pura 90）：

- `03-pull-refresh-refreshing-zh.png` / `-2-zh.png`：下拉刷新进行中**只有一个**指示器（Refresh 的 spinner +「刷新」），列表照常可见；`03-pull-refresh-done-zh.png` 为完成帧；
- `03-initial-loading-zh.png`：冷启动**首次加载**的居中 spinner 仍在（证明改条件没有把首屏加载反馈一起去掉）；
- `03-final-zh.png`：四个开关翻回 false、`MOCK_LATENCY_MILLIS=700` 后重新构建安装的界面；
- `03-hilog-refresh-30s.txt`：30s 延迟会话的 hilog（首次加载 30s + `pull refresh state: 1→2→3→4`）。

**取证期临时值**：为稳定截到 refreshing 帧与首屏加载帧，本次验证把 `MOCK_LATENCY_MILLIS` 临时置 30000（5s 不够：`devecocli ui`/`hdc` 单次调用 15-35s，必然错过窗口）；已复原为 700，四个 `*_FOR_EVIDENCE` 开关均为 false（`git show HEAD:...` 可逐行核对）。
**门禁重跑**：`devecocli build` exit 0；`hvigorw … test` 101 run / 0 failure；`check-domain-purity.mjs` PASS。
**这不是有意偏离**：参考实现刷新时只有 RefreshControl 自己的指示器、列表照常可见，所以按缺陷修掉，未登记为 deviation。
