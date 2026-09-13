# ticket 01（文件页头去掉多余入口与裸计数）设备取证清单

设备：模拟器 **Pura 90**（串口 `127.0.0.1:5557`，`const.product.devicetype` 回 `phone`）。窗口 1320×2856 px。
已安装包：`com.koracan.learnOH` versionName=`2.0.0` / versionCode=`2000000`（`bm dump -n`）。

> 这台机当时是**真实会话**（设置页显示账号 `han-wang23`，且**没有** Mock 模式自证行）。
> 全程没有点「退出登录」，没有点任何提交入口。

## 溯源

| 项 | 值 |
| --- | --- |
| `git rev-parse HEAD` | `39ada726932a8f7c7ffafb2484043ae2599c16bd` |
| 工作区脏（取证期间有未提交改动） | `git status --porcelain` 的 SHA256 = `75b65a3f04acb7397bdb0476035393cd452b6e0717a8c0bf4dcda788158c675f` |
| 产物指纹 `entry-default-signed.hap` | `517859DCB0A113809150DAFB5833C9BF0F9B6CC65ABE7A0FA0D6164F59C75E96` |
| 产物指纹（解包后）`ets/modules.abc` | `17550C1CDBE9CC7B3BB38761216FD1747BBA926C17A968DBA0C3D047D5BDA297` |

产物内容级检查（`docs/agents/gates.md` 的"陈旧产物"判据）：在解包出来的 `ets/modules.abc`（1746672 字节）里逐字节搜

- `ui_file_settings_open` → **NOT FOUND**（应为：该键已从资源、键表与调用点一并删除）
- `ui_file_settings_title` → FOUND ×1（文件设置页自己的标题，仍在）
- `ui_file_settings_root` → FOUND ×1
- `loh_files` → FOUND ×1
- `ui_files_empty` → FOUND ×1（对照组：证明这次字节搜索**找得到**存在的串，NOT FOUND 不是假阴性）

## 页头元素清单（before / after）

设备侧 `devecocli ui layout --device 127.0.0.1:5557 --format json` 的原始输出（剥掉首行 `- Dumping layout…`），
项目符号里的 `bounds` 单位是 px，格式 `[left, top, right, bottom]`。

**before**（`logs/layout-preinstall-files.json`，改动**生效前**装机的那一版，同一状态：文件 tab、四个 ZIP、屏蔽 4）

```
Text "文件"      bounds=[56,234,225,332]
Text "刚刚更新"  bounds=[253,287,408,332]
Text "4"         bounds=[863,287,885,332]      <- 裸计数
Text "文件设置"  bounds=[927,275,1124,332]     <- 页头第二个入口
Row              bounds=[1124,192,1264,332]    <- 搜索入口
  Text bounds=[1152,220,1236,304]
Text "全部 0"  Text "未读 0"  Text "收藏 0"  Text "归档 0"  Text "屏蔽 4"
```

**after**（`logs/layout-after-files.json`，本工作区构建装机的版本，同一状态：文件 tab、四个 ZIP、屏蔽 4）

```
Text "文件"      bounds=[56,234,225,332]
Text "刚刚更新"  bounds=[253,287,408,332]
Row              bounds=[1124,192,1264,332]    <- 搜索入口
  Text bounds=[1152,220,1236,304]
Text "全部 0"  Text "未读 0"  Text "收藏 0"  Text "归档 0"  Text "屏蔽 4"
```

两份 dump 里 **都存在**的：`文件` 标题、`刚刚更新`（相对更新时间）、搜索入口 Row、五个筛选片、
四个 `ListItem`（ZIP 文件名 / 大小 / 类型 / 相对时间）。**只在 before 里的**：裸计数 `"4"` 与 `"文件设置"`。

before 那一版不是本工作区构建的（装机时间早于本次改动），它的源码版本没有记录；把它当"删掉之前长什么样"的
参照时，配套的源码级依据是：`git show HEAD:entry/src/main/ets/features/files/FilesPage.ets` 里确实有
`Text(this.store === null ? '0' : this.store.files.length.toString())`、
`Text(this.s($r('app.string.ui_file_settings_open')))`、`private openSettings()` 与
`else if (name === ROUTE_FILE_SETTINGS)`。

## 逐文件论断表

