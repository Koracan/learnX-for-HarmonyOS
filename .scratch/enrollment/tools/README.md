# ticket 07 · 设备登记取证工具

## 这是什么

`EnrollmentProbe.ets` + `run-enrollment-probe.ps1`：为验收第 3 条（"凭据加密落盘；重启应用后仍处于
已登记状态"）准备的**一次性**探针。**完整登记**需要用户本人完成短信验证，在那之前用**合成占位凭据**
走一遍真实代码路径（`AssetSecretStore` → `CredentialStore` → `AuthStore.loadPersisted`），并在
**杀进程**之后读回来。

**它写进去的不是真实账号**：`probe-user` / `probe-not-a-real-password` / 一个固定的合成指纹；
`clear` 动作会把它删掉。跑完脚本会复原 `EntryAbility.ets` 并删除探针文件。

## 怎么用

1. 确认两把锁归你（构建锁 + 设备锁），设备是模拟器 `127.0.0.1:5555`。
2. `pwsh -File .scratch/enrollment/tools/run-enrollment-probe.ps1`
3. 看 `.scratch/enrollment/evidence/07-probe-*.txt` 四份 hilog（seed / 重启已登记 / clear / 重启未登记）
   与两张截图。判读要点：
   - `probe seed: saved=true readBack=true` —— 经 asset 写入并可读回；
   - `startup: enrolled -> main shell (credentials from asset store)`（**新 PID**） —— 跨进程持久化；
   - `probe clear: cleared=true foundAfterClear=false` 且随后 `not enrolled -> login page` —— 状态由存储决定。

## 两个坑（都踩过，脚本里已处理/写明）

- **`devecocli build` 在本机打完包后不返回**，会让一次性脚本挂住；脚本改用 `hvigorw assembleHap`。
  常设门禁里的 `devecocli build` 另行单独跑。
- **探针复原后必须强制全量重建**：`git checkout` 复原 `EntryAbility.ets` + 删除探针文件之后，
  增量构建可能报 `BUILD SUCCESSFUL` 却**不重编** `EntryAbility`，产物里仍带着已删除模块的引用，
  装机后启动即 `ReferenceError: cannot find record '...EnrollmentProbe'`。修法与判据见 ticket Comments
  的「构建缓存坑」：删 `entry/build` 全量重建 + **对产物做字节检索** + 装机后确认应用日志出现。

## 本目录里没有的东西

排查 `saveFinger` 时下载过的 ID 页脚本（`/ui/auth/js/saveTabchooseAndInit.js`、
`/res/selfservice/{tabshowclick,browser-alert}.js`、`/res/react/components.js`、`/res/ui/react/react.js`）
**没有入库**：它们只是用来确认"登录页的静态脚本里没有 `saveFinger`"这一**否定结论**，
且 `react.js` 是 136 KB 的第三方代码。与 singleLogin 结论直接相关的那份 `finger3.js` 早已在
`.scratch/migration/idp-js/` 里入库。
