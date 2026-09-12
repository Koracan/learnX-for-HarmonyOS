/*
 * 收藏 / 归档 / 屏蔽的**列表过滤语义** —— 与参考实现 `data/selectors/filteredData.ts` 逐行对齐。
 *
 * 为什么不放在 domain/：这里要用的条目类型 `NoticeRecord` 定义在 data/notices（data 层），
 * 而 domain 不许引用上层（scripts/check-domain-purity.mjs）。与
 * features/assignments/AssignmentFilter.ets 同一处境、同一处置：**纯函数 + 无平台依赖**，
 * 放在 features/marks 供四个列表共用，单测覆盖。
 *
 * ## 参考实现的口径（reference/learnOH-old/src/data/selectors/filteredData.ts）
 *
 * | 分组 | 参考实现 | 行号 |
 * | --- | --- | --- |
 * | all | `items.filter(i => !archived.includes(i.id) && !hidden.includes(i.courseId))` | :77-79 / :111-113 / :147-149 |
 * | unread | `all.filter(i => i.hasRead === false)`（公告） / `all.filter(i => i.isNew)`（文件） | :82 / :152 |
 * | unfinished / finished | `all.filter(i => !i.submitted)` / `all.filter(i => i.submitted)` | :116-117 |
 * | fav | `all.filter(i => fav.includes(i.id))` —— **在 all 之上再筛** | :83 / :118 / :153 |
 * | archived | `items.filter(i => archived.includes(i.id))` —— **用原始 items** | :84 / :119 / :154 |
 * | hidden | `items.filter(i => hidden.includes(i.courseId))` —— **用原始 items** | :85 / :120 / :155 |
 *
 * 三条**必须逐字保住**的语义（别"顺手统一"）：
 *
 * 1. **fav ⊆ all**：已归档 / 被屏蔽课程里的条目**不出现在收藏夹**；
 * 2. **archived 与 hidden 用原始 items**：归档视图里能看到被屏蔽课程的条目，
 *    屏蔽视图里也能看到已归档的条目（两者的排除条件不同）；
 * 3. **hidden 视图四个列表都有**，不只是课程页：`components/Filter.tsx:211-218` 无条件渲染
 *    "屏蔽"那一项，四个屏幕都把 `hidden` 传进来（screens/Notices.tsx:58、Assignments.tsx:60、
 *    Files.tsx:59、Courses.tsx:52）。课程页那一支的 `{all, hidden}` 见 filteredData.ts:51-57。
 *
 * 计数按各自分组数（filteredData.ts:90-99 / :125-135 / :160-169）；作业的"已完成"计数在
 * 参考实现里写的是 `allCount - unfinishedCount`（Filter.tsx:167），与 finished 分组长度同值
 * （submitted 是布尔、两组互补），这里保留参考实现的算式。
 */

import { Assignment, CourseFile } from '../../domain/model/ContentItem';
import { ContentFilter } from '../../domain/marks/ContentFilter';
import { NoticeRecord } from '../../data/notices/NoticeRepository';

// 过滤视图的取值域与解析在 domain/marks/ContentFilter（data 层也要用它校验持久化数据，
// 放在 features 会让 data → features 反向依赖）。调用方直接从那里 import ContentFilter。

/** 分组（三种内容域各自一套；字段名与参考实现 selectFilteredXxx 的返回对象一致）。 */
export interface FilteredNotices {
  all: NoticeRecord[];
  unread: NoticeRecord[];
  fav: NoticeRecord[];
  archived: NoticeRecord[];
  hidden: NoticeRecord[];
}

export interface FilteredAssignments {
  all: Assignment[];
  unfinished: Assignment[];
  finished: Assignment[];
  fav: Assignment[];
  archived: Assignment[];
  hidden: Assignment[];
}

export interface FilteredFiles {
  all: CourseFile[];
  unread: CourseFile[];
  fav: CourseFile[];
  archived: CourseFile[];
  hidden: CourseFile[];
}

export interface NoticeFilterCounts {
  all: number;
  unread: number;
  fav: number;
  archived: number;
  hidden: number;
}

