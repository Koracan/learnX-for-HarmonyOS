# 19: 导出日志改到「用户拿得到」的公共区域

**What to build:** 账号所有者第四轮反馈（2026-09-13）：

> 现在导出日志的保存位置是 `/data/storage/el2/base/haps/entry/files/logs/xxx.log`，这在应用沙盒之内，不方便用户拿到。
> 应该改为向系统申请公共区域。

现在的落点是应用私有沙箱（`context.filesDir`），**应用外部**（文件管理 / `hdc file recv`）拿不到；用户即便在界面上看到路径也没有用。
本 ticket 把导出目标改到**公共目录**（或由系统文件选择器让用户挑位置），并且**必须用应用外部的证据**证明文件真的落在那里。

**Blocked by:** None（可立即开始）

**Status:** verified

**判据**

A. 目的地
- [ ] 导出文件落在**应用外部可读**的位置。优先路线：`@kit.CoreFileKit` 的 `Environment.getUserDownloadDir()` / `getUserDocumentDir()`
      ＋ `module.json5` 声明 `ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY`（或 `..._DOCUMENTS_DIRECTORY`）＋ 运行期申请。
      备选路线：`@ohos.file.picker` 的 `DocumentViewPicker.save()`（用户选位置，无需权限）。
      **先用设备实测确认哪条在这台机器上真能走通**，再动手；两条都试过就写清哪条不行、为什么。
- [ ] **决定性的外部可见性证据**（这条是本 ticket 的核心）：设备上点一次「导出日志」后，
      ① 用 `hdc -t <dev> shell ls -l <公共目录>` 列出该文件（给出原始输出）；
      ② `hdc file recv` 把它取回本地，核对**首行 `learnOH 日志导出`**、文件字节数、以及界面/hilog 里的记录数与字节数**三者一致**。
      注意：**shell 用户能不能列出那个目录本身也是一条要记录的事实**（上一轮「沙箱读不到」就卡在这里）。
- [ ] 权限声明进 `entry/src/main/module.json5` 的 `requestPermissions`（这是**权限声明**，不是设备级永久设置，允许改）。
- [ ] **降级必须显式**：权限被拒 / 永久拒绝 / 公共目录不可写 / 平台不支持时，**不许假装导出成功**。
      要么明确失败（提示里给原因），要么明确「已导出到应用私有目录，外部拿不到」并保留沙箱兜底 —— 选哪种由你定，
      但**界面文案与 hilog 必须能区分这两种结局**。永久拒绝时提示里要告诉用户去哪开权限。
- [ ] **用户取消选择**（走 picker 时）：不得报成失败（那是用户意图），也不得报成成功；给一条中性提示。

B. 界面与文案
- [ ] 成功提示继续给出**确切路径**（ticket 18 已把 `ui_exported` 改成带 `{2}` = 路径，Toast 与设置页列表下方那一行都用它）。
      若新增/调整文案，走 `scripts/i18n-ui-strings.mjs` 并重跑 `node scripts/generate-i18n-resources.mjs` + `node scripts/gen-i18n-keys.mjs`，
      **生成物与生成器输入放进同一次提交**（`check-generated-fresh.mjs` 验这件事；同步更新 `entry/src/test/I18n.test.ets` 的断言）。
- [ ] 设置页那一行的位置提示（ticket 18 加的常驻行）在新方案下要**跟着变**：不能还留着沙箱路径。

C. 单测
- [ ] 把「目标目录怎么选 / 怎么降级」做成**可注入的纯逻辑**（输入示例：公共目录可用性 + 权限授予状态 + 宿主文件目录 + 时间戳；
      输出：写入目标 + 结果类别 + 给用户的路径文案），单测钉住成功 / 拒绝 / 不支持 / 用户取消四条。
      **不要在单测里碰平台 API**（沿用本仓库「端口注入」的口径，见 `entry/src/test/LogFormat.test.ets` 同族测试）。
