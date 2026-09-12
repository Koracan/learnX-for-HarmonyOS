# 09: 公告切真实数据 + 快照

**What to build:** 公告列表与详情改用真实抓取数据；抓取成功后保存带抓取时间与结构版本的内容快照，启动时先展示上次快照再后台刷新。

**Blocked by:** 08（保持登录 + 自动重登 + 降级）

**Status:** verified（模拟器口径，统筹复验 2026-09-12；真机转 ticket 18，桌面网页端人工比对见 Comments）

> **承接的临时技术债（来自 ticket 03）**：`entry/src/main/ets/features/notices/repository/` 下的 `NoticeRepository` 接口与 `MockNoticeRepository` 是**过渡位置**——ticket 03 开工时 `data/` 正被 ticket 05 占用，故接口暂寄在 features 下。本 ticket 落地时必须把接口与真实实现移到 `data/notices/`，并修改 `NoticeRepositoryProvider` 这一处工厂注入点；**界面不得改动**（这正是当初把接口与 Mock 分开放的目的）。迁移后删除 features 下的过渡文件。

> **公告卡片的保真项（来自 ticket 03 的验收，尚未实现）**：ticket 03 的卡片是 tracer bullet 的简化版。与参考实现 `src/components/NoticeCard.tsx` 相比缺三样，换真实数据时必须补齐（mock 数据里看不出差别，真实数据里这些都会显形）：
> 1. **标题与正文都要过 `removeTags` 等价物**（去注释 / 去标签 / `he.decode` 全实体集 / 折叠空白）。参考实现见 `NoticeCard.tsx:42,72`；目前 `NoticesPage` 直接渲染原始 `title`，且**正文根本没有渲染**。契约是两层的，见 `docs/reference-quirks.md` 第 4 条。
> 2. **正文预览**：`removeTags(content)`，`numberOfLines={2}`。
> 3. **两个状态图标**：`attachment`（橙）与 `markedImportant`（红），见 `NoticeCard.tsx:46-61`。
>
> 另有一处是**新增**而非缺失：参考实现的未读只用蓝色圆点（`NoticeCard.tsx:62-68`），ticket 03 额外加了「未读」文字。本 ticket 要么去掉文字改回纯圆点，要么在 `docs/reference-quirks.md` 登记为已批准的偏离。

