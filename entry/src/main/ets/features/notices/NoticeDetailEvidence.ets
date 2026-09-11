/*
 * ticket 04 的**取证夹具**（提交态关闭）。
 *
 * ## 为什么需要它
 *
 * 验收第 3 条要求"数学公式正确渲染"、第 4 条要求"正文中的链接可点"。但参考实现
 * `src/data/mock.ts:242-352` 的 7 条公告正文里**既没有 KaTeX 公式、也没有 <a> 链接**
 * （逐条核对过：只有 <p>/<strong>/<span style>）。而 Mock 数据是 ticket 03 已交付且
 * 被单测断言锁定的夹具（条数 7、排序、未读 2），ticket 04 不应为了取证去改它 ——
 * 那会让 ticket 03 的验收基准失效。
 *
 * 所以把"能被截到证据的正文"放在这里，由 `EVIDENCE_DETAIL_CONTENT` 开关决定是否使用：
 *   - 提交态 false：详情页渲染真实 Mock 正文，行为与参考实现一致；
 *   - 取证态 true：**整段替换**详情页的正文，里面含一个行内公式、一个行间公式、
 *     一个指向 learn.tsinghua.edu.cn 的链接（验证 `_csrf` 追加）与一个普通外链。
 *
 * ## 取证要求（AGENTS.md）
 *
 * "取证开关必须自证生效"：开启时 `logEvidenceContentState()` 会把**实际生效值**
 * 打进 hilog（开关值 + 正文字节数 + 是否含公式/链接），所以"没截到公式"与
 * "开关没生效"能区分开。开关值在提交前用 `git show HEAD:<file>` 核对。
 */
import { Logger } from '../../core/log/Logger';

const logger: Logger = new Logger('features.notices.evidence');

/** 取证开关：用夹具正文替换公告正文。**提交态必须为 false**。 */
export const EVIDENCE_DETAIL_CONTENT: boolean = false;

/**
 * 夹具正文：行内 `$...$`、行间 `$$...$$`、站内链接与站外链接各一条。
 * 公式取自 KaTeX 文档里最常见的写法，避免"公式本身写错"与"渲染没生效"混淆。
 */
export const EVIDENCE_CONTENT_HTML: string = '<p>公式渲染取证：行内 <strong>质能方程</strong> '
  + '$E = mc^2$，行间公式如下：</p>'
  + '<p>$$\\int_{-\\infty}^{\\infty} e^{-x^2}\\,dx = \\sqrt{\\pi}$$</p>'
  + '<p>站内链接：<a href="https://learn.tsinghua.edu.cn/f/info/xxfb">learn 公告列表</a></p>'
  + '<p>站外链接：<a href="https://www.example.com/path?a=1&amp;b=2">example.com</a></p>'
  + '<p>深色下的正文对比度：普通段落文字。</p>';

/** 取证态下的正文（关闭时原样返回真实正文）。 */
export function evidenceContentOr(real: string): string {
  return EVIDENCE_DETAIL_CONTENT ? EVIDENCE_CONTENT_HTML : real;
}

/**
 * 取证开关：在详情页显示"切换深浅"控制条。
 *
 * 用途是验收第 5 条「切换深浅色后正文样式即时更新」：**同一份构建内**点一下按钮
 * （本组件 @State 翻转 → HtmlWebView 重建 → 用新 dark 标志重新生成模板），
 * 于是可以截到"切换前 / 切换后"两张**不同**的截图，而不是跨两次源码修改的构建。
 * 提交态 false（那时按钮与代码一起消失）。
 */
export const EVIDENCE_DARK_TOGGLE: boolean = false;

/** 把开关的**实际生效值**打进 hilog（ticket 04 取证要求）。 */
export function logEvidenceContentState(): void {
  logger.info('detail evidence content: enabled=' + EVIDENCE_DETAIL_CONTENT.toString()
    + ' chars=' + EVIDENCE_CONTENT_HTML.length.toString()
    + ' hasInlineMath=' + EVIDENCE_CONTENT_HTML.includes('$E = mc^2$').toString()
    + ' hasDisplayMath=' + EVIDENCE_CONTENT_HTML.includes('$$').toString()
    + ' hasLink=' + EVIDENCE_CONTENT_HTML.includes('<a href=').toString());
}
