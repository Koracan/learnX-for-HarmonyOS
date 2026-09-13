# ticket 19 证据：导出日志改到「用户拿得到」的公共区域

- 树：`wt/t19` @ `D:/Koracan/source/harmony/learnOH-wt/t19`（开工前、每次构建前、每次取证前都跑
  `git rev-parse --show-toplevel`，输出始终是这一条）。
- 基线：`0c6351c`（main，已并入 ticket 17 / 18）。取证期间工作区是**脏的**（本轮改动 16 项，见文末），
  所有帧与日志对应的都是**同一份未提交源码**编出的交付构建。
- 设备：`127.0.0.1:5557`，hdc 实测 `const.product.devicetype=phone`、`const.ohos.apiversion=23`；
  `hdc shell id` = `uid=2000(shell) gid=2000(shell) groups=…,1006(file_manager),1007(log),…`。
- 交付构建：`assembleHap --no-incremental` → `.dsh/logs/t19-assemble2.log`（`BUILD SUCCESSFUL` × 1，
  `ERROR` / `ErrorCode` / `COMPILE RESULT` 各 0）；hap mtime **2026-09-13 19:01:33**、5164157 B。
- 交付产物指纹：解包后 `ets/modules.abc` 的 SHA256 = `AA5A52F977A7C9249C5F14F8894A2B3462B388F397F186061FABC0B087ECADF0`
  （1840928 B；**同树内可比**，hap 文件哈希不用）。装机用同一份 hap。
- **图片 / dump / hilog 只留本地**（`.dsh/logs/t19-frames/`、`.dsh/logs/t19-recv/`、`.dsh/logs/t19-hilog-0*.txt`，
  `.dsh/` 已 gitignore）。本文件只写文字论断 + 本地文件名 + 原始输出。

## 结论先行

**优先路线（`Environment.getUserDownloadDir()` + 运行时申请 `READ_WRITE_DOWNLOAD_DIRECTORY`）在这台设备上走得通**，
但走通的方式与派单情报的猜测不同：**那一次运行时权限申请根本没被平台受理**（`authResults=[2]`「请求无效」），
而公共目录**本来就写得进去** —— API 12 起 `getUserDownloadDir()` 的重载不再标 `@permission`，
实测这台 API 23 设备上**无需授权即可直写**。因此落点直接改成了公共「下载」目录，
**没有**走 picker 路线，用户不需要多点一次。

文件真的落在公共区域，且是**从设备外部**核实的：`hdc shell ls -l` 列得到、
`hdc file recv` 取回来 15464 字节、首行 `learnOH 日志导出`、头部 `记录数: 90/500`，
与界面/hilog 的 90 条 / 15464 字节四处逐字一致（下面论断 3 的六项 CHECK 全 True）。

## 论断 ↔ 证据（一条论断一个证据）

### 论断 1｜导出文件落在**应用外部可读**的公共「下载」目录，且从设备外部列得到

- 设备侧：点一次设置页的「导出日志」后（`06-export-public.png`），
  `hdc -t 127.0.0.1:5557 shell ls -l /storage/media/100/local/files/Docs/Download` 原始输出：

      total 20480
      -rw-rw---- 1 20001006 file_manager 15464 2026-09-13 19:03 learnOH-1789297382281.log

  同一个目录在**文件管理器视角**下也看得到（`/mnt/user/100/currentUser/filemgr/Download` 是同一份内容）：

      total 20480
      -rw-rw---- 1 20001006 file_manager 15464 2026-09-13 19:03 learnOH-1789297382281.log

- 写入前该目录是空的（`total 0`，装机后立即记录），所以这一条文件必然来自本次导出。
- 所有权值得记一笔：文件属主是 `20001006`（file_manager 一族的 uid），**不是**应用沙箱里的应用 uid
  `20020062` —— 说明它确实写到了共享的公共目录，而不是应用私有沙箱的另一个视图。

### 论断 2｜文件内容确实是我们导出的日志（不是同名空壳）

- `hdc -t 127.0.0.1:5557 file recv '/storage/media/100/local/files/Docs/Download/learnOH-1789297382281.log' .dsh/logs/t19-recv/learnOH-1789297382281.log`
  → `FileTransfer finish, Size:15464`，本地文件 15464 B。
