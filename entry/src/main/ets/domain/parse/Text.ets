/*
 * 文本与时间工具——**零平台依赖**（见 scripts/check-domain-purity.mjs）。
 *
 * 两件事：
 *  1. HTML 实体解码（参考实现 `decodeHTML` 的 6 个实体，移植自 DataProcessorModule.ts）；
 *  2. 网页时间串 → 可比较的时间戳。参考实现用 `dayjs(x).unix()` 排序，
 *     这里用 ECMA-262 保证的 `Date.parse` 对 RFC3339 串，并对站点实际下发的
 *     `YYYY-MM-DD HH:mm(:ss)` 形式显式补上本地时区（参考实现 dayjs 也是按本地时区解释）。
 */

const ENTITY_PATTERN = /&(quot|apos|lt|gt|amp|nbsp);/g;

/** HTML 实体解码；只处理参考实现覆盖的 6 个实体，其余原样保留。 */
export function decodeHtmlEntities(input: string): string {
  if (!input) {
    return '';
  }
  return input.replace(ENTITY_PATTERN, (match: string, name: string): string => {
    if (name === 'quot') {
      return '"';
    }
    if (name === 'apos') {
      return "'";
    }
    if (name === 'lt') {
      return '<';
    }
    if (name === 'gt') {
      return '>';
    }
    if (name === 'amp') {
      return '&';
    }
    return ' ';
  });
}

/** 站点下发的 `YYYY-MM-DD HH:mm` / `YYYY-MM-DD HH:mm:ss`（本地时间）。 */
const SITE_TIME_PATTERN = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?$/;

function parseSiteTime(raw: string): number {
  const matched: RegExpMatchArray | null = raw.match(SITE_TIME_PATTERN);
  if (matched === null) {
    return Number.NaN;
  }
  return new Date(
    Number.parseInt(matched[1], 10),
    Number.parseInt(matched[2], 10) - 1,
    Number.parseInt(matched[3], 10),
    Number.parseInt(matched[4], 10),
    Number.parseInt(matched[5], 10),
    matched[6] === undefined ? 0 : Number.parseInt(matched[6], 10)
  ).getTime();
}

/**
 * 解析时间串为毫秒时间戳；无法解析时返回 `Number.NaN`（排序时 NaN 排在最后）。
 * RFC3339（含时区）用 `Date.parse`，站点本地时间串用本地时区补全。
 */
export function parseTimestamp(raw: string | undefined): number {
  if (raw === undefined || raw === null) {
    return Number.NaN;
  }
  const text: string = raw.trim();
  if (text.length === 0) {
    return Number.NaN;
  }
  const offsetAware: number = Date.parse(text);
  if (!Number.isNaN(offsetAware) && (text.includes('Z') || text.includes('+') || text.includes('GMT'))) {
    return offsetAware;
  }
  const siteTime: number = parseSiteTime(text);
  if (!Number.isNaN(siteTime)) {
    return siteTime;
  }
  return offsetAware;
}

/** 时间倒序（新在前），不可解析的排最后。 */
export function compareTimeDesc(left: string | undefined, right: string | undefined): number {
  const a: number = parseTimestamp(left);
  const b: number = parseTimestamp(right);
  const aValid: boolean = !Number.isNaN(a);
  const bValid: boolean = !Number.isNaN(b);
  if (!aValid && !bValid) {
    return 0;
  }
  if (!aValid) {
    return 1;
  }
  if (!bValid) {
    return -1;
  }
  return b - a;
}

/**
 * 标识倒序。
 *
 * 参考实现用 `b.id.localeCompare(a.id)`（actions/notices.ts 等四处）。ArkTS 的
 * `localeCompare` 行为受设备 locale 影响，同一份数据在不同设备上可能给出不同顺序，
 * 所以这里用**码元比较**实现同一意图，并在单测里与 `localeCompare` 逐对拍。
 */
export function compareIdDesc(left: string, right: string): number {
  if (left === right) {
    return 0;
  }
  return left > right ? -1 : 1;
}

/** 参考实现的列表排序：时间倒序，同一时间按标识倒序。 */
export function compareByTimeThenIdDesc(
  timeLeft: string | undefined,
  idLeft: string,
  timeRight: string | undefined,
  idRight: string
): number {
  const byTime: number = compareTimeDesc(timeLeft, timeRight);
  if (byTime !== 0) {
    return byTime;
  }
  return compareIdDesc(idLeft, idRight);
}
