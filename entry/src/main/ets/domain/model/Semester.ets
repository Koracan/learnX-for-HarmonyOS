/*
 * 学期——领域纯逻辑，**零平台依赖**（见 scripts/check-domain-purity.mjs）。
 *
 * 标识形如 `YYYY-YYYY-N`（CONTEXT.md「学期 Semester」）。参考实现以字符串直接持久化与排序
 * （reference/learnOH-old/src/data/actions/semesters.ts 用 `sort().reverse()`），
 * 本模块把该约定显式化：解析 → 校验 → 比较，并与参考实现的排序语义保持一致。
 */

/** 学期季节。参考实现 helpers/parse.ts 的映射：1=秋季、2=春季、其余=夏季。 */
export enum SemesterSeason {
  FALL = 'fall',
  SPRING = 'spring',
  SUMMER = 'summer'
}

/** 学期标识的解析结果。 */
export interface SemesterParts {
  /** 学年起始年，如 2025。 */
  startYear: number;
  /** 学年结束年，必须为 startYear + 1。 */
  endYear: number;
  /** 学期序号，从 1 开始。 */
  term: number;
}

/** 学期标识格式：`YYYY-YYYY-N`。 */
const SEMESTER_ID_PATTERN = /^(\d{4})-(\d{4})-(\d{1,2})$/;

/** `2025-2026 学年` 的原始学年串。 */
export function academicYearOf(startYear: number, endYear: number): string {
  return startYear.toString() + '-' + endYear.toString();
}

/** 学期序号 → 季节（与参考实现一致：非 1/2 一律按夏季处理）。 */
export function seasonOfTerm(term: number): SemesterSeason {
  if (term === 1) {
    return SemesterSeason.FALL;
  }
  if (term === 2) {
    return SemesterSeason.SPRING;
  }
  return SemesterSeason.SUMMER;
}

/**
 * 解析学期标识。
 * @throws Error 格式非法、学年不连续、或学期序号 < 1 时抛出。
 */
export function parseSemesterId(raw: string): SemesterParts {
  const text: string = typeof raw === 'string' ? raw.trim() : '';
  const matched: RegExpMatchArray | null = text.match(SEMESTER_ID_PATTERN);
  if (matched === null) {
    throw new Error('学期标识格式非法（应为 YYYY-YYYY-N）：' + raw);
  }
  const startYear: number = Number.parseInt(matched[1], 10);
  const endYear: number = Number.parseInt(matched[2], 10);
  const term: number = Number.parseInt(matched[3], 10);
  if (endYear !== startYear + 1) {
    throw new Error('学期学年不连续（结束年应为起始年 + 1）：' + raw);
  }
  if (term < 1) {
    throw new Error('学期序号必须 >= 1：' + raw);
  }
  return { startYear: startYear, endYear: endYear, term: term };
}

/** 是否为合法的学期标识。 */
export function isValidSemesterId(raw: string): boolean {
  try {
    parseSemesterId(raw);
    return true;
  } catch (error) {
    return false;
  }
}

/** 比较两个学期标识：早 < 晚。非法标识排在最后（与合法标识的部分序无关，避免静默错序）。 */
export function compareSemesterIds(left: string, right: string): number {
  const a: Semester | null = Semester.tryParse(left);
  const b: Semester | null = Semester.tryParse(right);
  if (a === null && b === null) {
    return left === right ? 0 : left < right ? -1 : 1;
  }
  if (a === null) {
    return 1;
  }
  if (b === null) {
    return -1;
  }
  return a.compareTo(b);
}

/**
 * 排序学期标识。
 * @param order `desc`（默认，新 → 旧，同参考实现）或 `asc`。
 */
export function sortSemesterIds(ids: string[], order: string = 'desc'): string[] {
  const sorted: string[] = ids.slice();
  sorted.sort((left: string, right: string) => compareSemesterIds(left, right));
  if (order === 'desc') {
    sorted.reverse();
  }
  return sorted;
}

/** 最新的学期标识；空数组或全非法时返回 null。 */
export function latestSemesterId(ids: string[]): string | null {
  const sorted: string[] = sortSemesterIds(ids, 'desc');
  for (let i = 0; i < sorted.length; i++) {
    if (isValidSemesterId(sorted[i])) {
      return sorted[i];
    }
  }
  return null;
}

/** 一个学期。不可变值对象，用 `Semester.parse` 构造。 */
export class Semester {
  readonly id: string;
  readonly startYear: number;
  readonly endYear: number;
  readonly term: number;

  private constructor(id: string, parts: SemesterParts) {
    this.id = id;
    this.startYear = parts.startYear;
    this.endYear = parts.endYear;
    this.term = parts.term;
  }

  static isId(raw: string): boolean {
    return isValidSemesterId(raw);
  }

  /** @throws Error 标识非法。 */
  static parse(raw: string): Semester {
    return new Semester(raw.trim(), parseSemesterId(raw));
  }

  /** 标识非法时返回 null，不抛异常。 */
  static tryParse(raw: string): Semester | null {
    if (!isValidSemesterId(raw)) {
      return null;
    }
    return Semester.parse(raw);
  }

  /** `2025-2026`。 */
  get academicYear(): string {
    return academicYearOf(this.startYear, this.endYear);
  }

  get season(): SemesterSeason {
    return seasonOfTerm(this.term);
  }

  /** 早于 other 返回负数，晚于返回正数，相同返回 0。 */
  compareTo(other: Semester): number {
    if (this.startYear !== other.startYear) {
      return this.startYear - other.startYear;
    }
    return this.term - other.term;
  }

  isBefore(other: Semester): boolean {
    return this.compareTo(other) < 0;
  }

  isAfter(other: Semester): boolean {
    return this.compareTo(other) > 0;
  }

  equals(other: Semester): boolean {
    return this.id === other.id;
  }

  toString(): string {
    return this.id;
  }
}
