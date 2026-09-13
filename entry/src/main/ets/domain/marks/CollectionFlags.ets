/*
 * 收藏 / 归档 / 隐藏课程的**状态形状与迁移规则** —— 领域纯逻辑，零平台依赖
 * （见 scripts/check-domain-purity.mjs）。
 *
 * 逐条对齐参考实现的三个内容 reducer 与课程 reducer：
 *
 * | 动作 | 参考实现 | 出处 |
 * | --- | --- | --- |
 * | 收藏置真 | `[...state.favorites, id]`（**append，不去重**） | reference/learnOH-old/src/data/reducers/notices.ts:59-64 |
 * | 取消收藏 | `favorites.filter(x => x !== id)` | 同上 |
 * | 归档置真 | `[...state.archived, ...ids]` | reference/learnOH-old/src/data/reducers/notices.ts:65-72 |
 * | 取消归档 | `archived.filter(id => !ids.includes(id))` | 同上 |
 * | 隐藏课程置真 | `[...state.hidden, courseId]` | reference/learnOH-old/src/data/reducers/courses.ts:65-70 |
 * | 取消隐藏 | `hidden.filter(id => id !== courseId)` | 同上 |
 * | 作业 / 文件两域 | 与公告同形 | data/reducers/assignments.ts:69-96、files.ts:67-94 |
 *
 * **append 不去重是参考实现的行为，不要"顺手修好"**：
 * 界面上的收藏按钮状态取的是**过滤后**的 fav 分组（reference 的
 * components/FilterList.tsx:210-215 用 `fav?.some(...)`），因此在"屏蔽"视图里对一条
 * 已收藏、但课程被屏蔽的条目再点一次收藏，favorites 里会出现重复 id。
 * 一旦在这里偷偷去重，行为就与参考实现不一致，而"移植正确"将失去可比对的基准。
 *
 * ## 过滤选择（`tabFilterSelections`）
 *
 * 参考实现把每个列表当前选中的过滤视图存在 `settings.tabFilterSelections`（redux-persist
 * 落 AsyncStorage，见 data/reducers/root.ts:61-65），四个域的**默认值**在
 * data/reducers/settings.ts:24-29：notice=all / **assignment=unfinished** / file=all / course=all。
 * 本工程沿用同一组默认值与"按 tab 记住选择"的行为（存储位置见 data/marks）。
 */

import { ContentFilter } from './ContentFilter';

/** 三个内容域的标识（与参考实现 `FilterListProps.type` 的取值一致）。 */
export enum MarksDomain {
  NOTICE = 'notice',
  ASSIGNMENT = 'assignment',
  FILE = 'file'
}

/** 四个可记忆过滤选择的列表（参考实现 `tabFilterSelections` 的键）。 */
export enum MarksTab {
  NOTICE = 'notice',
  ASSIGNMENT = 'assignment',
  FILE = 'file',
  COURSE = 'course'
}

/**
 * 收藏 / 归档 / 隐藏的全部状态（参考实现分散在四个 reducer 里，这里合成一份，
 * 因为它们的**持久化与消费点**是同一处：跨列表过滤）。
 */
export interface CollectionFlags {
  noticeFavorites: string[];
  noticeArchived: string[];
  assignmentFavorites: string[];
  assignmentArchived: string[];
  fileFavorites: string[];
  fileArchived: string[];
  /** 被屏蔽（隐藏）的课程 id。三域内容项按 `courseId` 受它影响。 */
  hiddenCourseIds: string[];
}

/** 四个列表各自选中的过滤视图（字符串形态，取值见 FilteredContent.ContentFilter）。 */
export interface TabFilterSelections {
  notice: ContentFilter;
  assignment: ContentFilter;
  file: ContentFilter;
  course: ContentFilter;
}

/** 参考实现 data/reducers/settings.ts:24-29 的默认值（逐字照抄）。 */
export const DEFAULT_TAB_FILTER_SELECTIONS: TabFilterSelections = {
  notice: ContentFilter.ALL,
  assignment: ContentFilter.UNFINISHED,
  file: ContentFilter.ALL,
  course: ContentFilter.ALL
};

/** 空状态（四个 reducer 的 initialState 里 favorites / archived / hidden 全是空数组）。 */
export function emptyCollectionFlags(): CollectionFlags {
  return {
    noticeFavorites: [],
    noticeArchived: [],
    assignmentFavorites: [],
    assignmentArchived: [],
    fileFavorites: [],
    fileArchived: [],
    hiddenCourseIds: []
  };
}

/** 取副本（避免调用方改到 store 内部状态）。 */
export function copyCollectionFlags(value: CollectionFlags): CollectionFlags {
  return {
    noticeFavorites: value.noticeFavorites.slice(),
    noticeArchived: value.noticeArchived.slice(),
    assignmentFavorites: value.assignmentFavorites.slice(),
    assignmentArchived: value.assignmentArchived.slice(),
    fileFavorites: value.fileFavorites.slice(),
    fileArchived: value.fileArchived.slice(),
    hiddenCourseIds: value.hiddenCourseIds.slice()
  };
}