- 取回后的头四行与末行：

      line0=learnOH 日志导出
      line1=导出时间: 2026-09-13 19:03:02.280
      line2=记录数: 90/500
      line3=------------------------------------------------------------
      lastNonEmpty=2026-09-13 19:02:29.494 INFO  [features.shell.pageshown] page shown: source=tab-change:4 at=1789297349494 previousAt=1789297349401

  首行是 ticket 判据点名的 `learnOH 日志导出`；末行是应用自己的 hilog 记录（同一时刻 19:02:29），
  说明写出去的就是应用内存缓冲里的那批记录。

### 论断 3｜界面 ↔ hilog ↔ `ls -l` ↔ 取回字节数**四处一致**（判据 A 的「三者一致」）

判据脚本（`.dsh/logs/t19-frames/06-export-layout.json` 的 dump 文本、`.dsh/logs/t19-hilog-02.txt`、
`ls -l`、取回文件）四项对齐后的原始输出：

    UI   : records=90 bytes=15464 path=/storage/Users/currentUser/Download/learnOH-1789297382281.log
    hilog: outcome=exported-public destination=public records=90 bytes=15464 path=/storage/Users/currentUser/Download/learnOH-1789297382281.log
    ls -l: name=learnOH-1789297382281.log bytes=15464
    recv : bytes=15464 firstLine='learnOH 日志导出' header='记录数: 90/500'
    CHECK path.ui==path.hilog      : True
    CHECK basename.ui==ls.name     : True
    CHECK records ui==hilog        : True
    CHECK bytes ui==hilog==ls==recv: True
    CHECK firstLine==learnOH       : True
    CHECK header==90/500           : True

- 界面那两行来自常驻行（toast 消失后仍在屏幕上）：`06-export-public.png`（帧）+
  `06-export-layout.json` 里那个节点 `bounds=[0,2278,1320,2467]`，文本完整为
  `已导出 90 条 / 15464 字节\n保存位置：/storage/Users/currentUser/Download/learnOH-1789297382281.log`。
- 注意 `byteLength` 报的是**落盘后的 statSync 字节数**（15464），不是字符串长度（15170）：
  这条 hilog 行同时给出两者 —— `textLength=15170 writeSync=15464 statSize=15464`。
  旧实现报 `text.length`（15170），与 `ls -l` 对不上；本轮把它改成真实字节数，四处才可能一致。

### 论断 4｜落点与权限的真实行为（决定"优先路线"能不能走）

原始 hilog（`.dsh/logs/t19-hilog-02.txt`，`devecocli log --from 4m --tail 40000` 先全量拉再本地筛）：

    09-13 19:03:02.286 … [core.log.export] log export probe: state=available path=/storage/Users/currentUser/Download error=
    09-13 19:03:03.413 … [core.log.export] log export permission: name=ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY authResults=[2] dialogShown=true errorReasons=[0] effective=not-requestable
    09-13 19:03:03.413 … [core.log.export] log export after permission: permission=not-requestable state=available path=/storage/Users/currentUser/Download error=
    09-13 19:03:03.413 … [core.log.export] log export plan: outcome=exported-public destination=public fallback=none dir=/storage/Users/currentUser/Download path=/storage/Users/currentUser/Download/learnOH-1789297382281.log
    09-13 19:03:03.416 … [core.log.export] log export wrote file: path=/storage/Users/currentUser/Download/learnOH-1789297382281.log textLength=15170 writeSync=15464 statSize=15464
    09-13 19:03:03.418 … [core.log.export] log export done: outcome=exported-public destination=public fallback=none …
    09-13 19:03:03.420 … [features.settings] log export reported: outcome=exported-public destination=public … records=90 bytes=15464

- `authResults=[2]`：按 `@ohos.abilityServices.PermissionRequestResult` 的说明，2 = 「请求无效」，
  **不是**「用户拒绝」（拒绝是 -1）。这台设备上权限弹窗**一次都没出现**
  （`06-export-public.png` 与 `04-permission-dialog.png` 都没有系统弹窗），
  界面在点击后**直接**显示导出成功。
