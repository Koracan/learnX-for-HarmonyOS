/*
 * 收藏 / 归档 / 隐藏状态的**序列化与反序列化** —— 纯字符串运算，零平台依赖
 * （可在 Hypium Local Test 里直接跑）。
 *
 * 与公告快照（data/notices/NoticeSnapshotSerialization）同一套路数，理由也一样：
 * "落盘的字节必须能安全读回来"这件事不该只靠设备取证来证明。损坏（截断、字段缺失、
 * 类型不对、版本不符）在这里一律返回"丢弃 + 原因"，**绝不抛异常** —— 收藏状态坏了
 * 只应表现为"这次回到默认值"，而不是"公告页崩了"。
 *
 * 落盘信封是一个 JSON 文本（preferences 里一个字符串键）：
 *
 *     { schemaVersion, flags: {...七个 string[]}, tabFilters: {...四个 string} }
 *
 * 为什么是一个 JSON 而不是七个 preferences 键：七个键要七次 get/put，且"半写"
 * （写了三个键、崩了）会得到一个自相矛盾的状态；一个键的写入是原子的，
 * 反序列化要么整体可用、要么整体丢弃。
 */

import {
  CollectionFlags, DEFAULT_TAB_FILTER_SELECTIONS, TabFilterSelections,
  copyTabFilterSelections, emptyCollectionFlags
} from './CollectionFlags';
import { parseFilter } from './ContentFilter';

/** 落盘结构版本；**字段集变化时 +1**（版本不符即丢弃重建）。 */
export const COLLECTION_FLAGS_SCHEMA_VERSION: number = 1;

/** 反序列化结果：要么拿到状态，要么明确说明为什么丢弃（供日志/取证）。 */
export interface FlagsDecodeResult {
  flags: CollectionFlags;
  tabFilters: TabFilterSelections;
  /** 丢弃原因；空串 = 成功。取值：empty / parse_failed / not_an_object /
   *  version_missing / version_mismatch:<onDisk> / flags_missing / <key>_invalid /
   *  tab_filters_missing。 */
  discardReason: string;
  /** 磁盘上的结构版本（丢弃时用于对比；解析不出时为 -1）。 */
  onDiskVersion: number;
}

/** 失败结果：状态回到默认值（与参考实现 settings.ts 的 initialState 同形）。 */
function fail(reason: string, onDiskVersion: number): FlagsDecodeResult {
  return {
    flags: emptyCollectionFlags(),
    tabFilters: copyTabFilterSelections(DEFAULT_TAB_FILTER_SELECTIONS),
    discardReason: reason,
    onDiskVersion: onDiskVersion
  };
}

/** 读一个 string[] 字段；缺失 / 形状不对返回 undefined（由调用方决定丢弃原因）。 */
function readStringArray(raw: Record<string, Object>, key: string): string[] | undefined {
  const value: Object = raw[key];
  if (value === undefined || value === null || !Array.isArray(value)) {
    return undefined;
  }
  const array: Object[] = value as Object[];
  const out: string[] = [];
  for (let i = 0; i < array.length; i++) {
    const entry: Object = array[i];
    if (typeof entry !== 'string') {
      return undefined;
    }
    out.push(entry as string);
  }
  return out;
}

/** 读一个 string 字段；缺失 / 形状不对返回 undefined。 */
function readString(raw: Record<string, Object>, key: string): string | undefined {
  const value: Object = raw[key];
  if (value === undefined || value === null || typeof value !== 'string') {
    return undefined;
  }
  return value as string;
}

function readFlags(raw: Record<string, Object>): CollectionFlags | undefined {
  const noticeFavorites: string[] | undefined = readStringArray(raw, 'noticeFavorites');
  const noticeArchived: string[] | undefined = readStringArray(raw, 'noticeArchived');
  const assignmentFavorites: string[] | undefined = readStringArray(raw, 'assignmentFavorites');
  const assignmentArchived: string[] | undefined = readStringArray(raw, 'assignmentArchived');
  const fileFavorites: string[] | undefined = readStringArray(raw, 'fileFavorites');
  const fileArchived: string[] | undefined = readStringArray(raw, 'fileArchived');
  const hiddenCourseIds: string[] | undefined = readStringArray(raw, 'hiddenCourseIds');
  if (noticeFavorites === undefined || noticeArchived === undefined
    || assignmentFavorites === undefined || assignmentArchived === undefined
    || fileFavorites === undefined || fileArchived === undefined
    || hiddenCourseIds === undefined) {
    return undefined;
  }
  const flags: CollectionFlags = {
    noticeFavorites: noticeFavorites,
    noticeArchived: noticeArchived,
    assignmentFavorites: assignmentFavorites,
    assignmentArchived: assignmentArchived,
    fileFavorites: fileFavorites,
    fileArchived: fileArchived,
    hiddenCourseIds: hiddenCourseIds
  };
  return flags;
}

