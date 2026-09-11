/*
 * 公告详情的时间文案 —— **纯函数**，零平台依赖（见 scripts/check-domain-purity.mjs）。
 *
 * 逐条对齐参考实现 `reference/learnOH-old/src/screens/NoticeDetail.tsx:84-92`：
 *
 *   中文：`YYYY 年 M 月 D 日 dddd HH:mm`（`dddd` = 星期几，**含星期**）
 *   英文：`MMM D, YYYY HH:mm`（月份缩写）
 *
 * 三处必须照抄、别"顺手统一"：
 *  1. 详情用**绝对时间**，列表用**相对时间**（`fromNow()`）。两者不同是参考实现的现状。
 *  2. 月/日/时/分按 dayjs 的 `M`/`D`/`H`/`m` 取值：**不补零**，
 *     所以是 `2020 年 9 月 8 日`；时分在参考实现里也是 24 小时制且**不补零**（`9:49`）。
 *  3. 星期几是 dayjs 的 `dddd` 长格式（`星期二`），不是 `ddd`（`周二`）。
 *
 * 为什么不用 `Intl.DateTimeFormat`：本函数要 host 单测与设备上给出**同一串**字符，
 * 而 host 单测环境不加载 ICU（见 core/i18n/DateTimeUtil.ets 的既有教训），
 * `formatToParts` 的件名在两种环境下不保证一致。故用"文案模式 + 词表"的显式实现，
 * 与 core/i18n/DateTimeUtil.getSemesterTextFromId 同一策略（模式与词表都来自资源）。
 */

/** 日期文案参数：模式与词表都来自 i18n 资源（不在这里硬编码语言）。 */
export interface NoticeDateText {
  /**
   * 输出模式，取自 i18n 资源（`loh_notice_publish_time`）：
   * 中文 `YYYY 年 M 月 D 日 dddd HH:mm`、英文 `MMM D, YYYY HH:mm`。
   */
  pattern: string;
  /** 星期几长表，0 = 周日（`loh_weekday_sunday` … `loh_weekday_saturday`）。 */
  weekdays: string[];
  /** 月份缩写表，0 = 一月（`loh_month_jan` … ）。 */
  months: string[];
  /**
   * 12 小时制的上午/下午词，只被模式里的 `A` 记号用到。参考实现两种语言都用 24 小时制
   * （`HH:mm`）、都含 `A`，参考字典里也没有 am/pm 键，故留空是正常状态。
   */
  am: string;
  pm: string;
}

/** 补零到两位（`DD` / `HH` / `mm`）。 */
function pad2(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

/** 词表取值（越界或空词表时退回数字，绝不留空）。 */
function wordAt(words: string[], index: number, fallback: string): string {
  if (index >= 0 && index < words.length) {
    const word: string = words[index];
    if (word.length > 0) {
      return word;
    }
  }
  return fallback;
}

/**
 * 按模式渲染一个瞬时时间。只支持参考实现用到的记号：
 * `YYYY` `MM` `M` `DD` `D` `dddd` `HH` `H` `hh` `h` `mm` `m` `A`。
 * 实现方式是逐字符扫描并按最长记号优先匹配（不依赖正则的 `match` 结构类型）。
 */
export function formatNoticeDate(millis: number, text: NoticeDateText): string {
  const date: Date = new Date(millis);
  // 顺序即最长记号优先：`MMM` 必须在 `MM`/`M` 之前，否则 'MMM' 会被拆成 'MM'+'M'
  // （实测会渲染出 `099 8, 2020`：'09' + 字面量 '9'）。`dddd` 同理要在 `DD`/`D` 之前。
  const table: string[] = ['YYYY', 'dddd', 'MMM', 'MM', 'DD', 'HH', 'hh', 'mm', 'M', 'D', 'H', 'h', 'm', 'A'];
  let out: string = '';
  let i: number = 0;
  const pattern: string = text.pattern;
  while (i < pattern.length) {
    let matched: string = '';
    for (const token of table) {
      if (pattern.startsWith(token, i)) {
        matched = token;
        break;
      }
    }
    if (matched.length === 0) {
      out = out + pattern.charAt(i);
      i++;
      continue;
    }
    i += matched.length;
    if (matched === 'YYYY') {
      out = out + date.getFullYear().toString();
    } else if (matched === 'dddd') {
      out = out + wordAt(text.weekdays, date.getDay(), date.getDay().toString());
    } else if (matched === 'MMM') {
      out = out + wordAt(text.months, date.getMonth(), (date.getMonth() + 1).toString());
    } else if (matched === 'MM') {
      out = out + pad2(date.getMonth() + 1);
    } else if (matched === 'M') {
      out = out + (date.getMonth() + 1).toString();
    } else if (matched === 'DD') {
      out = out + pad2(date.getDate());
    } else if (matched === 'D') {
      out = out + date.getDate().toString();
    } else if (matched === 'HH') {
      out = out + pad2(date.getHours());
    } else if (matched === 'H') {
      out = out + date.getHours().toString();
    } else if (matched === 'hh') {
      out = out + pad2(hour12(date));
    } else if (matched === 'h') {
      out = out + hour12(date).toString();
    } else if (matched === 'mm') {
      out = out + pad2(date.getMinutes());
    } else if (matched === 'm') {
      out = out + date.getMinutes().toString();
    } else if (matched === 'A') {
      out = out + (date.getHours() < 12 ? text.am : text.pm);
    }
  }
  return out;
}

/** 12 小时制的小时数（dayjs 的 `h`：12 点整显示 12，0 点显示 12）。 */
function hour12(date: Date): number {
  const hour: number = date.getHours() % 12;
  return hour === 0 ? 12 : hour;
}
