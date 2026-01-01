import { useMemo } from 'react';
import Fuse, { type IFuseOptions } from 'fuse.js';
import type { Assignment, File, Notice } from 'data/types/state';

const noticeOptions: IFuseOptions<Notice> = {
  keys: [
    'courseName',
    'courseTeacherName',
    'publisher',
    'attachmentName',
    { name: 'title', weight: 2 },
    { name: 'content', weight: 2 },
  ],
};

const assignmentOptions: IFuseOptions<Assignment> = {
  keys: [
    'courseName',
    'courseTeacherName',
    'attachmentName',
    'submittedContent',
    'submittedAttachmentName',
    'graderName',
    'gradeContent',
    'gradeAttachmentName',
    'answerContent',
    'answerAttachmentName',
    { name: 'title', weight: 2 },
    { name: 'description', weight: 2 },
  ],
};

const fileOptions: IFuseOptions<File> = {
  keys: [
    'courseName',
    'courseTeacherName',
    { name: 'title', weight: 2 },
    { name: 'description', weight: 2 },
    { name: 'fileType', weight: 2 },
    { name: 'category.title', weight: 2 },
  ],
};

const filterBySummary = (summaries: any[], query: string) =>
  summaries
    .filter(
      s => s.upperTitle.includes(query) || s.upperCourseName.includes(query),
    )
    .map(s => s.item);

const merge = (manual: any[], fuseRes: any[]) => {
  const seen = new Set(manual.map(i => i.id));
  const combined = [...manual];
  fuseRes.forEach(res => {
    if (!seen.has(res.item.id)) {
      combined.push(res.item);
      seen.add(res.item.id);
    }
  });
  return combined;
};

export default function useSearch(
  notices: Notice[],
  assignments: Assignment[],
  files: File[],
  query: string,
) {
  const noticeFuse = useMemo(() => new Fuse(notices, noticeOptions), [notices]);
  const assignmentFuse = useMemo(
    () => new Fuse(assignments, assignmentOptions),
    [assignments],
  );
  const fileFuse = useMemo(() => new Fuse(files, fileOptions), [files]);

  // 由于未知原因，fuse.js 会漏掉一些明显匹配的结果，所以这里手动合并了标题或课程名完全匹配的内容
  const noticeSummaries = useMemo(
    () =>
      notices.map(item => ({
        upperTitle: item.title?.toUpperCase() || '',
        upperCourseName: item.courseName?.toUpperCase() || '',
        item,
      })),
    [notices],
  );

  const assignmentSummaries = useMemo(
    () =>
      assignments.map(item => ({
        upperTitle: item.title?.toUpperCase() || '',
        upperCourseName: item.courseName?.toUpperCase() || '',
        item,
      })),
    [assignments],
  );

  const fileSummaries = useMemo(
    () =>
      files.map(item => ({
        upperTitle: item.title?.toUpperCase() || '',
        upperCourseName: item.courseName?.toUpperCase() || '',
        item,
      })),
    [files],
  );

  const cleanQuery = query.trim().toUpperCase();
  const mN = filterBySummary(noticeSummaries, cleanQuery);
  const mA = filterBySummary(assignmentSummaries, cleanQuery);
  const mF = filterBySummary(fileSummaries, cleanQuery);

  const fN = noticeFuse.search(query);
  const fA = assignmentFuse.search(query);
  const fF = fileFuse.search(query);

  return [merge(mN, fN), merge(mA, fA), merge(mF, fF)];
}
