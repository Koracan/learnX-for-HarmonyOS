/*
 * 公告（Notice）数据源契约 —— features 只依赖本接口，不依赖任何具体实现。
 *
 * 分层归属说明（ticket 03）：按 spec.md 第 2 节，Repository 应落在 data/。
 * 但 data/ 与 domain/ 归 ticket 05 所有，本 ticket 不得写入；因此接口与 Mock
 * 实现暂放 features/notices/repository/，UI 只依赖接口。
 *
 * 【过渡位置】ticket 09（真实公告 + 快照）落地时：把本接口与实现迁往
 * data/notices/ 并删除本文件，同时改
 * NoticeRepositoryProvider.createNoticeRepository() 的返回值（唯一注入点，
 * 只改一行），界面不动。统筹已把这笔账挂在 ticket 09 上。
 *
 * 形状按 ticket 09 替换的方式设计：
 *   - loadSnapshot() 读“上次快照”（无则 null），refresh() 抓取并落快照；
 *   - 快照自带 fetchedAtMillis 与 schemaVersion，供“先展示旧快照再后台刷新”
 *     与“结构版本变化时丢弃重建”使用；
 *   - 排序不依赖数据源：契约要求 items 按发布时间倒序，UI 侧仍会再排一次
 *     （见 NoticeOrder.sortNoticesDesc）以对齐参考实现 data/actions/notices.ts。
 */
import { Attachment } from '../../../domain/model/ContentItem';

/** 快照结构版本；ticket 09 结构变化时 +1。 */
export const NOTICE_SNAPSHOT_SCHEMA_VERSION: number = 1;

/** 一条公告。字段对齐参考实现 mock.ts / data/types/state.ts 的 Notice。 */
export interface NoticeRecord {
  id: string;
  title: string;
  /** 正文（HTML）。列表不用，公告详情（ticket 04）用。 */
  content: string;
  /**
   * 附件（可选；参考实现 mock.ts:290-296 只有"第一次大作业"那条有）。
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
 * 公告数据源。Mock 与真实实现都实现它，替换实现不影响界面。
 */
export interface NoticeRepository {
  /** 读取上次保存的快照；首次运行返回 null。 */
  loadSnapshot(): Promise<NoticeSnapshot | null>;
  /** 抓取新数据（真实实现同时落盘快照），返回新快照。失败时 reject。 */
  refresh(): Promise<NoticeSnapshot>;
}
