# ticket 13（作业提交）证据

**口径**：模拟器 `Pura 90`（串口 `127.0.0.1:5555`，HarmonyOS **6.1.0(23)**）。**不是真机。**

- `git rev-parse HEAD` = `2757ff673149d243b74f236034ab3e0043687c63`
- 工作区**脏**：本 ticket 的改动尚未提交（改动清单见提交信息）。
  - A 轮（只读真实数据）：`MOCK_ASSIGNMENTS_FOR_EVIDENCE=false`，`git status --porcelain` 的 SHA-256 = `4d32622990d67a0c18ba32095dfb56b661a383141bf1dfc0b7deafa2ba53745c`
    （与 B 轮只差 `AssignmentEvidence.ets` 一个布尔值）。
  - B 轮（夹具，让提交页可达）：`MOCK_ASSIGNMENTS_FOR_EVIDENCE=true`，其余字节相同。
- 账号事实：2026-2027 秋季 **0 条**作业；2025-2026 春季 **57 条全部已截止**（见 A1/A4）。
  ⇒ **本轮没有对任何作业发起真实提交。**

## 文件与它证明的那**一个**论断

| 文件 | 论断 |
| --- | --- |
| `A0-launch-state.png` / `A0-layout-launch.json` | 装机后冷启动落在公告 tab（未读 2）；底部五个 tab 与截图一致 —— 证明本轮产物**启动正常**（不是 `ReferenceError` 那一类） |
| `A1-assignments-spring-list.png` | 只读-列表：`--ps lohSemester 2025-2026-2` 进春季后列表为 全部 57 / 未完成 0 / 已完成 57，逐条「已截止」 |
| `B4-layout-document-picker.json` / `B7-layout-all-windows.json` | `devecocli ui layout` 的 dump：**picker 的窗口不在其中**（既不在默认窗口，`--all-windows` 也没有它的节点树）⇒ picker 只能靠截图取证，这也解释了为什么「我的手机」那一行的节点无法用 `--id` 精确定位 |
| `A2-assignment-detail-spring-past.png` | 只读-详情：已截止作业的 chip / 截止时间 + 已截止 / 作业附件 / **已提交**（我的提交附件 + 提交于 2026-06-27 09:58）/ 成绩 10 + 批改人与时间 / 作业内容；**页头右侧是本轮新增的提交入口** |
| `A2-layout-assignment-detail.json` | 同一屏的可访问性树（与截图不同源，作为该屏的辅助证据） |
| `A3-detail-after-past-deadline-tap-toast-not-captured.png` | 点提交入口**之后**的画面（与 A2 同屏）。**toast 未抓到**（截图时延 15–35 s ≫ toast 2000 ms）——这张图**不**充当「toast 出现过」的证据 |
| `A4-hilog-spring-readonly-full.txt` | 只读-日志：`submission entry blocked: past deadline=2026-06-28 23:59`（截止门生效）、`assignments applied: semester=2025-2026-2 source=override items=57`、`assignment detail appear: … submitted=true graded=true completionType=1 submissionType=2 grade=10` |
| `B1-assignments-fixture-list.png` | 夹具构建生效：4 条夹具作业（未完成 2）。**只用于把提交页变得可达**，不代表真实账号状态 |
| `B2-fixture-upcoming-detail-with-entry.png` | 未到期夹具详情（提交入口可点进去） |
| `B3-submission-page-fixture.png` | 提交页**初始态**：标题「作业提交」、右侧「提交」**灰**（内容空 + 无附件 ⇒ `canSubmit=false`）、正文占位「作业内容（可选）」、底部「文件 / 照片」、**没有**自定义名输入 |
| `B3-layout-submission-page.json` | 同一屏的布局树（TextArea / 两个 Button / 「提交」Text 等节点） |
| `B4-document-picker-open.png` | **系统文件选择器能打开**（最近 / 浏览、已选(0)、完成禁用、「仅可访问所选项目」） |
| `B5-document-picker-browse-tab.png` | 文件选择器的「浏览」页签：位置（我的手机 13.79 GB 可用 / 32 GB、我的云盘）、媒体库（图库）、来源（下载与接收、浏览器） |
| `B6-document-picker-my-phone.png` / `B6b-document-picker-my-phone.png` | 「浏览 → 我的手机」两次点击（(340,635) 与 (900,640)）前后**字节完全相同**（sha256 `4fd49f27…a504`）⇒ 该行对 `hdc` 级点击无响应、画面未变 |
| `B7-document-picker-recent-after-push.png` | `hdc file send` 往 `…/Docs/Documents/t13probe.txt` 推入文件后，文件选择器「最近」**仍为空**（「没有文件」） |
| `B8-photo-picker-open.png` | **系统相册选择器能打开**（图片和视频 / 所有相册、安全访问图库、拍照磁贴）；图库为空（系统日志 `itemCount: 0`） |
| `B9-submission-page-after-picker-cancel.png` | 两次取消选择器之后，提交页原样（取消**不是**失败） |
| `B-log-pickers-full.txt` | 取消语义：`PickerSheetPage: onThirdSelectCancel` → `document/photo pick cancelled (empty uri list)` → `submission pick cancelled: source=documents|photos`；相册选择器参数含 `maxSelectCount:1 / isMultiPick:false / bundleName:com.koracan.learnOH` |
| `C1-submission-page-content-typed.png` | 正文输入 `t13-probe` 后页头「提交」变**紫色可用** ⇒ `canSubmit` 由正文驱动 |
| `C2-submit-confirmation-dialog.png` | 点「提交」出现**二次确认**：「提交作业 / 确定提交作业? / 取消 | 确定」 |
| `C3-after-confirm-cancel-content-kept.png` | 点「取消」后回到提交页：`t13-probe` **仍在**、按钮仍可用 |
| `C-log-confirm-cancel-full.txt` | `submission cancelled at the confirmation dialog`，且**没有**任何 `data.assignments.submit sending` 行 ⇒ 整个过程**一个请求都没发** |
| `D1-commit-state-spring-list.png` | 提交态（`MOCK=false`）装机后的真实春季列表（57/0/57）——取证态到提交态的**视觉**转变 |
| `D2-hilog-commit-state-full.txt` | 同一轮日志：`assignments evidence: mock=false …` + `assignments applied: … items=57 unfinished=0 finished=57` |
| `hap-modules-abc-symbols.txt` | 产物级：解 hap 后 `ets/modules.abc` 里本轮符号 = true、历史探针串 = false、`pendingAssignmentData` = false |

