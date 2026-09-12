# ticket 08 · 重登 / 降级取证工具

## 这是什么

`SessionProbe.ets` + `run-session-probe.ps1`：为验收第 1/3/4/5 条准备的**一次性**探针。

验收第 1 条（"杀掉应用重启后无需输入即进入主界面，日志证明会话由纯 HTTP 重建"）与第 6 条
（正常重启截图）都需要**先有一次真实设备登记**（用户手动完成短信验证）。真实凭据到来之前，
本探针用**合成占位凭据**走一遍真实代码路径，在设备上真实地产生：

- 应用向 `id.tsinghua.edu.cn` 发出的真请求（于是**内存 cookie jar 里会有一个真实的 `JSESSIONID`**）；
- 重登失败时的**显式降级**（回登录页 + "登录状态已失效，需要重新验证。" + 重试入口）；
- 杀进程之后对应用存储的扫描结果（证明那份会话 cookie **没有**落盘，ADR-0004）。

**它写进去的不是真实账号**：`probe-user` / `probe-not-a-real-password` / `0f0f0f0f-1a1a-4b4b-8c8c-2d2d2d2d2d2d`；
`clear` 动作会把它删掉。跑完脚本会复原 `EntryAbility.ets` 并删除探针文件。

## 怎么用

1. 确认两把锁归你（构建锁 + 设备锁），设备是模拟器 `127.0.0.1:5555`。
2. `pwsh -File .scratch/session/tools/run-session-probe.ps1`
3. 看 `.scratch/session/evidence/08-*.txt|png` 与 `revision.txt`。判读要点：

| 文件 | 看什么 | 判据 |
| --- | --- | --- |
| `08-probe-seed.txt` | `session probe seed: saved=true readBack=true` | 合成凭据经真实 asset 通道写入并可读回（**合成**，非真实登记） |
| `08-coldstart-reauth.txt` | `startup: restoring session ... (pure HTTP, no webview)` → `login: jar reset` → `login: id form ok status=200 ... jar=cookies=N names=[...]` → `restore: NOT rebuilt` → `startup(startup): session NOT rebuilt ... -> login page` | 会话由**纯 HTTP**重建过；有网络时内存 jar 里会出现**真实**的 `JSESSIONID`；失败**显式降级** |
| `08-coldstart-degraded.png` | 登录页出现"登录状态已失效，需要重新验证。"与"重试"按钮 | 验收第 3 条的**视觉**证据 |
| `08-storage-scan.txt` | `grep -ra -E "JSESSIONID|SERVERID|CASTGC|TGT-|_csrf|csrfToken"` 在 `el2/100/base` 与 `el2/100/database` 下 **0 命中** | 验收第 5 条：会话 cookie 不落盘 |
| `08-probe-clear.txt` | `session probe clear: cleared=true foundAfterClear=false` | 探针自己收尾 |
| `08-coldstart-unenrolled.txt` | 新 PID 的 `startup(startup): no persisted credentials -> login page` | 状态确实由存储决定，没有半登记残留 |
| `08-committed-*.txt/png` | 复原探针后的**全量重建**产物检索 `SessionProbe=0 TEMP-EVIDENCE=0 SessionRestorer>0` + 装机正常启动 | AGENTS.md「陈旧产物」要求的产物级/视觉级证据 |

## 两个坑（ticket 07 踩过，脚本已处理）

- **`devecocli build` 在本机打完包后可能不返回**，脚本改用 `hvigorw assembleHap`。
- **探针复原后必须强制全量重建**：增量构建可能报 `BUILD SUCCESSFUL` 却不重编，产物里仍带着
  已删除的 `SessionProbe`，装机启动即 `ReferenceError`。脚本默认会删 `entry/build` 全量重建 +
  解包 hap 在 `ets/modules.abc` 里做内容级检索（**不要直接对 .hap 做字节检索**，zip 条目是压缩的，
  搜不到会给假阴性）+ 装机确认。

## 本目录里没有的东西

真实账号、口令、真实设备指纹、真实会话 cookie。日志里出现的 cookie 值一律不落盘到证据文件
（`CookieJar.describe()` 只打域名/名字/条数/字符数）。
