/*
 * 课程文件解析与排序单测（ticket 05 验收项 4）。
 *
 * 覆盖：字段映射（kjxxid / wjid / bt / ms / fileSize / scsj / wjlx / isNew）、
 * 实体解码、isNew 的三种写法、体积数字/字符串两种形态、上传时间倒序 + 标识倒序。
 *
 * 夹具成色见 fixtures/README.md：本文件夹具均为**反推**。
 */

import { describe, it, expect } from '@ohos/hypium';
import { CourseFile } from '../main/ets/domain/model/ContentItem';
import { CourseName } from '../main/ets/domain/parse/CourseName';
import {
  RawCourseFile, parseCourseFile, parseCourseFileList, sortCourseFiles, isNewFile, fileSizeText
} from '../main/ets/domain/parse/FileParser';
import { FILE_LIST_RESPONSE_JSON, RAW_COURSE_FILE } from './fixtures/ContentItemFixtures';

const COURSES: Record<string, CourseName> = {
  '2019-2020-1139283212': { name: '通信与网络', teacherName: '周世东' }
};

function rowsOf(listJson: string): RawCourseFile[] {
  const parsed: Object = JSON.parse(listJson) as Object;
  const rows: Object[] = (parsed as Record<string, Object>)['object'] as Object[];
  const typed: RawCourseFile[] = [];
  for (let i = 0; i < rows.length; i++) {
    const record: Record<string, Object> = rows[i] as Record<string, Object>;
    const raw: RawCourseFile = { kjxxid: String(record['kjxxid']), wjid: String(record['wjid']) };
    if (record['bt'] !== undefined && record['bt'] !== null) {
      raw.bt = String(record['bt']);
    }
    if (record['ms'] !== undefined && record['ms'] !== null) {
      raw.ms = String(record['ms']);
    }
    if (record['fileSize'] !== undefined && record['fileSize'] !== null) {
      raw.fileSize = String(record['fileSize']);
    }
    if (record['scsj'] !== undefined && record['scsj'] !== null) {
      raw.scsj = String(record['scsj']);
    }
    if (record['wjlx'] !== undefined && record['wjlx'] !== null) {
      raw.wjlx = String(record['wjlx']);
    }
    if (record['isNew'] !== undefined && record['isNew'] !== null) {
      raw.isNew = record['isNew'] as boolean | string | number;
    }
    typed.push(raw);
  }
  return typed;
}

export default function fileParserTest() {
  describe('domain.FileParser', () => {
    it('mapsCourseFileFieldsFromRawRecord', 0, () => {
      const file: CourseFile = parseCourseFile(RAW_COURSE_FILE, '2019-2020-1139283212', COURSES);
      expect(file.id).assertEqual('2016310500_KJ_157080064094130b5f1dcc2');
      expect(file.fileId).assertEqual('2016310500_KJ_157080064094130b5f1dcc2');
      expect(file.title).assertEqual('第1讲 绪论&导读.pdf');
      expect(file.description).assertEqual('课件');
      expect(file.size).assertEqual('1.20MB');
      expect(file.uploadTime).assertEqual('2019-10-11 15:30');
      expect(file.fileType).assertEqual('pdf');
      expect(file.isNew).assertTrue();
      expect(file.courseName).assertEqual('通信与网络');
      expect(file.courseTeacherName).assertEqual('周世东');
      expect(file.downloadUrl).assertEqual(
        'https://learn.tsinghua.edu.cn/b/wlxt/kj/wlkc_kjxxb/student/downloadFile?sfgk=0&wjid=2016310500_KJ_157080064094130b5f1dcc2');
    });

    it('acceptsAllIsNewAndSizeForms', 0, () => {
      expect(isNewFile(true)).assertTrue();
      expect(isNewFile('true')).assertTrue();
      expect(isNewFile(1)).assertTrue();
      expect(isNewFile('false')).assertFalse();
      expect(isNewFile(0)).assertFalse();
      expect(isNewFile(undefined)).assertFalse();
      expect(fileSizeText(534528)).assertEqual('534528');
      expect(fileSizeText('139.54KB')).assertEqual('139.54KB');
      expect(fileSizeText(undefined)).assertEqual('');
    });

    it('parsesFileListResponse', 0, () => {
      const rows: RawCourseFile[] = rowsOf(FILE_LIST_RESPONSE_JSON);
      expect(rows.length).assertEqual(2);
      const files: CourseFile[] = parseCourseFileList(rows, '2019-2020-1139283212', COURSES);
      expect(files.length).assertEqual(2);
      expect(files[0].title).assertEqual('第1讲 绪论.pdf');
      expect(files[0].isNew).assertTrue();
      expect(files[1].description).assertEqual('');
      expect(files[0].courseName).assertEqual('通信与网络');
    });

    it('sortsByUploadTimeDescendingWithIdTieBreak', 0, () => {
      const older: CourseFile = parseCourseFile({ kjxxid: 'a', wjid: 'a', scsj: '2019-10-10 09:12' }, 'c', COURSES);
      const newer: CourseFile = parseCourseFile({ kjxxid: 'b', wjid: 'b', scsj: '2019-10-11 15:30' }, 'c', COURSES);
      const tieB: CourseFile = parseCourseFile({ kjxxid: 'bb', wjid: 'bb', scsj: '2019-10-11 15:30' }, 'c', COURSES);
      const tieA: CourseFile = parseCourseFile({ kjxxid: 'aa', wjid: 'aa', scsj: '2019-10-11 15:30' }, 'c', COURSES);
      const sorted: CourseFile[] = sortCourseFiles([older, newer, tieA, tieB]);
      expect(sorted[0].id).assertEqual('bb');
      expect(sorted[1].id).assertEqual('aa');
      expect(sorted[2].id).assertEqual('b');
      expect(sorted[3].id).assertEqual('a');
      expect(parseCourseFile({ kjxxid: 'z', wjid: 'z' }, 'c', COURSES).courseName).assertEqual('Unknown Course');
    });
  });
}