- [ ] 既有 `LogBuffer` / `LogFormat` 的单测不许退化。

D. 门禁与纪律
- [ ] 单测 + `assembleHap` + 四个脚本，**全部在你这棵树里跑**（见文末「构建 / 门禁环境」）。
- [ ] 不点「退出登录」、不改设备级永久设置（语言 / 分辨率 / 密度 / 时区）、不动 `.scratch/migration/**`、
      **不提交图片**（帧 / dump / 日志只留本地）、不把台账或 ticket 编号写进代码注释。

**派单情报（统筹者初查，均需你自己复核）**
- 现状落点：`core/log/LogBuffer.ets` 的 `exportLogs(context, buffer?)` 写 `context.filesDir + '/logs/learnOH-' + Date.now() + '.log'`，返回 `{ path, byteLength, recordCount }`；
  唯一调用点是 `features/settings/SettingsPage.ets` 的 `handleExportLogs()`（ticket 18 已把 path 显示出来）。
- SDK 证据（我读的，未实测）：
  - `<sdk>/default/openharmony/toolchains/lib/PermissionDefinitions.json:4962` = `ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY`：
    `grantMode: user_grant`、`availableLevel: normal`、`since: 11`（`:4974` 是 DOCUMENTS 同款）⇒ **普通应用可以声明并申请**。
  - `<sdk>/default/openharmony/ets/api/@ohos.file.environment.d.ts:26-89`：`getUserDownloadDir()` / `getUserDocumentDir()`；
    注意 API 11 的重载标了 `@permission`，而 **since 12 的重载没标** —— 实际要不要授权、授权后能不能写，**必须实测**。
- 参考实现（RN）**没有**日志导出功能（本工程增补）⇒ 这里没有「参考实现口径」；唯一标准是「用户在设备上拿得到这个文件」。
- 上一轮（ticket 18）留下的缺口正好由本 ticket 关掉：当时**无法**独立核实「导出文件真的落盘」，因为沙箱 shell 读不到
  （`hdc shell ls` / `hdc file recv` 返回 `No such file or directory`）。本 ticket 的外部可见性证据就是那条缺口的解药。
- 模拟器上权限弹窗可能是**系统 UI**：用 `devecocli ui layout` 取坐标再点（不要目测）；若确实点不到，如实记录并给出替代取证。
- 公共目录在这台模拟器上长什么样：先 `hdc -t <dev> shell ls -l /storage/Users/currentUser` 看一眼（shell 用户可见性本身也要记）。

**你的资源（独占，别人不得碰）**
- worktree：`D:\\Koracan\\source\\harmony\\learnOH-wt\\t19`（分支 `wt/t19`，基于 main `0c6351c`）。
  `ohpm install` 与 `reference/` 目录联接**已由统筹者做好**。**只在这棵树里改与构建，主树不要动。**
  开工前、每次构建前、每次取证前都 `git rev-parse --show-toplevel` 自证。
- 设备：`127.0.0.1:5557`（`hdc` 实测 `devicetype=phone`，**这台只有你用**；`devecocli device list` 会把它报成 Pura 90，别信那列）。
- i18n：本轮**只有你这一条线**在改 i18n 生成物的输入（ticket 17/18 已合并），没有并发写者。

**构建 / 门禁环境（照做，别自创）**
1. `$env:DEVECO_SDK_HOME='C:\\Program Files\\Huawei\\DevEco Studio\\sdk'`（不设会出现 `Configuration Error: Invalid value of 'DEVECO_SDK_HOME'` 且**一条测试都不跑**）。
2. hvigor 入口：`C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat`（不在 PATH 上）。构建以分钟计，用**后台作业**跑并重定向到 `.dsh/logs/`。
3. 单测：先删 `entry/.test`，再 `test --no-incremental`；判据是 `entry/.test/default/intermediates/test/coverage_data/test_result.txt` 里的 `Tests run:` 行 **+ 该文件的时间戳是本轮的**（基线：合并后的 main 上是 **441** 条）。
4. 打包：`assembleHap --no-incremental`，然后搜 `ERROR` / `ErrorCode` / `COMPILE RESULT`，不能只看 `BUILD SUCCESSFUL`。
5. 四个脚本：`node scripts/check-domain-purity.mjs`、`check-import-graph.mjs`、`check-i18n-keys.mjs`、`check-generated-fresh.mjs`。
6. 指纹：**不要用 hap 文件 SHA256**；要比就解包比 `ets/modules.abc` 的 SHA256（且只在同一棵树内可比）或用内容级检索。
7. 新增权限会不会影响装机/启动（`bm dump` 里的 `reqPermission` 列表）：装完自己核一眼。

