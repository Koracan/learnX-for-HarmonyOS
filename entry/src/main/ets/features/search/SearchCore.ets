/*
 * 全局搜索的检索核心（ticket 15）—— **纯逻辑、零平台依赖**，与参考实现
 * reference/learnOH-old/src/hooks/useSearch.ts 的三段结构逐段对齐。
 *
 * | 段 | 参考实现 | 这里 |
 * | --- | --- | --- |
 * | ① 手工精确/前缀合并层 | useSearch.ts:44-49,107-110 的 filterBySummary | manualHit（runSearch 第一段），判据**逐字相同** |
 * | ② 加权/模糊层 | useSearch.ts:5-42 的 fuse 键表 + fuse.search | fieldScore：**同一张字段表与同一批权重**，匹配分档 = 精确 > 前缀 > 子串 > ASCII 词编辑距离 |
 * | ③ 合并去重 | useSearch.ts:51-61 的 merge（手工在前，Set 按 id 去重） | runSearch 第三段，同样的顺序与去重口径 |
 *
 * ## 为什么必须有 ①（**不要当「冗余」删掉**）
 *
 * fuse 的 Bitap 与 flexsearch 的 cjk charset 对中文都
 * **按码点逐字切分**，匹配不了拼音/同音字；这段 includes 手工层是 CJK 语料下的**必要补偿**
 * （源码注释原文：「由于未知原因，fuse.js 会漏掉一些明显匹配的结果」）。工单验收第 2 条也要求保留它。
 *
 * ## 字段表（照抄 useSearch.ts:5-42）里有 5 个键**取不到值**
 *
 * - attachmentName / submittedAttachmentName / gradeAttachmentName / answerAttachmentName：
 *   参考实现的 Notice / Assignment（src/data/types/state.ts）**没有**这些字段（附件是对象
 *   attachment，名字在 attachment.name），fuse 按路径取到 undefined ⇒ **恒不命中**。
 *   这里**有意不补**：补上就是「比参考实现多搜到一些东西」的行为增强，不是移植；要加需另立验收标准。
 * - category.title：参考实现**有**这个字段（File.category.title，thu-learn-lib 的 File），
 *   但本工程的 CourseFile 没有 category（ticket 11/12 的文件模型没取它）⇒ 这一格在本工程里
 *   取不到值，因此**不在** FILE_SEARCH_FIELDS 里。这是数据模型缺口，不是有意的检索口径。
 *
 * ## 空查询的行为（**与参考实现一致，别「修」**）
 *
 * String.includes('') 恒为 true ⇒ filterBySummary 在空查询下返回**全部条目**，
 * 所以参考实现的搜索页在查询为空时列出三个域的全量内容（而不是空态/提示语）。
 * runSearch 用同一个 includes(cleanQuery) 保留这一行为（单测 emptyQueryListsEverything 钉住）。
 *
 * ## 与参考实现的边界（如实声明）
 *
 * 参考实现的 ② 是 **fuse.js** 的 Bitap 模糊匹配。本工程按 .scratch/migration/search-package-eval.md
 * 的选型先跑了 `@ohos/flexsearch@2.0.1` 的冒烟，**编译期即以 00507015 失败**（该包 index.d.ts 的具名导出
 * 与真实入口的 `export default` 不一致），于是采用该文档第 4 条的**兜底方案：下面这套自写加权评分** ——
 * **没有引入任何 ohpm 依赖**（编辑距离内核也是自写的）。**② 只影响「召回多少」，
 * 不影响 ①**：工单验收第 2 条要求的「标题或课程名的精确与前缀匹配必定命中」由 ① 独立保证。
 * 编辑距离只对 **ASCII 词**生效（词长 ≥3），CJK 的「模糊」仍然只有子串/前缀 —— 与评估文档
 * 第 3 条「CJK 只能到单字级」的事实一致。
 */

import { Assignment, CourseFile } from '../../domain/model/ContentItem';
import { NoticeRecord } from '../../data/notices/NoticeRepository';

