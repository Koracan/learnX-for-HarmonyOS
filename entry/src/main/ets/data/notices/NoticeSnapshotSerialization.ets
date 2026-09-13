/*
 * 快照的序列化 / 反序列化 —— **纯字符串运算，零平台依赖**（可在 Hypium Local Test 里直接跑）。
 *
 * 为什么单独成文件：快照要落盘（`NoticeSnapshotFileStore`），而"落盘的字节必须能安全地
 * 读回来"这件事**不该只靠设备取证来证明**。把它做成纯函数之后，版本不符、截断、字段缺失、
 * 类型不对这四类损坏都能用单测钉住（旧版本要能被识别并丢弃重建，不崩溃）。
 *
 * 落盘信封（`PersistedNoticeSnapshot`）刻意是 NoticeSnapshot 的**子集**：
 *   - items / fetchedAtMillis / schemaVersion / readNoticeIds 落盘；
 *   - `fromSnapshot` **不落盘**——它是"这一次读的是不是快照"的瞬时语义，由读取方置 true。
 *
 * `readNoticeIds` 是**本机已读集合**，与内容项同处一份记录，没有第二份存储。
 * 它与每条记录自带的 `hasRead`（站点说的）不是一回事：读取方拿它去合并，
 * 合并规则见 NoticeRepository.mergeNoticeReadState。
 */

import { Attachment } from '../../domain/model/ContentItem';
import {
  NOTICE_SNAPSHOT_SCHEMA_VERSION, NoticeRecord, NoticeSnapshot
} from './NoticeRepository';

/** 落盘信封的字段名（改这里等于改磁盘格式 ⇒ 必须同时把 schemaVersion +1）。 */
interface PersistedNoticeSnapshot {
  schemaVersion: number;
  fetchedAtMillis: number;
  items: NoticeRecord[];
  /** 本机已读集合（见文件头）。 */
  readNoticeIds: string[];
}

/** 反序列化结果：要么拿到条目，要么明确说明为什么丢弃（供日志/取证）。 */
export interface SnapshotDecodeResult {
  items: NoticeRecord[];
  fetchedAtMillis: number;
  /** 磁盘上记着的本地已读集合（空数组 = 没有）。丢弃时一律为空。 */
  readNoticeIds: string[];
  /** 丢弃原因；空串 = 成功。取值：empty / parse_failed / not_an_object / version_missing /
   *  version_mismatch:<onDisk> / fetched_at_invalid / items_missing /
   *  item_<i>_<field> / unsupported_attachment_<i> / read_ids_invalid */
  discardReason: string;
  /** 磁盘上的结构版本（丢弃时用于对比；解析不出时为 -1）。 */
  onDiskVersion: number;
}

function fail(reason: string, onDiskVersion: number): SnapshotDecodeResult {
  return {
    items: [], fetchedAtMillis: 0, readNoticeIds: [], discardReason: reason, onDiskVersion: onDiskVersion
  };
}

/**
 * 读回已读集合：**非字符串成员静默丢掉**（不丢弃整条快照）。
 *
 * 为什么与 items 的严格程度不同：已读集合丢一项只表现为"那条又变成未读"，
 * 下一次打开会重新记上；为它扔掉整份内容快照不划算。集合本身不是数组时返回 undefined，
 * 由调用方决定（与 items 同级，缺字段算损坏）。
 */
function readReadNoticeIds(envelope: Record<string, Object>): string[] | undefined {
  const raw: Object = envelope['readNoticeIds'];
  if (raw === undefined || raw === null) {
    return undefined;
  }
  if (!Array.isArray(raw)) {
    return undefined;
  }
  const array: Object[] = raw as Object[];
  const ids: string[] = [];
  for (let i = 0; i < array.length; i++) {
    const value: Object = array[i];
    if (typeof value !== 'string') {
      continue;
    }
    const text: string = value as string;
    if (text.length > 0 && !ids.includes(text)) {
      ids.push(text);
    }
  }
  return ids;
}

/** 字符串字段：必须存在且是 string，否则给 field 名让调用方组成丢弃原因。 */
function readString(raw: Record<string, Object>, key: string): string | undefined {
  const value: Object = raw[key];
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value !== 'string') {
    return undefined;
  }
  return value as string;
}

function readBoolean(raw: Record<string, Object>, key: string): boolean | undefined {
  const value: Object = raw[key];
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value !== 'boolean') {
    return undefined;
  }
  return value as boolean;
}

function readNumber(raw: Record<string, Object>, key: string): number | undefined {
  const value: Object = raw[key];
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value !== 'number') {
    return undefined;
  }
  return value as number;
}

/** 附件：形状不对时**整条快照丢弃**（而不是静默丢掉附件字段）。 */
function readAttachment(raw: Record<string, Object>, index: number): Attachment | undefined | string {
  const value: Object = raw['attachment'];
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value !== 'object') {
    return 'unsupported_attachment_' + index.toString();
  }
  const attachment: Record<string, Object> = value as Record<string, Object>;
  const name: string | undefined = readString(attachment, 'name');
  const downloadUrl: string | undefined = readString(attachment, 'downloadUrl');
  if (name === undefined || downloadUrl === undefined) {
    return 'unsupported_attachment_' + index.toString();
  }
  const result: Attachment = { name: name, downloadUrl: downloadUrl };
  const id: string | undefined = readString(attachment, 'id');
  if (id !== undefined) {
    result.id = id;
  }
  const size: string | undefined = readString(attachment, 'size');
  if (size !== undefined) {
    result.size = size;
  }
  return result;
}

