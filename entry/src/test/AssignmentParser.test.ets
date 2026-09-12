/*
 * 作业解析与排序单测（ticket 05 验收项 2、4）。
 *
 * 覆盖：
 *   - 列表字段映射（xszyid / zyid / wlkcid / bt / jzsj / bjjzsj / sfbj / zywcfs / zytjfs / scsj / cj / jsm / pynr）；
 *   - **四类附件**（附件 / 答案 / 已提交 / 成绩）的块序映射，含"只有第一块有附件"的情况；
 *   - 附件名三级回退（`<a>` 内文本 → title 属性 → span.ftitle）；
 *   - 参考实现的最终次序（未截止在前、由近及远；已截止在后）；
 *   - 详情补全不覆盖已有值。
 *
 * 夹具成色见 fixtures/README.md：本文件夹具均为**反推**。
 */

import { describe, it, expect } from '@ohos/hypium';
import { Assignment, Attachment } from '../main/ets/domain/model/ContentItem';
import { CourseName } from '../main/ets/domain/parse/CourseName';
import {
  AssignmentDetail, RawAssignment,
  assignmentKey, assignmentDetailUrl, assignmentSubmitUrl,
  parseAssignment, parseAssignmentList, parseAssignmentDetail, mergeAssignmentDetail,
  compareAssignmentsByUpcoming, sortAssignments
} from '../main/ets/domain/parse/AssignmentParser';
import { decodeHtmlEntities, parseTimestamp } from '../main/ets/domain/parse/Text';
import {
  ASSIGNMENT_DETAIL_FOUR_BLOCKS_HTML, ASSIGNMENT_DETAIL_ONE_BLOCK_HTML,
  ASSIGNMENT_LIST_RESPONSE_JSON, ASSIGNMENT_DESCRIPTION_RESPONSE_JSON, RAW_ASSIGNMENT
} from './fixtures/ContentItemFixtures';

const COURSES: Record<string, CourseName> = {
  '2019-2020-1139283212': { name: '通信与网络', teacherName: '周世东' }
};

function rowsOf(listJson: string): RawAssignment[] {
  const parsed: Object = JSON.parse(listJson) as Object;
  const box: Record<string, Object> = (parsed as Record<string, Object>)['object'] as Record<string, Object>;
  const rows: Object[] = box['aaData'] as Object[];
  const typed: RawAssignment[] = [];
  for (let i = 0; i < rows.length; i++) {
    const record: Record<string, Object> = rows[i] as Record<string, Object>;
    const raw: RawAssignment = { zyid: String(record['zyid']) };
    if (record['xszyid'] !== undefined && record['xszyid'] !== null) {
      raw.xszyid = String(record['xszyid']);
    }
    if (record['wlkcid'] !== undefined && record['wlkcid'] !== null) {
      raw.wlkcid = String(record['wlkcid']);
    }
    if (record['bt'] !== undefined && record['bt'] !== null) {
      raw.bt = String(record['bt']);
    }
    if (record['jzsj'] !== undefined && record['jzsj'] !== null) {
      raw.jzsj = String(record['jzsj']);
    }
    if (record['bjjzsj'] !== undefined && record['bjjzsj'] !== null) {
      raw.bjjzsj = String(record['bjjzsj']);
    }
    if (record['sfbj'] !== undefined && record['sfbj'] !== null) {
      raw.sfbj = String(record['sfbj']);
    }
    if (record['zywcfs'] !== undefined && record['zywcfs'] !== null) {
      raw.zywcfs = String(record['zywcfs']);
    }
    if (record['zytjfs'] !== undefined && record['zytjfs'] !== null) {
      raw.zytjfs = String(record['zytjfs']);
    }
    if (record['scsj'] !== undefined && record['scsj'] !== null) {
      raw.scsj = String(record['scsj']);
    }
    if (record['cj'] !== undefined && record['cj'] !== null) {
      raw.cj = Number(record['cj']);
    }
    if (record['jsm'] !== undefined && record['jsm'] !== null) {
      raw.jsm = String(record['jsm']);
    }
    if (record['pynr'] !== undefined && record['pynr'] !== null) {
      raw.pynr = String(record['pynr']);
    }
    typed.push(raw);
  }
  return typed;
}