**报告要求**：结论先行；每条论断配**一个**证据（file:line、`ls -l` 的原始输出、`file recv` 的字节数/首行、hilog 时间戳）；
做不到的如实写「没做到 / 存疑」；在 `.scratch/ui-optimize/issues/19-export-logs-to-public-area.md` 追加 Comment，
过程证据写进 `.scratch/ui-optimize/evidence/19-<slug>.md`（可提交），图片只留本地。
收尾必须回报「**窗口关闭**」并说明设备与工作区状态（权限状态、是否在公共目录里留了测试文件、工作区是否干净）。


## Comments

### 实现 Comment（wt/t19 @ 0c6351c 之上，未提交前记录）

**结论：优先路线（`Environment.getUserDownloadDir()` + 公共目录直写）在这台设备上走得通，没有换 picker 路线。**
过程证据：`.scratch/ui-optimize/evidence/19-export-logs-to-public-area.md`。

1. **落点已改**：导出目标是 `Environment.getUserDownloadDir()` 返回的公共「下载」目录
   （应用侧是 `/storage/Users/currentUser/Download`），文件名仍是 `learnOH-<时间戳>.log`；
   应用私有目录只作为**显式降级**的兜底（`filesDir/logs`，形状与旧落点一致）。
   `module.json5` 已声明 `ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY`（含 reason / usedScene），
   装完 `bm dump` 的 `reqPermissions` 里看得到。
2. **权限实测与派单情报不同，值得记一笔**：这台 API 23 模拟器上
   `requestPermissionsFromUser` 返回 `authResults=[2]`（"请求无效"，**不是** -1"用户拒绝"），
   `dialogShown=true` 但**系统弹窗一次都没出现**，`errorReasons=[0]`（与 authResults 自相矛盾，未解释）。
   **公共目录在这台设备上无需授权即可直写** —— 实测一次导出成功落盘。
   ⇒ 我没有把"权限不受理"当成失败：`LogExportTarget.publicDirUsable` 只在**用户明确拒绝（-1）**或路径不可用时才放弃公共目录，
   "不受理"放行、由**真的写一次**来判定（写不进去才降级，且把平台原话写进原因）。
3. **外部可见性证据（本 ticket 的核心）四路对齐，全 True**：
   界面常驻行 / hilog / `hdc shell ls -l /storage/media/100/local/files/Docs/Download` / `hdc file recv`
   都是 **90 条、15464 字节、`learnOH-1789297382281.log`**；取回文件首行 `learnOH 日志导出`、
   第三行 `记录数: 90/500`。`ls -l` 原始输出：
   `-rw-rw---- 1 20001006 file_manager 15464 2026-09-13 19:03 learnOH-1789297382281.log`
   （属主是 file_manager 一族的 uid，不是应用沙箱 uid `20020062` ⇒ 确实在共享公共目录里）。
   顺带纠正一处旧结论：`byteLength` 以前报的是字符串长度（15170），与 `ls -l` 对不上；
   现在报 `statSync` 的真实字节数（15464），四处才可能一致。