- 佐证"权限没用上也不影响写"：`hdc shell bm dump -n com.koracan.learnOH` 的 `reqPermissions`
  里有 `ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY`（声明进去了），
  但 `reqPermissionStates` 里它**没有**被授予 —— 文件照样写成功。
- 结论：**优先路线成立，代价是那次权限申请是空转的**（19:03:02.286 → 19:03:03.413，约 1.1 s）。
  这一秒没有白留：`LogExport.ets:94` 在受理结果不是"用户拒绝"时返回 `not-requestable`，
  `LogExportTarget.ets:138 publicDirUsable` 对它放行、由**真的写一次**来判定可行性；
  真正被用户拒绝（-1）时仍然直接降级，不去写。
- 为什么保留那条申请：ticket 明确要求"优先路线：… ＋ 模块声明 ＋ 运行期申请"，
  且换一台设备/换一个 API 版本时该权限可能真的会被受理（那时 GRANTED 分支才有意义）。

### 论断 5｜降级是**显式**的：两种结局的文案不可能被读成同一个

- 纯逻辑证据（离线、可复算）：`entry/src/main/ets/core/log/LogExportTarget.ets`
  的 `planLogExport`（:182）把成功与降级分成两套键 —— 成功用 `ui_exported`（三占位符，
  仍是 ticket 18 那条"已导出…保存位置"），降级按原因分别用
  `ui_export_private_denied` / `ui_export_private_blocked` / `ui_export_private_unsupported` /
  `ui_export_private_unwritable`，四条**都额外写清"文件在应用私有目录内，文件管理器里看不到"**；
  彻底无兜底时用 `ui_export_failed`；用户取消用中性的 `ui_export_cancelled`。
  四条分支由 `entry/src/test/LogExport.test.ets` 逐条钉住（见门禁表：单测 452 全绿）。
- 设备侧证据（**中间构建**，见"没做到"第 1 条）：`.dsh/logs/t19-frames/04-permission-dialog.png`
  是同一台设备、同一入口在 18:59 那一版上渲染出的降级文案，屏幕上完整三行：

      已导出 90 条 / 15464 字节
      保存位置：/data/storage/el2/base/haps/entry/files/logs/learnOH-1789297161645.log
      （申请「下载目录」权限被拒绝，文件在应用私有目录内，文件管理器里看不到；可在系统「设置 → 应用」里为 learnOH 打开该权限后重试）

  与成功态的 `06-export-public.png` 并排看，路径与结尾那句都不一样 ⇒ 两种结局在界面上可区分。
  该帧来自旧代码：那一版把 `authResults=[2]`（不受理）当成"被拒绝"，交付版把这种情况改成
  "不受理 → 试写 → 写不进去才降级"，所以**交付版不会出现这一幕**（这台设备上现在是成功的）。
- hilog 侧的区分：`log export plan` / `log export done` / `log export reported` 三条都带
  `outcome=` 与 `fallback=` 字段（本轮的 `outcome=exported-public fallback=none`）。

### 论断 6｜设置页那一行**跟着落点变**了（ticket 判据 B 第 2 条）

- 常驻行的文本直接来自落点：`SettingsPage.ets:234 handleExportLogs` 用
  `report.message` 的键与参数渲染，成功时参数第 3 项就是 `plan.path`。
- 设备侧同一张帧 `06-export-public.png` 里那一行是
  `保存位置：/storage/Users/currentUser/Download/learnOH-1789297382281.log` —— 已**不再是**
  `/data/storage/el2/base/haps/entry/files/logs/…`（旧落点；对照帧 `03-settings.png` 与
  ticket 18 的 `23-final-export-persistent.png` 都是旧路径）。

### 论断 7｜shell 用户能不能列出「那个目录」——三件事分开记

    ① 应用看到的路径（Environment.getUserDownloadDir 的返回值）
       hdc shell ls -l /storage/Users/currentUser/Download
       → ls: /storage/Users/currentUser/Download: No such file or directory
    ② 这个路径的物理落点 / 公共目录本体（论断 1 那条 ls -l 成功）
    ③ 应用私有沙箱（ticket 18 当时用的路径形态）
       hdc shell ls -l /data/storage/el2/base/haps/entry/files/logs
       → ls: /data/storage/el2/base/haps/entry/files/logs: No such file or directory

  ⇒ **界面上的路径与 shell 能列出的路径本来就是两套名字**。本轮把这条从"缺口"变成了"已解释"：
  用户拿文件靠的是文件管理器里的「下载」目录（②），而 shell 侧要核的就是 ② 这个物理路径。
  这条也解释了 ticket 18 为什么"读不到"：它查的是 ③ 那种应用沙箱相对形态。

