/*
 * Mock 提交线单测（host 侧 hypium）——把「mock 登录时作业无法提交」这条缺陷钉死。
 *
 * 缺陷原文：notice / course / file 三条线都在 provider 里对 `isMockMode()` 分支，
 * **提交这条线没有**——`createAssignmentSubmitter()` 永远装配真实 HTTP 路径，
 * mock 账号没有会话 ⇒ 提交必然降级成"需要重新验证" ⇒ 界面弹「提交失败」。
 *
 * 本套用例证明修复后的可观察量（全部不需要平台调用，可重复）：
 *   (a) 一次正常提交返回 `ok=true`、状态码 200，且 `onProgress` 被真的调用过；
 *   (b) 提交后 `mockAssignments()` 里那条作业 `submitted===true`、正文进了
 *       `submittedContent`（`<p>…</p>` 形状）、`submitTime` 能被
 *       `domain/parse/Text.parseTimestamp` 解开；
 *   (c) 「移除附件」那一支之后 `submittedAttachment` 被清掉（作业仍是已提交态）；
 *   (d) `plan === undefined` 既不写台账、也不发进度，返回 `noop`（status=0）；
 *   (e) 上面全过程 `networkAttemptCount()` **不变**（mock 零网络）；
 *   (f) `clearMockSubmissions()` 之后样例数据回到初始态（用例之间互不污染）。
 *
 * 隔离方式：每条用例开头都 `clearMockSubmissions()`（内存台账是模块级单例，
 * hypium 的各 `it` 共享同一个模块实例）。**不调用 `resetNetworkAudit()`**：
 * 它是别人的用例也在读的全局量，这里只做"前后相等"的比较，不去动它。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  AssignmentSubmitter, SubmitOutcome
} from '../main/ets/data/assignments/SubmitAssignment';
import { MockAssignmentSubmitter } from '../main/ets/data/mock/MockAssignmentSubmitter';
import {
  MockSubmissionEntry, clearMockSubmissions, submissionFor
} from '../main/ets/data/mock/MockSubmissionJournal';
import { mockAssignments } from '../main/ets/data/mock/MockData';
import { Assignment, Attachment } from '../main/ets/domain/model/ContentItem';
import { SubmissionPlan } from '../main/ets/domain/assignments/SubmissionState';
import { UploadProgress } from '../main/ets/data/remote/Port';
import { Logger } from '../main/ets/core/log/Logger';
import { networkAttemptCount } from '../main/ets/data/remote/NetworkAudit';
import { parseTimestamp } from '../main/ets/domain/parse/Text';

/** 样例里那条**未提交**的作业（提交线的目标）。 */
const XSZYID: string = 'mock-xszy-1';

function newSubmitter(): AssignmentSubmitter {
  return new MockAssignmentSubmitter(new Logger('test.mock.submit'));
}

/** 从样例列表里取一条作业（走的是界面同一条路：`mockAssignments()`）。 */
function assignmentFor(xszyid: string): Assignment | undefined {
  const items: Assignment[] = mockAssignments();
  for (let i = 0; i < items.length; i++) {
    if (items[i].studentHomeworkId === xszyid) {
      return items[i];
    }
  }
  return undefined;
}

function contentPlan(content: string): SubmissionPlan {
  return { studentHomeworkId: XSZYID, content: content, removeAttachment: false };
}

function attachmentPlan(name: string, size: number): SubmissionPlan {
  return {
    studentHomeworkId: XSZYID,
    content: '带附件的正文',
    removeAttachment: false,
    attachment: {
      uri: 'file://docs/storage/a/' + name,
      name: name,
      mimeType: 'application/pdf',
      size: size
    }
  };
}

function removePlan(): SubmissionPlan {
  return { studentHomeworkId: XSZYID, content: '', removeAttachment: true };
}

