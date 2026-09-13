/*
 * 公告详情（ticket 04）单测：模板拼装（纯区）、详情时间文案、附件名规则、Mock 附件字段。
 *
 * 覆盖 ticket 04 Comments 第 5 节要求的断言语义 —— **不靠截图**：
 *   - 产物包含 viewport / #root / CSRF 注入脚本；
 *   - 深色开关**只**切换 DarkReader 段，浅色产物里没有 DarkReader；
 *   - 空正文落到 noNoticeContent 文案；
 *   - csrfToken 确实被拼进注入脚本（且引号被转义，不能逃逸出字符串字面量）。
 *
 * 另加两类"最容易悄悄错"的纯逻辑：
 *   - 详情时间是**绝对时间 + 星期**（中文 `YYYY 年 M 月 D 日 dddd HH:mm`、
 *     英文 `MMM D, YYYY HH:mm`），与列表的**相对时间**是两条路；
 *   - 附件名规则逐字对齐参考实现 helpers/fs.ts:215-226（含 `a.` 与 `.gitignore` 两个边界）。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  DEFAULT_DARK_BACKGROUND, MEASURE_SCRIPT, TemplateAssets, buildNoticeContent, buildCsrfScript,
  escapeScriptEndTags, getWebViewTemplate, jsStringLiteral, removeTags, sanitizeColor
} from '../main/ets/domain/render/WebViewTemplate';
import {
  NoticeDateText, formatNoticeDate
} from '../main/ets/domain/render/NoticeDateText';
import { getExtension, stripExtension } from '../main/ets/domain/render/FileNames';
import { mockNoticeRecords } from './fixtures/NoticeFixtures';
import { NoticeRecord } from '../main/ets/data/notices/NoticeRepository';
import { Attachment } from '../main/ets/domain/model/ContentItem';

const LEARN_URL: string = 'https://learn.tsinghua.edu.cn';
const SURFACE: string = '#FFFBFF';
const EMPTY_TEXT: string = '无通知内容';
const KATEX_MARK: string = 'KATEX-SCRIPT-MARK';
const DARK_MARK: string = 'DARKREADER-SCRIPT-MARK';
const STYLE_MARK: string = 'KATEX-STYLE-MARK';

/** 一套可辨识的假资产：断言"资产被拼进来了"而不依赖 630 KB 真资产。 */
function assets(withDark: boolean): TemplateAssets {
  return {
    katexStyles: '.katex{' + STYLE_MARK + '}',
    katexScript: '/*' + KATEX_MARK + '*/',
    darkReaderScript: withDark ? '/*' + DARK_MARK + '*/' : undefined
  };
}

function build(content: string, dark: boolean, token: string, withDarkAsset: boolean): string {
  return getWebViewTemplate(content, dark, SURFACE, token, LEARN_URL, assets(withDarkAsset));
}

/** 中文词表（与资源里的 ui_weekday_* 同值）。 */
function chineseWeekdays(): string[] {
  return ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
}

/** 英文词表（与资源里的 ui_month_* 同值）。 */
function englishMonths(): string[] {
  return ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
}

function chineseText(): NoticeDateText {
  return {
    pattern: 'YYYY 年 M 月 D 日 dddd HH:mm',
    weekdays: chineseWeekdays(),
    months: englishMonths(),
    am: '',
    pm: ''
  };
}

function englishText(): NoticeDateText {
  return {
    pattern: 'MMM D, YYYY HH:mm',
    weekdays: chineseWeekdays(),
    months: englishMonths(),
    am: '',
    pm: ''
  };
}

/** 参考实现 mock.ts 的公告：'2020-09-08 21:46'（不含星期，靠 Date 求）。 */
function septemberEighth(): number {
  return new Date(2020, 8, 8, 21, 46, 0, 0).getTime();
}

