# 19: 导出日志改到「用户拿得到」的公共区域

**What to build:** 账号所有者第四轮反馈（2026-09-13）：

> 现在导出日志的保存位置是 `/data/storage/el2/base/haps/entry/files/logs/xxx.log`，这在应用沙盒之内，不方便用户拿到。
> 应该改为向系统申请公共区域。

现在的落点是应用私有沙箱（`context.filesDir`），**应用外部**（文件管理 / `hdc file recv`）拿不到；用户即便在界面上看到路径也没有用。
本 ticket 把导出目标改到**公共目录**（或由系统文件选择器让用户挑位置），并且**必须用应用外部的证据**证明文件真的落在那里。

**Blocked by:** None（可立即开始）

**Status:** open

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