/*
 * 公告（Notice）数据源契约 —— features 只依赖本接口，不依赖任何具体实现。
 *
 * 【ticket 09 迁移】本文件与 `RealNoticeRepository` 原寄在 features/notices/repository/
 * （ticket 03 开工时 data/ 正被 ticket 05 占用）。按 spec.md 第 2 节的分层，Repository
 * 属 data/；本 ticket 把接口与实现一起迁到 data/notices/，并把 features 下的过渡文件删掉。
 * 组装点只有一处：features/notices/repository/NoticeRepositoryProvider.ets。
 *
 * 形状说明：
 *   - loadSnapshot() 读"上次快照"（无则 null），refresh() 抓取并落快照；
 *   - markRead() 把一条公告记进本地的已读集合并落盘（打开详情时调用）；
 *   - 快照自带 fetchedAtMillis 与 schemaVersion，供"先展示旧快照再后台刷新"
 *     与"结构版本变化时丢弃重建"使用；
 *   - 排序不依赖数据源：契约要求 items 按发布时间倒序，UI 侧仍会再排一次
 *     （见 NoticeOrder.sortNoticesDesc）以对齐参考实现 data/actions/notices.ts。
 */
import { Attachment } from '../../domain/model/ContentItem';

/**
 * 快照结构版本；**本结构（NoticeRecord 字段集 / 快照信封）变化时 +1**。
 *
 * 版本不符时**丢弃重建**，不尝试迁移：快照只是缓存，重抓一次的代价远小于
 * "把两种形状混在一起"的风险（旧版本要能被识别、被丢弃、且不崩溃）。
 *
 * 当前版本 2：落盘信封新增了本地已读集合（见 SnapshotDecodeResult.readNoticeIds）。
 */
export const NOTICE_SNAPSHOT_SCHEMA_VERSION: number = 2;

/** 一条公告。字段对齐参考实现 mock.ts / data/types/state.ts 的 Notice。 */
export interface NoticeRecord {
  id: string;
  title: string;
  /** 正文（HTML）。列表只用于 2 行预览（渲染前去标签），公告详情（ticket 04）用原文。 */
  content: string;
  /**
   * 附件（可选；参考实现里只有带附件的公告才有）。
   * 公告详情在正文**上方**独立一行显示它（NoticeDetail.tsx:95-109），点击跳 FileDetail。
   */
  attachment?: Attachment;
  publisher: string;
  courseId: string;
  courseName: string;
  courseTeacherName: string;
  /** 发布时间，epoch 毫秒。排序依据（参考实现用 dayjs(publishTime).unix()）。 */
  publishTimeMillis: number;
  /**
   * 界面用的已读标志 = **站点说的已读** 或 **本地已读集合里记着它**。
   *
   * 两个来源语义不同，不要混成一份：站点在列表接口里用 `sfyd` 给出的状态可能落后
   * 于本机（也可能被站点重置），本地集合只记"这台设备打开过这一条"。
   * 两者取或：只要任一说已读，就按已读呈现。
   */
  hasRead: boolean;
  markedImportant: boolean;
  url: string;
}

/** 一次成功获取得到的公告集合。 */
export interface NoticeSnapshot {
  items: NoticeRecord[];
  /** 抓取时间，epoch 毫秒。 */
  fetchedAtMillis: number;
  schemaVersion: number;
  /** true = 来自本地快照（冷启动先渲染它），false = 本次实时抓取。 */
  fromSnapshot: boolean;
}

/**
 * 按本地已读集合重算每条记录的 `hasRead`：站点说已读的保持已读，
 * 本地集合里有的也置为已读，其余原样（**返回新数组，不改入参**）。
 *
 * 合并点只有这一处：抓取结果、读回的快照都经它过一遍，界面因此只看 `hasRead` 一个字段，
 * 不需要自己再查一次已读集合。
 */
export function mergeNoticeReadState(items: NoticeRecord[], readNoticeIds: string[]): NoticeRecord[] {
  const merged: NoticeRecord[] = [];
  for (let i = 0; i < items.length; i++) {
    const item: NoticeRecord = items[i];
    // 恒返回**新对象**：入参可能是抓取结果之外还被别处持有的集合（例如单测夹具），
    // 就地改 hasRead 会顺着共享引用漏出去。
    const record: NoticeRecord = {
      id: item.id,
      title: item.title,
      content: item.content,
      publisher: item.publisher,
      courseId: item.courseId,
      courseName: item.courseName,
      courseTeacherName: item.courseTeacherName,
      publishTimeMillis: item.publishTimeMillis,
      hasRead: item.hasRead || readNoticeIds.includes(item.id),
      markedImportant: item.markedImportant,
      url: item.url
    };
    // 显式"有则赋值"：可选字段塞 undefined 会改变记录的形状。
    if (item.attachment !== undefined) {
      record.attachment = item.attachment;
    }
    merged.push(record);
  }
  return merged;
}

/**
 * 公告数据源。真实实现与测试替身都实现它，替换实现不影响界面。
 */
export interface NoticeRepository {
  /** 读取上次保存的快照；首次运行 / 版本不符 / 内容损坏时返回 null（调用方随后 refresh）。 */
  loadSnapshot(): Promise<NoticeSnapshot | null>;
  /** 抓取新数据（真实实现同时落盘快照），返回新快照。失败时 reject。 */
  refresh(): Promise<NoticeSnapshot>;
  /**
   * 把一条公告记进**本地的已读集合**，并随快照一起落盘。重复调用同一条是幂等的。
   *
   * 只影响本地集合，**不向站点发任何请求**：站点侧的已读由它自己维护。
   * 落盘失败不抛异常（与快照落盘同口径：缓存写不进去不该让界面报错）。
   */
  markRead(noticeId: string): Promise<void>;
}
