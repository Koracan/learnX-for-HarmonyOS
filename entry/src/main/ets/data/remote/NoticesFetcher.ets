/*
 * 公告抓取仓储（data 层）。
 *
 * 参考实现：DataProcessorModule.`fetchNotices`——两个列表接口（未过期 / 已过期），
 * 列表记录里有附件名（`fjmc`/`fjbt`）时再抓一次详情页拿 `wjid` 并重拼标准下载地址。
 *
 * 移植后：网络调用走注入的 `FetchPort`，正文 Base64 解码器注入，
 * 字段映射与排序全部在 domain/parse/NoticeParser。
 *
 * 锚点日志（验收项 1）：
 *   data.notices fetched courses=<n> items=<n> elapsedMs=<n> requests=<n> failures=<n>
 */

import { Logger } from '../../core/log/Logger';
import { Attachment, Notice } from '../../domain/model/ContentItem';
import { CourseName } from '../../domain/parse/CourseName';
import {
  Base64Decoder, RawNotice, noticeAttachmentName, parseNotice, parseNoticeAttachment, sortNotices
} from '../../domain/parse/NoticeParser';
import { FetchOutcome, FetchPort, Session } from './Port';
import { LEARN_ORIGIN } from './Requests';

export const NOTICES_LOG_DOMAIN: string = 'data.notices';

/** 公告列表接口（照参考实现两个来源：未过期 / 已过期）。 */
export const NOTICE_LIST_PATHS: string[] = [
  '/b/wlxt/kcgg/wlkc_ggb/student/pageListXsbyWgq',
  '/b/wlxt/kcgg/wlkc_ggb/student/pageListXsbyYgq'
];

/** 列表响应 → 原始记录数组（`aaData`，退回 `resultsList`；照参考实现）。 */
export function extractNoticeRows(body: string): RawNotice[] {
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
  const box: Record<string, Object> = object as Record<string, Object>;
  const rows: Object[] = box['aaData'] === undefined || box['aaData'] === null
    ? [] : box['aaData'] as Object[];
  if (rows.length > 0) {
    return rows as RawNotice[];
  }
  return box['resultsList'] === undefined || box['resultsList'] === null
    ? [] : box['resultsList'] as RawNotice[];
}

/** 一条"这条记录属于哪个课程"的登记项（跨接口收集时需要）。 */
interface OwnedRow {
  courseId: string;
  raw: RawNotice;
}

/** 公告仓储。 */
export class NoticesFetcher {
  private readonly logger: Logger;
  private readonly port: FetchPort;
  private readonly session: Session;
  private readonly courseNames: Record<string, CourseName>;
  private readonly decodeBase64: Base64Decoder;

  constructor(
    logger: Logger,
    port: FetchPort,
    session: Session,
    courseNames: Record<string, CourseName>,
    decodeBase64: Base64Decoder
  ) {
    this.logger = logger;
    this.port = port;
    this.session = session;
    this.courseNames = courseNames;
    this.decodeBase64 = decodeBase64;
  }

  /** 抓取并解析；返回已排序公告（发布时间倒序 + 标识倒序）。 */
  async fetch(courseIds: string[]): Promise<Notice[]> {
    const startedAt: number = Date.now();
    let requests: number = 0;
    let failures: number = 0;
    const rows: OwnedRow[] = [];

    // 第一轮：列表接口（逐课程串行，照参考实现）。
    for (let i = 0; i < courseIds.length; i++) {
      const courseId: string = courseIds[i];
      for (let j = 0; j < NOTICE_LIST_PATHS.length; j++) {
        requests++;
        const outcome: FetchOutcome = await this.port.postForm(this.session, {
          url: LEARN_ORIGIN + NOTICE_LIST_PATHS[j] + '?_csrf=' + this.session.csrfToken,
          courseId: courseId
        });
        if (!outcome.ok) {
          failures++;
          this.reportFailure(courseId, j, outcome);
        }
        const parsedRows: RawNotice[] = extractNoticeRows(outcome.body);
        for (let k = 0; k < parsedRows.length; k++) {
          rows.push({ courseId: courseId, raw: parsedRows[k] });
        }
      }
    }

    // 第二轮：逐条组装（有附件名时才抓详情页）。
    const notices: Notice[] = [];
    for (let i = 0; i < rows.length; i++) {
      const owned: OwnedRow = rows[i];
      const notice: Notice = parseNotice(owned.raw, owned.courseId, this.courseNames, this.decodeBase64);
      const attachmentName: string | undefined = noticeAttachmentName(owned.raw);
      if (attachmentName !== undefined) {
        requests++;
        const detailOutcome: FetchOutcome = await this.port.get(this.session, {
          url: LEARN_ORIGIN + '/f/wlxt/kcgg/wlkc_ggb/student/beforeViewXs?wlkcid='
            + owned.courseId + '&id=' + owned.raw.ggid
        });
        if (!detailOutcome.ok) {
          failures++;
          this.reportFailure(owned.courseId, -1, detailOutcome);
        }
        const attachment: Attachment | undefined = parseNoticeAttachment(detailOutcome.body, attachmentName);
        if (attachment !== undefined) {
          notice.attachment = attachment;
        }
      }
      notices.push(notice);
    }

    const sorted: Notice[] = sortNotices(notices);
    const elapsedMs: number = Date.now() - startedAt;
    this.logger.info(NOTICES_LOG_DOMAIN + ' fetched courses=' + courseIds.length.toString()
      + ' items=' + sorted.length.toString()
      + ' elapsedMs=' + elapsedMs.toString()
      + ' requests=' + requests.toString()
      + ' failures=' + failures.toString());
    return sorted;
  }

  private reportFailure(courseId: string, sourceIndex: number, outcome: FetchOutcome): void {
    const detail: string = outcome.error === undefined ? 'HTTP ' + outcome.status.toString() : outcome.error;
    this.logger.warn(NOTICES_LOG_DOMAIN + ' request failed course=' + courseId
      + ' source=' + sourceIndex.toString() + ' ' + detail);
  }
}
