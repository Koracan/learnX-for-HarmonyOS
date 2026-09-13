/*
 * 作业提交（ticket 13）单测。
 *
 * 本账号**没有任何可提交的真实作业**（2026-2027 秋季 0 条；2025-2026 春季 57 条全部已截止），
 * 所以本轮判据是「提交链路的组装 + 状态机」用单测 + 假端口证明，而不是真实提交：
 *
 *   1. multipart 的字段与顺序：xszyid → zynr → isDeleted → fileupload → 结束边界，
 *      **没有 id 字段**（参考实现 source.ts:175-179）；
 *   2. 无附件时**不写文件部分**；移除附件时 isDeleted='1'、正文空串、无文件；
 *   3. 文件名编码：中文名在 filename 之外另给 RFC 5987 的 filename*（含空格 → %20）；
 *   4. `?_csrf=` 一定在 URL 上；
 *   5. 无正文、无附件、不移除 ⇒ **一个请求都不发**；
 *   6. 进度回调分段映射到 0..1；
 *   7. 失败后**已填正文与已选附件逐字段不变**（验收第 3 条的参考语义）；
 *   8. 会话失效 ⇒ requiresEnrollment（走既有 AuthedTaskRunner 的降级口径）。
 *
 * 假端口/假执行器都**不实现任何平台调用**，所以这些断言在 host 单测里可重复。
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  FetchOutcome, FetchPort, GetSpec, PostFormSpec, UploadFormParams, UploadProgress,
  UploadProgressSink, UploadSpec
} from '../main/ets/data/remote/Port';
import { LEARN_ORIGIN, Session } from '../main/ets/data/remote/Requests';
import {
  AssignmentSubmitter, AttachmentBytesSource, AuthedTaskExecutor, SubmitAssignment,
  SubmitOutcome, parseSubmitResponse, buildSubmissionSpec, SUBMIT_ASSIGNMENT_PATH
} from '../main/ets/data/assignments/SubmitAssignment';
import { AuthedRunResult, SessionTask } from '../main/ets/data/auth/SessionRestore';
import { FailReason } from '../main/ets/data/auth/AuthTypes';
import { TaskOutcome } from '../main/ets/data/auth/ReAuth';
import { buildUploadRequest, UploadRequest } from '../main/ets/data/upload/UploadForm';
import { UploadFile } from '../main/ets/data/upload/Multipart';
import { Logger } from '../main/ets/core/log/Logger';
import {
  PickedAttachment, applyCustomAttachmentName, defaultAttachmentName, extensionForMime,
  mimeTypeForName, pickedAttachmentFromUri, sanitizeCustomAttachmentName
} from '../main/ets/domain/assignments/SubmissionForm';
import {
  SubmissionPlan, SubmissionState, canSubmit, initialSubmissionState, planSubmission,
  shouldSendRequest, submitFailed, submitStarted, submitSucceeded, withAttachmentPicked,
  withContent, withCustomAttachmentName, withPickedAttachmentRemoved,
  withRemoveAttachmentToggled, withUploadProgress
} from '../main/ets/domain/assignments/SubmissionState';
import { decodeUtf8, deviceUtf8Encoder } from './TestHelpers';

const BOUNDARY: string = '----WebKitFormBoundaryTICKET13';
const SESSION: Session = { cookie: 'JSESSIONID=abcdef', csrfToken: 'TOKEN-123' };

/** 记录型假端口：把发出去的 spec 原样留下，并按脚本回一个响应。 */
class RecordingUploadPort implements FetchPort {
  readonly uploads: UploadSpec[] = [];
  readonly cookies: string[] = [];
  private readonly progressEvents: UploadProgress[];
  private readonly ok: boolean;
  private readonly status: number;
  private readonly body: string;

  constructor(progressEvents: UploadProgress[], ok: boolean, status: number, body: string) {
    this.progressEvents = progressEvents;
    this.ok = ok;
    this.status = status;
    this.body = body;
  }

  async postForm(session: Session, spec: PostFormSpec): Promise<FetchOutcome> {
    return { ok: false, status: 0, body: '', error: 'not used by this test' };
  }

  async get(session: Session, spec: GetSpec): Promise<FetchOutcome> {
    return { ok: false, status: 0, body: '', error: 'not used by this test' };
  }