## 门禁原始数字

| 门禁 | 数字 / 出处 |
| --- | --- |
| 单测 | `Tests run: 452, Failure: 0, Error: 0, Pass: 452, Ignore: 0`；`entry/.test/default/intermediates/test/coverage_data/test_result.txt` mtime **2026-09-13 19:01:18**（本轮，读取时刻 19:01:38）；`.dsh/logs/t19-test2.log` 里 `ERROR`=0 / `ErrorCode`=0 / `COMPILE RESULT`=0 / `BUILD SUCCESSFUL`=1。基线 441（派单给的合并后 main）⇒ **+11**（新增 `LogExport.test.ets` 11 条） |
| 打包 | `.dsh/logs/t19-assemble2.log`：`BUILD SUCCESSFUL`=1，`ERROR`/`ErrorCode`/`COMPILE RESULT`=0 |
| `check-domain-purity.mjs` | PASS（25 个领域源文件） |
| `check-import-graph.mjs` | PASS；WARN 仍是 `entrybackupability/EntryBackupAbility.ets` 与 `pages/Index.ets`（入口文件，属正常）。新增的 `LogExport.ets` / `LogExportTarget.ets` 都在可达路径上（SettingsPage 与单测各引一次） |
| `check-i18n-keys.mjs` | RESULT: OK；manifest **318**（313 + 5 条新导出文案）/ reference 178；三语 missing=empty=extra=0；source 186 个键全部可解析 |
| `check-generated-fresh.mjs` | PASS（6 个生成物 × 2 个生成器）；生成物与生成器输入同一次提交 |

## 没做到 / 存疑

1. **交付构建上没能在设备上重放"降级"那一幕**。论断 5 的降级帧 `04-permission-dialog.png`
   来自 18:59 的**中间构建**（`assemble` 于 18:56），不是交付构建（19:01:33）。
   原因：交付版不再把"平台不受理"当拒绝，而这台设备上直写公共目录**成功**，
   所以降级分支没有自然触发条件；要按需求触发就得加一个取证开关（改代码 → 构建 → 装 → 取证 → 复原 →
   再构建），成本是 3 次构建，我判断不值当。**降级路径的最终判据是单测（452 绿里那 6 条钉结局与文案键），
   不是这一帧。** 这一帧只能证明"那段文案在真实界面上渲染得出来"。
2. **"应用私有沙箱外部拿不到"这个前提，在本次会话里被实测推翻了**（见下方"顺带发现"）——
   它是派单情报的一部分，我需要如实指出而不是沿用。
3. 英文界面的两条新文案**没有取帧**（设备语言属硬禁止项，未动）；只核了生成物
   （`en_US/element/string.json` 里 5 条新键的值）与 `check-i18n-keys` 的 en_US 检查。
4. 权限在**真机（API 24，`3FYBB25407201890`）**上的行为未验：这台设备是 API 23 模拟器，
   `authResults=[2]` 的成因（是"API 12+ 不再需要"还是"模拟器特例"）**没有定案**。
   代码对两种情况都做了处理（受理→按授权走；不受理→试写），但真机可能弹出真弹窗、
   用户也可能真的拒绝 —— 那条分支只有单测覆盖。
5. `errorReasons=[0]` 与 `authResults=[2]` 是**自相矛盾的两个返回值**
   （0 = 操作成功、2 = 请求无效）。我按 `authResults` 判、把 `errorReasons` 原样打进日志，没有解释这个矛盾。
6. 公共目录里**留下了一个测试文件**：`/storage/media/100/local/files/Docs/Download/learnOH-1789297382281.log`
   （15464 B，19:03）。它是本 ticket 的交付证据本体（复核者要能自己 `ls -l` + `file recv`），
   所以**故意没删**。应用私有目录里另有 4 个历史导出文件（ticket 18 与本次中间构建留下的），
   也未清理。

## 顺带发现（会影响别的 ticket 的前提）

