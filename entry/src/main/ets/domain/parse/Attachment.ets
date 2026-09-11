/*
 * 附件解析——**零平台依赖**（见 scripts/check-domain-purity.mjs）。
 *
 * 移植自参考实现 DataProcessorModule.ts 的两段正则：
 *   - `extractAttachment`：作业详情页里 `<a href="...downloadFile|openNewWindow|fileId=|wjid=...">名字</a>`
 *     的抓取，含"名字退化为 title 属性 → 退化到 span.ftitle"三级回退；
 *   - 公告附件的 `class="ml-10"` 优先匹配 + 通用下载链接回退。
 *
 * 正则与字段映射是历经验证的资产，关键表达式与分支**逐条照搬**，只做两处去平台化：
 * 用 `startsWith` 代替 URL 类判断，用 `decodeURIComponent`（ArkTS 内置）代替 URL 解析。
 */

import { Attachment } from '../model/ContentItem';
import { decodeHtmlEntities } from './Text';

/** 学习站点根。 */
export const LEARN_ORIGIN: string = 'https://learn.tsinghua.edu.cn';

/** 作业详情页里"可下载链接"的判据（照参考实现 extractAttachment）。 */
const DOWNLOAD_HREF_PATTERN = /<a[^>]*href\s*=\s*["']([^"']*(?:downloadFile|openNewWindow|fileId=|wjid=)[^"']*)["'][^>]*>([\s\S]*?)<\/a>/i;
/** `<a>` 上的 title 属性（名字退化的第一候选）。 */
const TITLE_ATTRIBUTE_PATTERN = /title\s*=\s*["']([^"']+)["']/i;
/** 同块内的 `span.ftitle`（名字退化的第二候选）。 */
const FTITLE_PATTERN = /<span[^>]*class="ftitle"[^>]*>([^<]+)<\/span>/i;
/** 公告详情页里带 `ml-10` 类的附件链接（优先匹配）。 */
const ML10_HREF_PATTERN = /<a[^>]*class\s*=\s*["'][^"']*ml-10[^"']*["'][^>]*href\s*=\s*["']([^"']+)["']/i;
/** 通用下载链接（公告附件回退）。 */
const GENERIC_DOWNLOAD_PATTERN = /href\s*=\s*["']([^"']*(?:downloadFile|openNewWindow|fileId=)[^"']*)["']/i;
/** 从附件地址里取 wjid / fileId。 */
const FILE_ID_PATTERN = /(?:wjid|fileId)=([^"&]+)/i;
/** 附件体积文本（thu-learn-lib 从 `span[class^="color"]` 取）。 */
const SIZE_PATTERN = /<span[^>]*class\s*=\s*["']color[^"']*["'][^>]*>([^<]+)<\/span>/i;

/** 学习站点上的绝对地址；已是绝对地址时原样返回。 */
export function absoluteLearnUrl(href: string): string {
  if (!href) {
    return href;
  }
  if (href.startsWith('http')) {
    return href;
  }
  return LEARN_ORIGIN + href;
}

/**
 * 展开预览页地址：`...openNewWindow...downloadUrl=<真实地址>` 时取参数值。
 * 移植自参考实现 `unwrapDownloadUrl`。
 */
export function unwrapDownloadUrl(url: string): string {
  if (!url) {
    return url;
  }
  if (url.includes('openNewWindow') && url.includes('downloadUrl=')) {
    const matched: RegExpMatchArray | null = url.match(/[?&]downloadUrl=([^&]+)/);
    if (matched !== null) {
      let decoded: string = decodeURIComponent(matched[1]);
      if (!decoded.startsWith('http')) {
        decoded = LEARN_ORIGIN + decoded;
      }
      return decoded;
    }
  }
  return url;
}

/** 从附件地址里取标识（公告附件用于组装 downloadFile 地址）。 */
export function extractFileId(href: string): string | undefined {
  const matched: RegExpMatchArray | null = href.match(FILE_ID_PATTERN);
  if (matched === null) {
    return undefined;
  }
  try {
    return decodeURIComponent(matched[1]);
  } catch (error) {
    return matched[1];
  }
}

/** 公告附件下载地址（照参考实现拼接）。 */
export function noticeDownloadUrl(fileId: string): string {
  return LEARN_ORIGIN + '/b/wlxt/kj/wlkc_kjxxb/student/downloadFile?sfgk=0&wjid=' + fileId;
}

/** 课程文件下载地址（照参考实现拼接）。 */
export function courseFileDownloadUrl(fileId: string): string {
  return noticeDownloadUrl(fileId);
}

function cleanName(raw: string): string {
  return decodeHtmlEntities(raw.replace(/<[^>]+>/g, '').trim());
}

/**
 * 从一段 HTML（通常是 `<div class="list fujian clearfix">` 之后约 2000 字符）里取附件。
 * 取不到时返回 undefined——"这个块没有附件"是正常结果，不是错误。
 */
export function extractAttachment(htmlPart: string): Attachment | undefined {
  if (!htmlPart) {
    return undefined;
  }
  const matched: RegExpMatchArray | null = htmlPart.match(DOWNLOAD_HREF_PATTERN);
  if (matched === null) {
    return undefined;
  }
  let downloadUrl: string = absoluteLearnUrl(matched[1]);
  downloadUrl = unwrapDownloadUrl(downloadUrl);

  let name: string = cleanName(matched[2]);
  if (name.length < 2) {
    const titleMatched: RegExpMatchArray | null = matched[0].match(TITLE_ATTRIBUTE_PATTERN);
    if (titleMatched !== null) {
      name = decodeHtmlEntities(titleMatched[1]);
    }
  }
  if (name.length < 2) {
    const ftitleMatched: RegExpMatchArray | null = htmlPart.match(FTITLE_PATTERN);
    if (ftitleMatched !== null) {
      name = decodeHtmlEntities(ftitleMatched[1].trim());
    }
  }

  const sizeMatched: RegExpMatchArray | null = htmlPart.match(SIZE_PATTERN);
  const attachment: Attachment = {
    name: name.length === 0 ? 'Attachment' : name,
    downloadUrl: downloadUrl
  };
  const fileId: string | undefined = extractFileId(downloadUrl);
  if (fileId !== undefined) {
    attachment.id = fileId;
  }
  if (sizeMatched !== null) {
    attachment.size = sizeMatched[1].trim();
  }
  return attachment;
}

/** 附件块标记；参考实现按 `indexOf` 扫描并取其后 2000 字符。 */
const FUJIAN_MARKER: string = 'class="list fujian clearfix"';
const FUJIAN_WINDOW: number = 2000;

/** 按出现顺序切出所有附件块（每块为标记起点的定长窗口）。 */
export function splitAttachmentBlocks(html: string): string[] {
  const blocks: string[] = [];
  if (!html) {
    return blocks;
  }
  let startPos: number = 0;
  while (true) {
    const idx: number = html.indexOf(FUJIAN_MARKER, startPos);
    if (idx === -1) {
      break;
    }
    blocks.push(html.substring(idx, idx + FUJIAN_WINDOW));
    startPos = idx + FUJIAN_MARKER.length;
  }
  return blocks;
}