/**
 * 读四个过滤选择。单个取值不是已知视图时**按该 tab 的默认值回退**（不整体丢弃）：
 * 一个手改坏的视图名不该让收藏状态一起丢。
 */
function readTabFilters(raw: Record<string, Object>): TabFilterSelections {
  const fallback: TabFilterSelections = copyTabFilterSelections(DEFAULT_TAB_FILTER_SELECTIONS);
  return {
    notice: parseFilter(readStringOr(raw, 'notice', ''), fallback.notice),
    assignment: parseFilter(readStringOr(raw, 'assignment', ''), fallback.assignment),
    file: parseFilter(readStringOr(raw, 'file', ''), fallback.file),
    course: parseFilter(readStringOr(raw, 'course', ''), fallback.course)
  };
}

/** 读字符串；缺失 / 形状不对时给空串（交给 parseFilter 走回退）。 */
function readStringOr(raw: Record<string, Object>, key: string, fallback: string): string {
  const value: string | undefined = readString(raw, key);
  return value === undefined ? fallback : value;
}

/** 反序列化。任何一层不对都返回"丢弃"，不抛异常。 */
export function decodeCollectionFlags(payload: string): FlagsDecodeResult {
  if (payload.length === 0) {
    return fail('empty', -1);
  }
  let parsed: Object;
  try {
    parsed = JSON.parse(payload) as Object;
  } catch (error) {
    return fail('parse_failed', -1);
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return fail('not_an_object', -1);
  }
  const envelope: Record<string, Object> = parsed as Record<string, Object>;
  const versionValue: Object = envelope['schemaVersion'];
  if (versionValue === undefined || versionValue === null || typeof versionValue !== 'number') {
    return fail('version_missing', -1);
  }
  const version: number = versionValue as number;
  if (version !== COLLECTION_FLAGS_SCHEMA_VERSION) {
    return fail('version_mismatch:' + version.toString(), version);
  }
  const rawFlags: Object = envelope['flags'];
  if (rawFlags === undefined || rawFlags === null || typeof rawFlags !== 'object'
    || Array.isArray(rawFlags)) {
    return fail('flags_missing', version);
  }
  const flags: CollectionFlags | undefined = readFlags(rawFlags as Record<string, Object>);
  if (flags === undefined) {
    return fail('flags_invalid', version);
  }
  const rawTabs: Object = envelope['tabFilters'];
  if (rawTabs === undefined || rawTabs === null || typeof rawTabs !== 'object'
    || Array.isArray(rawTabs)) {
    // 过滤选择缺失不算致命：状态（收藏/归档/屏蔽）才是验收对象，缺了就用参考实现的默认值。
    const result: FlagsDecodeResult = {
      flags: flags,
      tabFilters: copyTabFilterSelections(DEFAULT_TAB_FILTER_SELECTIONS),
      discardReason: '',
      onDiskVersion: version
    };
    return result;
  }
  const resolvedTabs: TabFilterSelections = readTabFilters(rawTabs as Record<string, Object>);
  const ok: FlagsDecodeResult = {
    flags: flags,
    tabFilters: resolvedTabs,
    discardReason: '',
    onDiskVersion: version
  };
  return ok;
}

/** 序列化（envelope 字段名固定；改字段名等于改磁盘格式 ⇒ schemaVersion +1）。 */
export function encodeCollectionFlags(flags: CollectionFlags,
  tabFilters: TabFilterSelections): string {
  const envelope: Record<string, Object> = {
    'schemaVersion': COLLECTION_FLAGS_SCHEMA_VERSION,
    'flags': flags,
    'tabFilters': tabFilters
  };
  return JSON.stringify(envelope);
}
