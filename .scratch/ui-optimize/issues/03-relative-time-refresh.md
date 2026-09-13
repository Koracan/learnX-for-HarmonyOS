# 03: 页头相对时间不再冻结

**What to build:** 页头的相对更新时间在每次页面被显示时重新计算，而不是在页面构造那一刻算一次就冻住。
用户从别的 tab 切回来、或从后台回到前台，看到的时间必须是当下的；四个档位（刚刚 / N 分钟 / N 小时 / N 天）的措辞不变。

**Blocked by:** None（可立即开始）

**Status:** ready-for-agent

- [ ] 页面重新显示时，页头时间文本按当前时间重算
- [ ] 档位边界（59 秒 / 60 秒 / 59 分钟 / 60 分钟 / 23 小时 / 24 小时）仍由既有单测钉住且全绿
- [ ] 页面重新显示这件事有一个可命名的动作，四个列表页共用同一个模式（不各写一套）
- [ ] 证据：同一台设备上「进页面 → 等 ≥2 分钟 → 切走再切回」两帧截图/布局文本，时间文本确实变了

## Comments

### 2026-09-13 · 统筹者派单前的约束与提示（不是验收条款，是省你一轮返工的现场情报）

**现状（我已读过代码，四个页面同构）**：页头那一行是各页自己的方法，形如
`private updatedText(): string { return updatedTimeText(this.store.fetchedAtMillis, Date.now()); }`
（`NoticesPage.ets:156`、`AssignmentsPage.ets:236`、`CoursesPage.ets:221`、`FilesPage.ets:202`），
在 `build()` 里被调用一次。`updatedTimeText` 本身是**纯函数且有单测**（`ui/components/UpdatedTime.ets`）——
**把它改掉不是本 ticket 的做法**：它没错，错的是"只在页面构建那一刻算了一次"。

**三条硬约束**：
1. **一个可命名的动作，四处订阅同一个契约**：不要四个页面各写一个定时器 / 各写一套 `aboutToAppear` 重算。
   形状建议（名字可改、契约不可散）：`features/shell/PageShown.ets` 导出 `PAGE_SHOWN_TICK_KEY` 与 `markPageShown()`，
   四个列表页各自声明同一个 `@StorageProp(PAGE_SHOWN_TICK_KEY)`；动作只在这个文件里实现一次。
2. **两个触发源必须汇进同一个动作**：切 tab（`ShellTabs.ets:364` 的 `.onChange`）与回到前台（`EntryAbility.ets:185` 的 `onForeground`，目前只有一行日志）。
3. **事件驱动，不是心跳**：不要为了这一行加 1 秒定时器 —— 工单要求的是"页面被显示时重算"，不是"持续刷新"。

**两个坑（我替你先踩了）**：
- **`onPageShow` 在这四个页面上不存在**：它是 `@Entry` 页面级生命周期，而这四个是 shell 里的子组件（`TabContent(){ NoticesPage() }`）。所以必须从上往下发信号，别在页面内部找生命周期回调。
- **`ShellTabs` 自己重绘 ≠ 子页面重绘**：`.onChange` 里给 `this.activeIndex` 赋值只会重绘 `ShellTabs`，`TabContent` 的子组件实例是持久的、`build()` 不会重跑。这就是现在时间会冻住的原因 —— 也让"顺手在 onChange 里改个 state 就完事"这种做法**看起来像修好了、实际没修**。

**验收口径提醒**：工单只要求**既有**四档边界单测仍然全绿（不是新增边界测试）；新增的可测部分请只钉你能钉的（例如动作把计数推进了、纯函数在给定的 (fetchedAt, now) 下给出预期档位），
**不要**在单测里断言"UI 重绘了" —— 那只有设备能给答案。设备证据按工单写：同一台设备、同一状态、间隔 ≥2 分钟、切走再切回，两帧的**布局文本**里那一行必须不同（截图 + layout dump 各留一份）。
**不许改设备时钟**（会牵动别人的登录会话与 TLS 校验）—— 就等真实的两分钟。
