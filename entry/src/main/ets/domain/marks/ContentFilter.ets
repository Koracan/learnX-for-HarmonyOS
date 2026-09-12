/*
 * 列表过滤视图的**取值域与解析** —— 领域纯逻辑，零平台依赖。
 *
 * 取值逐字对齐参考实现 `components/Filter.tsx:14-21` 的 `FilterSelection`
 * （因为它会被持久化进 `settings.tabFilterSelections`，取值变了磁盘上的旧记录就失效）。
 */

/** 过滤视图（= 参考实现 FilterSelection）。 */
export enum ContentFilter {
  ALL = 'all',
  UNREAD = 'unread',
  FAV = 'fav',
  ARCHIVED = 'archived',
  HIDDEN = 'hidden',
  UNFINISHED = 'unfinished',
  FINISHED = 'finished'
}

/** 全部已知取值（校验持久化数据时用）。 */
export const ALL_CONTENT_FILTERS: ContentFilter[] = [
  ContentFilter.ALL, ContentFilter.UNREAD, ContentFilter.FAV, ContentFilter.ARCHIVED,
  ContentFilter.HIDDEN, ContentFilter.UNFINISHED, ContentFilter.FINISHED
];

/** 文本 → 视图；不是已知取值时 undefined（比较一律用字符串字面量，避免依赖枚举的类型关系）。 */
export function filterFromText(text: string): ContentFilter | undefined {
  if (text === 'all') {
    return ContentFilter.ALL;
  }
  if (text === 'unread') {
    return ContentFilter.UNREAD;
  }
  if (text === 'fav') {
    return ContentFilter.FAV;
  }
  if (text === 'archived') {
    return ContentFilter.ARCHIVED;
  }
  if (text === 'hidden') {
    return ContentFilter.HIDDEN;
  }
  if (text === 'unfinished') {
    return ContentFilter.UNFINISHED;
  }
  if (text === 'finished') {
    return ContentFilter.FINISHED;
  }
  return undefined;
}

/** 取值是否已知。 */
export function isKnownFilter(text: string): boolean {
  return filterFromText(text) !== undefined;
}

/**
 * 解析持久化下来的选择；不是已知取值时回退（参考实现 FilterList.tsx:85-91 的兜底语义：
 * `tabFilterSelections[type] ?? defaultSelected ?? 'all'`）。
 */
export function parseFilter(text: string, fallback: ContentFilter): ContentFilter {
  const parsed: ContentFilter | undefined = filterFromText(text);
  return parsed === undefined ? fallback : parsed;
}

/** 视图 → 持久化文本。 */
export function filterText(filter: ContentFilter): string {
  return filter.toString();
}
