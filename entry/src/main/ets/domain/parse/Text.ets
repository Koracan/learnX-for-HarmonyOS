/*
 * 文本与时间工具——**零平台依赖**（见 scripts/check-domain-purity.mjs）。
 *
 * 三件事：
 *  1. HTML 实体解码（参考实现 `decodeHTML` 的 6 个实体，移植自 DataProcessorModule.ts）；
 *  2. **渲染层**的完整实体解码（`he.decode` 等价物，见下）；
 *  3. 网页时间串 → 可比较的时间戳。参考实现用 `dayjs(x).unix()` 排序，
 *     这里用 ECMA-262 保证的 `Date.parse` 对 RFC3339 串，并对站点实际下发的
 *     `YYYY-MM-DD HH:mm(:ss)` 形式显式补上本地时区（参考实现 dayjs 也是按本地时区解释）。
 */

const ENTITY_PATTERN = /&(quot|apos|lt|gt|amp|nbsp);/g;

/** 参考实现 DataProcessor 的 6 个命名实体（**解析层**用；照参考实现只解这 6 个）。 */
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
/**
 * 常用命名实体的补全集（`he.decode` 的高频子集）。
 *
 * 为什么需要：`removeTags` 的契约是 `he.decode()` 的完整实体集
 * （docs/reference-quirks.md 第 4 条的**渲染层**那半）。ArkTS 里没有 `he`，
 * 也不该引第三方包（domain 禁平台/上层依赖），所以自己实现：
 * **命名实体走下面的 `switch`（覆盖核心 6 个 + 排版/符号/希腊字母高频项），
 * 数字实体（十进制 / 十六进制）走公式，认不出的原样保留**——
 * `he` 对未知实体名也是原样保留，这才是同一行为。
 *
 * 为什么用 `switch` 而不是查表：ArkTS 三条硬约束把"表"这条路全堵死了——
 * 无索引签名（arkts-no-indexed-signatures）、不能按字段名索引（arkts-no-props-by-index）、
 * 无类型对象字面量（arkts-no-untyped-obj-literals）。`switch` 是唯一的纯函数写法
 * （另两条路是 `Map` 与 class 的 `get` 方法链，前者要构造、后者等价于 switch 但更难读）。
 * 单测 `removeTags` 的用例覆盖了每一类实体（命名 / 十进制数字 / 十六进制数字 / 未知原样）。
 */