/**
 * 反序列化落盘的信封。**任何一层不对都返回"丢弃"而不是抛异常**：
 * 快照是缓存，丢掉了下一条 refresh 会重建；抛异常会把界面卡在错误态。
 */
export function decodeNoticeSnapshot(payload: string): SnapshotDecodeResult {
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
  const version: number | undefined = readNumber(envelope, 'schemaVersion');
  if (version === undefined) {
    return fail('version_missing', -1);
  }
  if (version !== NOTICE_SNAPSHOT_SCHEMA_VERSION) {
    return fail('version_mismatch:' + version.toString(), version);
  }
  const fetchedAt: number | undefined = readNumber(envelope, 'fetchedAtMillis');
  if (fetchedAt === undefined || fetchedAt <= 0) {
    return fail('fetched_at_invalid', version);
  }
  const rawItems: Object = envelope['items'];
  if (rawItems === undefined || rawItems === null || !Array.isArray(rawItems)) {
    return fail('items_missing', version);
  }
  const readNoticeIds: string[] | undefined = readReadNoticeIds(envelope);
  if (readNoticeIds === undefined) {
    return fail('read_ids_invalid', version);
  }
  const array: Object[] = rawItems as Object[];
  const items: NoticeRecord[] = [];
  for (let i = 0; i < array.length; i++) {
    const entry: Object = array[i];
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
      return fail('item_' + i.toString() + '_not_an_object', version);
    }
    const raw: Record<string, Object> = entry as Record<string, Object>;
    const fields: string[] = ['id', 'title', 'content', 'publisher', 'courseId', 'courseName',
      'courseTeacherName', 'url'];
    const values: string[] = [];
    let missing: string = '';
    for (let f = 0; f < fields.length; f++) {
      const value: string | undefined = readString(raw, fields[f]);
      if (value === undefined) {
        missing = fields[f];
        break;
      }
      values.push(value);
    }
    if (missing.length > 0) {
      return fail('item_' + i.toString() + '_' + missing, version);
    }
    const publishTime: number | undefined = readNumber(raw, 'publishTimeMillis');
    const hasRead: boolean | undefined = readBoolean(raw, 'hasRead');
    const markedImportant: boolean | undefined = readBoolean(raw, 'markedImportant');
    if (publishTime === undefined) {
      return fail('item_' + i.toString() + '_publishTimeMillis', version);
    }
    if (hasRead === undefined) {
      return fail('item_' + i.toString() + '_hasRead', version);
    }
    if (markedImportant === undefined) {
      return fail('item_' + i.toString() + '_markedImportant', version);
    }
    const attachment: Attachment | undefined | string = readAttachment(raw, i);
    if (typeof attachment === 'string') {
      return fail(attachment, version);
    }
    const record: NoticeRecord = {
      id: values[0],
      title: values[1],
      content: values[2],
      publisher: values[3],
      courseId: values[4],
      courseName: values[5],
      courseTeacherName: values[6],
      url: values[7],
      publishTimeMillis: publishTime,
      hasRead: hasRead,
      markedImportant: markedImportant
    };
    if (attachment !== undefined) {
      record.attachment = attachment as Attachment;
    }
    items.push(record);
  }
  return {
    items: items, fetchedAtMillis: fetchedAt, readNoticeIds: readNoticeIds,
    discardReason: '', onDiskVersion: version
  };
}

/**
 * 序列化快照。**必须能 round-trip**：单测断言 `decode(encode(s)) == s`
 * （附件可选字段的 undefined 不能在往返中变成 null）。
 *
 * 已读集合写盘前**去重、丢掉空串**：集合是"有哪些 id"，重复成员没有意义。
 */
export function encodeNoticeSnapshot(items: NoticeRecord[], fetchedAtMillis: number,
  readNoticeIds: string[] = []): string {
  const ids: string[] = [];
  for (let i = 0; i < readNoticeIds.length; i++) {
    const id: string = readNoticeIds[i];
    if (id.length > 0 && !ids.includes(id)) {
      ids.push(id);
    }
  }
  const envelope: PersistedNoticeSnapshot = {
    schemaVersion: NOTICE_SNAPSHOT_SCHEMA_VERSION,
    fetchedAtMillis: fetchedAtMillis,
    items: items,
    readNoticeIds: ids
  };
  return JSON.stringify(envelope);
}

/** 由解码结果组装内存快照（`fromSnapshot=true`：读的就是快照）。 */
export function snapshotFromDecoded(decoded: SnapshotDecodeResult): NoticeSnapshot {
  return {
    items: decoded.items,
    fetchedAtMillis: decoded.fetchedAtMillis,
    schemaVersion: NOTICE_SNAPSHOT_SCHEMA_VERSION,
    fromSnapshot: true
  };
}