/** 打分的字段（名 + 权重）。权重 2 = 参考实现的 { name, weight: 2 }，缺省 fuse 权重 = 1。 */
export interface WeightedField {
  name: string;
  weight: number;
}

/** 公告的字段表：useSearch.ts:5-14（去掉恒不命中的 attachmentName）。 */
export const NOTICE_SEARCH_FIELDS: WeightedField[] = [
  { name: 'courseName', weight: 1 },
  { name: 'courseTeacherName', weight: 1 },
  { name: 'publisher', weight: 1 },
  { name: 'title', weight: 2 },
  { name: 'content', weight: 2 }
];

/** 作业的字段表：useSearch.ts:16-31（去掉恒不命中的四个 *AttachmentName）。 */
export const ASSIGNMENT_SEARCH_FIELDS: WeightedField[] = [
  { name: 'courseName', weight: 1 },
  { name: 'courseTeacherName', weight: 1 },
  { name: 'submittedContent', weight: 1 },
  { name: 'graderName', weight: 1 },
  { name: 'gradeContent', weight: 1 },
  { name: 'answerContent', weight: 1 },
  { name: 'title', weight: 2 },
  { name: 'description', weight: 2 }
];

/** 文件的字段表：useSearch.ts:33-42（category.title 在本工程的数据模型里没有来源，见文件头）。 */
export const FILE_SEARCH_FIELDS: WeightedField[] = [
  { name: 'courseName', weight: 1 },
  { name: 'courseTeacherName', weight: 1 },
  { name: 'title', weight: 2 },
  { name: 'description', weight: 2 },
  { name: 'fileType', weight: 2 }
];

/** 参考实现字段表里**恒不命中**的四个键（Notice / Assignment 没有这些属性）。 */
export const REFERENCE_INERT_KEYS: string[] = [
  'attachmentName', 'submittedAttachmentName', 'gradeAttachmentName', 'answerAttachmentName'
];

/** 参考实现能命中、但本工程数据模型里没有来源的键（File.category.title）。 */
export const MODEL_MISSING_KEYS: string[] = ['category.title'];

/* ------------------------------------------------------------------ *
 * 匹配分档（② 的评分内核）
 * ------------------------------------------------------------------ */

/** 字段值整串等于查询。 */
export const SCORE_EXACT: number = 1;
/** 字段值以查询开头。 */
export const SCORE_PREFIX: number = 0.8;
/** 字段值包含查询。 */
export const SCORE_SUBSTRING: number = 0.55;
/** ASCII 词与查询在编辑距离阈值内（打字错误容忍）。 */
export const SCORE_FUZZY: number = 0.3;

/*
 * 为什么没有"词前缀"单独一档：词是以分隔符切出来的，所以"某个词以查询开头"必然意味着
 * 整串 contains 查询 ⇒ 已经被 SCORE_SUBSTRING 吃掉。留一档永远到不了的分档只会误导。
 */

/** 词切分：非 [0-9A-Za-z] 且非 CJK 统一表意文字 的字符都是分隔符。 */
const TOKEN_SEPARATOR: RegExp = /[^0-9A-Za-z\u4e00-\u9fff]+/;

/** 一条条目的检索摘要：手工层用前两个字段，② 用 fields。 */
export interface SearchHaystack {
  id: string;
  /** item.title.toUpperCase()（参考实现 useSearch.ts:80）。 */
  upperTitle: string;
  /** item.courseName.toUpperCase()（参考实现 useSearch.ts:81）。 */
  upperCourseName: string;
  fields: FieldText[];
}

/** 一个字段的待匹配文本（已去掉空串）。 */
export interface FieldText {
  weight: number;
  text: string;
}

/** ② 的排序项：分数相同则保持输入顺序（对齐 fuse 结果的稳定观感）。 */
interface ScoredEntry {
  index: number;
  score: number;
}

/** 摘要 + 原条目（泛型包装，三个域共用同一套 runSearch）。 */
interface Ranked<T> {
  hay: SearchHaystack;
  item: T;
}