- [x] 公告卡片补齐参考实现的保真项（`removeTags` 标题与正文、正文 2 行预览、附件与重要图标；未读标记保持纯圆点或登记偏离）
- [x] 真实公告与站点原始响应的数量、顺序一致（**模拟器口径**；未登录桌面网页端做人工比对，见 Comments 第 2 节；真机转 ticket 18）
- [x] **把 NoticeRepository 接口与 MockNoticeRepository 从 features/ 迁到 data/notices/**（见上方技术债说明），界面零改动
- [x] 抓取成功后写入带抓取时间与结构版本的快照
- [x] 冷启动先用快照渲染（无空白与闪跳），随后刷新并更新
- [x] 快照结构版本变化时能识别旧版本并丢弃重建，不崩溃
- [x] 界面能看出数据的陈旧程度（时间或提示）
- [x] **模拟器**截图（真机截图转 ticket 18）

## Comments

### 统筹提示（2026-09-12，**用户提供的事实**，非设备观测）—— 本学期**公告非空**

- 用户账号在 **2026-2027 学年秋季学期**的实际情况：**公告、文件、课程都有非空数据**；**只有作业为空**（作业相关见 ticket 10/13）。
- ⇒ 对本 ticket 的判读纪律是**确定性的**：真实公告取数**返回空就是失败信号**（端点 / 参数 / 解析 / 会话，四者之一有问题），**不是**"合法空结果"。**不许**用"可能这学期没数据"来解释空结果。
- 期望值：与**网页端**对照，**条数与顺序一致**（ticket 10 的验收里有同名判据，口径保持一致）。
- 归因顺序（照 `AGENTS.md` 与 `docs/reference-quirks.md` 第 15 条）：空/异常时**先把"我们发出去的请求"与"原始响应形态"落成证据**（端点、参数、Cookie 名与长度、status、bytes、响应是 JSON / HTML / 登录页），再谈服务端行为。

### ticket 09 交付（2026-09-12，模拟器 Pura 90 / HarmonyOS 6.1.0(23)）

**提交**：`df66e44`（仓库迁移 + 真实数据源 + 快照）/ `46aa84e`（卡片保真项）。
按统筹要求拆成两个提交：前一个只做"接口与 Mock 迁到 `data/notices/`、组装点只改
`NoticeRepositoryProvider` 一处"，后一个才是界面保真项（removeTags / 2 行预览 / 两个图标 /
陈旧程度）。**迁移那一步没有为迁移本身改任何界面文件**；后一个提交里 `NoticesPage` 的改动
是保真项本身，`ShellTabs` 只有一行"取证开关实际生效值"自证日志（见下）。

#### 1. 落地了什么

| 项 | 落点 |
| --- | --- |
| 接口与真实实现 | `data/notices/NoticeRepository.ets` / `RealNoticeRepository.ets` |
| 取数入口 | 一律走 `data/auth/SessionRestore.AuthedTaskRunner`（**没有自造重登/重试/降级**） |
| 课程表 | `data/notices/CourseListFetcher.ets`（ticket 12 只做公告需要的那一小段；未做学期切换） |
| 公告抓取 | `data/notices/NoticeFetchSource.ets` 包 ticket 05 的 `NoticesFetcher`（每次用当次会话现构造） |
| 快照 | `NoticeSnapshotFileStore.ets`（preferences）+ `NoticeSnapshotSerialization.ets`（纯函数、版本校验） |
| 组装点 | `NoticeRepositoryProvider.createNoticeRepository()` → 真实仓储（Context 取不到时显式失败，**不回落 Mock**） |

**"界面零改动"的取证**：迁移提交 `df66e44` 的 `--stat` 里没有 `NoticesPage` /
`NoticeListStore` 之外的界面文件新增改动方向；`NoticeListStore` 只换了 import 路径，
`NoticeOrder` 只把 `parseNoticeTime` 变成再导出（实现移到 `data/notices/NoticeTime.ets`，
因为 data 层也要用它落快照时间戳）。保真项提交 `46aa84e` 才动 `NoticesPage`。

#### 2. 设备实测（模拟器）——条数与顺序

- **裸请求 403，带 `?_csrf=` 才 200**：`getCurrentAndNextSemester` 与
  `loadCourseBySemesterId` 都这样（403 是站点自己的"服务器内部错误"页，不是登录页，
  正文里没有 `login_timeout`）。**生产代码一律带 `_csrf`**，所以不受影响；
  但这条是判读未来失败的基线（ticket 08 的教训：先证明请求完备）。
- 真实链路：**2 门课 / 2 条公告**，`requests=4 failures=0`：
  - 形式语言与自动机 / 课程信息和微信群 / 赵乙宁 / 2026-09-11 11:44 / `sfqd=1`
  - 英语听说交流（A）/ Welcome message from the professor / 张为民 / 2026-09-10 13:07 / `sfqd=0`
  - 两条 `sfyd=否`（都未读）⇒ 头部"未读 2"。
- **顺序**：契约是发布时间倒序 + 同一时间 id 倒序（参考实现 `actions/notices.ts`）；
  这 2 条时间不同，界面顺序 = 时间倒序，与两个列表接口的原始顺序一致。
- **网页端对照的来源与代价（必须如实说明）**：本轮**没有登录桌面网页端**做人工比对
  （账号的重登链路只在本应用里可用）。对照用的是"站点自己的响应"——两个列表接口的
  **原始 `aaData`**（保存在 `.scratch/notices/evidence/raw/learnoh_diag.txt`），
  逐条与界面上的课程名 / 标题 / 发布者 / 时间对照一致。另外站点页面自己的
  `/b/wlxt/gg/gg_xxb/querynotetop3` **不是**同一条链路（裸 POST 200 / 带 csrf 403，
  语义是"全站 Top N"），**不要**拿它当基准。
- 证据：`.scratch/notices/evidence/`（截图 3 张 + hilog 4 份 + 原始响应/快照二进制 + README），
  按本仓库惯例**本地保留、不入库**。

#### 3. 快照三条验收

1. **写入带抓取时间与结构版本**：`snapshot save ok: chars=3145`；设备上
   `…/preferences/learnoh_notice_snapshot`。
2. **冷启动先快照再刷新**（无空白闪跳）：
   `snapshot applied: items=2 fetchedAt=1789192225900` →
   `refresh done: items=2 fetchedAt=1789192706054`（时间戳变了 = 刷新确实发生）。
3. **版本不符丢弃重建、不崩溃**：把设备上快照的 `schemaVersion` 逐字节改成 9（长度不变），
   重启后：`snapshot load: chars=3145 usable=false discard=version_mismatch:9 items=0` →
   `snapshot discarded: reason=version_mismatch:9 onDiskVersion=9 currentVersion=1 -> will rebuild` →
   重新抓取并 `save ok`，界面正常渲染同 2 条。
4. **陈旧程度**：头部 = `更新于 HH:mm:ss · <相对时间>`；冷启动先渲染快照时显示的就是上次
   抓取时间，后台刷新后时间戳前移（截图 `09-list-real-simulator.png` 的"更新于 13:58:26 · 现在"）。
   相对时间措辞取不到时只显示绝对时间（不写死英文）。

#### 4. 三处必须说明的实现选择

1. **状态图标用同色 emoji 而不是 `SymbolGlyph`**：参考实现是 MaterialCommunityIcons 的
   `attachment` / `flag` / `checkbox-blank-circle`。系统符号库的 id 不可移植（猜 id 会
   "编译通过、运行时空格"），而颜色语义（橙/红）要由令牌保证。已按 AGENTS.md 的规矩**先**在
   `docs/reference-quirks.md` 新增**第 16 条**并写明**替代验收标准**（判据是截图上的颜色与
   位置，不是"用了名为 attachment 的图标"），再改代码。
2. **未读标记改回纯蓝圆点**（`#2196f3`），删掉 ticket 03 额外加的"未读"文字——这是"保持
   与参考实现一致"的那一支，因此**没有**登记为偏离。
3. **`removeTags` 落在 `domain/render/WebViewTemplate.ets`**（渲染层），不是解析层：
   保持台账第 4 条的两层契约（解析层不解码、渲染层解码）。实体集是 `he.decode` 的高频子集
   （命名实体 + 十进制/十六进制数字实体；认不出的**原样保留**，与 `he` 对未知实体名的行为一致）。

#### 5. 解析器在真实数据上的第一处缺陷（ticket 05 的待验证项关掉一条）

站点的记录主键 `id` **不是** `ggid`，而是 `<ggid><学号>`：
`id=26ef84e8a00ef07901a0755e06e333502023011272` / `ggid=26ef84e8a00ef07901a0755e06e33350`。
参考实现的 mock 里两者恰好相同，所以 ticket 05 的夹具看不出来。已改为优先取 `raw.id`、
缺失回落 `ggid`；`url` 仍用 `ggid`（站点 `beforeViewXs` 的 `id` 参数）。单测
`usesTheSiteIdWhichIsGgidPlusStudentNumber` 钉住。其余字段（`bt` / `fbrxm` / `fbsj` /
`sfqd` / `sfyd` / `ggnr` / `jzsj`）逐项与原始响应核对一致。

#### 6. 未验证项（如实记录）

1. **公告附件（橙图标）没有真实样本**：本轮两条公告的 `fjmc` 都是 `null` ⇒
   `parseNoticeAttachment` 的 `ml-10` 与通用回退分支仍只有 ticket 05 的夹具覆盖。
   要拿真实样本需要"带附件的公告"或换学期（ticket 12）。
2. **公告是否按学期过滤未验证**：两个列表接口的请求体只有 `wlkcid`、没有学期参数，
   但"当前学期课程少 ⇒ 公告少"这条因果没有直接证据。判定需要学期切换（ticket 12）。
3. **真机未验**：全部证据来自**模拟器** Pura 90。真机（MatePad Air / API 24）转 **ticket 18**
   的一次性复验（本 ticket 原文里的"真机截图/真机显示与网页端一致"按模拟器口径完成）。
4. **`MarkedImportant` 的 `sfqd` 只见到 `"0"`/`"1"` 两种字符串**；若服务端也下发
   `"是"`，`Number('是')` 是 NaN ⇒ 会被判成不重要的。参考实现同样如此（锁定行为），故未改。

#### 7. 取样代价与工具链坑（写下来省下一次）

- 一轮探针 = 构建（20–70s）+ 安装启动（~20s）+ hilog 拉取（~30s）；本轮 4 轮探针 + 3 轮全量
  构建 + 4 轮单测，约 40 分钟设备/构建窗口。
- **`devecocli run` 在 BUILD SUCCESSFUL 之后可能长时间无输出**（实测一次 6 分钟没进安装）。
  处置：`devecocli run --skip-build` 部署已有 hap（20 秒级），或直接
  `hdc install` + `aa start`。**杀掉 run 后要显式清掉残留的 hvigor/deveco 子进程**，
  否则下一次构建会卡在 `Another build is already running`。
- **`devecocli log --keyword` 会丢 tag**：用 `--keyword 'data.notices'` 过滤时
  `data.courses` 的行**一条都不在**（差点把"课程表没取到"当成结论）。要么不加 keyword，
  要么按 `--from <时间>` 全量拉再本地筛。
- **preferences 文件是二进制 + 应用内有缓存**：改设备上的快照文件前必须 `aa force-stop`，
  否则应用会把缓存里的旧内容 flush 回去覆盖你的改动；改版本号要**逐字节等长替换**
  （`printf 9 | dd of=… bs=1 seek=<偏移> count=1 conv=notrunc`），不要用文本读写
  （会把头部字节弄坏，`dd if=… of=…` 复制时也会截断）。
- **ArkTS 的三条硬约束**在本 ticket 里连续撞了三次，值得记：`arkts-no-indexed-signatures` /
  `arkts-no-props-by-index` / `arkts-no-untyped-obj-literals` 把"用表查 HTML 实体"整条路堵死
  （`Record<string,string>` 字面量、interface 断言成 Record、`table[name]` 全部失败），
  最后只能用 `switch`；`arkts-no-structural-typing` 让 `AuthedTaskRunner` 不能直接赋给
  自定义同形接口，必须写一个一行的适配器类；`arkts-no-delete` 让测试不能 `delete` 可选字段。
- **`hilog` 单条有长度上限**：2400 字符的响应体打进去会被截断。要看全文就落到
  preferences 再 `hdc file recv`（本轮这么做才拿到两条公告的完整 `aaData`）。

#### 8. 门禁

- 单测：`Tests run: 256, Failure: 0, Error: 0`（基线 242，只加不减；新增 `NoticeRepository.test`、
  `removeTags` 五条、真实记录 id 一条）。
- `devecocli build` 全量重建 BUILD SUCCESSFUL；四个脚本 PASS/OK/PASS/PASS。
- 提交后工作区只剩未跟踪的 `.scratch/notices/`（证据目录，按惯例不入库）。

### 统筹验收（2026-09-12，模拟器口径）→ Status: verified

**结论：8 条验收在模拟器口径下全部达成，且这是本工程第一次用"真实数据"把验收判死。** 下面是我**自己**复核过的（不是转述）：

- **提交与门禁**：`df66e44`（迁移+真实源+快照）/ `46aa84e`（保真项）/ `a988fe6`（交付记录），HEAD `a988fe6`；`test_result.txt` 最后一行 **`Tests run: 256, Failure: 0, Error: 0`**（基线 242，只加）；工作区只剩未跟踪的 `.scratch/notices/`（证据目录）。
- **产物级（我自己解的包）**：hap `1,717,696 B @14:11:49` / SHA256 `B437A10D…74A23`，解开后在 `ets/modules.abc`（564,472 B）里查：`RealNoticeRepository` / `NoticeSnapshotFileStore` / `CourseListFetcher` / `snapshot discarded` / `data.notices.source` **全部命中**；`RealNoticesProbe` / `DiagLog` / `runNoticesProbe` **全部未命中** ⇒ 探针不在提交态产物里。
- **真实数据（本 ticket 的核心）**：hilog 里 `data.notices fetched courses=2 items=2 requests=4 failures=0` 在 5 次运行中逐次复现；课程 = `英语听说交流（A）` / `形式语言与自动机`；**截图 `09-list-real-simulator.png` 上就是这两条真实公告**（标题、发布者 赵乙宁 / 张为民、`昨天` / `前天`、红色重要标记 + 蓝色未读圆点、2 行正文预览），头部 `未读 2`。**相对时间是「昨天/前天」而不是 mock 的「5年前」——mock 的指纹消失，这是"真的是真实数据"最直观的一条。**
- **快照**：`snapshot applied: items=2 fetchedAt=1789192225900`（13:58:25.669）**早于** `notices refresh done: … fetchedAt=1789192706054`（13:58:26.069）⇒ 先用快照、后刷新，且时间戳前移。版本不符：把设备上快照的 `schemaVersion` 改成 9 后 `usable=false discard=version_mismatch:9 items=0` → `will rebuild` → 重建成功（`09-v9-rebuild-simulator.png` 仍是同 2 条）。
- **`_csrf` 基线**：裸请求 `status=403 bytes=2628 text/html`、带 `?_csrf=` → `200 application/json`；403 正文是站点自己的「服务器内部错误 403」页，**不是**登录页。原始行在 `.scratch/notices/evidence/README.md:25-29` 与 probe3 hilog 里。已登记为 `reference-quirks` 第 17 条。

**我唯一要加限定的地方**：验收第 5 条里的「**无空白与闪跳**」——机制（先快照、后刷新、时间戳前移）**已证**，但"没有任何一帧空白"**没有直接观测**（截图为稳定态，未录屏）。按"抓不到就写未抓到"的规矩，这一半记为**未直接观测**；不影响判 `verified`（机制才是该条判据的实质）。

**未验证项（照单收下，不阻塞）**：公告附件无真实样本（两条 `fjmc` 均 `null`）⇒ 橙图标只有夹具覆盖；"公告是否按学期过滤"需 ticket 12；真机转 ticket 18；**桌面网页端人工比对未做**——对照改用站点自身两个列表接口的原始 `aaData` 逐条比对（方法论上比"人眼看网页"更硬，但**不等价**，已如实标注）。

**账号所有者确认（2026-09-12，用户陈述）**：用户核对了界面上的公告**数量**，确认 **2 条正确**。⇒ 上面那条「桌面网页端人工比对未做」的缺口**部分关闭**：**数量**由账号所有者独立确认（这是**外部真值**，比我们的接口自比对更硬）；**顺序**仍然只有"站点原始响应逐条对照"这一层（参考实现的契约是发布时间倒序 + 同一时间按 id 倒序）。此后本 ticket 的**唯一**实质缺口只剩：公告附件无真实样本、公告是否按学期过滤、真机。

**技术债交接已确认**：`NoticeRepository` 与 `MockNoticeRepository` 已从 `features/notices/repository/` 迁到 `data/notices/`；迁移提交只改 import 与再导出、**没有为迁移改界面结构**（`NoticesPage` 的改动全部属于保真项）；`features/` 下过渡文件已删；组装点仍是一处，且**取不到 Context 时显式失败、不回落 Mock**——这条很重要：不会再出现"悄悄用 mock 顶替真实数据"而无人察觉的情况。

**一条真缺陷（ticket 05 的待验证项关掉一条）**：站点公告主键 `id` 是 `<ggid><学号>`，不是 `ggid`（`id=…333502023011272` vs `ggid=…33350`）。参考实现的 mock 里两者恰好相同 ⇒ 夹具看不出来。

### 边界说明（2026-09-12，由 ticket 11.5 带入）—— 图标由 emoji 换成同源矢量；页头改版

- **变了什么**：
  1. 公告卡片右上角三个标记由 emoji（📎 / 🚩 / 画出来的蓝点）改为**与参考实现同源的字体图标**
     （`ui/icons` 的闭集枚举：MCI `attachment` / `flag` / `checkbox-blank-circle`，颜色仍是
     `PLAIN_PALETTE.orange500 / red500 / blue500`）——这是 `docs/accepted-deviations.md` 第 16 条的改判落地；
  2. 页头由「标题 / 更新于 HH:mm:ss · N 分钟前 | 未读 n」改为「**标题 + 刚刚更新**（同一行）+ `未读 n`」，
     底色由 `#FFFBFF` 变 `#FFFFFF`（第 24/25 条）。
- **你的证据还成立到哪一步**：ticket 09 的截图（`09-list-real-simulator.png` 等）证明的是
  **真实数据（课程名/标题/发布者/相对时间/红色重要标记 + 蓝色未读标记/未读计数）**——
  这些**结论全部仍然成立**（顺序、颜色语义、计数一字未变）；当时的"判据是颜色与位置、不是形状"这半句
  **升级为"形状也要对得上"**（第 16 条改判）。旧图里的**底色**（`254,250,254`）与**页头那行绝对时间**
  不再可复现，复核旧证据时不要再拿它们当基准。
- **可观察量转移到哪里**：ticket 11.5 的逐屏对照证据（`.scratch/icons/evidence/`，一屏一对文件）
  与"公告附件图标为矢量"的补齐（本账号两条公告 `fjmc` 均为 `null`，橙图标仍只有夹具覆盖——
  这一条**仍然未闭合**，如实转 ticket 18）。