4. **shell 可见性分三件事记**（判据点名要记）：应用看到的 `/storage/Users/currentUser/Download`
   在 shell 下 `No such file or directory`；它的物理落点（公共目录本体）`ls -l` 列得到；
   ticket 18 查的 `/data/storage/el2/base/haps/entry/files/logs` 形态也不存在。
   ⇒ 界面路径与 shell 能列的路径本来就是两套名字，这解释了 ticket 18 的"沙箱读不到"。
5. **降级必须显式**：`LogExportTarget.ets` 把结局分成
   成功 `ui_exported` / 私有降级 `ui_export_private_{denied,blocked,unsupported,unwritable}` /
   失败 `ui_export_failed` / 用户取消 `ui_export_cancelled`；四条降级文案都写明
   "文件在应用私有目录内，文件管理器里看不到"并给出各自原因（权限被拒时告诉用户去哪开）。
   新增 5 条 i18n（生成物与生成器输入同一次提交），`I18n.test.ets` 的键数断言同步到 318。
6. **门禁**（都在本树里跑）：单测 `Tests run: 452, Failure: 0, Error: 0, Pass: 452, Ignore: 0`
   （test_result.txt mtime 19:01:18 = 本轮；基线 441 ⇒ +11 条，都在新增的 `LogExport.test.ets`）；
   `assembleHap --no-incremental` BUILD SUCCESSFUL 且 ERROR/ErrorCode/COMPILE RESULT = 0；
   四个脚本全绿（i18n RESULT: OK，manifest 318）。产物指纹（同树可比）：
   解包 `ets/modules.abc` SHA256 = `AA5A52F977A7C9249C5F14F8894A2B3462B388F397F186061FABC0B087ECADF0`。
7. **没做到 / 存疑**：
   - 交付构建上**没能在设备上重放"降级"那一幕**（这台设备直写成功，降级没有自然触发条件；
     为它加取证开关要 3 次构建，判断不值当）。现有降级帧来自 18:59 的**中间构建**，
     且那一版把"不受理"误当"被拒绝"；交付版的降级判据是单测（11 条里 6 条钉结局与文案键）。
   - **"应用私有沙箱外部拿不到"这个前提被实测推翻**：用物理路径
     `/data/app/el2/100/base/<bundle>/haps/entry/files/logs` 时，shell **列得到也 recv 得到**；
     `/data/app/el2/100/base/com.koracan.learnOH` 实测是 `drwxrwxrwx`（应用是 hdc 装的 debug HAP）。
     shell 本身没有特权（`uid=2000`、`CapEff=0`，读别的应用沙箱是 `Permission denied`）。
     机制只解释到一半（`…/haps/entry/files` 是 `drwxrwx---` 却仍可读），留作存疑。
     ⇒ 本 ticket 的判据因此落在**落点在不在公共目录**（属主 uid 与路径两处都变了），
     而不是退化成"hdc 列得到"。
   - 英文侧文案未取帧；真机（API 24）上的权限行为未验；`authResults=[2]` 的成因未定案。
8. **设备与工作区状态**：公共目录里留了 **1 个** 测试文件
   `/storage/media/100/local/files/Docs/Download/learnOH-1789297382281.log`（15464 B，故意留给复核者自查）；
   应用私有目录另有 4 个历史导出文件未清；设备权限状态未做任何永久修改
   （`READ_WRITE_DOWNLOAD_DIRECTORY` 仍是"已声明未授予"）；未点过退出登录，未动语言/分辨率/密度/时区；
   主树未动，未 merge / rebase / push。

### 复核 Comment（统筹者，merge `fade90a`）

**结论：通过。** 四条判据（A 目的地 / B 外部可见 / C 降级显式 / D 门禁与纪律）由**我自己**重做一遍，
不采信实现者自报；下面每个数字都来自我这一轮的原始输出。

**我独立重做的那一次导出**（不依赖实现者留下的文件）：关闭前 5557 的公共目录里只有实现者的 1 个文件
（`learnOH-1789297382281.log`，15464 B，19:03）。我在设置页自己点了「导出日志为文本文件」，`ls -l` 前后对照：

    before: total 20480 -> 1 个文件（19:03）
    after : total 45056 -> + -rw-rw---- 1 20001006 file_manager 17082 2026-09-13 19:09 learnOH-1789297754146.log