export default function noticeDetailTest() {
  describe('features.notices.detail.WebViewTemplate', () => {
    it('keeps the reference template skeleton', 0, () => {
      const html: string = build('<p>正文</p>', false, '', false);
      expect(html.includes('<!DOCTYPE html>')).assertTrue();
      expect(html.includes('<meta name="viewport" content="width=device-width, initial-scale=1" />')).assertTrue();
      expect(html.includes('<div id="root">')).assertTrue();
      expect(html.includes('正文')).assertTrue();
      // 模板样式：body padding 与 #root 的两条规则（照参考实现 html.ts:40-48）。
      expect(html.includes('padding: 1rem;')).assertTrue();
      expect(html.includes('#root {')).assertTrue();
      expect(html.includes('#root > p:first-child {')).assertTrue();
      expect(html.includes('#root > p:last-child {')).assertTrue();
      // CSP 与数学渲染调用。
      expect(html.includes('upgrade-insecure-requests')).assertTrue();
      expect(html.includes('renderMathInElement(document.querySelector("#root")')).assertTrue();
      expect(html.includes('throwOnError: false')).assertTrue();
      // 资产被拼进来。
      expect(html.includes(STYLE_MARK)).assertTrue();
      expect(html.includes(KATEX_MARK)).assertTrue();
    });

    it('never leaves a placeholder token behind', 0, () => {
      const dark: string = build('<p>x</p>', true, 'tok', true);
      const light: string = build('<p>x</p>', false, 'tok', false);
      expect(dark.includes('learnoh:head')).assertFalse();
      expect(dark.includes('learnoh:dark')).assertFalse();
      expect(dark.includes('learnoh:katex')).assertFalse();
      expect(light.includes('learnoh:dark')).assertFalse();
      // 深色开关只切 DarkReader 段：其它结构在两条路径上完全一致。
      const darkBody: string = dark.split('/*' + DARK_MARK + '*/').join('DARK');
      const lightBody: string = light;
      expect(darkBody.includes('DARK')).assertTrue();
      expect(lightBody.includes(DARK_MARK)).assertFalse();
      expect(lightBody.includes('DarkReader')).assertFalse();
      expect(lightBody.includes('darkSchemeBackgroundColor')).assertFalse();
    });

    it('injects the dark reader only when dark is on', 0, () => {
      const dark: string = build('<p>x</p>', true, '', true);
      expect(dark.includes(DARK_MARK)).assertTrue();
      expect(dark.includes('DarkReader.enable({')).assertTrue();
      expect(dark.includes('darkSchemeBackgroundColor: ' + jsStringLiteral(SURFACE))).assertTrue();
      const light: string = build('<p>x</p>', false, '', true);
      expect(light.includes(DARK_MARK)).assertFalse();
    });

    it('injects the csrf token into the link rewriter', 0, () => {
      const withToken: string = build('<p>x</p>', false, 'TOKEN-123', false);
      expect(withToken.includes('addCSRFTokenToUrl')).assertTrue();
      expect(withToken.includes('tsinghua.edu.cn')).assertTrue();
      expect(withToken.includes("var csrfToken = 'TOKEN-123';")).assertTrue();
      const withoutToken: string = build('<p>x</p>', false, '', false);
      expect(withoutToken.includes("var csrfToken = '';")).assertTrue();
      // 注入脚本里的 learn 站点前缀来自参数。
      expect(withToken.includes(jsStringLiteral(LEARN_URL))).assertTrue();
    });

    it('escapes a hostile csrf token instead of breaking out of the literal', 0, () => {
      const hostile: string = "'+alert(1)+'";
      const script: string = buildCsrfScript(hostile, LEARN_URL);
      // 未转义的形态必须消失；留下的是被反斜杠转义的那个（于是它只是字符串内容）。
      expect(script.includes("'"+'+alert(1)+'+"'")).assertFalse();
      expect(script.includes("\\'" + '+alert(1)+' + "\\'")).assertTrue();
      const backslash: string = buildCsrfScript('a\\b', LEARN_URL);
      expect(backslash.includes("'a\\\\b'")).assertTrue();
    });

    it('falls back to the no-notice-content paragraph', 0, () => {
      expect(buildNoticeContent('', EMPTY_TEXT)).assertEqual('<p>' + EMPTY_TEXT + '</p>');
      expect(buildNoticeContent('   \n  ', EMPTY_TEXT)).assertEqual('<p>' + EMPTY_TEXT + '</p>');
      expect(buildNoticeContent('<p>有正文</p>', EMPTY_TEXT)).assertEqual('<p>有正文</p>');
      const html: string = build(buildNoticeContent('', EMPTY_TEXT), false, '', false);
      expect(html.includes(EMPTY_TEXT)).assertTrue();
    });

    it('escapes script end tags in the notice content', 0, () => {
      const content: string = '<p>a</p><script>alert(1)</script>';
      const escaped: string = escapeScriptEndTags(content);
      expect(escaped.includes('</script')).assertFalse();
      expect(escaped.includes('<\\/script')).assertTrue();
      const html: string = build(buildNoticeContent(content, EMPTY_TEXT), false, '', false);
      // 正文里只应剩下模板自己的两个 </script>（CSRF 段与 katex 段 + 数学调用段），
      // 正文那个已被转义。
      const occurrences: number = html.split('</script').length - 1;
      expect(occurrences).assertEqual(3);
    });

    it('sanitises the dark background colour', 0, () => {
      expect(sanitizeColor('#1E1A1D')).assertEqual('#1E1A1D');
      expect(sanitizeColor('rgb(30, 26, 29)')).assertEqual('rgb(30, 26, 29)');
      expect(sanitizeColor('')).assertEqual(DEFAULT_DARK_BACKGROUND);
      expect(sanitizeColor(undefined)).assertEqual(DEFAULT_DARK_BACKGROUND);
      // 注入尝试回退到默认色，不进入 JS 字面量。
      expect(sanitizeColor('");alert(1);//')).assertEqual(DEFAULT_DARK_BACKGROUND);
      const html: string = build('<p>x</p>', true, '', true);
      expect(html.includes('alert(1)')).assertFalse();
    });

    it('measures the content height with the reference max() formula', 0, () => {
      expect(MEASURE_SCRIPT.includes('Math.max(')).assertTrue();
      expect(MEASURE_SCRIPT.includes('documentElement')).assertTrue();
      expect(MEASURE_SCRIPT.includes('scrollHeight')).assertTrue();
      expect(MEASURE_SCRIPT.includes('clientHeight')).assertTrue();
      expect(MEASURE_SCRIPT.includes('getElementById(\'root\')')).assertTrue();
      // 桥 + console 兜底两条回传通道都在（取证要求：不能只有一个静默通道）。
      expect(MEASURE_SCRIPT.includes('learnOHBridge')).assertTrue();
      expect(MEASURE_SCRIPT.includes('learnoh:height:')).assertTrue();
      // 原生侧要能主动再测一次。
      expect(MEASURE_SCRIPT.includes('window.learnOHMeasure = measure')).assertTrue();
    });
  });

  describe('features.notices.detail.NoticeDateText', () => {
    it('formats the Chinese absolute time with the weekday', 0, () => {
      // 2020-09-08 是星期二（参考实现 dayjs 'dddd' 的 zh-CN 长格式）。
      expect(formatNoticeDate(septemberEighth(), chineseText())).assertEqual('2020 年 9 月 8 日 星期二 21:46');
      const singleDigitMinutes: number = new Date(2020, 8, 25, 7, 21, 0, 0).getTime();
      expect(formatNoticeDate(singleDigitMinutes, chineseText())).assertEqual('2020 年 9 月 25 日 星期五 07:21');
    });

    it('formats the English absolute time with the month name', 0, () => {
      expect(formatNoticeDate(septemberEighth(), englishText())).assertEqual('Sep 8, 2020 21:46');
      const august: number = new Date(2020, 7, 17, 22, 30, 0, 0).getTime();
      expect(formatNoticeDate(august, englishText())).assertEqual('Aug 17, 2020 22:30');
    });

    it('does not pad month and day (dayjs M/D semantics)', 0, () => {
      const january5: number = new Date(2021, 0, 5, 9, 5, 0, 0).getTime();
      expect(formatNoticeDate(january5, chineseText())).assertEqual('2021 年 1 月 5 日 星期二 09:05');
      expect(formatNoticeDate(january5, englishText())).assertEqual('Jan 5, 2021 09:05');
    });

    it('keeps the remaining literal text untouched', 0, () => {
      const text: NoticeDateText = {
        pattern: 'YYYY/MM/DD HH:mm',
        weekdays: chineseWeekdays(),
        months: englishMonths(),
        am: 'AM',
        pm: 'PM'
      };
      expect(formatNoticeDate(septemberEighth(), text)).assertEqual('2020/09/08 21:46');
      const twelveHour: NoticeDateText = {
        pattern: 'h:mm A',
        weekdays: chineseWeekdays(),
        months: englishMonths(),
        am: 'AM',
        pm: 'PM'
      };
      expect(formatNoticeDate(septemberEighth(), twelveHour)).assertEqual('9:46 PM');
      const midnight: number = new Date(2020, 8, 8, 0, 7, 0, 0).getTime();
      expect(formatNoticeDate(midnight, twelveHour)).assertEqual('12:07 AM');
    });
  });

  describe('features.notices.detail.FileNames', () => {
    it('matches the reference strip/get extension semantics', 0, () => {
      expect(stripExtension('a.b.pdf')).assertEqual('a.b');
      expect(getExtension('a.b.pdf')).assertEqual('pdf');
      expect(stripExtension('noext')).assertEqual('noext');
      expect(getExtension('noext')).assertEqual(undefined);
      // 参考实现的两个边界：以点结尾 → 扩展名是空串；隐藏文件 → 整体当扩展名。
      expect(stripExtension('a.')).assertEqual('a');
      expect(getExtension('a.')).assertEqual('');
      expect(stripExtension('.gitignore')).assertEqual('');
      expect(getExtension('.gitignore')).assertEqual('gitignore');
      // mock 里的附件名（含重复汉字）。
      const name: string = '附件附件附件附件附件附件附件附件附件附件附件附件附件附件附件附件.pdf';
      expect(getExtension(name)).assertEqual('pdf');
      expect(stripExtension(name).endsWith('附件')).assertTrue();
    });
  });

  describe('features.notices.detail.SeedAttachment', () => {
    it('carries the reference attachment exactly once', 0, () => {
      const items: NoticeRecord[] = mockNoticeRecords();
      const withAttachment: NoticeRecord[] = [];
      for (const item of items) {
        if (item.attachment !== undefined) {
          withAttachment.push(item);
        }
      }
      expect(withAttachment.length).assertEqual(1);
      const attachment: Attachment | undefined = withAttachment[0].attachment;
      expect(attachment !== undefined).assertTrue();
      if (attachment !== undefined) {
        expect(attachment.id).assertEqual('1998990181_ZY_1604316692859411626215e-c233-4663-a567-a932bf4d4962');
        expect(attachment.name).assertEqual('附件附件附件附件附件附件附件附件附件附件附件附件附件附件附件附件.pdf');
        expect(attachment.downloadUrl.startsWith('https://')).assertTrue();
      }
      expect(withAttachment[0].id).assertEqual('26ef84e76db3f55b016db4c4e8832da6');
      expect(withAttachment[0].courseName).assertEqual('基于数字信号处理器的系统设计');
      expect(withAttachment[0].courseTeacherName).assertEqual('窦维蓓');
    });
  });

  /**
   * removeTags —— 参考实现 helpers/html.ts:11-22 的等价物。ticket 09 补齐；它同时服务
   * 卡片标题、卡片正文预览与详情页标题。
   */
  describe('features.notices.detail.RemoveTags', () => {
    it('stripsCommentsTagsDecodesEntitiesAndCollapsesWhitespace', 0, () => {
      expect(removeTags('<!-- c --><p>Hello</p>')).assertEqual('Hello');
      expect(removeTags('<p>a</p>\n  <p>b</p>')).assertEqual('a b');
      expect(removeTags('  <span>  x  </span>  ')).assertEqual('x');
      expect(removeTags('<p>&nbsp;&nbsp;</p>')).assertEqual('');
    });

    it('decodesTheFullEntitySetIncludingNumericOnes', 0, () => {
      // 参考实现用 he.decode（全实体集）：命名实体 + &#39; / &#x27; 数字实体。
      expect(removeTags('a &amp; b &lt;c&gt; &quot;d&quot; &#39;e&#39; &#x27;f&#x27;'))
        .assertEqual(`a & b <c> "d" 'e' 'f'`);
      expect(removeTags('x&nbsp;y')).assertEqual('x y');
      expect(removeTags('r&eacute;sum&eacute;')).assertEqual('résumé');
    });

    it('keepsUnknownEntitiesVerbatimInsteadOfDroppingThem', 0, () => {
      // he 对未知实体名也是原样保留——照做，不要"顺手清掉"。
      expect(removeTags('a &notanentity; b')).assertEqual('a &notanentity; b');
      expect(removeTags('100% & &;')).assertEqual('100% & &;');
    });

    it('returnsAnEmptyStringForEmptyInputAndForUnclosedMarkup', 0, () => {
      expect(removeTags('')).assertEqual('');
      expect(removeTags(undefined)).assertEqual('');
      // 未闭合的 '<' 与未闭合的注释：参考实现的正则匹配不到 ⇒ 原样保留。
      expect(removeTags('a < b')).assertEqual('a < b');
      expect(removeTags('a <!-- b')).assertEqual('a <!-- b');
    });

    it('makesTheRealNoticeTitleReadable', 0, () => {
      // 真实公告形状：标题含标签与实体（ticket 09 的模拟器取证里 ggnrStr 就是这个形态）。
      // 单层解码：&amp;nbsp; → &nbsp;（**不再二次解码**，与 he.decode 一致）。
      // 真实记录的 ggnrStr 就是把正文实体化成这个样子；卡片拿到的是 ggnr 解码后的 HTML。
      expect(removeTags('&lt;p&gt;课程信息&amp;nbsp;与微信群&lt;/p&gt;'))
        .assertEqual('<p>课程信息&nbsp;与微信群</p>');
    });
  });
}
