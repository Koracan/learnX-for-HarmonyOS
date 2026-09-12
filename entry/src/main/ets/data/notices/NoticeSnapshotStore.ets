/*
 * 快照的持久化端口（data/notices，ticket 09）。
 *
 * 端口只描述"存/取一段字符串"，**格式与版本判定在 NoticeSnapshotSerialization**，
 * 因此在单测里可以用内存替身跑通"读快照 → 版本不符丢弃 → 重建"整条逻辑，
 * 不需要碰平台（平台实现见 NoticeSnapshotFileStore）。
 */

import { SnapshotDecodeResult } from './NoticeSnapshotSerialization';

/** 一次落盘的结果（失败不抛异常：快照是缓存，写不进去不该让刷新失败）。 */
export interface SnapshotSaveResult {
  ok: boolean;
  diagnostic: string;
}

/** 一次读取的结果。 */
export interface SnapshotLoadResult {
  /** 磁盘上有东西（无论是否可用）。 */
  present: boolean;
  /** 解码结果；`present=false` 时 discardReason='absent' 且 items 为空。 */
  decoded: SnapshotDecodeResult;
}

/** 快照存储端口。 */
export interface NoticeSnapshotPort {
  load(): Promise<SnapshotLoadResult>;
  save(payload: string): Promise<SnapshotSaveResult>;
}