  async upload(session: Session, spec: UploadSpec,
    onProgress?: UploadProgressSink): Promise<FetchOutcome> {
    this.uploads.push(spec);
    this.cookies.push(session.cookie);
    if (onProgress !== undefined) {
      for (let i = 0; i < this.progressEvents.length; i++) {
        onProgress(this.progressEvents[i]);
      }
    }
    return { ok: this.ok, status: this.status, body: this.body };
  }
}

/** 假的附件字节来源：记下 URI，返回固定字节。 */
class FakeAttachmentBytes implements AttachmentBytesSource {
  readonly uris: string[] = [];
  private readonly bytes: number[];

  constructor(bytes: number[]) {
    this.bytes = bytes;
  }

  async read(uri: string): Promise<Uint8Array> {
    this.uris.push(uri);
    const out = new Uint8Array(this.bytes.length);
    for (let i = 0; i < this.bytes.length; i++) {
      out[i] = this.bytes[i];
    }
    return out;
  }
}

/** 脚本化执行器：伪装成 AuthedTaskRunner（成功 / 直接降级两种）。 */
class ScriptedExecutor implements AuthedTaskExecutor {
  private readonly degraded: boolean;
  runs: number = 0;

  constructor(degraded: boolean) {
    this.degraded = degraded;
  }

  async run(task: SessionTask): Promise<AuthedRunResult> {
    this.runs++;
    if (this.degraded) {
      return AuthedRunResult.degraded(FailReason.NETWORK_UNREACHABLE, true, 'scripted degradation');
    }
    const outcome: TaskOutcome = await task(SESSION);
    return AuthedRunResult.success(outcome.body, false, 'status=' + outcome.status.toString());
  }
}

function picked(name: string): PickedAttachment {
  return { uri: 'file://docs/storage/a/' + name, name: name, mimeType: mimeTypeForName(name), size: 3 };
}

function stateWithContentOnly(): SubmissionState {
  return withContent(initialSubmissionState(''), '我的正文');
}

function stateWithAttachment(): SubmissionState {
  const state: SubmissionState = withAttachmentPicked(initialSubmissionState(''), picked('作业 一.pdf'));
  return withContent(state, '带附件的正文');
}

/** 把一次提交的 spec 用固定边界组装成字节，供逐字节断言。 */
function assemble(spec: UploadSpec): string {
  const params: Record<string, string> = {};
  params['xszyid'] = spec.params.xszyid;
  params['zynr'] = spec.params.zynr;
  params['isDeleted'] = spec.params.isDeleted;
  const request: UploadRequest = buildUploadRequest(spec.url, params, spec.file,
    deviceUtf8Encoder, SESSION.cookie, BOUNDARY);
  return decodeUtf8(request.body);
}

function submitterFor(port: RecordingUploadPort, files: AttachmentBytesSource,
  degraded: boolean): AssignmentSubmitter {
  const useCase: SubmitAssignment = new SubmitAssignment(port, files, new Logger('test.submit'));
  return new AssignmentSubmitter(new ScriptedExecutor(degraded), useCase, new Logger('test.submit'));
}