**ticket 18 的"沙箱外部读不到"结论，在这次的证据形态下不成立** —— 而且是两种不同的原因叠在一起：

1. **路径形态错了**：ticket 18 查的是 `/data/storage/el2/base/haps/entry/files/logs`（应用沙箱内的相对形态），
   它在 shell 视角根本不存在；物理路径是 `/data/app/el2/100/base/<bundle>/haps/entry/files/logs`。
2. **这条路在这台设备上真的读得到**：本轮用物理路径 `ls -l` 列到了 4 个历史日志文件，
   并且 `hdc file recv` 成功取回其中一个（15464 B，与 `ls -l` 一致）。

原始输出：

    hdc shell ls -l /data/app/el2/100/base/com.koracan.learnOH/haps/entry/files/logs
    total 98304
    -rw-rw---- 1 20020062 20020062 16325 2026-09-13 17:59 learnOH-1789293563425.log
    -rw-rw---- 1 20020062 20020062 15458 2026-09-13 18:08 learnOH-1789294109474.log
    -rw-rw---- 1 20020062 20020062 32543 2026-09-13 18:44 learnOH-1789296286469.log
    -rw-rw---- 1 20020062 20020062 15464 2026-09-13 18:59 learnOH-1789297161645.log

    hdc shell ls -ld /data/app/el2/100/base/com.koracan.learnOH
    drwxrwxrwx 8 20020062 20020062 4096 2026-09-12 15:22 /data/app/el2/100/base/com.koracan.learnOH

- **不是** hdc 拿到了特权：shell 实测 `uid=2000` / `CapEff=0000000000000000`，
  且**别的应用沙箱读不到** —— `hdc shell ls -l /data/app/el2/100/base/com.huawei.hmos.settings/haps/entry/files`
  → `Permission denied`。
- **解释（假设，未定案）**：本应用是用 hdc 装的 **debug HAP**（`/mnt/debugtmp/100/debug_hap/com.koracan.learnOH/…`
  有对应挂载），它的数据目录实测是 `drwxrwxrwx`，比正式安装的应用松。但 `…/haps/entry/files` 与
  `…/logs` 本身是 `drwxrwx---`（属主 `20020062`），shell 按 DAC 不该读得到 —— 这一层我**没解释清楚**，
  作为存疑留在这里。
- **对本 ticket 的含义（要写清楚，免得被读成"什么都没改"）**：
  - 用户视角的目标（"在文件管理器里拿得到"）**确实变了**：文件现在在公共「下载」目录（论断 1 的
    文件管理器视角 + 属主 uid 都变了），旧落点在应用沙箱里、文件管理器不暴露；
  - hdc 视角的"外部可见性"**两种落点在这台模拟器上都成立**，所以判据不能退化成
    "hdc 列得到就算成功" —— 本 ticket 的真正判据是**落点在不在公共目录**：
    属主 uid 从 `20020062` 变成 `20001006`（file_manager 一族）、路径从应用沙箱变成共享「下载」目录。
  - `ui_export_private_* / ui_export_failed` 那几条降级文案里"文件管理器里看不到"这句，
    对**用户**仍然成立；若有人拿 hdc 去列，会看到它其实列得出来（就是上面那条顺带发现）。

## 本轮改了哪些文件（工作区，取证期间同一份）

- 新增：`entry/src/main/ets/core/log/LogExportTarget.ets`（纯决策）、
  `entry/src/main/ets/core/log/LogExport.ets`（设备侧编排）、`entry/src/test/LogExport.test.ets`。
- 改：`entry/src/main/ets/core/log/LogBuffer.ets`（摘掉 `exportLogs`/`LogExportResult`，不再碰文件系统）、
  `entry/src/main/ets/features/settings/SettingsPage.ets`（异步导出 + 重入拦截 + 文案渲染）、
  `entry/src/main/module.json5`（声明 `READ_WRITE_DOWNLOAD_DIRECTORY` + reason + usedScene）、
  `entry/src/main/resources/{base,zh_CN,en_US}/element/string.json`（权限理由串，非 i18n 前缀，生成器会保留）、
  `scripts/i18n-ui-strings.mjs` + 5 个 i18n 生成物、`entry/src/test/{I18n,List}.test.ets`。