function baseAssignment(id: string, deadline: string): Assignment {
  return parseAssignment({ zyid: id, xszyid: id, bt: 't', jzsj: deadline },
    '2019-2020-1139283212', COURSES, false, false);
}

export default function assignmentParserTest() {
  describe('domain.AssignmentParser', () => {
    /*
     * 真实数据回归（2026-09-12 模拟器 Pura 90，2025-2026 春季学期）：
     * 站点把 jzsj 下发成 epoch 毫秒的**数字**（57/57 条），于是
     *   - parseTimestamp 的 raw.trim() 抛 "undefined is not callable"，整条链路失败；
     *   - 修好之后 deadline 仍是数字，作业行渲染不出截止时间。
     * 这里钉住"数字 ⇒ 本地时间 'YYYY-MM-DD HH:mm'（与 Assignment.deadline 的既定形状一致）"。
     */
    it('normalizes a numeric site deadline into the documented string shape', 0, () => {
      // 站点在 2025-2026 春季学期把 jzsj 下发成 epoch 毫秒的**数字**（57/57 条，实测）。
      // 类型上 RawAssignment.jzsj 是 string，所以这里直接从 JSON 造一行，保留运行时数字。
      const raw: RawAssignment =
        JSON.parse('{"xszyid":"x1","zyid":"z1","jzsj":1780243140000}') as RawAssignment;
      const assignment: Assignment = parseAssignment(raw, 'c1', {}, false, false);
      const expected: Date = new Date(1780243140000);
      const pad: (n: number) => string = (n: number): string => (n < 10 ? '0' + n.toString() : n.toString());
      const expectedText: string = expected.getFullYear().toString() + '-'
        + pad(expected.getMonth() + 1) + '-' + pad(expected.getDate()) + ' '
        + pad(expected.getHours()) + ':' + pad(expected.getMinutes());
      expect(assignment.deadline).assertEqual(expectedText);
      // 规范化后的串能被 parseTimestamp 读回同一个瞬时（秒以下被截掉）。
      const truncated: number = expected.getTime() - expected.getSeconds() * 1000 - expected.getMilliseconds();
      expect(parseTimestamp(assignment.deadline)).assertEqual(truncated);
      // 字符串截止时间一律原样保留（ticket 05 的既有行为不受影响）。
      const stringRaw: RawAssignment =
        JSON.parse('{"zyid":"z2","jzsj":"2020-09-01 23:59"}') as RawAssignment;
      expect(parseAssignment(stringRaw, 'c1', {}, false, false).deadline).assertEqual('2020-09-01 23:59');
    });

    it('mapsAssignmentFieldsFromRawRecord', 0, () => {
      const assignment: Assignment = parseAssignment(RAW_ASSIGNMENT, '2019-2020-1139283212', COURSES, false, false);
      expect(assignment.id).assertEqual('26ef84e8937624450193ba443c9414bd');
      expect(assignment.studentHomeworkId).assertEqual('26ef84e8937624450193ba443c9414bd');
      expect(assignment.baseId).assertEqual('26ef84e8937624450193ba443c9414aa');
      expect(assignment.title).assertEqual('大作业&1');
      expect(assignment.deadline).assertEqual('2020-09-01 23:59');
      expect(assignment.lateSubmissionDeadline).assertEqual('2020-09-08 23:59');
      expect(assignment.isLateSubmission).assertTrue();
      expect(assignment.completionType).assertEqual('个人');
      expect(assignment.submissionType).assertEqual('网络学堂');
      expect(assignment.submitTime).assertEqual('2020-08-30 10:00');
      expect(assignment.grade).assertEqual(88);
      expect(assignment.graderName).assertEqual('周世东');
      expect(assignment.gradeContent).assertEqual('思路清晰');
      expect(assignment.courseName).assertEqual('通信与网络');
      expect(assignment.courseTeacherName).assertEqual('周世东');
      expect(assignment.description).assertEqual('');
      expect(assignment.submitted).assertFalse();
      expect(assignment.graded).assertFalse();
    });

    it('buildsDetailAndSubmitUrlsLikeTheReference', 0, () => {
      expect(assignmentKey(RAW_ASSIGNMENT)).assertEqual('26ef84e8937624450193ba443c9414bd');
      expect(assignmentDetailUrl('2019-2020-1139283212', RAW_ASSIGNMENT)).assertEqual(
        'https://learn.tsinghua.edu.cn/f/wlxt/kczy/zy/student/viewCj?wlkcid=2019-2020-1139283212&xszyid=26ef84e8937624450193ba443c9414bd');
      const withoutStudentId: RawAssignment = { zyid: 'zy-1', bt: 't' };
      expect(assignmentKey(withoutStudentId)).assertEqual('zy-1');
      expect(assignmentDetailUrl('c1', withoutStudentId)).assertEqual(
        'https://learn.tsinghua.edu.cn/f/wlxt/kczy/zy/student/viewZy?wlkcid=c1&zyid=zy-1');
      expect(assignmentSubmitUrl('c1', 'x1')).assertEqual(
        'https://learn.tsinghua.edu.cn/f/wlxt/kczy/zy/student/tijiao?wlkcid=c1&xszyid=x1');
    });

    it('parsesFourAttachmentKindsInBlockOrder', 0, () => {
      const detail: AssignmentDetail = parseAssignmentDetail(ASSIGNMENT_DETAIL_FOUR_BLOCKS_HTML);
      expect(detail.attachment !== undefined).assertTrue();
      expect(detail.answerAttachment !== undefined).assertTrue();
      expect(detail.submittedAttachment !== undefined).assertTrue();
      expect(detail.gradeAttachment !== undefined).assertTrue();
      expect(detail.attachment?.name).assertEqual('作业要求.pdf');
      expect(detail.attachment?.id).assertEqual('1298990181_ZY_4a1b');
      // 参考实现不解码 HTML 实体（docs/reference-quirks.md 第 4 条）：
      // href 里的 '&amp;' 原样留在 downloadUrl 里；id 仍能取到（字符类在 '&' 处停下）
      expect(detail.attachment?.downloadUrl).assertEqual(
        'https://learn.tsinghua.edu.cn/b/wlxt/kczy/zy/student/downloadFile?fileId=1298990181_ZY_4a1b&amp;wjid=1298990181_ZY_4a1b');
      expect(detail.answerAttachment?.name).assertEqual('参考答案.pdf');
      expect(detail.answerAttachment?.id).assertEqual('1298990182_ZY_5b2c');
      expect(detail.submittedAttachment?.name).assertEqual('我的提交.pdf');
      expect(detail.submittedAttachment?.id).assertEqual('1298990183_ZY_6c3d');
      expect(detail.gradeAttachment?.name).assertEqual('批改结果.pdf');
      expect(detail.gradeAttachment?.downloadUrl).assertEqual(
        'https://learn.tsinghua.edu.cn/b/wlxt/kczy/zy/student/downloadFile?fileId=1298990184_ZY_7d4e');
    });

    it('leavesMissingAttachmentKindsUndefined', 0, () => {
      const detail: AssignmentDetail = parseAssignmentDetail(ASSIGNMENT_DETAIL_ONE_BLOCK_HTML);
      expect(detail.attachment !== undefined).assertTrue();
      expect(detail.attachment?.name).assertEqual('附件1.pdf');
      expect(detail.attachment?.id).assertEqual('1234990181_ZY_9a9a');
      expect(detail.answerAttachment === undefined).assertTrue();
      expect(detail.submittedAttachment === undefined).assertTrue();
      expect(detail.gradeAttachment === undefined).assertTrue();
      expect(Object.keys(parseAssignmentDetail('')).length).assertEqual(0);
      expect(parseAssignmentDetail('<div>no fujian here</div>').attachment === undefined).assertTrue();
    });

    it('fallsBackToTitleAttributeForAttachmentName', 0, () => {
      const html: string = '<div class="list fujian clearfix"><div class="fl">'
        + '<a href="/b/wlxt/kczy/zy/student/downloadFile?fileId=abc" title="评分细则.pdf"></a>'
        + '</div></div>';
      const detail: AssignmentDetail = parseAssignmentDetail(html);
      expect(detail.attachment?.name).assertEqual('评分细则.pdf');
      expect(detail.attachment?.id).assertEqual('abc');
    });

    it('parsesListResponse', 0, () => {
      const rows: RawAssignment[] = rowsOf(ASSIGNMENT_LIST_RESPONSE_JSON);
      expect(rows.length).assertEqual(2);
      const parsed: Assignment[] = parseAssignmentList(rows, '2019-2020-1139283212', COURSES, false, false);
      expect(parsed.length).assertEqual(2);
      expect(parsed[0].title).assertEqual('大作业1');
      expect(parsed[0].grade).assertEqual(88);
      expect(parsed[0].courseName).assertEqual('通信与网络');
      expect(parsed[1].lateSubmissionDeadline === undefined).assertTrue();
      expect(parsed[1].submitTime === undefined).assertTrue();
      expect(parsed[1].grade === undefined).assertTrue();
      expect(parsed[1].graderName === undefined).assertTrue();
      expect(parsed[1].isLateSubmission).assertFalse();
      expect(ASSIGNMENT_DESCRIPTION_RESPONSE_JSON.length > 0).assertTrue();
      expect(decodeHtmlEntities('<p>要求见课件&amp;讲义</p>')).assertEqual('<p>要求见课件&讲义</p>');
    });

    it('sortsByDeadlineDescending', 0, () => {
      const a: Assignment = baseAssignment('aa', '2020-09-25 07:21');
      const b: Assignment = baseAssignment('bb', '2020-09-25 07:21');
      const c: Assignment = baseAssignment('cc', '2020-09-24 07:21');
      const sorted: Assignment[] = sortAssignments([a, b, c]);
      expect(sorted[0].id).assertEqual('bb');
      expect(sorted[1].id).assertEqual('aa');
      expect(sorted[2].id).assertEqual('cc');
    });

    it('ordersUpcomingFirstLikeTheReferenceFinalSort', 0, () => {
      const now: number = new Date(2020, 8, 15, 12, 0, 0).getTime();
      const items: Assignment[] = [
        baseAssignment('p1', '2020-09-01 00:00'),
        baseAssignment('u1', '2020-09-20 00:00'),
        baseAssignment('u2', '2020-09-16 00:00'),
        baseAssignment('p2', '2020-09-10 00:00')
      ];
      const ordered: Assignment[] = compareAssignmentsByUpcoming(items, now);
      expect(ordered.length).assertEqual(4);
      expect(ordered[0].id).assertEqual('u2');
      expect(ordered[1].id).assertEqual('u1');
      expect(ordered[2].id).assertEqual('p1');
      expect(ordered[3].id).assertEqual('p2');
    });

    it('mergesDetailWithoutLosingExistingValues', 0, () => {
      const base: Assignment = baseAssignment('aa', '2020-09-01 00:00');
      base.description = '<p>已有描述</p>';
      const keep: Assignment = mergeAssignmentDetail(base, { description: '' });
      expect(keep.description).assertEqual('<p>已有描述</p>');
      const fill: Assignment = mergeAssignmentDetail(baseAssignment('bb', '2020-09-01 00:00'), {
        description: '<p>新描述</p>',
        attachment: { name: 'a.pdf', downloadUrl: 'https://x/a.pdf' },
        gradeAttachment: { name: 'g.pdf', downloadUrl: 'https://x/g.pdf' } as Attachment
      });
      expect(fill.description).assertEqual('<p>新描述</p>');
      expect(fill.attachment?.name).assertEqual('a.pdf');
      expect(fill.gradeAttachment?.name).assertEqual('g.pdf');
      expect(fill.answerAttachment === undefined).assertTrue();
      expect(fill.submittedAttachment === undefined).assertTrue();
    });
  });
}