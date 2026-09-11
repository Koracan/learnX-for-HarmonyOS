# ticket 07 · 设备登记 Enrollment —— 证据清单

设备：**模拟器** Pura 90（serial `127.0.0.1:5555`，HarmonyOS 6.1.0(23)）。真机 `3FYBB25407201890` 未连接。

取证版本：见同目录 `revision.txt`（HEAD + 工作区脏哈希 + 已装包版本）。
包：`com.koracan.learnOH` versionName=1.1.0 / versionCode=1000042（`bm dump -n`）。

两批证据（都是最终源码；区别只在第二批多了一个临时探针，见 ticket Comments）：

- **A. 固定构建**（07:05–07:22）——登录页 / 预填 / 注入 / 取消 / 重启无残留 / 最终安装态
- **B. 探针构建**（07:10–07:11）——用**合成凭据**走真实 `AssetStore` → `CredentialStore` 路径，证明跨进程持久化

| 文件 | 字节 | SHA256(前16) | 用途 | 承载的论断 |
| --- | --- | --- | --- | --- |
| `07-final-login-page.png` | 117587 | C410FBA787138AB5 | 冷启动进入登录页（最终构建、未登记） | 验收 4：登录页是未登记时的默认入口 |
| `07-final-login-filled.png` | 115039 | A4BD4CF3F734174A | 合成账号/口令已填入（口令掩码） | 登记入口可用（合成值，非真实账号） |
| `07-final-sso-note-dialog.png` | 678714 | 72C205E71583791E | 点「登录」后的说明对话框（loh_sso / loh_sso_note，逐字取自 ticket 02 迁移的键） | 对齐参考实现 Login.tsx:48-64 的确认步骤 |
| `07-final-id-page-injected.png` | 551737 | 7B37751CE191852F | ArkWeb 里的 ID 登录页：用户名/口令已预填，顶部诊断行 stage=page fpChars=36 prefill=11 saveFinger=1 singleLogin=1 | 注入生效（预填 + 指纹 + 勾选信任） |
| `07-final-inject.txt` | 3509 | 01B592F453E3A69D | 注入会话 hilog（域 0x4C4F）：saveFinger patchInstalled=1 / [singleLogin] forced=1 pageLeftItUnchecked=1 / [submitHook] attached=1 / fingerprint digest point=formFieldDom=d4314739 | 验收 2（三点等式的第①点）+ 验收 5（脱敏） |
| `07-final-after-cancel.png` | 115277 | 663FA3BCC1E74DBF | 点「取消」后回到登录页 | 验收 4：中途放弃回登录页 |
| `07-final-cancel.txt` | 2765 | CEB1CA98B6AF4ED3 | 取消路径 hilog：cancel tapped -> stage=cancelled -> web cookies cleared: when=on-disappear | 验收 4：取消即清理，无半登记状态 |
| `07-final-restart-after-cancel.png` | 117407 | C8742D5D92BF22E1 | 取消后杀进程重启，仍是登录页 | 验收 4：重启后仍无半登记状态 |
| `07-final-restart-after-cancel.txt` | 2350 | FDBF3D5DDBF5D6BB | 重启 hilog（新 PID）：no persisted credentials -> startup: not enrolled -> login page | 验收 4：磁盘上没有半条凭据 |
| `07-final-startup.txt` | 1524 | C9848977E2D8E6DB | 最终干净构建首次启动 hilog：no persisted credentials / not enrolled | 最终安装态（探针已从源码与产物中清除） |
| `07-final-installed-state.png` | 117334 | 13A8A2E99F7D1F72 | 最终干净构建安装后的首屏（登录页） | 最终安装态（探针已从源码与产物中清除） |
| `07-final-installed-state.txt` | 1524 | F8A2061CF02182FB | 同上时刻的 hilog | 最终安装态（探针已从源码与产物中清除） |
| `07-probe-seed.txt` | 5197 | D1BE430ADAF3F75F | 探针 seed：credentials saved: ok=true … fingerPrint=0f0f…(36) -> credentials loaded -> startup: enrolled -> main shell | 验收 3：凭据经真实 AssetStore 写入并可读回 |
| `07-probe-restart-enrolled.txt` | 6328 | 7120363165C9AA35 | 杀掉进程后【无参数】重启（新 PID）：credentials loaded -> startup: enrolled -> main shell (credentials from asset store) | 验收 3：跨进程重启后仍处于已登记状态 |
| `07-probe-restart-shell.png` | 337479 | 40660CC106DF013D | 上一步的界面：五 tab 主壳（公告列表正常渲染） | 验收 3：已登记 -> 主界面 |
| `07-probe-clear.txt` | 8671 | 717642A74BDBE059 | 探针 clear：credentials cleared: ok=true -> no persisted credentials -> startup: not enrolled | 验收 4/3：清除后不留痕（也证明 seed 不是假成功） |
| `07-probe-restart-unenrolled.txt` | 6670 | 9DDECB9EA2D8E1D8 | 清除后再重启：no persisted credentials -> not enrolled -> login page | 验收 3：状态确实由存储决定 |

## 这批证据**不能**证明什么（勿越读）

1. **完整登记（含短信验证）**：需要用户本人操作，本轮未做。页面上「预填 + 指纹 + 勾选信任」是**短信之前**就能观测的环节；提交之后的漫游、saveFinger 响应、会话收割都未触发。
2. **三点等式的第②③点**：saveFingerXhr 与 persistedReadBack 只有在用户提交表单、登记走完时才会出现。本轮 saveFingerXhr=empty 是**预期**（saveFinger 未触发），不是失败。
3. **「勾选信任 = 服务端已授予 180 天信任」**：勾选只是「我们请求了信任」。端到端证明是 ticket 08 在无短信的情况下纯 HTTP 重登成功。
4. **凭据「加密」本身**：DEVICE_UNLOCKED 的加密由系统 asset 服务承担；本清单只能证明「走的是 asset 通道且读回一致」，不能代替系统侧的加密证明。

## 取样代价（如实登记）

- 探针阶段「清除后重启」的**截图**在收尾时被我当作重复文件删除（07-probe-restart-login.png）；该论断的判据改为 07-probe-restart-unenrolled.txt 里的 startup: not enrolled -> login page 与 foundAfterClear=false。界面外观由 07-final-installed-state.png（同一代码路径）承载。
- 06:57 那一次安装实际是**探针构建的残留**（源码里的探针文件已被复原删除，但增量构建没有重编 EntryAbility）：启动即 ReferenceError: cannot find record ...EnrollmentProbe。这批证据已全部作废重采，修法与验证见 ticket Comments 的「构建缓存坑」一节。

## 复现方式

- A 批：devecocli build → hdc install -r entry/build/default/outputs/default/entry-default-signed.hap → aa force-stop/start → devecocli ui click/text/screenshot → hdc shell "hilog -x -D 0x4C4F > /data/local/tmp/x.txt" + hdc file recv。
- B 批：pwsh -File .scratch/enrollment/tools/run-enrollment-probe.ps1（自带注入/构建/安装/seed/重启/clear/复原；跑完 git status 只剩我自己的改动）。