| 文件 | 字节 | SHA256(前16) | 用途（一条主论断） |
| --- | ---: | --- | --- |
| files-header-before.png | 232461 | fef35875a8080679 | 改动**生效前**的文件页头：标题 + 相对时间 + 裸数字 4 + 「文件设置」+ 搜索，四个 ZIP 可见 |
| files-header-after.png | 226692 | 9cb2652407f62b31 | 改动**生效后**的同状态文件页头：只剩标题 + 相对时间 + 搜索；裸数字与「文件设置」都不在 |
| settings-page-file-entry.png | 189781 | 67d64836a5aec276 | 设置页里「文件」那一行的入口仍然在（功能没丢，只是页头不再有第二个入口） |
| file-settings-from-settings-page.png | 253527 | b136a6ef01214729 | 从设置页点进去确实到了文件设置页：两个开关 + 清空文件缓存 + 当前保存位置都在，值没被本次改动动过 |
| logs/layout-preinstall-files.json | 12102 | c0b25491a9954cd0 | 页头 before 的元素清单（原始 dump） |
| logs/layout-after-files.json | 11690 | 88cb8f984ed6e9b9 | 页头 after 的元素清单（原始 dump） |
| logs/layout-after-settings.json | 11213 | 518cf9c11d78b03c | 设置页行清单：`Row` 里 `Text "文件"` bounds=[0,1256,1320,1438]，带 `>` 箭头（可进入） |
| logs/layout-after-filesettings-from-settings.json | 6394 | 22e039b83d00e401 | 文件设置页的元素清单（标题 / 两个 Toggle / 清空缓存 / 当前保存位置） |
| logs/screenshot-notices-preinstall.png | 192138 | e1017fa5fda7261b | 过程帧（改动前装机版本的公告 tab），不作为本 ticket 的论断证据 |
| logs/layout-after-boot.json、logs/layout-preinstall.json | 9232 | 443a071c048c3bca | 两次冷启动都落在公告 tab，两份 dump 逐字节相同（说明两次启动状态一致） |

## 逐条验收

1. **页头不再出现「文件设置」入口，也不再出现裸数字** —— after 的 dump 与截图（`files-header-after.png` / `layout-after-files.json`）：页头只剩标题 + 相对时间 + 搜索；`"4"` 与 `"文件设置"` 两个节点都不存在。
2. **设置页里进文件设置的那条路径仍然可用** —— `settings-page-file-entry.png` + `layout-after-settings.json`（入口行在），点它后到达 `file-settings-from-settings-page.png` + `layout-after-filesettings-from-settings.json`（两个 Toggle `bounds` 分别 [1132,1028,1258,1098] 与 [1132,1323,1258,1393]，都还在）。
3. **两个文件设置仍然生效** —— 本次改动没有碰 `FileSettingsPage.ets` / `data/settings`（`git diff` 里没有它们）；页面上两个 Toggle 的当前值与页内自证行 `useDocumentDir=false omitCourseName=false` 一致。
4. **条数：要么带标签要么不显示** —— 选择**不显示**（页头不再有条数节点）；带标签的条数仍在下面五个筛选片上（`全部 0 / 未读 0 / 收藏 0 / 归档 0 / 屏蔽 4`）。
5. **零引用的 i18n 键连同多语言资源与键登记表一并清理，门禁仍绿** —— `scripts/i18n-ui-strings.mjs` 删掉 `ui_file_settings_open`，重跑 `generate-i18n-resources.mjs` + `gen-i18n-keys.mjs`；四个脚本结果见交付回报。
6. **证据：一次页头 layout dump（元素清单）+ 同状态截图** —— 见上面两节。

**【追记 · 2026-09-13（界面优化轮：页头相对时间不再冻结）】上面反复出现的 `Text "刚刚更新"` 那一行仍然在，
但它**不再冻结**：页头相对时间从"构建那一刻算一次"改成"每次页面被显示时重算"
（见 `docs/accepted-deviations.md` 第 24 条的追记）。⇒ 今天按本文档的步骤重拍 dump，那一行可能显示
`N 分钟前更新` 而不是 `刚刚更新`。本表的论断是**页头剩下的节点是哪三样**（标题 + 相对时间 + 搜索），
不依赖那一行的文本取值 —— **按节点读**即可，不要把它读成回归。