export function copyTabFilterSelections(value: TabFilterSelections): TabFilterSelections {
  return {
    notice: value.notice,
    assignment: value.assignment,
    file: value.file,
    course: value.course
  };
}

/** 该域的收藏 id 列表（只读语义；返回内部数组本身，调用方不得修改）。 */
export function favoritesOf(value: CollectionFlags, domain: MarksDomain): string[] {
  if (domain === MarksDomain.NOTICE) {
    return value.noticeFavorites;
  }
  if (domain === MarksDomain.ASSIGNMENT) {
    return value.assignmentFavorites;
  }
  return value.fileFavorites;
}

/** 该域的归档 id 列表。 */
export function archivedOf(value: CollectionFlags, domain: MarksDomain): string[] {
  if (domain === MarksDomain.NOTICE) {
    return value.noticeArchived;
  }
  if (domain === MarksDomain.ASSIGNMENT) {
    return value.assignmentArchived;
  }
  return value.fileArchived;
}

/** 某个 tab 当前选中的过滤视图（未记过时用参考实现的默认值兜底）。 */
export function tabFilterOf(value: TabFilterSelections, tab: MarksTab): ContentFilter {
  if (tab === MarksTab.NOTICE) {
    return value.notice;
  }
  if (tab === MarksTab.ASSIGNMENT) {
    return value.assignment;
  }
  if (tab === MarksTab.FILE) {
    return value.file;
  }
  return value.course;
}

/** 是否收藏 / 归档 / 屏蔽。 */
export function includesId(ids: string[], id: string): boolean {
  return ids.includes(id);
}

/**
 * 收藏置真 / 置假 —— 逐字对齐参考实现（**置真 append 不去重**）。
 */
export function withFavorite(value: CollectionFlags, domain: MarksDomain, id: string,
  flag: boolean): CollectionFlags {
  const next: CollectionFlags = copyCollectionFlags(value);
  if (domain === MarksDomain.NOTICE) {
    next.noticeFavorites = mergeId(next.noticeFavorites, id, flag);
  } else if (domain === MarksDomain.ASSIGNMENT) {
    next.assignmentFavorites = mergeId(next.assignmentFavorites, id, flag);
  } else {
    next.fileFavorites = mergeId(next.fileFavorites, id, flag);
  }
  return next;
}

function mergeId(current: string[], id: string, flag: boolean): string[] {
  return flag ? current.concat([id]) : removeId(current, id);
}

/** 归档置真（append，不去重）/ 置假（按 id 集合整体移除）。 */
export function withArchived(value: CollectionFlags, domain: MarksDomain, ids: string[],
  flag: boolean): CollectionFlags {
  const next: CollectionFlags = copyCollectionFlags(value);
  if (domain === MarksDomain.NOTICE) {
    next.noticeArchived = mergeIds(next.noticeArchived, ids, flag);
  } else if (domain === MarksDomain.ASSIGNMENT) {
    next.assignmentArchived = mergeIds(next.assignmentArchived, ids, flag);
  } else {
    next.fileArchived = mergeIds(next.fileArchived, ids, flag);
  }
  return next;
}

/** 屏蔽 / 取消屏蔽一门课。 */
export function withHiddenCourse(value: CollectionFlags, courseId: string,
  flag: boolean): CollectionFlags {
  const next: CollectionFlags = copyCollectionFlags(value);
  next.hiddenCourseIds = flag ? next.hiddenCourseIds.concat([courseId])
    : removeId(next.hiddenCourseIds, courseId);
  return next;
}

/** 记住某个 tab 的过滤选择。 */
export function withTabFilter(value: TabFilterSelections, tab: MarksTab,
  selection: ContentFilter): TabFilterSelections {
  const next: TabFilterSelections = copyTabFilterSelections(value);
  if (tab === MarksTab.NOTICE) {
    next.notice = selection;
  } else if (tab === MarksTab.ASSIGNMENT) {
    next.assignment = selection;
  } else if (tab === MarksTab.FILE) {
    next.file = selection;
  } else {
    next.course = selection;
  }
  return next;
}

/** 收集**当前生效**的收藏 id（供日志自证；三域合成一条串）。 */
export function describeCollectionFlags(value: CollectionFlags): string {
  return 'favorites=notice:' + value.noticeFavorites.length.toString()
    + ',assignment:' + value.assignmentFavorites.length.toString()
    + ',file:' + value.fileFavorites.length.toString()
    + ' archived=notice:' + value.noticeArchived.length.toString()
    + ',assignment:' + value.assignmentArchived.length.toString()
    + ',file:' + value.fileArchived.length.toString()
    + ' hidden=' + value.hiddenCourseIds.length.toString();
}

function removeId(ids: string[], id: string): string[] {
  const out: string[] = [];
  for (let i = 0; i < ids.length; i++) {
    if (ids[i] !== id) {
      out.push(ids[i]);
    }
  }
  return out;
}

function mergeIds(current: string[], ids: string[], flag: boolean): string[] {
  if (flag) {
    return current.concat(ids);
  }
  const out: string[] = [];
  for (let i = 0; i < current.length; i++) {
    if (!ids.includes(current[i])) {
      out.push(current[i]);
    }
  }
  return out;
}