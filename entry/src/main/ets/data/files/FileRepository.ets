/*
 * 文件数据源契约（data/files）——features 只依赖本接口。
 *
 * 与 `data/courses/CourseRepository` 的关系：课程那条线的一次 refresh 里**也**含文件
 * （`CourseSnapshot.files`，课程详情的"文件"标签页读它）。本接口是**文件 tab 自己的**取数：
 * 只解析学期 + 取课程列表 + 取文件（与参考实现 `Files.tsx → getAllFilesForCourses(courseIds)`
 * 同一件事），不重复抓公告与作业。于是打开文件 tab 的请求数是 `1 + 1 + N`，
 * 而不是把三域再抓一遍。
 *
 * 三个"绝不"（与 RealNoticeRepository / RealCourseRepository 同一口径）：
 *   - 取数失败一律 reject，**绝不用空列表兜底**；
 *   - `AuthedRunResult.requiresEnrollment` 为真时抛错并带 `requiresEnrollment=true`；
 *   - 站点当前学期返回 **0 个文件 = 失败信号**（统筹给的事实：本账号本学期文件非空），
 *     只有"显式覆盖到别的学期"时空结果才被当作合法空态。
 */

import { CourseFile } from '../../domain/model/ContentItem';
import { ClearCacheResult, DownloadProgressSink, FileDownloadOutcome, FileDownloadRequest } from './FileDownloader';

/** 一次成功获取得到的文件视图。 */
export interface FileSnapshot {
  files: CourseFile[];
  /** 实际生效的学期（覆盖 / 站点当前，见 FileFetchSource）。 */
  semesterId: string;
  fetchedAtMillis: number;
}

/** 一次下载的结果 + 会话降级标记。 */
export interface FileDownloadReport {
  outcome: FileDownloadOutcome;
  /** true = 必须回登录页并说明需要重新验证。 */
  requiresEnrollment: boolean;
  diagnostic: string;
}

/** 文件数据源。 */
export interface FileRepository {
  /** 抓取全部课程文件（上传时间倒序）。 */
  refresh(): Promise<FileSnapshot>;
  /**
   * 下载一个文件（走 AuthedTaskRunner：会话失效时重登且只重试一次）。
   * @param onProgress 已接收字节 + 总字节（total<0 = 未知）。
   */
  download(request: FileDownloadRequest, onProgress?: DownloadProgressSink): Promise<FileDownloadReport>;
  /** 目标落盘路径（界面显示"保存在哪"）。 */
  targetPath(request: FileDownloadRequest): string;
  /** 当前生效的落盘根目录（设置页显示"当前保存位置"）。 */
  cacheRoot(): string;
  /** 清空文件缓存目录（"清理缓存"）。 */
  clearCache(): ClearCacheResult;
}
