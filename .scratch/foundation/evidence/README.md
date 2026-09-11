# foundation 证据清单

ticket 01（工程分层/日志/主题令牌）与 ticket 02（i18n 资源化）的真机（模拟器 Pura 90）证据。

图片与日志本体被 `.scratch/.gitignore` 排除（体积原因），**只在本机磁盘上**；
本清单纳入版本控制，用于在全新克隆中说明“存在过哪些证据、其内容指纹是什么”。

校验方式：`Get-FileHash -Algorithm SHA256 <文件>`

| 文件 | 字节 | SHA256（前16位） |
| --- | --- | --- |
| `01-exported-log.txt` | 663 | `d5b3ca0b978ab7a1` |
| `01-hvigor-test-run.log` | 2665 | `dcfca0cb031b741d` |
| `01-hypium-test-result.txt` | 1255 | `46a78b11a61ba840` |
| `01-index-dark.png` | 367044 | `c2249f529801ec1d` |
| `01-index-en.png` | 396315 | `231cd0a40a31e546` |
| `01-layout-dark.json` | 19221 | `fc6df726c5f35318` |
| `01-layout-dark.txt` | 0 | `n/a(locked)` |
| `01-layout-light.json` | 8827 | `d7bc26315e5f704d` |
| `01-layout-light.txt` | 1758 | `a237e2d8587425f9` |
| `02-check-i18n-negative.txt` | 736 | `c47f2cf180856813` |
| `02-i18n-key-counts.txt` | 842 | `f0f6c01d58598a0b` |
| `02-layout-zh.json` | 8815 | `6cab4b231d843cd8` |
| `02-ohpm-dayjs-info.txt` | 6170 | `9bc3227a53aa7244` |
| `02-unit-test.txt` | 324 | `bcf9841e201ce54b` |
| `02-zh.png` | 367698 | `a877e5d030c08a79` |
| `tmp-chk.png` | 149123 | `650f1757c4939787` |
| `tmp-darkmode-on.png` | 157911 | `a9ed8898f9847bf4` |
| `tmp-darkmode-on2.png` | 149418 | `f9c7e7f8a4c8478b` |
| `tmp-display.png` | 279796 | `e68b28e1235f60f5` |
| `tmp-display2.png` | 280003 | `80acd519f84b46b2` |
| `tmp-export.png` | 332604 | `62870b71d19000d7` |
| `tmp-now.png` | 294050 | `ef68325bcbe15b40` |
| `tmp-settings.png` | 278056 | `bbd984eead0d73fd` |
| `tmp-state.png` | 158642 | `f6607e5799b34de7` |