export default function mockSubmissionTest() {
  describe('data.MockSubmission', () => {
    it('submitsLocallyAndDrivesTheProgressBar', 0, async () => {
      clearMockSubmissions();
      const submitter: AssignmentSubmitter = newSubmitter();
      const seen: UploadProgress[] = [];
      const outcome: SubmitOutcome = await submitter.submit(contentPlan('第一次作业正文'), 'req-mock-a',
        (progress: UploadProgress): void => {
          seen.push(progress);
        });
      expect(outcome.ok).assertTrue();
      expect(outcome.status).assertEqual(200);
      expect(outcome.requiresEnrollment).assertFalse();
      // 进度回调被真的调用过，而且最后一步走到 100%（否则进度条不会走完）。
      expect(seen.length >= 2).assertTrue();
      const last: UploadProgress = seen[seen.length - 1];
      expect(last.requestId).assertEqual('req-mock-a');
      expect(last.total > 0).assertTrue();
      expect(last.sent).assertEqual(last.total);
    });

    it('showsTheJournaledSubmissionInMockAssignments', 0, async () => {
      clearMockSubmissions();
      const content: string = '台账里的正文';
      await newSubmitter().submit(contentPlan(content), 'req-mock-b');
      const entry: MockSubmissionEntry | undefined = submissionFor(XSZYID);
      expect(entry !== undefined).assertTrue();
      const item: Assignment | undefined = assignmentFor(XSZYID);
      expect(item !== undefined).assertTrue();
      if (item !== undefined) {
        expect(item.submitted).assertTrue();
        expect(item.submittedContent.includes(content)).assertTrue();
        // 与样例里其它已提交条目同一形状（站点给的就是 HTML 段落）。
        expect(item.submittedContent.startsWith('<p>')).assertTrue();
        expect(item.submittedContent.endsWith('</p>')).assertTrue();
        // submitTime 必须是 domain 层认的时间串（YYYY-MM-DD HH:mm）。
        const parsed: number = parseTimestamp(item.submitTime);
        expect(Number.isNaN(parsed)).assertFalse();
        expect(parsed > 0).assertTrue();
      }
    });

    it('clearsTheSubmittedAttachmentOnTheRemoveBranch', 0, async () => {
      clearMockSubmissions();
      const submitter: AssignmentSubmitter = newSubmitter();
      await submitter.submit(attachmentPlan('实验报告.pdf', 2048), 'req-mock-c1');
      const withFile: Assignment | undefined = assignmentFor(XSZYID);
      expect(withFile !== undefined).assertTrue();
      let attached: Attachment | undefined = undefined;
      if (withFile !== undefined) {
        attached = withFile.submittedAttachment;
      }
      expect(attached !== undefined).assertTrue();
      if (attached !== undefined) {
        expect(attached.name).assertEqual('实验报告.pdf');
        expect(attached.size).assertEqual('2.00KB');
      }
      await submitter.submit(removePlan(), 'req-mock-c2');
      const removed: Assignment | undefined = assignmentFor(XSZYID);
      expect(removed !== undefined).assertTrue();
      if (removed !== undefined) {
        expect(removed.submittedAttachment === undefined).assertTrue();
        // 「移除附件」仍是一次提交（作业仍是已提交态），只是没有附件。
        expect(removed.submitted).assertTrue();
      }
    });

    it('treatsAnUndefinedPlanAsANoopWithoutJournaling', 0, async () => {
      clearMockSubmissions();
      const seen: UploadProgress[] = [];
      const outcome: SubmitOutcome = await newSubmitter().submit(undefined, 'req-mock-d',
        (progress: UploadProgress): void => {
          seen.push(progress);
        });
      // noop 的形状：ok 但 status=0（与 success(200) 区分开）。
      expect(outcome.ok).assertTrue();
      expect(outcome.status).assertEqual(0);
      expect(outcome.requiresEnrollment).assertFalse();
      expect(seen.length).assertEqual(0);
      expect(submissionFor(XSZYID) === undefined).assertTrue();
      const item: Assignment | undefined = assignmentFor(XSZYID);
      if (item !== undefined) {
        expect(item.submitted).assertFalse();
        expect(item.submitTime === undefined).assertTrue();
      }
    });

    it('neverTouchesTheNetworkAcrossTheWholeFlow', 0, async () => {
      clearMockSubmissions();
      // 只比"前后相等"，不 resetNetworkAudit()：那是别的用例也读的全局量。
      const before: number = networkAttemptCount();
      const submitter: AssignmentSubmitter = newSubmitter();
      await submitter.submit(contentPlan('零网络正文'), 'req-mock-e1');
      await submitter.submit(attachmentPlan('a.pdf', 10), 'req-mock-e2');
      await submitter.submit(removePlan(), 'req-mock-e3');
      await submitter.submit(undefined, 'req-mock-e4');
      mockAssignments();
      const after: number = networkAttemptCount();
      expect(after).assertEqual(before);
    });

    it('restoresTheSampleStateAfterClearingTheJournal', 0, async () => {
      clearMockSubmissions();
      await newSubmitter().submit(contentPlan('会被清掉的正文'), 'req-mock-f');
      const submitted: Assignment | undefined = assignmentFor(XSZYID);
      expect(submitted !== undefined).assertTrue();
      if (submitted !== undefined) {
        expect(submitted.submitted).assertTrue();
      }
      clearMockSubmissions();
      const restored: Assignment | undefined = assignmentFor(XSZYID);
      expect(restored !== undefined).assertTrue();
      if (restored !== undefined) {
        expect(restored.submitted).assertFalse();
        expect(restored.submitTime === undefined).assertTrue();
        expect(restored.submittedContent).assertEqual('');
        expect(restored.submittedAttachment === undefined).assertTrue();
      }
      // 样例里本来就已提交的两条**不受台账清空影响**（覆盖层只加不减）。
      const alreadySubmitted: Assignment | undefined = assignmentFor('mock-xszy-3');
      expect(alreadySubmitted !== undefined).assertTrue();
      if (alreadySubmitted !== undefined) {
        expect(alreadySubmitted.submitted).assertTrue();
        expect(alreadySubmitted.submittedContent).assertEqual('<p>见附件。</p>');
      }
      const graded: Assignment | undefined = assignmentFor('mock-xszy-4');
      expect(graded !== undefined).assertTrue();
      if (graded !== undefined) {
        expect(graded.submitted).assertTrue();
        expect(graded.submittedContent).assertEqual('<p>提纲见正文。</p>');
        expect(graded.grade).assertEqual(92);
      }
    });
  });
}