function text(weight: number, value: string): FieldText {
  return { weight: weight, text: value };
}

/** 公告的检索摘要（字段表见 NOTICE_SEARCH_FIELDS）。 */
export function noticeHaystack(item: NoticeRecord): SearchHaystack {
  return {
    id: item.id,
    upperTitle: item.title.toUpperCase(),
    upperCourseName: item.courseName.toUpperCase(),
    fields: [
      text(1, item.courseName), text(1, item.courseTeacherName), text(1, item.publisher),
      text(2, item.title), text(2, item.content)
    ]
  };
}

/** 作业的检索摘要（字段表见 ASSIGNMENT_SEARCH_FIELDS）。 */
export function assignmentHaystack(item: Assignment): SearchHaystack {
  return {
    id: item.id,
    upperTitle: item.title.toUpperCase(),
    upperCourseName: item.courseName.toUpperCase(),
    fields: [
      text(1, item.courseName), text(1, item.courseTeacherName), text(1, item.submittedContent),
      text(1, item.graderName === undefined ? '' : item.graderName),
      text(1, item.gradeContent), text(1, item.answerContent),
      text(2, item.title), text(2, item.description)
    ]
  };
}

/** 文件的检索摘要（字段表见 FILE_SEARCH_FIELDS）。 */
export function fileHaystack(item: CourseFile): SearchHaystack {
  return {
    id: item.id,
    upperTitle: item.title.toUpperCase(),
    upperCourseName: item.courseName.toUpperCase(),
    fields: [
      text(1, item.courseName), text(1, item.courseTeacherName),
      text(2, item.title), text(2, item.description), text(2, item.fileType)
    ]
  };
}

/** 查询是否只含 ASCII 字母数字（编辑距离只对它有意义）。 */
function isAsciiQuery(query: string): boolean {
  for (let i = 0; i < query.length; i++) {
    const c: number = query.charCodeAt(i);
    const isDigit: boolean = c >= 48 && c <= 57;
    const isUpper: boolean = c >= 65 && c <= 90;
    const isLower: boolean = c >= 97 && c <= 122;
    if (!isDigit && !isUpper && !isLower) {
      return false;
    }
  }
  return query.length > 0;
}

/**
 * 编辑距离是否 ≤ max（带上界早退的两行 DP）。只用于 ASCII 词，
 * 作为「打字错误也能命中」的兜底；阈值由调用方按词长给（3-7 字 → 1，≥8 字 → 2）。
 */
export function withinEditDistance(a: string, b: string, max: number): boolean {
  const diff: number = a.length - b.length;
  if (diff > max || -diff > max) {
    return false;
  }
  let previous: number[] = [];
  for (let j = 0; j <= b.length; j++) {
    previous.push(j);
  }
  for (let i = 1; i <= a.length; i++) {
    const current: number[] = [i];
    let rowMin: number = i;
    for (let j = 1; j <= b.length; j++) {
      const substitution: number = previous[j - 1] + (a.charCodeAt(i - 1) === b.charCodeAt(j - 1) ? 0 : 1);
      const deletion: number = previous[j] + 1;
      const insertion: number = current[j - 1] + 1;
      let best: number = substitution;
      if (deletion < best) {
        best = deletion;
      }
      if (insertion < best) {
        best = insertion;
      }
      current.push(best);
      if (best < rowMin) {
        rowMin = best;
      }
    }
    if (rowMin > max) {
      return false;
    }
    previous = current;
  }
  return previous[b.length] <= max;
}

/** 单个字段的匹配分（query 已 trim + 大写）。 */
export function fieldScore(value: string, query: string): number {
  if (value.length === 0 || query.length === 0) {
    return 0;
  }
  const upper: string = value.toUpperCase();
  if (upper === query) {
    return SCORE_EXACT;
  }
  if (upper.startsWith(query)) {
    return SCORE_PREFIX;
  }
  if (upper.includes(query)) {
    return SCORE_SUBSTRING;
  }
  // 到这里查询已经不是整串的子串，只剩「某个 ASCII 词与查询在编辑距离内」这一档。
  if (!isAsciiQuery(query) || query.length < 3) {
    return 0;
  }
  const tokens: string[] = upper.split(TOKEN_SEPARATOR);
  for (let i = 0; i < tokens.length; i++) {
    const token: string = tokens[i];
    if (token.length >= 3 && token !== query) {
      const max: number = token.length >= 8 ? 2 : 1;
      if (withinEditDistance(token, query, max)) {
        return SCORE_FUZZY;
      }
    }
  }
  return 0;
}

