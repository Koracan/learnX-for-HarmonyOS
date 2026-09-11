# ticket 06 · 设备侧登录验证工具（凭据门控）

**用途**：等用户手动完成登记（ticket 07）后，用一次命令在设备上真跑
「纯 HTTP 登录 → 取 CSRF → 抓一次列表」，关闭 ticket 06 的验收第 1、3 条。

## 为什么现在不能跑

验收第 1 条（真实账号纯 HTTP 登录）与第 3 条（SM2 输出被服务端接受）都需要**真实账号**，
而账号只在用户手动登记后才存在。本轮交付的是**能力 + 可复核的准备**，不是「跑到过」的结论。

## 怎么用（一轮）

1. 打开 `AuthProbe.ets`，填 `USERNAME` / `PASSWORD` / `FINGER_PRINT`（指纹取 ticket 07 登记时用的那个）。
   **不要把填好的文件提交**；`AuthProbe.ets` 只应保持在占位状态入库。
2. 确认两把锁归你（没有别的 agent 在构建/用设备）。
3. `pwsh -File .scratch/auth/tools/run-auth-probe.ps1`
4. 看输出里的 `PROBE` 行：
   - `PROBE-SWITCH auth=on credentialsFilled=true` —— 开关与凭据自证生效；
   - `PROBE login ok=true reason=none requiresEnrollment=false csrfChars=<n> cookieChars=<n>` —— 登录成功；
   - `PROBE session page status=200 bytes=<n> firstCourseId=<id>` —— 会话在后续请求上有效；
   - `data.files fetched ... items=<n> elapsedMs=<n>` —— 三域管道在真实会话下跑通（抓的是文件域）。
5. 失败时看 `reason` / `diag` / `jar=`：
   - `NO_TICKET_IN_RESPONSE` + `idLoginPage=true` ⇒ 服务端要浏览器/验证码 —— 这正是验收第 5 条的判定出口，
     请保留原始响应并提请复审 ADR-0004。
   - `ERROR_FETCH_FROM_ID` ⇒ 公钥没取到或 SM2 加密失败（`diag` 里区分）。
   - `ERROR_ROAMING` ⇒ 票据不被接受（SM2 产物可能不被服务端接受，验收第 3 条的反证条件）。
6. 脚本会把 `auth-probe-compile.log` / `auth-probe-run.log` / `auth-probe-hilog.log` 落在 `.dsh/logs/`，
   **并在 finally 里复原**探针与 `EntryAbility`；请核对最后那段 `git status` 是干净的。

## 本轮做到哪一步

- 探针代码 + 脚本 + 本说明：**已落盘**，并在本轮用 `hvigorw test` 做过**编译校验**（见 ticket Comments）。
- 真跑：**未执行**（凭据门控）。