export interface AssignmentFilterCounts {
  all: number;
  unfinished: number;
  /** 参考实现 Filter.tsx:167 的算式 `allCount - unfinishedCount`。 */
  finished: number;
  fav: number;
  archived: number;
  hidden: number;
}

export interface FileFilterCounts {
  all: number;
  unread: number;
  fav: number;
  archived: number;
  hidden: number;
}

/** 公告的三个分组（参考实现 selectFilteredNotices）。 */
export function selectFilteredNotices(items: NoticeRecord[], favorites: string[],
  archived: string[], hiddenCourseIds: string[]): FilteredNotices {
  const all: NoticeRecord[] = [];
  for (let i = 0; i < items.length; i++) {
    const item: NoticeRecord = items[i];
    if (!archived.includes(item.id) && !hiddenCourseIds.includes(item.courseId)) {
      all.push(item);
    }
  }
  const unread: NoticeRecord[] = [];
  const fav: NoticeRecord[] = [];
  for (let i = 0; i < all.length; i++) {
    const item: NoticeRecord = all[i];
    // 参考实现是 `i.hasRead === false`（严格等），这里同义。
    if (item.hasRead === false) {
      unread.push(item);
    }
    if (favorites.includes(item.id)) {
      fav.push(item);
    }
  }
  const archivedGroup: NoticeRecord[] = [];
  const hiddenGroup: NoticeRecord[] = [];
  for (let i = 0; i < items.length; i++) {
    const item: NoticeRecord = items[i];
    if (archived.includes(item.id)) {
      archivedGroup.push(item);
    }
    if (hiddenCourseIds.includes(item.courseId)) {
      hiddenGroup.push(item);
    }
  }
  return { all: all, unread: unread, fav: fav, archived: archivedGroup, hidden: hiddenGroup };
}

/** 作业的五个分组（参考实现 selectFilteredAssignments）。 */
export function selectFilteredAssignments(items: Assignment[], favorites: string[],
  archived: string[], hiddenCourseIds: string[]): FilteredAssignments {
  const all: Assignment[] = [];
  for (let i = 0; i < items.length; i++) {
    const item: Assignment = items[i];
    if (!archived.includes(item.id) && !hiddenCourseIds.includes(item.courseId)) {
      all.push(item);
    }
  }
  const unfinished: Assignment[] = [];
  const finished: Assignment[] = [];
  const fav: Assignment[] = [];
  for (let i = 0; i < all.length; i++) {
    const item: Assignment = all[i];
    if (item.submitted) {
      finished.push(item);
    } else {
      unfinished.push(item);
    }
    if (favorites.includes(item.id)) {
      fav.push(item);
    }
  }
  const archivedGroup: Assignment[] = [];
  const hiddenGroup: Assignment[] = [];
  for (let i = 0; i < items.length; i++) {
    const item: Assignment = items[i];
    if (archived.includes(item.id)) {
      archivedGroup.push(item);
    }
    if (hiddenCourseIds.includes(item.courseId)) {
      hiddenGroup.push(item);
    }
  }
  return {
    all: all, unfinished: unfinished, finished: finished, fav: fav,
    archived: archivedGroup, hidden: hiddenGroup
  };
}

/** 文件的三个分组（参考实现 selectFilteredFiles）。 */
export function selectFilteredFiles(items: CourseFile[], favorites: string[],
  archived: string[], hiddenCourseIds: string[]): FilteredFiles {
  const all: CourseFile[] = [];
  for (let i = 0; i < items.length; i++) {
    const item: CourseFile = items[i];
    if (!archived.includes(item.id) && !hiddenCourseIds.includes(item.courseId)) {
      all.push(item);
    }
  }
  const unread: CourseFile[] = [];
  const fav: CourseFile[] = [];
  for (let i = 0; i < all.length; i++) {
    const item: CourseFile = all[i];
    if (item.isNew) {
      unread.push(item);
    }
    if (favorites.includes(item.id)) {
      fav.push(item);
    }
  }
  const archivedGroup: CourseFile[] = [];
  const hiddenGroup: CourseFile[] = [];
  for (let i = 0; i < items.length; i++) {
    const item: CourseFile = items[i];
    if (archived.includes(item.id)) {
      archivedGroup.push(item);
    }
    if (hiddenCourseIds.includes(item.courseId)) {
      hiddenGroup.push(item);
    }
  }
  return { all: all, unread: unread, fav: fav, archived: archivedGroup, hidden: hiddenGroup };
}

