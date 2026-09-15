/*
 * Mock 提交线单测（host 侧 hypium）——把「mock 登录时作业无法提交」这条缺陷钉死，
 * 以及本轮收口的**附件字节**那一半。
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
 *   (f) `clearMockSubmissions()` 之后样例数据回到初始态（用例之间互不污染）；
 *   (g) **附件连字节一起进台账**：读器返回的那份字节原样存住（长度、首字节、扩展名），
 *       `mockAssignments()` 里那条 `submittedAttachment.downloadUrl` 能被
 *       `mockBlobForUrl` 解析（上一版这里是一条谁都打不开的死链）；
 *   (h) **读不到就不留死链**：读器抛异常 / 返回 0 字节时，提交照常成功、正文照常记下，
 *       但那条件业**没有** `submittedAttachment`。
 *
 * ## 分工（三份证据不重复）
 *
 *   - 本文件：提交侧的**可观察后果**（台账里的字节、地址可解析、失败形态）；
 *   - `MockFiles.test.ets`：把那条地址**真的下载一遍**（组合 source + 假 FileStore，
 *     落盘字节与选中附件逐字节相同）；
 *   - `scripts/check-mock-files.mjs`：真实产物（包内 PDF/PPTX）的**结构**。
 *
 * ## 替身为什么是"伪字节"
 *
 * host 单测既跑不到 rawfile 也跑不到 picker：`AttachmentBytesSource` 的替身返回确定字节，
 * 于是"台账里存的是不是这份字节"可以逐字节断言，而"设备上 picker 能不能读到"由端口
 * 自己的实现负责（不在本文件能证明的范围内）。
 *
 * 隔离方式：每条用例开头都 `clearMockSubmissions()`（内存台账是模块级单例，
 * hypium 的各 `it` 共享同一个模块实例）。**不调用 `resetNetworkAudit()`**：
 * 它是别人的用例也在读的全局量，这里只做"前后相等"的比较，不去动它。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  AssignmentSubmitter, AttachmentBytesSource, SubmitOutcome
} from '../main/ets/data/assignments/SubmitAssignment';
import { MockAssignmentSubmitter } from '../main/ets/data/mock/MockAssignmentSubmitter';
import {
  MockSubmissionEntry, clearMockSubmissions, submissionFor
} from '../main/ets/data/mock/MockSubmissionJournal';
import { mockAssignments } from '../main/ets/data/mock/MockData';
import {
  MockFileBlob, buildMockSubmittedAttachmentId, mockBlobForUrl
} from '../main/ets/data/mock/MockFileBlobs';
import { Assignment, Attachment } from '../main/ets/domain/model/ContentItem';
import { SubmissionPlan } from '../main/ets/domain/assignments/SubmissionState';
import { UploadProgress } from '../main/ets/data/remote/Port';
import { Logger } from '../main/ets/core/log/Logger';
import { networkAttemptCount } from '../main/ets/data/remote/NetworkAudit';
import { parseTimestamp } from '../main/ets/domain/parse/Text';

/** 样例里那条**未提交**的作业（提交线的目标）。 */
const XSZYID: string = 'mock-xszy-1';

/** picker 给的 URI 形状（与真实 `file://docs/…` 同一形状；本文件不解析它）。 */
function attachmentUri(name: string): string {
  return 'file://docs/storage/a/' + name;
}

/** 确定字节：第 i 个 = (i * 31 + 7) & 0xFF（长度可控、内容可核对、无随机数）。 */
function payload(length: number): Uint8Array {
  const out: Uint8Array = new Uint8Array(length);
  for (let i = 0; i < length; i++) {
    out[i] = (i * 31 + 7) & 0xFF;
  }
  return out;
}

/** 附件读取器的替身：登记的 uri 返回确定字节；没登记 / 在 failFor 里则抛。 */
class FakeAttachmentReader implements AttachmentBytesSource {
  readonly files: Map<string, Uint8Array> = new Map<string, Uint8Array>();
  readonly failFor: string[] = [];
  reads: number = 0;

  async read(uri: string): Promise<Uint8Array> {
    this.reads++;
    if (this.failFor.includes(uri)) {
      throw new Error('fake attachment reader refuses: ' + uri);
    }
    const bytes: Uint8Array | undefined = this.files.get(uri);
    if (bytes === undefined) {
      throw new Error('fake attachment reader has no bytes for: ' + uri);
    }
    return bytes;
  }
}

