# ticket 07 · 设备登记 Enrollment —— 证据清单

设备：**模拟器** Pura 90（serial `127.0.0.1:5555`，HarmonyOS 6.1.0(23)）。真机 `3FYBB25407201890` 未连接。

取证版本：见同目录 `revision.txt`（HEAD + 工作区脏哈希 + 已装包版本）。
包：`com.koracan.learnOH` versionName=1.1.0 / versionCode=1000042（`bm dump -n`）。

四批证据：

- **A. 主链路**（07:05–07:22）：登录页 / 预填 / 注入 / 取消 / 重启无残留 / 最终安装态
- **B. 落盘探针**（07:10–07:11）：合成凭据走真实 `AssetStore` → `CredentialStore`，跨进程读回
- **C. 诊断（方案 A 之前，08:02）**：`07-diag-prefix-*` —— 判定「两个站点指纹为什么是空的」，并判死两条嫌疑
- **D. 方案 A（提交前观测，08:26）**：`07-planA-prefix-*` —— 生效指纹改为页面值，诊断开关关闭

| 文件 | 字节 | SHA256(前16) | 用途 | 承载的论断 |
| --- | --- | --- | --- | --- |
| `07-final-login-page.png` | 117587 | C410FBA787138AB5 | 冷启动进入登录页（未登记） | 验收 4：登录页是未登记时的默认入口 |
| `07-final-login-filled.png` | 115039 | A4BD4CF3F734174A | 合成账号/口令已填入（口令掩码） | 登记入口可用（合成值，非真实账号） |
| `07-final-sso-note-dialog.png` | 678714 | 72C205E71583791E | 点「登录」后的说明对话框 | 对齐参考实现 Login.tsx:48-64 的确认步骤 |
| `07-final-id-page-injected.png` | 551737 | 7B37751CE191852F | ArkWeb 里的 ID 登录页：预填 + 顶部状态行 | 注入生效（预填 + 勾选信任） |
| `07-final-inject.txt` | 3509 | 01B592F453E3A69D | 注入会话 hilog：saveFinger patchInstalled=1 / [singleLogin] forced=1 / [submitHook] attached=1 / 指纹摘要 | 验收 2（第①点）+ 验收 5（脱敏） |
| `07-final-after-cancel.png` | 115277 | 663FA3BCC1E74DBF | 点「取消」后回到登录页 | 验收 4 |
| `07-final-cancel.txt` | 2765 | CEB1CA98B6AF4ED3 | 取消路径 hilog：cancel -> web cookies cleared | 验收 4：取消即清理 |
| `07-final-restart-after-cancel.png` | 117407 | C8742D5D92BF22E1 | 取消后杀进程重启，仍是登录页 | 验收 4：重启后无半登记状态 |
| `07-final-restart-after-cancel.txt` | 2350 | FDBF3D5DDBF5D6BB | 重启 hilog（新 PID）：no persisted credentials -> not enrolled | 验收 4：磁盘上没有半条凭据 |
| `07-final-startup.txt` | 1524 | C9848977E2D8E6DB | 干净构建首次启动 hilog | 最终安装态 |
| `07-final-installed-state.png` | 117334 | 13A8A2E99F7D1F72 | 干净构建安装后的首屏 | 最终安装态 |
| `07-final-installed-state.txt` | 1524 | F8A2061CF02182FB | 同上时刻的 hilog | 最终安装态 |
| `07-probe-seed.txt` | 5197 | D1BE430ADAF3F75F | 探针 seed：credentials saved: ok=true -> 读回一致 | 验收 3：经真实 AssetStore 写入并可读回 |
| `07-probe-restart-enrolled.txt` | 6328 | 7120363165C9AA35 | 杀进程后无参数重启（新 PID）：enrolled -> main shell | 验收 3：跨进程重启后仍已登记 |
| `07-probe-restart-shell.png` | 337479 | 40660CC106DF013D | 上一步界面：五 tab 主壳 | 验收 3 |
| `07-probe-clear.txt` | 8671 | 717642A74BDBE059 | 探针 clear：cleared=true -> 未登记 | 验收 3/4：状态由存储决定 |
| `07-probe-restart-unenrolled.txt` | 6670 | 9DDECB9EA2D8E1D8 | 清除后重启：not enrolled | 验收 3/4 |
| `07-diag-prefix-finger3-empty.txt` | 8242 | BB9FB146DFE11DBA | 【诊断·方案 A 之前】加载期 hilog：xhr req/res /b/doubleAuth/personal/getFinger3 -> status=200 result=error objectChars=0；diag:idb roundTripOk=true；diag:env origin=[https://id.tsinghua.edu.cn] localStorageOk=true indexedDB=object；页面 console 的 Uncaught (in promise)；diag=true（开关自证） | 根因收窄：两个字段为空是站点对未登录会话的固有行为；IndexedDB 可用 |
| `07-diag-prefix.png` | 554712 | 48BC294A7536D7FF | 同一轮的状态行截图（diag=1，fpChars=36 fgChars=0 fg3Chars=0） | 同上 |
| `07-planA-prefix.txt` | 7582 | 994A08245454D15F | 【方案 A · 加载期】hilog：fingerPrintChars=32 fingerPrintSource=page；[finger3] source=localstorage chars=0 -> tryRemote -> remote rejected result=error；f3Remote=0；diag=0 且 0 条 diag 报告 | 方案 A 生效（生效指纹=页面值）且诊断开关已关闭 |
| `07-planA-prefix.png` | 556363 | 3E541A3B7AFEAF56 | 状态行截图：stage=page fpChars=32 fpSource=page f3Remote=0 singleLogin=1 | 同上 |

## 这批证据**不能**证明什么（勿越读）

1. **完整登记（含短信验证）**：需要用户本人操作。短信之前的环节（预填 / 注入 / 勾选信任 / 生效指纹来源）已自测；提交之后的漫游、saveFinger 响应、会话收割与落盘都未触发。
2. **三点等式的②③点**：saveFingerXhr 与 persistedReadBack 只在提交走完时才出现；本轮 saveFingerXhr=empty 是预期。
3. **方案 A 是否真的解决服务端「隐私/匿名模式」**：未验证。A 只是让登录报文与 stock 浏览器逐字段一致（唯一不同的一栏就是被我们覆盖的 fingerPrint）——它是**有依据的推断修法**，不是已证结论。
4. **「勾选信任 = 已授予 180 天信任」**：勾选只是请求信任；端到端证明是 ticket 08 在无短信下纯 HTTP 重登成功。
5. **凭据「加密」本身**：由系统 asset 服务承担，本清单只能证明「走 asset 通道且读回一致」。
6. **提交前自检的运行时行为**（submitGate allowed/blocked 两行）：只有真正点提交才会执行；本轮只做了脚本内容与协议解析的单测。

## 取样代价（如实登记）

- 探针阶段「清除后重启」的截图在收尾时被当作重复文件删除；该论断的判据改为 07-probe-restart-unenrolled.txt 的 startup: not enrolled。
- 06:57 的一次安装是**探针构建的残留**（增量构建没重编 EntryAbility，产物仍引用已删除模块 → 启动 ReferenceError）。那批证据已全部作废重采，修法与判据见 ticket Comments 的「构建缓存坑」。
- 诊断批次（C）里 diag:lf localstorageUtil=absent 是**探针时机**造成的（document-start 时全局还没定义），不是「站点对象不存在」——同一轮 load 期的调用正常。已在 reference-quirks 第 11 条记明。

## 复现方式

- A/B 批：devecocli build → hdc install -r ...entry-default-signed.hap → aa force-stop/start → devecocli ui click/text/screenshot → hdc shell 「hilog -x -D 0x4C4F > /data/local/tmp/x.txt」 + hdc file recv。
- B 批的探针：pwsh -File .scratch/enrollment/tools/run-enrollment-probe.ps1。
- C 批：把 ENROLLMENT_DIAGNOSTICS_FOR_EVIDENCE 临时置 true 构建，登录页只做到「确认对话框 → 打开 ID 页面」，**不点页面里的登录**。
