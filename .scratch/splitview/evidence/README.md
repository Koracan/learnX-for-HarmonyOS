# ticket 16（断点分栏）取证记录

**来源一律是「模拟器」**（两台都在本机跑，不是真机；真机只做 ticket 18 的最终一次性复验）。

- 双栏达标设备：**MatePad Pro 13**（模拟器，tablet，串口 `127.0.0.1:5557`，2880×1920 px @320dpi ⇒ **1440×960 vp** 横向）
- 单栏基线设备：**Pura 90**（模拟器，phone，串口 `127.0.0.1:5555`，1320×2856 px ⇒ 约 **377×749 vp** 竖向）
- 构建：`assembleHap --no-incremental`；应用包 `com.koracan.learnOH`
- **HEAD**：`92a080adf5ea2a3af011e75ea8a311f405dc8c6d`（工作区脏：21 项，`git status --porcelain` 的 SHA256 =
  `B1A56B8FBE9D7F709D060AF4929DFC08BF5776D8E769C41D1227BB8BB4FC54D1`）
- 取证期间源码未再改动，**唯一例外**已单独标注（C1 那次取证用的是临时构建期开关，取完即复原，
  复原后的重建产物另拍 A11；`git diff -- entry/src/main/ets/pages/Index.ets` 为空）

## 逐文件论断表

| 文件 | 它**只**支撑这一个论断 | 关键数字 / 说明 |
| --- | --- | --- |
| `A-log-tablet-coldstart.txt` | 平板上的**断点判据实际生效值 = 双栏** | `split view decision: active=true measured=0x0 fallback=1440x960 breakpoint=750 masterWidth=393` → 随后 `active=true measured=1440x893`（实测渲染区 1440×893 vp） |
| `A1-tablet-split-notices-empty-right.png` + `-layout.json` | 平板上**并排两栏**且右栏是"未选中"空态 | master `Refresh [0,250,786,1752]` ⇒ 786 px = **393 vp**；右栏空态"无内容"居中在 x≈1834（右栏从 788 px 起 = 393vp + 1vp 分隔线） |
| `A2-tablet-split-notice-detail-right-highlight-left.png` + `-layout.json` | **验收 2**：主栏选中项显示在右栏，且主栏保留高亮 | 左栏仍是那两条公告；右栏 `Scroll [788,158,2880,1752]` 是公告详情；截图里第一行卡片为选中底色（未选中的第二行仍是白底） |
| `A5-tablet-split-files-list.png` + `-layout.json` | 换一个 tab（文件）**同样是双栏** | master `Refresh [0,242,786,1752]`；右栏空态 |
| `A6-tablet-split-file-detail.png` + `-layout.json` | 双栏里文件详情落在右栏、页头出现**全屏按钮** | 右栏 `返回` 在 x=820；右上 `Row [2638,102,2686,150]` 就是全屏按钮（AppIcon.FULLSCREEN） |
| `A7-tablet-file-detail-fullscreen-master-hidden.png` + `-layout.json` | **验收 4 前半**：全屏切换真的把主栏收掉了 | 详情页 `返回` 移到 x=34（整屏），右上按钮换成 fullscreen-exit 字形 |
| `A8-tablet-exit-fullscreen-split-restored.png` + `-layout.json` | **验收 4**：退出全屏后**双栏原样恢复** | master 回到 `Refresh [0,242,786,1752]`；`返回` 回到 x=820；按钮换回 fullscreen |
| `A9-tablet-back-from-detail-still-split.png` + `-layout.json` | **验收 4 后半**：从详情返回后**布局状态不丢**（仍是双栏 + 主栏可见） | 仍是 786 px 主栏；右栏回到空态 |
| `A10-tablet-coldstart-split.png` | 冷启动即双栏（不是"进过某个页面才有"） | 与 A11 同态的另一次冷启动 |
| `A11-tablet-shipped-build-shell-split.png` + `-layout.json` | **复原开关后的交付构建**表现正常（登录页覆盖已消失） | 同一个包（hap 时间戳 02:26:23）在平板上启动即主壳 + 双栏；`git diff -- Index.ets` 为空 |
| `A-log-tablet-full.txt` | 消费点自证：点击与全屏开关走的是**双栏分支** | `file tapped: … split=true`；`file detail fullscreen toggle: masterHidden=true/false split=true` |
| `B1-phone-single-notices-list.png` + `-layout.json` | **验收 1**：电话形态（377 vp）**是单栏** | 列表 `Refresh [0,437,1320,2562]` 铺满屏宽；**没有**第二个导航容器、没有分隔线 |
| `B-log-phone-full.txt` | 电话上的断点判据实际生效值 = 单栏 | `split view decision: active=false measured=377.14285714285717x749.1428571428571 breakpoint=750` |
| `B2-phone-single-notice-detail.png` + `-layout.json` | **验收 1 / 单栏那一半**：电话上详情仍是**整屏**（行为与 ticket 03/04 一致） | `Scroll [0,276,1320,2562]` 整屏；只有本 tab 的栈 |
| `B3-phone-tab-switch-back-detail-kept.png` + `-layout.json` | **ticket 03 的"切 tab 保留状态"未被破坏** | 切到"文件"再切回"公告"后，公告详情仍在栈上；其 layout JSON 正文与 `B2-…-layout.json` **逐字节相同**（sha256 都是 `8d22be3a…b879`） |
| `C1-tablet-login-landscape-maxwidth.png` + `-layout.json` | **统筹追加的第 7 条**：登录页在 ≥750vp 横向**不整屏拉伸** | 平板上两个输入框与「登录」按钮都是 `[960,*,1920,*]` ⇒ **960 px = 480 vp**，且居中（屏中心 1440 = 表单中心）；修复前同机实测是 `w=2848`（≈1424 vp） |
| `D-log-rotate-resize-unavailable.txt` + `D1-…-layout.json` + `D2-…png` | **反证**：本环境**无法**触发旋转/缩放（验收 3 的运行期触发条件） | `emulator rotate/fold` 要 Emulator ≥7.0（当前 6.1.1.300）；`aa start --ww/--wh` 被忽略（dump 仍 2880×1920）；设备无 `wm`；WMS hidumper 只读；多任务上滑无效果 |

## 未抓到 / 未验证（详见工单交付节）

1. **验收 3 的运行期一半（旋转或缩放窗口时详情不丢、不重复请求）没有抓到**：本环境没有任何可用的
   窗口尺寸/方向触发手段（见 D 系列），因此"尺寸变化 → 双向迁移"这条路只在**单测**里被钉住
   （`entry/src/test/SplitView.test.ets`），没有设备截图；"详情页没有被重建、也没有第二次取数"
   这一条同样未抓到。
2. **登录页那次取证的"开关自证"hilog 行没抓到**（`pages.index evidence login-page override`）：那次启动
   发生在设备锁屏期间，该时段的 hilog 缓冲里**没有应用域（A04c4f）的行**（同一窗口只有 SCB/WMS 行）。
   自证由消费点本身承担——屏幕上渲染出来的就是**生产用的 LoginPage**，且它的 `TextInput`/`Button`
   几何量就是本条的判据；开关的复原由 A11 那张截图 + `git diff` 为空承担。
   开关补丁留在 `.dsh/logs/t16-login-override.patch`（已 gitignore）。
3. 登录页只验了 **≥750vp 横向**（平板 1440 vp）与单栏电话的版式两端；平板上登录表单在**竖屏**那一格没量
   （平板不能旋转，见 D 系列）。
