/*
 * 课程文件响应解析——**纯函数，零平台依赖**（见 scripts/check-domain-purity.mjs）。
 *
 * 移植自参考实现 DataProcessorModule.ts 的 `fetchFiles` 与 `processFiles`：
 * 字段映射 kjxxid / wjid / bt / ms / fileSize / scsj / wjlx / isNew；
 * 排序 uploadTime 倒序 + 标识倒序（参考实现 actions/files.ts）。
 */

import { CourseFile } from '../model/ContentItem';
import { decodeHtmlEntities, compareByTimeThenIdDesc } from './Text';
import { courseFileDownloadUrl } from './Attachment';
import { CourseName, UNKNOWN_COURSE_NAME } from './CourseName';

/** 列表接口 `object` 数组里的一条文件原始记录。 */
export interface RawCourseFile {
  kjxxid: string;
  wjid: string;
  bt?: string;
  ms?: string;
  fileSize?: string | number;
  scsj?: string;
  wjlx?: string;
  isNew?: boolean | string | number;
}

function text(value: string | undefined): string {
  return value === undefined || value === null ? '' : value;
}

/** 站点对"新文件"的三种写法（照参考实现）。 */
export function isNewFile(raw: boolean | string | number | undefined): boolean {
  return raw === true || raw === 'true' || raw === 1;
}

/** 体积统一成字符串：站点可能给数字，也可能给 `'139.54KB'`。 */
export function fileSizeText(raw: string | number | undefined): string {
  if (raw === undefined || raw === null) {
    return '';
  }
  return typeof raw === 'number' ? raw.toString() : raw;
}

/** 一条文件记录 → 课程文件。 */
export function parseCourseFile(
  raw: RawCourseFile,
  courseId: string,
  courseNames: Record<string, CourseName>
): CourseFile {
  const known: CourseName | undefined = courseNames[courseId];
  const fileId: string = text(raw.wjid);
  return {
    id: text(raw.kjxxid),
    fileId: fileId,
    title: decodeHtmlEntities(text(raw.bt)),
    description: decodeHtmlEntities(text(raw.ms)),
    size: fileSizeText(raw.fileSize),
    uploadTime: text(raw.scsj),
    fileType: text(raw.wjlx),
    courseId: courseId,
    courseName: known !== undefined ? known.name : UNKNOWN_COURSE_NAME,
    courseTeacherName: known !== undefined ? known.teacherName : '',
    isNew: isNewFile(raw.isNew),
    downloadUrl: courseFileDownloadUrl(fileId)
  };
}

/** 文件排序：上传时间倒序，同时间按标识倒序。 */
export function sortCourseFiles(files: CourseFile[]): CourseFile[] {
  const sorted: CourseFile[] = files.slice();
  sorted.sort((left: CourseFile, right: CourseFile): number =>
    compareByTimeThenIdDesc(left.uploadTime, left.id, right.uploadTime, right.id));
  return sorted;
}

/** 列表响应 → 已排序课程文件。 */
export function parseCourseFileList(
  rawRecords: RawCourseFile[],
  courseId: string,
  courseNames: Record<string, CourseName>
): CourseFile[] {
  const parsed: CourseFile[] = [];
  for (let i = 0; i < rawRecords.length; i++) {
    parsed.push(parseCourseFile(rawRecords[i], courseId, courseNames));
  }
  return sortCourseFiles(parsed);
}
