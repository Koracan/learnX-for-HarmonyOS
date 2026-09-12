/*
 * 优秀作业（ticket 10 补做）单测：`yxzylist` 列表 → 解析 → 按 `zyid` 挂到作业 → 渲染取值。
 *
 * 夹具形状来自**真实响应**：探针把 2025-2026 春季两门课的原始响应落到了
 * `.scratch/assignments/evidence/P1-excellent-probe-spring.txt`（18 + 6 条），
 * 这里的 `PROBE_ROWS` 逐字段照抄其中几条（含"同一 zyid 两条"与"全部匿名"这两个真实特征）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { Assignment, Attachment, ExcellentHomework } from '../main/ets/domain/model/ContentItem';
import {
  RawExcellent, attachExcellentHomework, excellentAuthorId, excellentAuthorName,
  excellentDisplayAttachment, excellentHomeworkPageUrl, parseExcellentHomework
} from '../main/ets/domain/parse/AssignmentParser';
import { extractExcellentRows } from '../main/ets/data/remote/AssignmentsFetcher';
import { hasExcellentHomework } from '../main/ets/features/assignments/AssignmentFilter';

/** 与探针实收原文同形的两段列表响应（春季 `…719` 课取前三条；`…1080` 课取前两条）。 */
const PROBE_PAYLOAD: string = '{"result":"success","msg":null,"object":{"iTotalRecords":"3",'
  + '"aaData":['
  + '{"wlkcid":"2025-2026-2151370719","bt":"作业&amp;（12）","xszyid":"26ef84e89df9fa33019e6ccfc4a165e9",'
  + '"zyid":"26ef84e89df9fa33019e6ccfc47265e6","zywcfs":"1","cy":"","sfzm":"是",'
  + '"zyfjid":"285f816ab5b7e500b4d7959efe3b2167_ZY_1780474648991906163739d","id":null},'
  + '{"wlkcid":"2025-2026-2151370719","bt":"作业（11）","xszyid":"26ef84e89df9fa33019e48ba33b038e6",'
  + '"zyid":"26ef84e89df9fa33019e48ba337c38e4","zywcfs":"1","cy":"","sfzm":"是",'
  + '"zyfjid":"9b394cad4cb0634bbdfd4aceef367289_ZY_177998336829602302859c3","id":null},'
  + '{"wlkcid":"2025-2026-2151370719","bt":"作业（8）","xszyid":"26ef84e89d905f53019d94770c5b0101",'
  + '"zyid":"26ef84e89d905f53019d94770c2d00ec","zywcfs":"1","cy":"","sfzm":"是",'
  + '"zyfjid":"240c00030ce8cb73d32c86ffbee7326e_ZY_17769433426780162195aa2","id":null}'
  + ']}}';

/** 空响应（实测 172 字节：`aaData` 为空数组，`result` 仍是 success）。 */
const EMPTY_PAYLOAD: string = '{"result":"success","msg":null,"object":{"iTotalRecords":"0",'
  + '"iTotalDisplayRecords":"0","iDisplayStart":null,"iDisplayLength":null,"sEcho":null,'
  + '"sSearch":null,"aaData":[]}}';

function excellentRow(zyid: string, authorId: string, authorName: string, anonymous: boolean): ExcellentHomework {
  return {
    id: 'exc-' + zyid + '-' + authorId, baseId: zyid, title: 't',
    authorId: authorId, authorName: authorName, anonymous: anonymous
  };
}

function assignmentOf(id: string, baseId: string): Assignment {
  return {
    id: id, baseId: baseId, title: 't', url: '', deadline: '2026-05-31 23:59',
    isLateSubmission: false, completionType: '1', submissionType: '2', submitUrl: '',
    courseId: 'c1', courseName: '课程', courseTeacherName: '教师',
    description: '', submittedContent: '', answerContent: '', gradeContent: '',
    submitted: true, graded: true
  };
}

function attachment(name: string, id: string): Attachment {
  return { name: name, id: id, downloadUrl: 'https://x/' + id };
}

