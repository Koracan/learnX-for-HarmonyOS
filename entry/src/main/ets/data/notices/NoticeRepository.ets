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
 * "把两种形状混在一起"的风险（验收第 6 条：识别旧版本、丢弃重建、不崩溃）。
 */
export const NOTICE_SNAPSHOT_SCHEMA_VERSION: number = 1;

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
 * 公告数据源。真实实现与测试替身都实现它，替换实现不影响界面。
 */
export interface NoticeRepository {
  /** 读取上次保存的快照；首次运行 / 版本不符 / 内容损坏时返回 null（调用方随后 refresh）。 */
  loadSnapshot(): Promise<NoticeSnapshot | null>;
  /** 抓取新数据（真实实现同时落盘快照），返回新快照。失败时 reject。 */
  refresh(): Promise<NoticeSnapshot>;
}