export default function assignmentSubmissionTest() {
  describe('data.SubmitAssignment', () => {
    it('sendsReferenceFieldsInOrderAndNeverSendsId', 0, async () => {
      const port = new RecordingUploadPort([], true, 200, '{"result":"success"}');
      const files = new FakeAttachmentBytes([1, 2, 3]);
      const submitter: AssignmentSubmitter = submitterFor(port, files, false);
      const state: SubmissionState = stateWithAttachment();
      const plan: SubmissionPlan | undefined = planSubmission(state, 'xszyid-42');
      expect(plan !== undefined).assertTrue();
      const outcome: SubmitOutcome = await submitter.submit(plan, 'req-1');
      expect(outcome.ok).assertTrue();
      expect(port.uploads.length).assertEqual(1);
      const spec: UploadSpec = port.uploads[0];
      expect(spec.url).assertEqual(LEARN_ORIGIN + SUBMIT_ASSIGNMENT_PATH + '?_csrf=' + SESSION.csrfToken);
      expect(spec.params.xszyid).assertEqual('xszyid-42');
      expect(spec.params.zynr).assertEqual('带附件的正文');
      expect(spec.params.isDeleted).assertEqual('0');
      expect(port.cookies[0]).assertEqual(SESSION.cookie);
      expect(files.uris[0]).assertEqual('file://docs/storage/a/作业 一.pdf');
      const file: UploadFile | undefined = spec.file;
      expect(file !== undefined).assertTrue();
      if (file !== undefined) {
        expect(file.fieldName).assertEqual('fileupload');
        expect(file.fileName).assertEqual('作业 一.pdf');
        expect(file.contentType).assertEqual('application/pdf');
        expect(file.data.length).assertEqual(3);
      }
      const text: string = assemble(spec);
      const xszyidAt: number = text.indexOf('name="xszyid"');
      const zynrAt: number = text.indexOf('name="zynr"');
      const isDeletedAt: number = text.indexOf('name="isDeleted"');
      const fileAt: number = text.indexOf('name="fileupload"');
      const endAt: number = text.indexOf('--' + BOUNDARY + '--');
      expect(xszyidAt > 0).assertTrue();
      expect(xszyidAt < zynrAt).assertTrue();
      expect(zynrAt < isDeletedAt).assertTrue();
      expect(isDeletedAt < fileAt).assertTrue();
      expect(fileAt < endAt).assertTrue();
      // 参考实现的提交**没有 id 字段**：多一个站点没预期的字段最坏会让提交被拒。
      expect(text.indexOf('name="id"')).assertEqual(-1);
      // 中文名：filename 之外另给 RFC 5987 的 filename*，空格编码为 %20。
      expect(text.includes('filename="作业 一.pdf"')).assertTrue();
      expect(text.includes("filename*=UTF-8''%E4%BD%9C%E4%B8%9A%20%E4%B8%80.pdf")).assertTrue();
    });

    it('sendsNoFilePartWhenOnlyContentIsGiven', 0, async () => {
      const port = new RecordingUploadPort([], true, 200, '{"result":"success"}');
      const submitter: AssignmentSubmitter = submitterFor(port, new FakeAttachmentBytes([]), false);
      const plan: SubmissionPlan | undefined = planSubmission(stateWithContentOnly(), 'xszyid-7');
      const outcome: SubmitOutcome = await submitter.submit(plan, 'req-2');
      expect(outcome.ok).assertTrue();
      const spec: UploadSpec = port.uploads[0];
      expect(spec.file === undefined).assertTrue();
      const text: string = assemble(spec);
      expect(text.includes('name="xszyid"')).assertTrue();
      expect(text.indexOf('filename=')).assertEqual(-1);
      expect(text.indexOf('fileupload')).assertEqual(-1);
    });

    it('removeAttachmentSendsIsDeletedOneEmptyContentAndNoFile', 0, async () => {
      const port = new RecordingUploadPort([], true, 200, '{"result":"success"}');
      const submitter: AssignmentSubmitter = submitterFor(port, new FakeAttachmentBytes([]), false);
      const base: SubmissionState = withAttachmentPicked(initialSubmissionState(''), picked('a.pdf'));
      const state: SubmissionState = withRemoveAttachmentToggled(withContent(base, '应被忽略的正文'));
      // 移除态下提交按钮可用（即使正文为空、附件还在）。
      expect(canSubmit(state)).assertTrue();
      const plan: SubmissionPlan | undefined = planSubmission(state, 'xszyid-9');
      expect(plan !== undefined).assertTrue();
      const outcome: SubmitOutcome = await submitter.submit(plan, 'req-3');
      expect(outcome.ok).assertTrue();
      const spec: UploadSpec = port.uploads[0];
      expect(spec.params.isDeleted).assertEqual('1');
      expect(spec.params.zynr).assertEqual('');
      expect(spec.file === undefined).assertTrue();
      const text: string = assemble(spec);
      expect(text.includes('name="isDeleted"\r\n\r\n1\r\n')).assertTrue();
    });

    it('doesNotSendAnyRequestWhenThereIsNothingToSubmit', 0, async () => {
      const port = new RecordingUploadPort([], true, 200, '{"result":"success"}');
      const submitter: AssignmentSubmitter = submitterFor(port, new FakeAttachmentBytes([]), false);
      const empty: SubmissionState = initialSubmissionState('');
      expect(shouldSendRequest(empty)).assertFalse();
      expect(canSubmit(empty)).assertFalse();
      expect(planSubmission(empty, 'xszyid-0') === undefined).assertTrue();
      const outcome: SubmitOutcome = await submitter.submit(planSubmission(empty, 'xszyid-0'), 'req-4');
      expect(outcome.ok).assertTrue();
      expect(port.uploads.length).assertEqual(0);
    });

    it('mapsProgressCallbacksOntoZeroToOne', 0, async () => {
      const events: UploadProgress[] = [
        { requestId: 'req-5', sent: 0, total: 100 },
        { requestId: 'req-5', sent: 25, total: 100 },
        { requestId: 'req-5', sent: 50, total: 100 },
        { requestId: 'req-5', sent: 100, total: 100 }
      ];
      const port = new RecordingUploadPort(events, true, 200, '{"result":"success"}');
      const submitter: AssignmentSubmitter = submitterFor(port, new FakeAttachmentBytes([]), false);
      let observed: SubmissionState = submitStarted(stateWithContentOnly());
      const seen: number[] = [];
      const plan: SubmissionPlan | undefined = planSubmission(observed, 'xszyid-5');
      await submitter.submit(plan, 'req-5', (progress: UploadProgress): void => {
        observed = withUploadProgress(observed, progress.sent, progress.total);
        seen.push(observed.progress);
      });
      expect(seen.length).assertEqual(4);
      expect(seen[0]).assertEqual(0);
      expect(seen[1]).assertEqual(0.25);
      expect(seen[2]).assertEqual(0.5);
      expect(seen[3]).assertEqual(1);
      expect(observed.content).assertEqual('我的正文');
    });

    it('keepsTypedContentAndPickedAttachmentWhenSubmissionFails', 0, async () => {
      const port = new RecordingUploadPort([], false, 500, 'server exploded');
      const submitter: AssignmentSubmitter = submitterFor(port, new FakeAttachmentBytes([9]), false);
      const start: SubmissionState = withCustomAttachmentName(stateWithAttachment(), '我的.名字');
      const uploading: SubmissionState = submitStarted(start);
      const plan: SubmissionPlan | undefined = planSubmission(uploading, 'xszyid-6');
      const outcome: SubmitOutcome = await submitter.submit(plan, 'req-6');
      expect(outcome.ok).assertFalse();
      expect(outcome.serverRejected).assertFalse();
      const failed: SubmissionState = submitFailed(uploading);
      // 验收第 3 条：失败后**已填正文与已选附件逐字段不变**（参考实现 :233-237）。
      expect(failed.content).assertEqual('带附件的正文');
      expect(failed.customAttachmentName).assertEqual('我的名字');
      const kept: PickedAttachment | undefined = failed.attachment;
      expect(kept !== undefined).assertTrue();
      if (kept !== undefined) {
        expect(kept.name).assertEqual('作业 一.pdf');
        expect(kept.uri).assertEqual('file://docs/storage/a/作业 一.pdf');
      }
      expect(failed.uploading).assertFalse();
      expect(failed.error).assertTrue();
      expect(failed.progress).assertEqual(0);
      // 失败之后还能再提交一次（内容没丢，按钮因此仍然可用）。
      expect(canSubmit(failed)).assertTrue();
    });

    it('degradesToEnrollmentWhenTheSessionIsLost', 0, async () => {
      const port = new RecordingUploadPort([], true, 200, '{"result":"success"}');
      const submitter: AssignmentSubmitter = submitterFor(port, new FakeAttachmentBytes([]), true);
      const plan: SubmissionPlan | undefined = planSubmission(stateWithContentOnly(), 'xszyid-8');
      const outcome: SubmitOutcome = await submitter.submit(plan, 'req-7');
      expect(outcome.ok).assertFalse();
      expect(outcome.requiresEnrollment).assertTrue();
      // 降级发生在任务之外：请求本身没有被发出（执行器的替身直接返回降级）。
      expect(port.uploads.length).assertEqual(0);
    });

    it('treatsServerRejectionAsFailureAndSuccessShapeAsOk', 0, () => {
      const rejected = parseSubmitResponse('{"result":"error","msg":"已截止"}');
      expect(rejected.ok).assertFalse();
      expect(rejected.message).assertEqual('已截止');
      expect(parseSubmitResponse('{"result":"success"}').ok).assertTrue();
      expect(parseSubmitResponse('').ok).assertTrue();
      expect(parseSubmitResponse('not json at all').ok).assertTrue();
      expect(parseSubmitResponse('<p>服务器内部错误 error</p>').ok).assertFalse();
    });

    it('buildsSpecWithoutFileForContentViewOnly', 0, () => {
      const plan: SubmissionPlan = { studentHomeworkId: 'x', content: 'c', removeAttachment: false };
      const spec: UploadSpec = buildSubmissionSpec('https://x/y?_csrf=t', plan, undefined, 'r');
      expect(spec.file === undefined).assertTrue();
      expect(spec.params.isDeleted).assertEqual('0');
    });
  });

  describe('domain.SubmissionForm', () => {
    it('derivesDefaultAttachmentNameLikeTheReference', 0, () => {
      expect(defaultAttachmentName('作业一', 'application/pdf', true)).assertEqual('作业一-提交.pdf');
      expect(defaultAttachmentName('Homework 1', 'application/pdf', false))
        .assertEqual('Homework 1 Submission.pdf');
      // image/jpeg 的第一个扩展名是 jpeg（mime-db 顺序），与参考实现一致。
      expect(extensionForMime('image/jpeg')).assertEqual('jpeg');
      expect(defaultAttachmentName('作业一', 'image/jpeg', true)).assertEqual('作业一-提交.jpeg');
      // 推不出来的 MIME 用 bin（参考实现 `|| 'bin'`）。
      expect(extensionForMime('application/x-unknown-thing')).assertEqual('bin');
      expect(defaultAttachmentName('作业一', 'application/octet-stream', true)).assertEqual('作业一-提交.bin');
    });

    it('stripsDotsInCustomNameAndAppendsTheOriginalExtension', 0, () => {
      expect(sanitizeCustomAttachmentName('a.b.c')).assertEqual('abc');
      expect(sanitizeCustomAttachmentName('无点')).assertEqual('无点');
      expect(applyCustomAttachmentName('作业 一.pdf', '我的名字')).assertEqual('我的名字.pdf');
      expect(applyCustomAttachmentName('作业 一.pdf', '   ')).assertEqual('作业 一.pdf');
      // 参考实现用 `${customName}.${getExtension(name)}`，没有扩展名时会拼出字面量 undefined。
      expect(applyCustomAttachmentName('README', 'x')).assertEqual('x.undefined');
    });

    it('derivesAttachmentNameAndMimeFromPlatformUri', 0, () => {
      const document = pickedAttachmentFromUri(
        'file://docs/storage/Users/currentUser/Documents/实验报告 v2.pdf', '作业一', true);
      expect(document.name).assertEqual('实验报告 v2.pdf');
      expect(document.mimeType).assertEqual('application/pdf');
      const photo = pickedAttachmentFromUri('file://media/Photo/12/IMG_1/IMG_20240101_120000.jpg?networkid=1',
        '作业一', true);
      expect(photo.name).assertEqual('IMG_20240101_120000.jpg');
      expect(photo.mimeType).assertEqual('image/jpeg');
      // 末段取不到名字时退回参考实现的默认名。
      const bare = pickedAttachmentFromUri('file://media/Photo/', '作业一', true);
      expect(bare.name).assertEqual('作业一-提交.bin');
      expect(mimeTypeForName('unknown.zzz')).assertEqual('application/octet-stream');
    });
  });

  describe('domain.SubmissionState', () => {
    it('derivesInitialContentLikeTheReference', 0, () => {
      const state: SubmissionState = initialSubmissionState('<p>第一行</p><p>第二行</p>');
      // removeTags 只去标签 / 解实体 / 折叠空白，**不插入分隔符** ⇒ 相邻的 <p> 之间没有空格。
      expect(state.content).assertEqual('第一行第二行');
      expect(initialSubmissionState('').content).assertEqual('');
      expect(initialSubmissionState(undefined).content).assertEqual('');
      // 只去掉**第一处**字面量 -->（参考实现用的是字符串参数的 replace）。
      const arrows: SubmissionState = initialSubmissionState('a --> b --> c');
      expect(arrows.content).assertEqual('a  b --> c');
    });

    it('keepsCustomNameAndProgressTransitionsIndependent', 0, () => {
      let state: SubmissionState = initialSubmissionState('');
      state = withContent(state, 'x');
      state = withCustomAttachmentName(state, 'a.b');
      expect(state.customAttachmentName).assertEqual('ab');
      expect(state.content).assertEqual('x');
      state = withUploadProgress(state, 1, 3);
      expect(state.progress).assertEqual(0.33);
      state = withUploadProgress(state, 1, 0);
      expect(state.progress).assertEqual(0);
      state = withPickedAttachmentRemoved(withAttachmentPicked(state, picked('a.pdf')));
      expect(state.attachment === undefined).assertTrue();
      const toggled: SubmissionState = withRemoveAttachmentToggled(state);
      expect(toggled.removeAttachment).assertTrue();
      expect(withRemoveAttachmentToggled(toggled).removeAttachment).assertFalse();
      expect(submitSucceeded(submitStarted(toggled)).uploading).assertFalse();
    });
  });
}