export default function excellentHomeworkTest() {
  describe('features.assignments.excellent', () => {
    it('extractsRowsFromTheProbeShapedPayload', 0, () => {
      const rows: RawExcellent[] = extractExcellentRows(PROBE_PAYLOAD);
      expect(rows.length).assertEqual(3);
      expect(rows[0].xszyid).assertEqual('26ef84e89df9fa33019e6ccfc4a165e9');
      expect(rows[0].zyid).assertEqual('26ef84e89df9fa33019e6ccfc47265e6');
      expect(rows[0].sfzm).assertEqual('是');
      // 空响应 / 坏输入 / 非 success 一律 0 条
      expect(extractExcellentRows(EMPTY_PAYLOAD).length).assertEqual(0);
      expect(extractExcellentRows('').length).assertEqual(0);
      expect(extractExcellentRows('}{').length).assertEqual(0);
      expect(extractExcellentRows('{"result":"fail","msg":"not login"}').length).assertEqual(0);
      expect(extractExcellentRows('{"result":"success"}').length).assertEqual(0);
    });

    it('mapsFieldsLikeThuLearnLib', 0, () => {
      const rows: RawExcellent[] = extractExcellentRows(PROBE_PAYLOAD);
      const entry: ExcellentHomework = parseExcellentHomework(rows[0]);
      expect(entry.id).assertEqual('26ef84e89df9fa33019e6ccfc4a165e9');
      expect(entry.baseId).assertEqual('26ef84e89df9fa33019e6ccfc47265e6');
      // bt 走实体解码（与作业标题同一口径）
      expect(entry.title).assertEqual('作业&（12）');
      expect(entry.anonymous).assertTrue();
      expect(entry.authorId).assertEqual('');
      expect(entry.authorName).assertEqual('');
      expect(entry.attachmentId).assertEqual('285f816ab5b7e500b4d7959efe3b2167_ZY_1780474648991906163739d');
      // 具名作者（cy 形如 "<学号> <姓名>"）；sfzm 非 '是' ⇒ 不匿名
      const named: RawExcellent = {
        zyid: 'z1', xszyid: 'x1', bt: 'b', cy: '2021000000 张三', sfzm: '否'
      };
      const namedEntry: ExcellentHomework = parseExcellentHomework(named);
      expect(namedEntry.anonymous).assertFalse();
      expect(namedEntry.authorId).assertEqual('2021000000');
      expect(namedEntry.authorName).assertEqual('张三');
      expect(namedEntry.attachmentId === undefined).assertTrue();
    });

    it('authorSplitHandlesEmptyAndSingleToken', 0, () => {
      expect(excellentAuthorId('')).assertEqual('');
      expect(excellentAuthorName('')).assertEqual('');
      expect(excellentAuthorId('2021000000')).assertEqual('2021000000');
      expect(excellentAuthorName('2021000000')).assertEqual('');
      expect(excellentAuthorId('A B C')).assertEqual('A');
      expect(excellentAuthorName('A B C')).assertEqual('B');
    });

    it('displayAttachmentPrefersGradeThenSubmitted', 0, () => {
      const both: ExcellentHomework = excellentRow('z1', 'a', 'n', false);
      both.gradeAttachment = attachment('grade.pdf', 'g');
      both.submittedAttachment = attachment('submitted.pdf', 's');
      expect(excellentDisplayAttachment(both)?.name).assertEqual('grade.pdf');
      const onlySubmitted: ExcellentHomework = excellentRow('z2', 'a', 'n', false);
      onlySubmitted.submittedAttachment = attachment('submitted.pdf', 's');
      expect(excellentDisplayAttachment(onlySubmitted)?.name).assertEqual('submitted.pdf');
      const none: ExcellentHomework = excellentRow('z3', 'a', 'n', false);
      expect(excellentDisplayAttachment(none) === undefined).assertTrue();
    });

    it('attachesByBaseIdAndLeavesOthersUndefined', 0, () => {
      const assignments: Assignment[] = [
        assignmentOf('a1', 'base-a'),
        assignmentOf('b1', 'base-b')
      ];
      const entries: ExcellentHomework[] = [
        excellentRow('base-a', '2021000001', '甲', false),
        excellentRow('base-a', '2021000002', '乙', false),
        excellentRow('base-c', '2021000003', '丙', false)
      ];
      attachExcellentHomework(assignments, entries);
      const attached: ExcellentHomework[] | undefined = assignments[0].excellentHomeworkList;
      expect(attached === undefined ? 0 : attached.length).assertEqual(2);
      expect(attached === undefined ? '' : attached[0].authorName).assertEqual('甲');
      // 名单里没有的作业保持 undefined（不是空数组）——界面据此不显示 medal
      expect(assignments[1].excellentHomeworkList === undefined).assertTrue();
      expect(hasExcellentHomework(assignments[0])).assertTrue();
      expect(hasExcellentHomework(assignments[1])).assertFalse();
      // 空列表是 no-op
      const untouched: Assignment[] = [assignmentOf('c1', 'base-c')];
      attachExcellentHomework(untouched, []);
      expect(untouched[0].excellentHomeworkList === undefined).assertTrue();
    });

    it('sameAssignmentCanCarrySeveralEntriesLikeTheRealData', 0, () => {
      // 真实数据：18 条落在 12 个 zyid 上，其中 6 个 zyid 各 2 条
      const assignments: Assignment[] = [assignmentOf('x', '26ef84e89d905f53019d94770c2d00ec')];
      const entries: ExcellentHomework[] = [
        parseExcellentHomework({ zyid: '26ef84e89d905f53019d94770c2d00ec', xszyid: 's1', sfzm: '是', cy: '' }),
        parseExcellentHomework({ zyid: '26ef84e89d905f53019d94770c2d00ec', xszyid: 's2', sfzm: '是', cy: '' })
      ];
      attachExcellentHomework(assignments, entries);
      const list: ExcellentHomework[] | undefined = assignments[0].excellentHomeworkList;
      expect(list?.length).assertEqual(2);
      let anonymous: number = 0;
      for (let i = 0; i < (list === undefined ? 0 : list.length); i++) {
        if (list !== undefined && list[i].anonymous) {
          anonymous++;
        }
      }
      expect(anonymous).assertEqual(2);
    });

    it('pageUrlMatchesTheReferenceShape', 0, () => {
      expect(excellentHomeworkPageUrl('2025-2026-2151370719', '26ef84e89df9fa33019e6ccfc4a165e9'))
        .assertEqual('https://learn.tsinghua.edu.cn/f/wlxt/kczy/zy/student/viewYxzy'
          + '?wlkcid=2025-2026-2151370719&xszyid=26ef84e89df9fa33019e6ccfc4a165e9');
    });
  });
}