function newSubmitter(reader: AttachmentBytesSource): AssignmentSubmitter {
  return new MockAssignmentSubmitter(new Logger('test.mock.submit'), reader);
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
      uri: attachmentUri(name),
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
      const submitter: AssignmentSubmitter = newSubmitter(new FakeAttachmentReader());
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
      await newSubmitter(new FakeAttachmentReader()).submit(contentPlan(content), 'req-mock-b');
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

    it('journalsTheRealAttachmentBytesAndAResolvableUrl', 0, async () => {
      // 本轮的决定性用例（提交侧那一半）：附件字节进台账，且"我的提交附件"的地址
      // 是**已知 id**（mockBlobForUrl 认得），不是上一版那条谁都打不开的 `submitted-<xszyid>`。
      clearMockSubmissions();
      const name: string = '实验报告.pdf';
      const selected: Uint8Array = payload(2048);
      const reader: FakeAttachmentReader = new FakeAttachmentReader();
      reader.files.set(attachmentUri(name), selected);
      const outcome: SubmitOutcome =
        await newSubmitter(reader).submit(attachmentPlan(name, 2048), 'req-attach-a');
      expect(outcome.ok).assertTrue();
      expect(reader.reads).assertEqual(1);

      const entry: MockSubmissionEntry | undefined = submissionFor(XSZYID);
      expect(entry !== undefined).assertTrue();
      if (entry !== undefined) {
        const attachment = entry.attachment;
        expect(attachment !== undefined).assertTrue();
        if (attachment !== undefined) {
          expect(attachment.name).assertEqual(name);
          // 体积来自**读到的字节**，不是 picker 报的数。
          expect(attachment.size).assertEqual(selected.length);
          expect(attachment.extension).assertEqual('pdf');
          expect(attachment.bytes.length).assertEqual(selected.length);
          let same: boolean = true;
          for (let i = 0; i < selected.length; i++) {
            if (attachment.bytes[i] !== selected[i]) {
              same = false;
              break;
            }
          }
          expect(same).assertTrue();
        }
      }

      const item: Assignment | undefined = assignmentFor(XSZYID);
      expect(item !== undefined).assertTrue();
      if (item !== undefined) {
        expect(item.submitted).assertTrue();
        const submitted: Attachment | undefined = item.submittedAttachment;
        expect(submitted !== undefined).assertTrue();
        if (submitted !== undefined) {
          expect(submitted.name).assertEqual(name);
          expect(submitted.size).assertEqual('2.00KB');
          // 地址里的 id 由 MockFileBlobs 的共用构造函数拼（MockData 与台账侧同一份）。
          const expectedId: string = buildMockSubmittedAttachmentId(XSZYID, 'pdf');
          expect(submitted.downloadUrl.includes('mock=' + expectedId)).assertTrue();
          const blob: MockFileBlob | null = mockBlobForUrl(submitted.downloadUrl);
          expect(blob !== null).assertTrue();
          if (blob !== null) {
            expect(blob.contentType).assertEqual('application/pdf');
            expect(blob.rawfilePath.startsWith('mock-submitted/')).assertTrue();
            expect(blob.rawfilePath.endsWith('.pdf')).assertTrue();
          }
          // 没有 _csrf 时也认得（真实编排会往地址追加它）。
          const withCsrf: MockFileBlob | null =
            mockBlobForUrl(submitted.downloadUrl + '&_csrf=abc');
          expect(withCsrf !== null).assertTrue();
        }
      }
    });

    it('mapsTheAttachmentExtensionToAContentTypeAndToleratesNoExtension', 0, async () => {
      // 扩展名 → Content-Type：已知的用表，未知的 / 没有扩展名的给 application/octet-stream。
      clearMockSubmissions();
      const binName: string = '实验数据.bin';
      const binReader: FakeAttachmentReader = new FakeAttachmentReader();
      binReader.files.set(attachmentUri(binName), payload(300));
      await newSubmitter(binReader).submit(attachmentPlan(binName, 300), 'req-attach-b1');
      const binItem: Assignment | undefined = assignmentFor(XSZYID);
      if (binItem !== undefined && binItem.submittedAttachment !== undefined) {
        const blob: MockFileBlob | null = mockBlobForUrl(binItem.submittedAttachment.downloadUrl);
        expect(blob !== null).assertTrue();
        if (blob !== null) {
          expect(blob.contentType).assertEqual('application/octet-stream');
        }
      } else {
        expect(false).assertTrue();
      }

      const bareName: string = 'README';
      const bareReader: FakeAttachmentReader = new FakeAttachmentReader();
      bareReader.files.set(attachmentUri(bareName), payload(64));
      await newSubmitter(bareReader).submit(attachmentPlan(bareName, 64), 'req-attach-b2');
      const bareItem: Assignment | undefined = assignmentFor(XSZYID);
      if (bareItem !== undefined && bareItem.submittedAttachment !== undefined) {
        // 没有扩展名 ⇒ id 里不留点，地址仍然可解析（Content-Type 退回二进制流）。
        expect(bareItem.submittedAttachment.downloadUrl.includes('mock=submitted-' + XSZYID))
          .assertTrue();
        expect(bareItem.submittedAttachment.downloadUrl.endsWith(XSZYID)).assertTrue();
        const blob: MockFileBlob | null = mockBlobForUrl(bareItem.submittedAttachment.downloadUrl);
        expect(blob !== null).assertTrue();
        if (blob !== null) {
          expect(blob.contentType).assertEqual('application/octet-stream');
        }
      } else {
        expect(false).assertTrue();
      }
    });

    it('keepsTheSubmissionButDropsTheAttachmentWhenTheReaderFails', 0, async () => {
      // 读不到就**不留死链**：提交照常成功、正文照常记下，但那条件业没有 submittedAttachment。
      clearMockSubmissions();
      const name: string = '读不到的附件.pdf';
      const reader: FakeAttachmentReader = new FakeAttachmentReader();
      reader.failFor.push(attachmentUri(name));
      const outcome: SubmitOutcome =
        await newSubmitter(reader).submit(attachmentPlan(name, 4096), 'req-attach-c');
      expect(outcome.ok).assertTrue();
      expect(outcome.status).assertEqual(200);
      expect(reader.reads).assertEqual(1);

      const entry: MockSubmissionEntry | undefined = submissionFor(XSZYID);
      expect(entry !== undefined).assertTrue();
      if (entry !== undefined) {
        expect(entry.attachment === undefined).assertTrue();
        expect(entry.content.length > 0).assertTrue();
      }
      const item: Assignment | undefined = assignmentFor(XSZYID);
      expect(item !== undefined).assertTrue();
      if (item !== undefined) {
        expect(item.submitted).assertTrue();
        expect(item.submittedContent.includes('带附件的正文')).assertTrue();
        expect(item.submittedAttachment === undefined).assertTrue();
      }
    });

    it('dropsTheAttachmentWhenTheReaderReturnsZeroBytes', 0, async () => {
      // 0 字节的附件会被下载端口显式拒绝（空资产）⇒ 记下来就等于留一条死链，故按"没有附件"处理。
      clearMockSubmissions();
      const name: string = '空文件.pdf';
      const reader: FakeAttachmentReader = new FakeAttachmentReader();
      reader.files.set(attachmentUri(name), new Uint8Array(0));
      const outcome: SubmitOutcome =
        await newSubmitter(reader).submit(attachmentPlan(name, 0), 'req-attach-d');
      expect(outcome.ok).assertTrue();
      const entry: MockSubmissionEntry | undefined = submissionFor(XSZYID);
      if (entry !== undefined) {
        expect(entry.attachment === undefined).assertTrue();
      }
      const item: Assignment | undefined = assignmentFor(XSZYID);
      if (item !== undefined) {
        expect(item.submitted).assertTrue();
        expect(item.submittedAttachment === undefined).assertTrue();
      }
    });

    it('clearsTheSubmittedAttachmentOnTheRemoveBranch', 0, async () => {
      clearMockSubmissions();
      const name: string = '实验报告.pdf';
      const reader: FakeAttachmentReader = new FakeAttachmentReader();
      reader.files.set(attachmentUri(name), payload(2048));
      const submitter: AssignmentSubmitter = newSubmitter(reader);
      await submitter.submit(attachmentPlan(name, 2048), 'req-mock-c1');
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
      // 台账里的字节也随覆盖一起丢掉（移除之后不该还留着上一次的附件字节）。
      const entry: MockSubmissionEntry | undefined = submissionFor(XSZYID);
      if (entry !== undefined) {
        expect(entry.removeAttachment).assertTrue();
        expect(entry.attachment === undefined).assertTrue();
      }
    });

    it('treatsAnUndefinedPlanAsANoopWithoutJournaling', 0, async () => {
      clearMockSubmissions();
      const seen: UploadProgress[] = [];
      const outcome: SubmitOutcome = await newSubmitter(new FakeAttachmentReader())
        .submit(undefined, 'req-mock-d',
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
      const reader: FakeAttachmentReader = new FakeAttachmentReader();
      reader.files.set(attachmentUri('a.pdf'), payload(10));
      const submitter: AssignmentSubmitter = newSubmitter(reader);
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
      const name: string = '会被清掉的附件.pdf';
      const reader: FakeAttachmentReader = new FakeAttachmentReader();
      reader.files.set(attachmentUri(name), payload(128));
      await newSubmitter(reader).submit(attachmentPlan(name, 128), 'req-mock-f');
      const submitted: Assignment | undefined = assignmentFor(XSZYID);
      expect(submitted !== undefined).assertTrue();
      if (submitted !== undefined) {
        expect(submitted.submitted).assertTrue();
        expect(submitted.submittedAttachment !== undefined).assertTrue();
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
