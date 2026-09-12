# AGENTS.md

## 项目

learnOH —— HarmonyOS 原生（ArkTS / ArkUI）应用，是原 React Native for OpenHarmony 实现的重写。

 - 原始 RN 工程在 `reference/learnOH-old/`，作移植参考。

## 注意

 - 多设备时必须显式传 `--device`。当前目标设备是**模拟器** `Pura 90`（电话形态，HarmonyOS 6.1.0(23)，串口 `127.0.0.1:5555`；未启动则 `devecocli emulator start "Pura 90"`）。真机 `3FYBB25407201890`（HUAWEI MatePad Air，API 24）暂未连接。先用 `devecocli device list` 解析出确切串口再传。

 - `devecocli run` 必须作为后台作业运行。 它在应用启动后仍保持运行，直到应用退出才返回——前台调用会一直挂住。

 - **`devecocli run` 可能在 `BUILD SUCCESSFUL` 之后长时间不进安装**（实测一次 6 分钟无输出）。处置：`devecocli run --skip-build` 部署已有 hap，或直接 `hdc install` + `aa start`。**杀掉 run 之后必须显式清掉残留的 hvigor / deveco 子进程**，否则下一次构建会卡在 `Another build is already running`。

 - 构建耗时以分钟计，不要用会阻塞的短超时前台调用：把输出重定向到 `.dsh/logs/`，或作为后台作业运行。用管道（`| Select-Object`）转发 devecocli 的 stdout 会丢失 hvigor 的失败信息并让命令迟迟不返回。

 - 签名问题参见 `docs\sign.md`。

 - **验收证据口径**：日常验收在模拟器 `Pura 90` 上取证即可（串口 `127.0.0.1:5555`，HarmonyOS **6.1.0(23)**，与工程声明的 `compatibleSdkVersion` 同版本）。截图与日志按实标注来源为"模拟器"，**不要写成"真机"**。真机 `3FYBB25407201890`（MatePad Air，**API 24**）只做**最终一次性复验**，时点卡在 ticket 18（发布收尾）之前，用于覆盖"更高 API 上的向后兼容"这一层——见 `spec.md` 第 8 节。