export function entityByName(name: string): string | undefined {
  switch (name) {
    // 核心 6 个（与 decodeHtmlEntities 同一组）
    case 'quot': return '"';
    case 'apos': return "'";
    case 'lt': return '<';
    case 'gt': return '>';
    case 'amp': return '&';
    case 'nbsp': return ' ';
    // 拉丁补充
    case 'iexcl': return '¡';
    case 'cent': return '¢';
    case 'pound': return '£';
    case 'curren': return '¤';
    case 'yen': return '¥';
    case 'brvbar': return '¦';
    case 'sect': return '§';
    case 'uml': return '¨';
    case 'copy': return '©';
    case 'ordf': return 'ª';
    case 'laquo': return '«';
    case 'not': return '¬';
    case 'shy': return '\u00AD';
    case 'reg': return '®';
    case 'macr': return '¯';
    case 'deg': return '°';
    case 'plusmn': return '±';
    case 'sup2': return '²';
    case 'sup3': return '³';
    case 'acute': return '´';
    case 'micro': return 'µ';
    case 'para': return '¶';
    case 'middot': return '·';
    case 'cedil': return '¸';
    case 'sup1': return '¹';
    case 'ordm': return 'º';
    case 'raquo': return '»';
    case 'frac14': return '¼';
    case 'frac12': return '½';
    case 'frac34': return '¾';
    case 'iquest': return '¿';
    case 'times': return '×';
    case 'divide': return '÷';
    case 'szlig': return 'ß';
    case 'agrave': return 'à';
    case 'aacute': return 'á';
    case 'acirc': return 'â';
    case 'atilde': return 'ã';
    case 'auml': return 'ä';
    case 'aring': return 'å';
    case 'aelig': return 'æ';
    case 'ccedil': return 'ç';
    case 'egrave': return 'è';
    case 'eacute': return 'é';
    case 'ecirc': return 'ê';
    case 'euml': return 'ë';
    case 'igrave': return 'ì';
    case 'iacute': return 'í';
    case 'icirc': return 'î';
    case 'iuml': return 'ï';
    case 'eth': return 'ð';
    case 'ntilde': return 'ñ';
    case 'ograve': return 'ò';
    case 'oacute': return 'ó';
    case 'ocirc': return 'ô';
    case 'otilde': return 'õ';
    case 'ouml': return 'ö';
    case 'oslash': return 'ø';
    case 'ugrave': return 'ù';
    case 'uacute': return 'ú';
    case 'ucirc': return 'û';
    case 'uuml': return 'ü';
    case 'yacute': return 'ý';
    case 'thorn': return 'þ';
    case 'yuml': return 'ÿ';
    case 'OElig': return 'Œ';
    case 'oelig': return 'œ';
    case 'Scaron': return 'Š';
    case 'scaron': return 'š';
    case 'Yuml': return 'Ÿ';
    case 'fnof': return 'ƒ';
    case 'circ': return 'ˆ';
    case 'tilde': return '˜';
    // 排版 / 标点
    case 'ensp': return ' ';
    case 'emsp': return ' ';
    case 'thinsp': return ' ';
    case 'ndash': return '–';
    case 'mdash': return '—';
    case 'lsquo': return '‘';
    case 'rsquo': return '’';
    case 'sbquo': return '‚';
    case 'ldquo': return '“';
    case 'rdquo': return '”';
    case 'bdquo': return '„';
    case 'dagger': return '†';
    case 'Dagger': return '‡';
    case 'bull': return '•';
    case 'hellip': return '…';
    case 'permil': return '‰';
    case 'prime': return '′';
    case 'Prime': return '″';
    case 'lsaquo': return '‹';
    case 'rsaquo': return '›';
    case 'oline': return '‾';
    case 'frasl': return '⁄';
    case 'euro': return '€';
    case 'trade': return '™';
    // 箭头 / 数学符号
    case 'larr': return '←';
    case 'uarr': return '↑';
    case 'rarr': return '→';
    case 'darr': return '↓';
    case 'harr': return '↔';
    case 'crarr': return '↵';
    case 'forall': return '∀';
    case 'part': return '∂';
    case 'exist': return '∃';
    case 'empty': return '∅';
    case 'nabla': return '∇';
    case 'isin': return '∈';
    case 'notin': return '∉';
    case 'ni': return '∋';
    case 'prod': return '∏';
    case 'sum': return '∑';
    case 'minus': return '−';
    case 'lowast': return '∗';
    case 'radic': return '√';
    case 'prop': return '∝';
    case 'infin': return '∞';
    case 'ang': return '∠';
    case 'and': return '∧';
    case 'or': return '∨';
    case 'cap': return '∩';
    case 'cup': return '∪';
    case 'int': return '∫';
    case 'there4': return '∴';
    case 'sim': return '∼';
    case 'cong': return '≅';
    case 'asymp': return '≈';
    case 'ne': return '≠';
    case 'equiv': return '≡';
    case 'le': return '≤';
    case 'ge': return '≥';
    case 'sub': return '⊂';
    case 'sup': return '⊃';
    case 'nsub': return '⊄';
    case 'sube': return '⊆';
    case 'supe': return '⊇';
    case 'oplus': return '⊕';
    case 'otimes': return '⊗';
    case 'perp': return '⊥';
    case 'sdot': return '⋅';
    case 'loz': return '◊';
    case 'spades': return '♠';
    case 'clubs': return '♣';
    case 'hearts': return '♥';
    case 'diams': return '♦';
    // 希腊字母
    case 'Alpha': return 'Α';
    case 'Beta': return 'Β';
    case 'Gamma': return 'Γ';
    case 'Delta': return 'Δ';
    case 'Epsilon': return 'Ε';
    case 'Zeta': return 'Ζ';
    case 'Eta': return 'Η';
    case 'Theta': return 'Θ';
    case 'Iota': return 'Ι';
    case 'Kappa': return 'Κ';
    case 'Lambda': return 'Λ';
    case 'Mu': return 'Μ';
    case 'Nu': return 'Ν';
    case 'Xi': return 'Ξ';
    case 'Omicron': return 'Ο';
    case 'Pi': return 'Π';
    case 'Rho': return 'Ρ';
    case 'Sigma': return 'Σ';
    case 'Tau': return 'Τ';
    case 'Upsilon': return 'Υ';
    case 'Phi': return 'Φ';
    case 'Chi': return 'Χ';
    case 'Psi': return 'Ψ';
    case 'Omega': return 'Ω';
    case 'alpha': return 'α';
    case 'beta': return 'β';
    case 'gamma': return 'γ';
    case 'delta': return 'δ';
    case 'epsilon': return 'ε';
    case 'zeta': return 'ζ';
    case 'eta': return 'η';
    case 'theta': return 'θ';
    case 'iota': return 'ι';
    case 'kappa': return 'κ';
    case 'lambda': return 'λ';
    case 'mu': return 'μ';
    case 'nu': return 'ν';
    case 'xi': return 'ξ';
    case 'omicron': return 'ο';
    case 'pi': return 'π';
    case 'rho': return 'ρ';
    case 'sigmaf': return 'ς';
    case 'sigma': return 'σ';
    case 'tau': return 'τ';
    case 'upsilon': return 'υ';
    case 'phi': return 'φ';
    case 'chi': return 'χ';
    case 'psi': return 'ψ';
    case 'omega': return 'ω';
    case 'thetasym': return 'ϑ';
    case 'upsih': return 'ϒ';
    case 'piv': return 'ϖ';
    default: return undefined;
  }
}