export function noticeCounts(filtered: FilteredNotices): NoticeFilterCounts {
  return {
    all: filtered.all.length,
    unread: filtered.unread.length,
    fav: filtered.fav.length,
    archived: filtered.archived.length,
    hidden: filtered.hidden.length
  };
}

export function assignmentCounts(filtered: FilteredAssignments): AssignmentFilterCounts {
  return {
    all: filtered.all.length,
    unfinished: filtered.unfinished.length,
    // 参考实现 Filter.tsx:167 就是这个算式（与 finished.length 同值）。
    finished: filtered.all.length - filtered.unfinished.length,
    fav: filtered.fav.length,
    archived: filtered.archived.length,
    hidden: filtered.hidden.length
  };
}

export function fileCounts(filtered: FilteredFiles): FileFilterCounts {
  return {
    all: filtered.all.length,
    unread: filtered.unread.length,
    fav: filtered.fav.length,
    archived: filtered.archived.length,
    hidden: filtered.hidden.length
  };
}

/** 公告列表当前视图要显示的条目（参考实现 FilterList.tsx:97-111 的 data 选择）。 */
export function noticesForFilter(filtered: FilteredNotices, filter: ContentFilter): NoticeRecord[] {
  if (filter === ContentFilter.UNREAD) {
    return filtered.unread;
  }
  if (filter === ContentFilter.FAV) {
    return filtered.fav;
  }
  if (filter === ContentFilter.ARCHIVED) {
    return filtered.archived;
  }
  if (filter === ContentFilter.HIDDEN) {
    return filtered.hidden;
  }
  return filtered.all;
}

export function assignmentsForFilter(filtered: FilteredAssignments,
  filter: ContentFilter): Assignment[] {
  if (filter === ContentFilter.UNFINISHED) {
    return filtered.unfinished;
  }
  if (filter === ContentFilter.FINISHED) {
    return filtered.finished;
  }
  if (filter === ContentFilter.FAV) {
    return filtered.fav;
  }
  if (filter === ContentFilter.ARCHIVED) {
    return filtered.archived;
  }
  if (filter === ContentFilter.HIDDEN) {
    return filtered.hidden;
  }
  return filtered.all;
}

export function filesForFilter(filtered: FilteredFiles, filter: ContentFilter): CourseFile[] {
  if (filter === ContentFilter.UNREAD) {
    return filtered.unread;
  }
  if (filter === ContentFilter.FAV) {
    return filtered.fav;
  }
  if (filter === ContentFilter.ARCHIVED) {
    return filtered.archived;
  }
  if (filter === ContentFilter.HIDDEN) {
    return filtered.hidden;
  }
  return filtered.all;
}

/**
 * 某一行的收藏状态 —— **取过滤后的 fav 分组**（参考实现 FilterList.tsx:210-215
 * 的 `fav?.some(f => f.id === item.id)`），不是原始 favorites 数组。
 * 这个差别在"屏蔽"视图里可见：一条已收藏但课程被屏蔽的条目会显示为**未收藏**。
 * 见 docs/reference-quirks.md 第 30 条。
 */
export function isInGroupNotices(group: NoticeRecord[], id: string): boolean {
  for (let i = 0; i < group.length; i++) {
    if (group[i].id === id) {
      return true;
    }
  }
  return false;
}

export function isInGroupAssignments(group: Assignment[], id: string): boolean {
  for (let i = 0; i < group.length; i++) {
    if (group[i].id === id) {
      return true;
    }
  }
  return false;
}

export function isInGroupFiles(group: CourseFile[], id: string): boolean {
  for (let i = 0; i < group.length; i++) {
    if (group[i].id === id) {
      return true;
    }
  }
  return false;
}

/** 课程是否被屏蔽（参考实现 selectFilteredCourses 的两支判据）。 */
export function isHiddenCourse(hiddenCourseIds: string[], courseId: string): boolean {
  return hiddenCourseIds.includes(courseId);
}

