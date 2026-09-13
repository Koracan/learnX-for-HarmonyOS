# 02: 文件详情与课程详情顶栏改用图标

**What to build:** 文件详情与课程详情的顶栏按钮从文字改成图标，与公告详情、作业详情的顶栏一致；图标取自应用内嵌的那套字形字体，不再出现文字与图标混合的形态。
字体未就绪时的可读文本回退必须继续可用，无障碍文案必须继续可读。

**Blocked by:** None（可立即开始）

**Status:** verified-partial（统筹者已复核：主树合并态全绿；一项设备帧未取到，见 Comments）

- [x] 图标闭集新增五个成员：刷新、分享、外跳、信息、预览；每个都有唯一映射
- [x] 文件详情顶栏的返回 / 刷新 / 分享 / 预览是图标；课程详情顶栏的返回是图标
- [x] 图标按钮仍带无障碍文案；字体未就绪时回退成可读文案而非图标短名
- [x] 点击区域尺寸与改动前一致（不因为换成图标而变小）
- [x] 证据：顶栏 layout dump 的 bounds（图标形态）+ 同状态截图

## Comments

**2026-09-13 · wt/t02 · commit 9437c15**

变了什么：`AppIcon` 新增 REFRESH / SHARE / OPEN_IN_NEW / PREVIEW / INFO 五个成员与五条
`iconSpec` 映射（码位按图标名从随包 TTF 的 cmap 表反查，逐条确认字形存在）；
`FileDetailPage` 顶栏的返回 / 刷新 / 分享 / 详情-预览切换改成图标按钮，
`CourseDetailPage` 页头的返回改成图标；两者点击目标统一为外层 `Stack` 的
40vp×40vp（`sizes.controlHeight`），`label` 继续传可读 i18n 文案。

设备证据（Pura 90 / phone / 127.0.0.1:5557 / API 23）：
- 文件详情顶栏三个命中区各 `[56,178,196,318]` / `[942,178,1082,318]` / `[1124,178,1264,318]`
  ⇒ **140×140 px = 40vp×40vp**（密度 3.5；相邻间隙 42 px = 12vp `space3`，与改动前逐点相同）。
- 课程详情返回命中区 `[56,192,196,332]` ⇒ 140×140 px。
- 点刷新图标后 hilog：`refresh=true` → `GET …` → `done bytes=223208183`（12:54:05→12:54:14）。
- 证据文件在 `.scratch/ui-optimize/evidence/t02/`（含 README 逐文件论断表）。

未闭合：**"详情 / 预览"图标的设备截图没抓到** —— 它只在
`previewable() && localPath.length > 0` 时出现，而本机 mock 数据里文件全是 ZIP、
课程文件页为空、公告无附件，取不到可复现输入。该按钮只在代码层与单测（码位映射）覆盖。

门禁：domain-purity PASS、import-graph PASS、check-i18n-keys `RESULT: OK`、
单测 `Tests run: 391, Failure: 0, Error: 0`（基线 390）、assembleHap 无 ERROR/ErrorCode。
`check-generated-fresh` 在本 worktree FAIL，但与本次改动无关：那 6 个生成物与 HEAD
内容完全相同（`git diff --quiet` exit 0），差异只是 `core.autocrlf=true` 下工作区 CRLF 与
生成器写出的 LF 不同；同样的命令在主树（文件为 CRLF）PASS。详见证据 README。
### 2026-09-13 · 统筹者复核（合并进 main 后的验收）

**判 verified-partial。** 已达成：闭集 26→31 且映射唯一、文件详情顶栏按钮图标化、课程详情返回图标化、label 仍传可读文案、点击区不小于改动前。

**我独立复核的东西（不采信自述）**：
- 自己解析 filedetail-topbar-layout.json（root [0,0,1320,2856] = Pura 90 竖屏、密度 3.5），可点击节点恰好三个 Stack：
  [56,178,196,318] / [942,178,1082,318] / [1124,178,1264,318]，**各 140×140 px = 40vp×40vp**，与回报一致。
- 主树合并态（ticket 02 + 09）：单测 **Tests run: 392, Failure: 0, Error: 0**（基线 390，两个 ticket 各 +1）；
  四门禁脚本全绿；assembleHap --no-incremental 无 ERROR/ErrorCode，产物重刷；
  解包 hap 在 ets/modules.abc 里检索到 open-in-new / [refresh] / [preview] / [info] / [external] / [share]（产物级证据，排除陈旧产物假绿）。

**仍未闭合（如实记账，不当作已验）**：
1. 「详情 / 预览」按钮**没有设备帧**：它只在"文件可预览且已落盘"时渲染，而本机文件全是 ZIP、课程文件页为空 ⇒ 取不到输入。
   处置：留待统筹者用学期覆盖（aa start --ps lohSemester=…）在有可预览文件的学期上补一帧；补不上就永久记为"未验"，不写成"不存在"。
2. **字体未就绪的回退分支未在设备上制造**（本轮字体就绪）。回退分支本身未被本 ticket 改动，风险低，但"未验"就是"未验"。

**待账号所有者裁定的一条（不阻塞本 ticket）**：OPEN_IN_NEW 只声明、零渲染（参考实现的"跳系统打开方式"是本工程有意去掉的动作，且没有可读文案键）。本 ticket 的验收只要求"闭集新增五个成员、每个都有唯一映射"，故判达成。