/** 数字实体 → 字符；超出 Unicode 范围或非法数字时返回 undefined（原样保留）。 */
export function entityByCode(digits: string, radix: number): string | undefined {
  if (digits.length === 0) {
    return undefined;
  }
  for (let i = 0; i < digits.length; i++) {
    const code: number = digits.charCodeAt(i);
    const isDigit: boolean = code >= 48 && code <= 57;
    const isLowerHex: boolean = radix === 16 && code >= 97 && code <= 102;
    const isUpperHex: boolean = radix === 16 && code >= 65 && code <= 70;
    if (!isDigit && !isLowerHex && !isUpperHex) {
      return undefined;
    }
  }
  const value: number = Number.parseInt(digits, radix);
  if (Number.isNaN(value) || value < 0 || value > 0x10FFFF) {
    return undefined;
  }
  return String.fromCodePoint(value);
}

/**
 * `he.decode()` 的等价物：命名实体（NAMED_ENTITIES）+ 数字实体（`&#39;` / `&#x27;`）。
 * 未知实体**原样保留**（与 `he` 对未知实体名的行为一致）。
 *
 * 手写扫描而不是正则：ArkTS 的 `RegExpMatchArray` 会撞 arkts-no-structural-typing，
 * 且正则的替换回调在这里反而更难读。单次线性扫描，遇到 `&` 才尝试解析。
 */
export function decodeAllEntities(input: string): string {
  if (input.length === 0) {
    return input;
  }
  let output: string = '';
  let cursor: number = 0;
  while (cursor < input.length) {
    const amp: number = input.indexOf('&', cursor);
    if (amp < 0) {
      output += input.substring(cursor);
      break;
    }
    output += input.substring(cursor, amp);
    const semi: number = input.indexOf(';', amp + 1);
    // 实体名最长不到 32 字符；超出就不可能是实体，避免把整篇文本当实体找 ';'。
    if (semi < 0 || semi - amp > 32) {
      output += '&';
      cursor = amp + 1;
      continue;
    }
    const name: string = input.substring(amp + 1, semi);
    let decoded: string | undefined = undefined;
    if (name.length > 1 && name.charAt(0) === '#') {
      const body: string = name.substring(1);
      decoded = body.length > 1 && (body.charAt(0) === 'x' || body.charAt(0) === 'X')
        ? entityByCode(body.substring(1), 16)
        : entityByCode(body, 10);
    } else if (name.length > 0) {
      decoded = entityByName(name);
    }
    if (decoded === undefined) {
      output += input.substring(amp, semi + 1);
    } else {
      output += decoded;
    }
    cursor = semi + 1;
  }
  return output;
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
export function parseTimestamp(raw: string | number | undefined): number {
  if (raw === undefined || raw === null) {
    return Number.NaN;
  }
  if (typeof raw !== 'string') {
    // dayjs 对**数字**按 epoch 毫秒解释；站点个别字段会给数字（实测作业 jzsj，见
    // AssignmentsFetcher 的 non-string deadline 警告）。这里与 dayjs 对齐：
    // 有限数字按毫秒返回；其它非字符串（运行时仍可能收到）视为不可解析，
    // 等价于 dayjs 的 Invalid Date ⇒ isAfter 恒 false。
    // 不这样写的话，数字会走到下面的 raw.trim() 上抛 "undefined is not callable"。
    return typeof raw === 'number' && !Number.isNaN(raw) ? raw : Number.NaN;
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
export function compareTimeDesc(left: string | number | undefined, right: string | number | undefined): number {
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
  timeLeft: string | number | undefined,
  idLeft: string,
  timeRight: string | number | undefined,
  idRight: string
): number {
  const byTime: number = compareTimeDesc(timeLeft, timeRight);
  if (byTime !== 0) {
    return byTime;
  }
  return compareIdDesc(idLeft, idRight);
}