## 并发资源（多 agent 同仓时必须遵守）

 - **构建产物与模拟器都是单例资源**，同一时刻只允许一个 agent 占用。两个 agent 同时跑 `devecocli build` 会互相覆盖 `entry/build/default/outputs/default/entry-default-signed.hap`——后者的产物会让前者已装的 app 与源码对不上；两个 agent 同时操作同一台模拟器会让 `hdc install`/点击/截图互相踩踏（已实测：一次 install 卡死 11 分钟，产物于 02:32:35 被另一 agent 的构建覆盖）。

 - **实际是两把锁，别只按"设备"分**：
   1. **构建锁**——任何 `hvigorw`（**含 `test`**）与 `devecocli build` 都会写 `entry/build` 与 `.hvigor` 缓存。**同一时刻只允许一个构建进程**：两个并发构建会互相污染产物，并给出不可信的编译/测试结果。
   2. **设备锁**——`devecocli install/run`、`devecocli ui`（截图 / layout / 点击）、`devecocli log`、任何 `hdc` 命令。同一时刻只允许一个 agent 操作设备。
   `devecocli run` 同时占两把锁（既构建又安装）。两把锁相互独立：**改代码与读文件不需要任何锁**，所以"改代码"和"占设备取证"可以真并行——这才是让多 agent 不排长队的办法。

 - **需要独占时向统筹者申请窗口**，不要在共享资源上自行重试或抢占；拿到窗口的 agent 在收尾时明确回报"窗口关闭"。

 - **多 worktree 并行：条件与代价（2026-09-13 实测，两台模拟器在线时）**

   判据是"**有独立设备**"。worktree 只隔离文件系统，不给你第二台模拟器；没有独立设备就不要开 worktree——那只是把文件冲突换成设备冲突。两台模拟器在线时，可以给每条线配一棵 worktree + 一台设备。

   - **worktree 解决的是**：每棵树有各自的 `entry/build` ⇒ **构建产物不再互相覆盖**（本文件上面记的那次"后者的产物让前者已装的 app 与源码对不上"就是这个）。
     **它不解决的是**：构建锁与设备锁仍各只有一把——每台设备同一时刻仍只允许一个 agent 取证。跨树并行的是"改代码 + 各自构建 + 各自取证"。
   - **实测（HEAD `0456055`，两棵 `--detach` worktree 同时 `assembleHap --no-incremental`）**：两棵各约 45s 且都 `BUILD SUCCESSFUL`（a `44s761ms` / exit 0，b `46s733ms` / exit 0），
     **各自起自己的 hvigor 守护进程**（各约 2s 就绪），**没有出现** `no-daemon mode`，也没有 `Another build is already running`；主树产物时间戳**未被动**。
     三份产物互异（4,259,881 / 4,259,876 / 主树 4,259,874 字节，SHA256 各不相同）= native 抖动，不是互相污染。
     ⇒ **"构建成本翻倍"要收窄**：真正重复的是 **ohpm 安装与缓存构建**的一次性成本（本仓库 `oh_modules` 仅 **0.3 MB**、`.hvigor` 15.5 MB），
     **不是每次构建的墙钟时间**——两棵并发与单棵基线（1m08s / 1m23s）相比几乎没有惩罚。
   - **签名材料不用复制**：`build-profile.json5` 的 `signingConfigs` 指向**用户级** `C:\Users\<user>\.ohos\config\` 下的绝对路径，新 worktree 天然能读到。
     （仓库里的 `keys/` 是历史遗留、未被 profile 引用；`keys/`、`.dsh/`、`oh_modules/`、`**/build` 都在 `.gitignore` 里，所以新树里不会有它们。）
   - **收尾要清两样东西**：① `git worktree remove --force <path>`；② **先杀掉该树的 hvigor 守护进程**，否则目录会因文件占用删不掉
     （现象：`failed to delete …: Permission denied`、`the file is being used by another process`）。定位方法：`Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -like '*<worktree路径片段>*' }`。
     **别误杀主树的守护进程**（按命令行里的路径片段筛，别按时间盲杀）。

   本机可用模拟器（2026-09-13；每台约 4 GB 内存 + 4 核，本机 31.5 GB / 14 核）：

   | 实例 | 形态 | 串口 | 视口 | 备注 |
   | --- | --- | --- | --- | --- |
   | Pura 90 | phone | `127.0.0.1:5555` | 电话 | 基准机 |
   | MatePad Pro 13 | tablet | `127.0.0.1:5557` | **1440×960 vp** | 平板/大屏；**跑登录前必须先放大数据分区**（见 `docs/reference-quirks.md` 第 28 条） |
   | Mate X7 | foldable | 未启动 | 折叠 345.6 vp / 展开约 1008 vp | 复用 phone 镜像，实例已铺开 |
   | MateBook Pro | 2in1 | 起不来 | — | 缺 `pc_all_x86` 镜像 |

   **多设备时必须显式传 `--device <serial>`**（`devecocli install/run/ui/log` 与任何 `hdc`）。

 - **工作区是共享的：任何"半成品"都会冻住别人的构建。** 实测过两次：ticket 05 留下 21 个编译错误挡住 ticket 03；ticket 07 给 `EnrollmentScriptSpec` 加了必填字段却没同步它的测试，挡住 ticket 08（对方 `COMPILE RESULT:FAIL {ERROR:2}`，一行自己的代码都没编到）。因此：
   - **加/改必填字段、改签名、改导出名，必须与所有构造点/调用点在**同一次编辑**里落地**——不要让工作区停留在编译不过的状态；
   - **并行只在文件与层都真正不重叠时才开。** 同一个 feature 目录（`features/auth`、`domain/auth` 之类）下的两条线应当串行；
   - 交付顺序仍是"**先让门禁全绿再交接**"；多线并行时，让**在关键路径上的那条线先提交**。

 - **改动一条已被已验收 ticket 依赖的前提时，必须在两边都留下边界说明。** 实测两次：
   1. ticket 04 给公告 tab 引入 `NavPathStack`，使 ticket 03 验收第 1 条（切 tab 保留浏览位置）的证据**早于**该改造；
   2. ticket 08 把认证门从"有凭据 = 已登记"收紧为"有凭据**且会话建起来** = 已登记"，使 ticket 07 验收第 3 条那条"合成凭据 → 重启显示已登记"的**复现路径**失效（机制证据仍有效，变的是可观察量）。
   处理方式：在**改方**与**被影响方**两个 ticket 里各写一句——说明变了什么、原证据还成立到哪一步、可观察量转移到哪个 ticket 去关。**不要悄悄改掉一个别人证据所依赖的前提。** 已验收不是"永不失效"，而是"失效时必须被记录"。

 - **取证必须可追溯到源码版本**：截图与日志要记下当时的 `git rev-parse HEAD`；若工作区是脏的，同时记下 `git status --porcelain` 的哈希。取证期间工作区被他人改动，该取证就不再对应任何提交，只能作为过程证据。

## 取证要点

 - **取证开关必须自证生效**：改掉开关值之后，把**实际生效值**打进 hilog。实测过一次：`SLOW_MOCK_FOR_EVIDENCE=true` 的构建仍按 700ms 跑（疑似增量编译/常量内联未跟上）——若只"以为开关生效了"，就会把"没抓到"误判成"现象不存在"。同理，**提交前用 `git show HEAD:<文件>` 核对开关已复原**，而不是相信自己改回来了。

 - **时间敏感的证据不要赌手速**：`devecocli ui` / `hdc` 单次调用要 15–35s，5s 的窗口必然抓不到。要抓瞬时状态就把延迟**直接改大**（ticket 03 用 30000ms）并在取证后复原，而不是去赌一个更短的窗口。

 - **`hvigorw test` 退出码 0 不代表测试跑了**：若几秒就返回、日志里没有 `Tests run`，那是命中了 up-to-date 缓存。要真跑，先删 `entry/.test` 并加 `--no-incremental`。（同一现象也适用于 `devecocli build`：产物时间戳没变就是没重新构建。）

 - **layout dump 只有 `type` / `bounds` / `children`，没有滚动偏移字段**；但因为 bounds 树覆盖列表项，两份 dump 逐字节相同**恰好是**"滚动位置未变"的正向证据——别把它误读成"dump 看不出来所以不算证据"。

 - **两个论断不能复用同一份证据**：同一张 PNG 同时充当"刷新反馈"与"刷新后"的证据，等于两个论断都没有证据。抓不到就如实写"未抓到"——重复文件比缺失更糟，因为它看起来像有证据。

 - **证据文件名里的状态标签必须与画面内容一致**（实测，ticket 12）：`B0-notices-tab-spring-final.png` 里拍的是**秋季**公告
   （未读 2、"更新于 15:09:40"、状态栏 03:10，早于同轮 15:36 的那次切换），名字却写着 `spring`。
   若不复核，后来者会拿它当"切到春季后公告 tab 也变了"的证据，从而**掩盖**"学期覆盖只作用于课程这条线"这个事实。
   规矩：① 文件名里的状态词要与画面内容对得上；② 复用一张图支撑第二个论断前，先确认它拍的是那个状态；
   ③ 发现名不符实就**在文件名附近与文档两处**标注清楚，不要静默留用。

 - **"开关自证生效"只证明开关被设上了，不证明它到达了每一条数据路径**（实测，ticket 12）：
   `aa start --ps lohSemester=2025-2026-2` 在冷启动时立刻打出 `effective="2025-2026-2"`，
   但**不去点课程 tab** 的话，数据侧仍是站点当前学期（`courses=2 requested=`）；要证明开关起作用，
   必须看到**消费点**那一行（`data.courses effective semester=… source=override`）。
   教训：自证日志要打在**消费点**（谁读它、谁用它），只在**设置点**打一行会让人误以为整条链路都生效了。

 - **`read` 工具会截断超长行：minified 文件必须用 pwsh 取全文再搜。** 实测：一个 34,992 字符的单行站点 JS（`localstorageUtil.js`）用 `read` 只回来 **4,273 字符**，据此搜「文件里有没有 `location`」会得到**假阴性**。判据：读回来的字符数与文件大小/行数对不上（8 行却只有 4 千字符）就先怀疑工具，而不是内容。检查 minified 文件或超长日志行时，用 `Get-Content -Raw` + `.IndexOf()`。

 - **未提交的诊断补丁，唯一副本就是那个 patch 文件——还原前先另存。** 实测：`git checkout --` 把当时唯一一份探针代码清掉，事后只能靠 `.dsh/logs/*.patch` 找回。规矩：① 探针代码先落成 `.dsh/logs/<ticket>-probe.patch`（`.dsh/` 已 gitignore，`git checkout` 波及不到）；② 还原前再另存一份 `.keep`；③ **工作区脏的时候不要改 `AGENTS.md`**——那次编辑被卷进补丁，又被 `git checkout` 一起清掉。
 - **在把失败归因给站点或架构之前，先证明我们自己发出去的请求是完备的。** 实测（ticket 08）：冷启动纯 HTTP 重登一直失败于「响应里没有票据」，一度被升级成「要不要改 ADR-0004」的决策；真因是 `CookieJar` 解析不了平台 `response.cookies` 的 Netscape 制表符格式 ⇒ **一个 cookie 都没入库** ⇒ POST 带着空 `JSESSIONID` 发出，服务端按「会话失效」回了一张通用报错页。教训：**在断言「站点给了奇怪的响应」之前，先把我们发了什么变成可观察量**（请求头、cookie 名与长度、表单字段），否则下游所有推断都建立在错误的前提上。

 - **`devecocli log --keyword` 会丢 tag**（实测，ticket 09）：用 `--keyword 'data.notices'` 过滤时 `data.courses` 的行**一条都不在**——差点把「课程表没取到」当成结论。要过滤就**先全量拉再本地筛**（或按 `--from <时间>`），并**先确认工具返回的是全集**。这是「取证工具本身会撒谎」的又一例。

 - **`hilog` 单条有长度上限**（实测 ~2400 字符会被截断）：要把完整响应体 / 大正文当证据，就**落到应用自己的存储再 `hdc file recv`**，不要指望一行 hilog 装得下。

 - **改设备上的二进制 / 带缓存文件前先 `aa force-stop`**：应用会把内存中的旧内容 flush 回去覆盖你的改动（实测 `preferences` 里的快照）；改定长字段要**逐字节等长替换**（`dd … bs=1 seek=<偏移> count=1 conv=notrunc`），用文本读写会把文件头弄坏。

 - **本机 `devecocli emulator` 的 scene 组命令全部不可用**（rotate / fold / power / volume / battery / sensor / geolocation / shake）：
   一律返回 `Emulator scene control commands require Emulator 7.0 or later. Current Emulator version is 6.1.1.300.`（ticket 16 逐条实测，见 `docs/reference-quirks.md` 第 31 条）。
   所以**旋转 / 折叠 / 缩放窗口 / 灭亮屏这些都别再用 CLI 试**——想改视口只有三条路：换机型（如 tablet 1440vp）、升 Emulator 到 ≥7.0、或用 **DevEco 模拟器窗口上的旋转按钮**（GUI，不在 CLI 可达范围）。
   顺带一个会骗人的现象：设备锁屏时 `devecocli ui screenshot` 可能给**竖屏尺寸的黑帧**，别把它读成“设备转到竖屏了”——先 `power-shell wakeup` 再上滑解锁后重拍。

## 门禁（提交前都要真跑）

 - **先设 `DEVECO_SDK_HOME`**，否则 hvigor 一旦重建守护进程就会失败、**一条测试都不跑**：
   `$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'`
   症状：日志里只有 `00303217 Configuration Error: Invalid value of 'DEVECO_SDK_HOME' in the system environment path` 与 `BUILD FAILED`，**没有 `Tests run`**。实测过：不设它、且守护进程因 `isNodeEnvChanged` 被重建时必现（之前几次能跑，只是因为恰好还有一个带着正确环境的老守护进程活着）。

 - 单测：`& 'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat' --mode module -p module=entry@default -p product=default test --no-incremental`。**先删 `entry/.test`**，否则命中 up-to-date 缓存 = 空跑。

 - `devecocli build`（后台作业或重定向到 `.dsh/logs/`；构建以分钟计）。

 - `node scripts/check-domain-purity.mjs` → PASS；`node scripts/check-import-graph.mjs` → PASS；`node scripts/check-i18n-keys.mjs` → `RESULT: OK`。

 - `node scripts/check-generated-fresh.mjs` → PASS。**要守的不变量**：在任何一次提交上，**重跑生成器后 `git diff` 必须为空**（生成物与生成器输入一致）。该脚本就是它的可操作形式：对 6 个 i18n 生成物取哈希 → 重跑两个生成器 → 再取哈希，**变了就 FAIL 并已就地重生**（一致时不动任何文件）。
   - 起因（实测）：两个 agent 同时改了 i18n 的生成器输入（一个 `generate-i18n-resources.mjs`、一个 `i18n-ui-strings.mjs`），生成物同时含两边的键；此时任一方只提交自己那份输入，提交点上的生成物就无法由已提交的输入复现。
   - **两个 agent 不要同时改 i18n 生成器的输入。** 若不可避免：**后提交者负责重跑生成器**；先提交者若带上对方的输入，必须在**提交信息里写明归因**。
   - 安全方向是明确的：**键已声明但没人用 = 无害；有人用但键没声明 = 编译错误**（`I18nKeys.ets` 是类型化联合）。所以"先把键声明带上"是可以接受的。

 - **不要用作业退出码判断成败**：把命令写成 `cmd *> log; ('EXIT=' + $LASTEXITCODE) | Out-File ...` 时，进程退出码会变成 **0**（最后一条是 `Out-File`）。必须读日志/产物。

 - **"看到 BUILD SUCCESSFUL"不等于编译成功**（实测，ticket 15）：引入 `@ohos/flexsearch` 做冒烟时，日志里先是
   `> hvigor ERROR: ErrorCode: 00507015 … does not provide an export name 'Document'`，**紧接着仍打印 `BUILD SUCCESSFUL`**。
   判编译成败必须搜 `ERROR`/`ErrorCode`/`COMPILE RESULT`，**不能只看最后一行**。这与上面"退出码不可信"是同一族坑。

 - **`devecocli build` 报 BUILD SUCCESSFUL 也可能是陈旧产物**（ticket 07 实测）：探针用完后把模块删掉，增量构建仍返回成功、**产物时间戳不变**，而 hap 里的 `ets/modules.abc` **仍引用已删除的模块**，装机启动即 `ReferenceError`。判定与修法：
   1. **时间戳不变 = 没重新构建**——这是必要条件，但不充分；
   2. 还需要**内容级检查**：把 hap 当 zip 解开（`Copy-Item x.hap x.zip; Expand-Archive x.zip out`），在解出来的 `ets/modules.abc` 里搜「应当消失的符号」（探针名）与「应当存在的符号」（本轮新增的桥名）。**不要直接对 `.hap` 做字节检索**——zip 条目是压缩的，搜不到不等于没有，会给出**假阴性**；
   3. 不确定时**删 `entry/build` 全量重建**，并装机后确认应用日志里启动正常——`ReferenceError` 只在运行时才会炸。

   推论（很重要）：**"我把开关翻回 false / 把探针删了，并重新构建过"不是证据**。取证态到提交态的转变必须给出**产物级或视觉级**证据（产物内容检索，或一张提交态界面截图），否则可能验的是上一个产物。

 - **`check-import-graph.mjs` 为什么存在（实测）**：`data/upload/UploadForm.ets` 从 ticket 05 起就 import 了不存在的 `../../domain/parse/Multipart`（真身在 `data/upload/Multipart.ets`），而 ticket 05 的 `devecocli build` 与 116 条单测**全绿**。原因是 **ArkTS 的编译按入口可达性进行**：没有任何可达者 import 的模块**不会被编译**，其中的硬错误（含无法解析的 import）不会让任何门禁变红。直到 ticket 06 第一次 import 它才暴露。
   因此：**新交付的模块必须至少被一条可达路径（应用入口或某个测试）import**，否则它的"编译通过"是没被验证过的。该脚本会 FAIL 掉不可解析的相对 import，并 WARN 列出**孤儿模块**（没有任何可达者 import 的 main 源文件）——入口文件出现在该列表属正常，**其余任何文件出现在那里，就意味着它从未被编译过**。

## 移植时的硬约束

 - **改参考实现的"怪癖"之前，先读 `docs/reference-quirks.md`**。它现在是**约束清单**：只放**仍然生效**的条目（`锁定`／`待查`／【平台事实】／【站点事实】），每条带源文件行号与"为什么别急着改"。**移植的完成定义是与参考实现行为一致**——顺手"修好"它会让行为偏离，并让验收失去可比对的基准。
 - **已复审的偏离不在那张表里**：某条一旦被复审并**批准偏离**，它的正文就迁到 **`docs/accepted-deviations.md`**（**编号沿用原编号**，旧引用按号仍能找到；quirks 里只留索引一行）。那个文件**不再阻止改动** —— 它是变更记录与"替代验收标准"的出处，别拿它当约束；也别把 `锁定` 就地改成 `已复审` 继续留在 quirks 里（那会让约束清单重新混进历史）。
 - 要偏离某一条时：**先写明理由与替代验收标准**，复审通过后把该条**迁到 `docs/accepted-deviations.md`**（保持编号），再改代码。只改代码不改表，等于隐式推翻决策。

## Agent skills

### 问题跟踪

本仓库的 issue 和 spec 以 Markdown 文件形式存放在 `.scratch/<feature-slug>/` 下。参见 `docs/agents/issue-tracker.md`。

### 领域文档

单上下文（single-context）：仓库根目录一份 `CONTEXT.md`，外加 `docs/adr/`。参见 `docs/agents/domain.md`。