## 抓不到 / 未验证（不许当成已证）

1. **服务端接受这一条未验证**（无真实未截止作业）。见 ticket 13 交付第 1 条。
2. **picker 返回 URI → 附件进入状态机这一段未验证**：模拟器用户区为空（B4/B7）、相册为空（B8）、
   「我的手机」行对 `hdc` 点击无响应（B6/B6b）。见交付第 3 条。
3. **上传进度条、失败提示（不丢内容）在设备上未验证**：两者都需要真实请求。
   单测覆盖了分段进度（0→0.25→0.5→1）与 `submitFailed` 的字段保持。
4. **toast 未抓到**（A3）：截图时延远大于 toast 时长；该论断由 hilog 的 `submission entry blocked …` 承担。

## 可重跑的命令

```powershell
# 装机 + 带学期覆盖启动（A 轮）
hdc -t 127.0.0.1:5555 install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc -t 127.0.0.1:5555 shell aa force-stop com.koracan.learnOH
hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b com.koracan.learnOH --ps lohSemester 2025-2026-2
# 截图 / 布局 / 点击 / 输入
devecocli ui screenshot --device 127.0.0.1:5555 --path <file.png>
devecocli ui layout --device 127.0.0.1:5555 --format json
devecocli ui click --device 127.0.0.1:5555 <x> <y>
devecocli ui text --device 127.0.0.1:5555 t13-probe
# 全量拉日志再本地筛（--keyword 会丢 tag，见 AGENTS.md）
devecocli log --device 127.0.0.1:5555 --from 5m > log.txt
```

> 设备上的中间物：`hdc file send` 推进 `…/Docs/Documents/` 的探针文件已在轮次结束前删除（`ls` 为空）。

## 提交与版本对应（取证之后才提交，按 AGENTS 要求写明）

- 取证时的源码版本：`HEAD = 2757ff673149d243b74f236034ab3e0043687c63` + **脏工作区**
  （A 轮 `MOCK=false`：`git status --porcelain` SHA-256 = `4d32622990d67a0c18ba32095dfb56b661a383141bf1dfc0b7deafa2ba53745c`；
  B 轮仅把 `AssignmentEvidence.ets` 的一个布尔值改为 `true`）。
- 取证之后提交为两步：
  - `78e1c3a` docs(ticket13)：台账（偏离 26/27、平台事实 29）与工单交付节；
  - `0456055` feat(ticket13)：本 ticket 的全部代码与单测。
- **提交态与取证态的代码差异 = 0**：提交前已把 `MOCK_ASSIGNMENTS_FOR_EVIDENCE` 复原为 `false`，
  并用 `git show HEAD:…AssignmentEvidence.ets` 核对（输出 `boolean = false`），随后又用提交态产物装机拍下 `D1/D2`。
- 提交时工作区里**唯一**别人未提交的改动是 `.scratch/migration/issues/16-split-view-breakpoints.md`
  （ticket 16 的并行 agent），我没有暂存它；`docs/reference-quirks.md` 里带上了它的第 28 条（提交信息已注明归因）。

