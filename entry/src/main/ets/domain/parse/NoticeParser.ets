/*
 * 公告响应解析——**纯函数，零平台依赖**（见 scripts/check-domain-purity.mjs）。
 *
 * 移植自参考实现 DataProcessorModule.ts 的 `fetchNotices` 与 `processNotices`：
 *   - 列表接口的字段映射（ggid / bt / fbrxm / fbsj / jzsj / sfqd / sfyd / fjmc / fjbt / ggnr）；
 *   - Base64 正文解码，**解码器由调用方注入**（设备上给 core 的 util.Base64Helper 封装，
 *     单测里给可控实现），解码失败返回空串——参考实现同样吞掉异常；
 *   - 时间倒序 + 标识倒序（参考实现 `processNotices` 只按时间倒序；作业/文件两个域
 *     在 actions 里补了 `b.id.localeCompare(a.id)`，这里统一成同一套比较器，
 *     对公告是"多了一级稳定次序"，不改变同时间条目的相对顺序语义）。
 */

import { Attachment, Notice } from '../model/ContentItem';
import { CourseName, UNKNOWN_COURSE_NAME } from './CourseName';
import { decodeHtmlEntities, compareByTimeThenIdDesc } from './Text';
import { absoluteLearnUrl, unwrapDownloadUrl, extractFileId, noticeDownloadUrl } from './Attachment';

/** Base64 → 文本；解码失败返回空串（异常输入容错由实现方或本函数兜底）。 */
export type Base64Decoder = (encoded: string) => string;

/** 列表接口 `aaData` 里的一条公告原始记录（字段名照站点中文拼音缩写）。 */
export interface RawNotice {
  ggid: string;
  bt: string;
  fbrxm: string;
  fbsj?: string;
  fbsjStr?: string;
  jzsj?: string;
  sfqd?: string | number;
  sfyd?: string | number;
  fjmc?: string;
  fjbt?: string;
  /** 正文，Base64 编码的 HTML。 */
  ggnr?: string;
}

/** 是否已读：参考实现接受字符串 `'1'`、数字 `1`、`'是'`、`'已读'` 四种写法。 */
export function isNoticeRead(raw: string | number | undefined): boolean {
  return raw === '1' || raw === 1 || raw === '是' || raw === '已读';
}

/** 公告详情页地址。 */
export function noticeDetailUrl(courseId: string, noticeId: string): string {
  return 'https://learn.tsinghua.edu.cn/f/wlxt/kcgg/wlkc_ggb/student/beforeViewXs?wlkcid='
    + courseId + '&id=' + noticeId;
}

function text(value: string | undefined): string {
  return value === undefined || value === null ? '' : value;
}

/**
 * 用列表记录 + 可选的正文覆盖组装一条公告。
 * `contentText` 为 undefined 时表示"没有拿到正文"，此时用列表里的 ggnr 解码，
 * 这样参考实现里"详情页只补附件、正文一直在列表里"的行为保持不变。
 */
export function parseNotice(
  raw: RawNotice,
  courseId: string,
  courseNames: Record<string, CourseName>,
  decodeBase64: Base64Decoder,
  contentText?: string
): Notice {
  const known: CourseName | undefined = courseNames[courseId];
  let content: string = contentText === undefined ? decodeHtmlEntities(decodeBase64(text(raw.ggnr))) : contentText;
  const notice: Notice = {
    id: text(raw.ggid),
    title: decodeHtmlEntities(text(raw.bt)),
    publisher: text(raw.fbrxm),
    publishTime: raw.fbsj !== undefined ? raw.fbsj : text(raw.fbsjStr),
    markedImportant: Number(raw.sfqd) === 1,
    hasRead: isNoticeRead(raw.sfyd),
    url: noticeDetailUrl(courseId, text(raw.ggid)),
    courseId: courseId,
    courseName: known !== undefined ? known.name : UNKNOWN_COURSE_NAME,
    courseTeacherName: known !== undefined ? known.teacherName : '',
    content: content
  };
  if (raw.jzsj !== undefined && raw.jzsj !== null) {
    notice.expireTime = raw.jzsj;
  }
  return notice;
}

/**
 * 列表响应 → 已排序公告。
 * @param rawRecords 一个列表接口返回的 `aaData`（或 `resultsList`）。
 * @param decodeBase64 正文解码器。
 */
export function parseNoticeList(
  rawRecords: RawNotice[],
  courseId: string,
  courseNames: Record<string, CourseName>,
  decodeBase64: Base64Decoder
): Notice[] {
  const parsed: Notice[] = [];
  for (let i = 0; i < rawRecords.length; i++) {
    parsed.push(parseNotice(rawRecords[i], courseId, courseNames, decodeBase64));
  }
  return sortNotices(parsed);
}

/** 公告排序：发布时间倒序，同时间按标识倒序。 */
export function sortNotices(notices: Notice[]): Notice[] {
  const sorted: Notice[] = notices.slice();
  sorted.sort((left: Notice, right: Notice): number =>
    compareByTimeThenIdDesc(left.publishTime, left.id, right.publishTime, right.id));
  return sorted;
}

/** 公告附件：优先 `class="ml-10"` 的链接，取到 `wjid` 后重拼标准下载地址。 */
export function parseNoticeAttachment(detailHtml: string, attachmentName: string): Attachment | undefined {
  if (!detailHtml) {
    return undefined;
  }
  const ml10: RegExpMatchArray | null = detailHtml.match(/<a[^>]*class\s*=\s*["'][^"']*ml-10[^"']*["'][^>]*href\s*=\s*["']([^"']+)["']/i);
  if (ml10 !== null) {
    const fileId: string | undefined = extractFileId(ml10[1]);
    if (fileId !== undefined) {
      return { name: decodeHtmlEntities(attachmentName), downloadUrl: noticeDownloadUrl(fileId), id: fileId };
    }
  }
  const generic: RegExpMatchArray | null = detailHtml.match(/href\s*=\s*["']([^"']*(?:downloadFile|openNewWindow|fileId=)[^"']*)["']/i);
  if (generic !== null) {
    return {
      name: decodeHtmlEntities(attachmentName),
      downloadUrl: unwrapDownloadUrl(absoluteLearnUrl(generic[1]))
    };
  }
  return undefined;
}

/** 列表里的附件名；`'null'` 字符串视为没有附件（照参考实现）。 */
export function noticeAttachmentName(raw: RawNotice): string | undefined {
  const candidate: string | undefined = raw.fjmc !== undefined && raw.fjmc !== null && raw.fjmc.length > 0
    ? raw.fjmc : raw.fjbt;
  if (candidate === undefined || candidate === null || candidate.length === 0 || candidate === 'null') {
    return undefined;
  }
  return candidate;
}