- **落点在公共目录**：属主 uid `20001006`（file_manager 一族）≠ 应用 uid `20020062`；同一时刻应用私有目录
  `…/haps/entry/files/logs` 仍是原来 4 个文件、时间戳未变 ⇒ 这次成功没有落到私有目录。
- **四路一致**（界面 / hilog / `ls -l` / `file recv`）：界面常驻行与 Toast 都是 `已导出 98 条 / 17082 字节`
  ＋ `保存位置：/storage/Users/currentUser/Download/learnOH-1789297754146.log`；`file recv` 17082 B，
  首行 `learnOH 日志导出`、第三行 `记录数: 98/500`；hilog `core.log.export`：`probe state=available`
  → `authResults=[2] dialogShown=true errorReasons=[0] effective=not-requestable` → `plan outcome=exported-public`
  → `wrote file … textLength=16766 writeSync=17082 statSize=17082`。
- **字节数那处旧缺陷被独立证实**：同一份文本 `charLength=16766`，落盘 `17082` —— 旧实现报 `text.length`，
  界面会显示 16766 而 `ls -l` 显示 17082；现在界面 / hilog / `ls -l` / `recv` 四处同为 17082。
- **权限弹窗没有出现**（19:09 的帧里只有 Toast），与 `authResults=[2]` 吻合：这条路线在本机无需授权即可直写。

**对上一轮一处前提的纠正（与 ticket 18 的残留相关）**：本机实测 shell（`uid=2000`，属组含 `file_manager`）
用物理路径 `/data/app/el2/100/base/com.koracan.learnOH/haps/entry/files/logs` **列得到**应用私有目录里的 4 个
历史导出文件；而 `/data/app/el1/bundle/public/com.koracan.learnOH`（装好的 hap）是 `Permission denied`。
⇒ 我此前「应用私有沙箱在 hdc 里看不到」的说法不成立；能站住的判据是**落点在不在公共目录**（路径 + 属主 uid 两处都变），
本 ticket 用的正是这个。对**用户**而言，「私有降级时文件管理器里看不到」仍然成立。

**门禁（两处都是我自己跑的）**：
- 工树 `wt/t19`（HEAD `b7817dd`）：`Tests run: 452, Failure: 0, Error: 0, Pass: 452, Ignore: 0`，
  test_result.txt mtime 19:08:37；`assembleHap --no-incremental` BUILD SUCCESSFUL ×1，ERROR / ErrorCode / COMPILE RESULT = 0；
  四脚本 PASS / PASS / RESULT: OK / PASS；解包 `ets/modules.abc` SHA256 `AA5A52F9…`、1840928 B —— 与实现者自报逐字一致。
- 合并后主树 `fade90a`：`Tests run: 452 …`（mtime 19:10:47），assemble 同样 BUILD SUCCESSFUL 且 0 错误，四脚本全绿，`git status` 干净。
  （跨树的 `modules.abc` 指纹不可比是本工程已知口径，这里只用来证明「同一棵树内实现者与复核者跑出同一个产物」。）

**合并过程**：唯一冲突是本 ticket 文件（add/add）—— 两侧前 78 行是同一份派单正文，工树在其后追加了实现 Comment；
取工树版本，与合并前主体的差异是 `60 insertions, 1 deletion`，那 1 行删除是文件末尾「无换行符」的那一行本身（文本保留）。

**接受的残留（不阻塞收口）**：
1. 降级那一幕在本机**没有自然触发条件**（直写总是成功），交付版的降级判据是 11 条单测里的 6 条；
   实现者在 18:59 的**中间构建**上拍过降级帧，但那一版把「不受理」误当「被拒绝」，不能当作交付版的证据。
