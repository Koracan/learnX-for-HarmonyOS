# SM2 验证证据清单

spec 第 11 节待验证项 #1 的取证材料：cryptoFramework 的 SM2 变换串与密文排列是否与 sm-crypto 兼容。结论为兼容，ADR-0004 不变。

图片与日志本体被 `.scratch/.gitignore` 排除（体积原因），**只在本机磁盘上**；
本清单纳入版本控制，用于在全新克隆中说明“存在过哪些证据、其内容指纹是什么”。

校验方式：`Get-FileHash -Algorithm SHA256 <文件>`

| 文件 | 字节 | SHA256（前16位） |
| --- | --- | --- |
| `analyze-sha256-der.js` | 4310 | `bc232515ccb94ff3` |
| `analyze-sha256-der.log` | 1316 | `8cb077706ed52f06` |
| `arkts-verify-console.log` | 1407 | `fb8e0e58d4c4cbba` |
| `arkts-verify.log` | 1385 | `439d6aa51fef7a71` |
| `arkts-wire.txt` | 257 | `de4d6c8ba0b95075` |
| `device-sm2probe-hilog.log` | 7286 | `e285288be1469b3a` |
| `doc-faq-31.txt` | 8591 | `fd846822f075cac9` |
| `doc-faq-38.txt` | 9275 | `f9c943da553b4c4d` |
| `doc-search-c1c2c3.json` | 699 | `3eae26076404d9df` |
| `doc-search-sm2spec.json` | 5268 | `82134401b3a37a14` |
| `doc-sm2-asym.txt` | 8099 | `7579921c04841ac0` |
| `doc-sm2-conversion.txt` | 3074 | `1798976f245242f8` |
| `node-output.json` | 1661 | `2d02a883b2b84a08` |
| `sm2-probe.js` | 6478 | `8496309a0eb11adf` |
| `sm2-probe.log` | 5505 | `badca5caf353f6e8` |
| `verify-arkts-output.js` | 4131 | `5e4985f961a7f372` |