/** ② 的总分：各字段分数 × 字段权重之和。 */
export function haystackScore(hay: SearchHaystack, cleanQuery: string): number {
  let total: number = 0;
  for (let i = 0; i < hay.fields.length; i++) {
    const field: FieldText = hay.fields[i];
    const score: number = fieldScore(field.text, cleanQuery);
    if (score > 0) {
      total += score * field.weight;
    }
  }
  return total;
}

/**
 * ① + ② + ③ 的合成：手工层在前（输入顺序），② 按分数降序补上（同分保持输入顺序），按 id 去重。
 *
 * cleanQuery 的算法与参考实现完全一致：query.trim().toUpperCase()。
 */
function runSearch<T>(entries: Ranked<T>[], query: string): T[] {
  const cleanQuery: string = query.trim().toUpperCase();
  const manual: T[] = [];
  const seen: Set<string> = new Set<string>();
  for (let i = 0; i < entries.length; i++) {
    const entry: Ranked<T> = entries[i];
    // ① 手工精确/前缀合并层：参考实现 filterBySummary 的判据（空查询 ⇒ includes('') 为真 ⇒ 全量）。
    if (entry.hay.upperTitle.includes(cleanQuery) || entry.hay.upperCourseName.includes(cleanQuery)) {
      manual.push(entry.item);
      seen.add(entry.hay.id);
    }
  }
  // ② 加权字段分（空查询时全部为 0，手工层已经是全量）。
  const scored: ScoredEntry[] = [];
  for (let i = 0; i < entries.length; i++) {
    const entry: Ranked<T> = entries[i];
    const score: number = haystackScore(entry.hay, cleanQuery);
    if (score > 0) {
      scored.push({ index: i, score: score });
    }
  }
  scored.sort((a: ScoredEntry, b: ScoredEntry): number => {
    if (b.score !== a.score) {
      return b.score - a.score;
    }
    return a.index - b.index;
  });
  // ③ 合并去重（手工在前）。
  const out: T[] = manual;
  for (let i = 0; i < scored.length; i++) {
    const entry: Ranked<T> = entries[scored[i].index];
    if (!seen.has(entry.hay.id)) {
      out.push(entry.item);
      seen.add(entry.hay.id);
    }
  }
  return out;
}

/**
 * 公告检索。items 应当已经是**原始条目只排除被屏蔽课程**的口径
 * （见 features/marks/FilteredContent 的 noticesExcludingHiddenCourses）。
 */
export function searchNotices(items: NoticeRecord[], query: string): NoticeRecord[] {
  const entries: Ranked<NoticeRecord>[] = [];
  for (let i = 0; i < items.length; i++) {
    entries.push({ hay: noticeHaystack(items[i]), item: items[i] });
  }
  return runSearch(entries, query);
}

/** 作业检索（items 口径同 searchNotices）。 */
export function searchAssignments(items: Assignment[], query: string): Assignment[] {
  const entries: Ranked<Assignment>[] = [];
  for (let i = 0; i < items.length; i++) {
    entries.push({ hay: assignmentHaystack(items[i]), item: items[i] });
  }
  return runSearch(entries, query);
}

/** 文件检索（items 口径同 searchNotices）。 */
export function searchFiles(items: CourseFile[], query: string): CourseFile[] {
  const entries: Ranked<CourseFile>[] = [];
  for (let i = 0; i < items.length; i++) {
    entries.push({ hay: fileHaystack(items[i]), item: items[i] });
  }
  return runSearch(entries, query);
}
