/*
 * 列表行的 ForEach key（features/assignments）—— 纯函数、零平台依赖、零 i18n。
 *
 * ## 为什么 key 必须覆盖"这一行渲染出来的状态"
 *
 * ArkUI 的 ForEach 用 key 做**等价类**：key 相同的项被当成"没变"，**复用旧行、不重建**，
 * 行里捕获的还是上一份数据。所以只要有一格会被渲染、又可能在不改变 key 的情况下变，
 * 那一格就会停在旧值上 —— 页面头部（直接读 store）已经更新、行却还是旧的，正是这个形态。
 *
 * **实测事故（t24 设备验收）**：mock 提交作业后课程卡片仍显示"1 未完成作业"。
 * 当时的 key 是 `semesterId|id|hidden|sel`；提交只改了三个**推导计数**，
 * 四个 key 分量一个都没动 ⇒ ForEach 判定"这一项没变" ⇒ 卡片不重建。
 * 这不是 mock 专有：真实路径读掉一条公告（未读数）、站点侧提交一次作业（未完成数）、
 * 文件刷新出新体积，都是同一个形态。
 *
 * ## 规则
 *
 *   key = 数据身份（课程 / 条目 id）+ **这一行渲染出来的状态与派生值**（标记、计数、体积、
 *   上传时间、类型、短标题）+ 交互态（收藏 / 归档 / 屏蔽 / 高亮）。
 *
 * **有意不进 key 的东西**（有边界的取舍，别当成遗漏）：
 *   1. theme / 文案：页面级状态驱动，字符串化成本高；换主题时页面自身会重绘；
 *   2. **时间驱动的文本**（"还剩 X 天"、"3 小时前"）：它随时间变，与刷新无关，
 *      key 化解决不了（要它自己走秒得另加定时器，不在本 ticket 范围）；
 *   3. **长自由文本**（公告正文 HTML、描述）：把它拼进 key 会让 key 与正文同量级
 *      （每行几千字符），代价不成比例；本 ticket 的缺陷类别是**状态标记与派生值**。
 *      同一 id 的正文被站点改写时行不会重建 —— 这条残留缺口写在回报里，要收再收。
 *
 * ## 为什么是独立模块而不是页面里的私有函数
 *
 * key 的等价类是**可以在 host 上钉死**的东西（ArkUI 的复用行为本身在 host 测不到），
 * 而页面文件 import 了 ArkUI。把纯函数放在这里，单测
 * （entry/src/test/ListRowKeys.test.ets）才能直接断言
 * "只有计数不同的两条记录必须给出不同的 key"。
 */

import { Assignment } from '../../domain/model/ContentItem';
import { hasAnswer, hasExcellentHomework } from './AssignmentFilter';

/**
 * 作业列表（AssignmentsPage 的 ForEach）。
 *
 * 这一行的状态格：附件、已提交、已评分、有答案、优秀作业（五枚图标，判据就取
 * 卡片自己用的那三个纯函数 `hasAnswer` / `hasExcellentHomework`）+ 收藏 / 归档 / 高亮。
 * 原 key 有 fav / arch / sel，但**五枚标记与截止时间一个都没进**：
 * 提交一次作业后 `submitted` 从 false 变 true，id 不变 ⇒ 行不重建，
 * 卡片一直显示没有"已提交"对勾（这正是 mock 提交那条链路的可观察后果之一）。
 */
export function assignmentListRowKey(assignment: Assignment, favorite: boolean, archived: boolean,
  selected: boolean): string {
  return assignment.id + '|' + assignment.title + '|' + assignment.deadline
    + '|' + (assignment.submitted ? 'submitted' : 'unsubmitted')
    + '|' + (assignment.graded ? 'graded' : 'ungraded')
    + '|' + (assignment.attachment !== undefined ? 'attach' : 'noattach')
    + '|' + (hasAnswer(assignment) ? 'answer' : 'noanswer')
    + '|' + (hasExcellentHomework(assignment) ? 'excellent' : 'noexcellent')
    + '|' + (favorite ? 'fav' : 'nofav')
    + '|' + (archived ? 'arch' : 'noarch')
    // 高亮态要进 key：否则 ForEach 认为这一项没变、不会重建行（选中态就不会跟着变）。
    + '|' + (selected ? 'sel' : 'nosel');
}