2. `authResults=[2]` 与 `errorReasons=[0]` 自相矛盾未解释；真机（API 24）的权限行为未验；英文文案未取帧。
3. 装好的 hap 取不到（`/data/app/el1/bundle/public/…` shell 无权限 ⇒ 无法用哈希把设备产物钉到源树）；
   本轮产物身份由**只有新代码才会打的 hilog 标签**（`core.log.export` / `log export reported:`）与**新落点**共同确立。
4. 小 nit：`LogExportFallback.NO_PRIVATE_DIR` 的 reason 是英文硬编码（平台错误串同样原样透出），
   但该分支只在 `filesDir` 为空时才会走到，实践中不可达。

**我复核后的设备与工作区状态**：5557 上我取回并删除了公共目录里的 **2 个**测试文件
（现在 `/storage/media/100/local/files/Docs/Download` 为空；两份文件已存到本地证据目录 `orchestrator-round4/`）；
应用私有目录 4 个历史文件未清；未点退出登录，未改任何永久设置；设备锁已释放。
主树 `fade90a`，工作区干净，领先 `origin/main` 62。

### Comment（2026-09-13 晚）：落点改走系统文件选择器 —— 解 AGC 的 ACL 上传阻塞

**结论先行**：AGC「上传产品」报的 `ACL permission consistency` 已消除。包里不再请求
`ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY`（装机后 `bm dump` 与交付产物解包后的 `module.json` 都**只剩 `INTERNET`**），
`node scripts/check-release-profile.mjs` → `RESULT: OK`。导出改走 `DocumentViewPicker.save()`：用户自己挑位置，
应用侧不需要任何权限 —— 这正是本 ticket 判据 A 里写明的备选路线。

**为什么非改不可**：那条权限是**受 ACL 限制**的权限，而发布 Profile（`keys/learnOHRelease.p7b`）的
`acls.allowed-acls` 是空的；工具链本地不查这条，只有 AGC 侧拦。先试过 AGC 那条路（申请受限 ACL 权限 +
重新生成发布 Profile），下载回来的 `keys/learnOH-2Release.p7b` 仍是 `allowed-acls: []` ⇒ 改成把权限从包里去掉。

**设备实测（模拟器 `Pura 90` / `127.0.0.1:5555` / hdc 实测 `phone` + API 23；真机没碰）**：

- 选 `Download` 保存 ⇒ 文件在 `/storage/media/100/local/files/Docs/Download`，属主 `20001006`（file_manager 一族，不是应用沙箱 uid）；
  界面 / hilog / `ls -l` / `file recv` **四处一致**（48 条 / 6481 字节 / `learnOH-1789307405990.log`，首行 `learnOH 日志导出`）。
- 取消 ⇒ `[picker] resCode is -1` → `state=cancelled`、`[ui.toast] text=已取消导出`；公共目录与私有兜底目录**都没有多出文件**。
- 副产品：模拟器上 `install -r` 报过 `9568332 install sign info inconsistent`（原装那份是 09-11 那批 debug 材料签的，
  `appIdentifier` 不同）；`uninstall` 后重装通过。日后换签名材料的调试装机可能再遇到。

**门禁**（主树，取证件与提交态都在同一棵树）：单测 `Tests run: 455, Failure: 0, Error: 0, Pass: 455, Ignore: 0`
（mtime 22:03:38，**改回取证开关之后**重跑）；`assembleHap`（release 签名）`BUILD SUCCESSFUL` 且 `ERROR`/`ErrorCode`/`COMPILE RESULT` 0/0/0；
四脚本全绿；`check-release-profile` OK。i18n 降级文案 4 → 3 条、键总量 318 → 317（生成物与生成器输入同一次改）。

**过程证据**：`.scratch/ui-optimize/evidence/19-export-logs-to-public-area.md` 的「追加（2026-09-13 晚）」一节；
帧在 `.dsh/logs/picker-frames/`（本地，不入库）。**没做到**：真机（API 24）未验；带 Toast 的帧来自取证构建。
