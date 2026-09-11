# foundation 证据清单

ticket 01（工程分层/日志/主题令牌）与 ticket 02（i18n 资源化）的模拟器（Pura 90，`127.0.0.1:5555`）证据。

图片与日志本体被 `.scratch/.gitignore` 排除（体积原因），**只在本机磁盘上**；
本清单纳入版本控制，用于在全新克隆中说明"存在过哪些证据、其内容指纹是什么"。

校验方式：`Get-FileHash -Algorithm SHA256 <文件>`（下表为前 16 位）

## ticket 01

| 文件 | 字节 | SHA256（前16位） | 说明 |
| --- | --- | --- | --- |
| `01-index-light.png` | 368060 | `007FBA4168CD12E1` | 首屏浅色（系统浅色，冷启动，同一版代码） |
| `01-index-dark-final.png` | 367206 | `2618035DC79CE47C` | 首屏深色（**同进程**切系统深浅色后前台化，未重启） |
| `01-layout-light.txt` | 1758 | `B827ED3A487705DA` | 浅色态无障碍树：系统配色=浅色 / LIGHT_COLORS |
| `01-layout-light.json` | 8815 | `82CEEE291F32FB8E` | 同上（JSON） |
| `01-layout-dark-final.txt` | 1758 | `1664C508389DD7D7` | 深色态无障碍树：系统配色=深色 / DARK_COLORS |
| `01-hilog-live-switch.txt` | 1850 | `05B7807708AE7425` | 关键证据：PID 16244 从冷启动浅色 → 切系统深色 → 同 PID `configuration updated: colorMode=0`，无新 onCreate |
| `01-hilog-switch.txt` | 984 | `79779BFE93643EDA` | 更早一次同类切换记录 |
| `01-exported-log.txt` | 663 | `D5B3CA0B978AB7A1` | 应用内"导出日志"按钮落盘的文件（从沙箱 recv 出来） |
| `01-hypium-test-result.txt` | 2826 | `968968BF385D2459` | Hypium 最终结果：Tests run 42 / Failure 0 / Error 0 / Pass 42 |
| `01-hvigor-test-run.log` | 4316 | `3AE9CD03B9286A35` | `hvigorw ... test` 完整输出 |
| `01-build-arkts.log` | 5518 | `B22D340740E6A8CD` | `devecocli run` 构建输出，BUILD SUCCESSFUL |

> `01-index-dark.png` / `01-layout-dark.*` / `01-index-en.png` 是 02 与统筹在 01 的取证过程中留下的中间件，保留但不作为 ticket 01 的验收依据。

## ticket 02

| 文件 | 字节 | SHA256（前16位） |
| --- | --- | --- |
| `02-check-i18n-negative.txt` | 736 | `C47F2CF180856813` |
| `02-i18n-key-counts.txt` | 842 | `F0F6C01D58598A0B` |
| `02-layout-zh.json` | 8815 | `6CAB4B231D843CD8` |
| `02-ohpm-dayjs-info.txt` | 6170 | `9BC3227A53AA7244` |
| `02-unit-test.txt` | 324 | `BCF9841E201CE54B` |
| `02-zh.png` | 367698 | `A877E5D030C08A79` |
