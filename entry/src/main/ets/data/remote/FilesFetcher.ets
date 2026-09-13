/*
 * 课程文件抓取仓储（data 层）。
 *
 * 参考实现：DataProcessorModule.`fetchFiles`——每课程一个接口
 * `kjxxbByWlkcidAndSizeForStudent?wlkcid=..&size=200&_csrf=..`，
 * 响应 `object` 是数组，字段映射在 domain/parse/FileParser。
 *
 * 锚点日志：
 *   data.files fetched courses=<n> items=<n> elapsedMs=<n> requests=<n> failures=<n>
 */

import { Logger } from '../../core/log/Logger';
import { CourseFile } from '../../domain/model/ContentItem';
import { CourseName } from '../../domain/parse/CourseName';
import { RawCourseFile, parseCourseFileList, sortCourseFiles } from '../../domain/parse/FileParser';
import { FetchOutcome, FetchPort, Session } from './Port';
import { LEARN_ORIGIN } from './Requests';

export const FILES_LOG_DOMAIN: string = 'data.files';

/** 列表响应 → 原始记录数组（`object` 为数组；照参考实现）。 */
export function extractCourseFileRows(body: string): RawCourseFile[] {
  if (body.length === 0) {
    return [];
  }
  let parsed: Object;
  try {
    parsed = JSON.parse(body) as Object;
  } catch (error) {
    return [];
  }
  const root: Record<string, Object> = parsed as Record<string, Object>;
  if (String(root['result']) !== 'success') {
    return [];
  }
  const object: Object | undefined = root['object'] as Object | undefined;
  if (object === undefined || object === null) {
    return [];
  }
  return object as RawCourseFile[];
}

/** 课程文件仓储。 */
export class FilesFetcher {
  private readonly logger: Logger;
  private readonly port: FetchPort;
  private readonly session: Session;
  private readonly courseNames: Record<string, CourseName>;

  constructor(logger: Logger, port: FetchPort, session: Session, courseNames: Record<string, CourseName>) {
    this.logger = logger;
    this.port = port;
    this.session = session;
    this.courseNames = courseNames;
  }

  /** 抓取并解析；返回上传时间倒序的课程文件。 */
  async fetch(courseIds: string[]): Promise<CourseFile[]> {
    const startedAt: number = Date.now();
    let requests: number = 0;
    let failures: number = 0;
    const collected: CourseFile[] = [];

    for (let i = 0; i < courseIds.length; i++) {
      const courseId: string = courseIds[i];
      requests++;
      const outcome: FetchOutcome = await this.port.get(this.session, {
        url: LEARN_ORIGIN + '/b/wlxt/kj/wlkc_kjxxb/student/kjxxbByWlkcidAndSizeForStudent?wlkcid='
          + courseId + '&size=200&_csrf=' + this.session.csrfToken
      });
      if (!outcome.ok) {
        failures++;
        const detail: string = outcome.error === undefined ? 'HTTP ' + outcome.status.toString() : outcome.error;
        this.logger.warn(FILES_LOG_DOMAIN + ' request failed course=' + courseId + ' ' + detail);
      }
      const rows: RawCourseFile[] = extractCourseFileRows(outcome.body);
      const parsed: CourseFile[] = parseCourseFileList(rows, courseId, this.courseNames);
      for (let j = 0; j < parsed.length; j++) {
        collected.push(parsed[j]);
      }
    }

    // 跨课程统一排序（每个课程内部已排好，这里用同一比较器再做一次全局归并）。
    const sorted: CourseFile[] = sortCourseFiles(collected);

    const elapsedMs: number = Date.now() - startedAt;
    this.logger.info(FILES_LOG_DOMAIN + ' fetched courses=' + courseIds.length.toString()
      + ' items=' + sorted.length.toString()
      + ' elapsedMs=' + elapsedMs.toString()
      + ' requests=' + requests.toString()
      + ' failures=' + failures.toString());
    return sorted;
  }
}
