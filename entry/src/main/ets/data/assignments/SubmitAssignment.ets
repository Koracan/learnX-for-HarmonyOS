/*
 * 作业提交用例（data 层）。
 *
 * 端点与字段逐条对齐参考实现 `reference/learnOH-old/src/data/source.ts:149,161-179`：
 *
 *   POST {learn}/b/wlxt/kczy/zy/student/tjzy?_csrf=<token>
 *   表单字段（顺序即 object 插入序）：`xszyid` → `zynr` → `isDeleted`
 *   文件部分：multipart，字段名 `fileupload`，文件名 = 用户选定/改过的名字，MIME 按扩展名查表
 *   无正文且无附件且不移除 ⇒ **直接返回，不发请求**
 *
 * **没有 `id` 字段**。ticket 05 的 `UploadFormParams` 曾经是 `{id, xszyid}`，那是把
 * 作业描述接口（`PostFormSpec.id`，发 `id=<zyid>`）的字段揉进了提交接口；参考实现的提交
 * 只发上面三个字段。`FetchPort.upload` 在本次改动前**没有任何调用点**（只有定义与实现），
 * 所以这次对齐不推翻任何已验收 ticket 的证据。
 *
 * 会话与降级**不在这里**：本用例只做"一次带会话的请求"，重登 / 只重试一次 / 显式降级
 * 全部由 `AuthedTaskRunner`（data/auth/SessionRestore）承担 —— 与三域仓储同一条路径。
 *
 * 所有请求都带 `?_csrf=`（裸请求会拿到站点自己的 403
 * 报错页，而 403 被判成"会话失效"）。
 */

import { Logger } from '../../core/log/Logger';
import { SubmissionPlan } from '../../domain/assignments/SubmissionState';
import { AuthedRunResult, SessionTask } from '../auth/SessionRestore';
import { FailReason } from '../auth/AuthTypes';
import { FetchPort, UploadProgressSink, UploadSpec, UploadFormParams } from '../remote/Port';
import { HttpOutcome, LEARN_ORIGIN, Session, withCsrf } from '../remote/Requests';
import { TaskOutcome } from '../auth/ReAuth';
import { DEFAULT_FILE_FIELD, UploadFile } from '../upload/Multipart';
import { makeUploadFile } from '../upload/UploadForm';

/** 提交端点（参考实现 `source.ts:149`）。 */
export const SUBMIT_ASSIGNMENT_PATH: string = '/b/wlxt/kczy/zy/student/tjzy';

/** 日志域：与作业抓取分开，便于 `hdc` 全量拉日志后本地筛。 */
export const SUBMIT_LOG_DOMAIN: string = 'data.assignments.submit';

/** 提交请求的 multipart 文件字段名（参考实现固定 `fileupload`）。 */
export const SUBMIT_FILE_FIELD: string = DEFAULT_FILE_FIELD;

/** 读一个本地 URI 的字节（picker 给的 URI 是平台事实，故这一步是端口）。 */
export interface AttachmentBytesSource {
  /** 读全部字节；失败时抛出（消息进日志）。 */
  read(uri: string): Promise<Uint8Array>;
}

/** 提交结果（不抛异常；失败也是结果）。 */
export class SubmitOutcome {
  readonly ok: boolean;
  /** 服务端是否明确回了 `result: error`。 */
  readonly serverRejected: boolean;
  readonly status: number;
  readonly message: string;
  /** 会话失效 / 降级：调用方据此回登录页（spec 第 5 节）。 */
  readonly requiresEnrollment: boolean;
  readonly diagnostic: string;

  private constructor(ok: boolean, serverRejected: boolean, status: number, message: string,
    requiresEnrollment: boolean, diagnostic: string) {
    this.ok = ok;
    this.serverRejected = serverRejected;
    this.status = status;
    this.message = message;
    this.requiresEnrollment = requiresEnrollment;
    this.diagnostic = diagnostic;
  }

  static success(status: number, diagnostic: string): SubmitOutcome {
    return new SubmitOutcome(true, false, status, '', false, diagnostic);
  }

  /** 不需要发请求（无正文 / 无附件 / 不移除）——参考实现同样直接返回。 */
  static noop(diagnostic: string): SubmitOutcome {
    return new SubmitOutcome(true, false, 0, '', false, diagnostic);
  }

  static serverError(status: number, message: string, diagnostic: string): SubmitOutcome {
    return new SubmitOutcome(false, true, status, message, false, diagnostic);
  }

  static transportError(status: number, diagnostic: string): SubmitOutcome {
    return new SubmitOutcome(false, false, status, '', false, diagnostic);
  }

  static degraded(reason: FailReason, diagnostic: string): SubmitOutcome {
    return new SubmitOutcome(false, false, 0, '', true,
      'requiresEnrollment=true reason=' + reason + ' ' + diagnostic);
  }
}

/** 提交响应的判定（参考实现 `source.ts:210-223`，纯函数、可单测）。 */
export interface SubmitResponse {
  ok: boolean;
  message: string;
}

/**
 * 判定服务端响应。
 *
 * 逐条照参考实现：
 *   - 能解析成 JSON 且 `result === 'error'` ⇒ 失败（消息 = `msg`）；
 *   - 解析不了、但正文非空且含 `error` ⇒ 失败；
 *   - 其余（含解析不了的空/正常正文）⇒ 视为成功。
 */
export function parseSubmitResponse(body: string): SubmitResponse {
  let parsed: Object | undefined = undefined;
  try {
    parsed = JSON.parse(body) as Object;
  } catch (error) {
    parsed = undefined;
  }
  if (parsed !== undefined && parsed !== null) {
    const root: Record<string, Object> = parsed as Record<string, Object>;
    if (String(root['result']) === 'error') {
      const msg: Object | undefined = root['msg'] as Object | undefined;
      return { ok: false, message: msg === undefined || msg === null ? '' : String(msg) };
    }
    return { ok: true, message: '' };
  }
  if (body.length > 0 && body.includes('error')) {
    return { ok: false, message: 'unparseable error response' };
  }
  return { ok: true, message: '' };
}

/** 把一次提交计划翻成端口的 `UploadSpec`（纯函数，字段顺序可单测）。 */
export function buildSubmissionSpec(url: string, plan: SubmissionPlan, file: UploadFile | undefined,
  requestId: string): UploadSpec {
  // 顺序 = 参考实现对象字面量的插入序：xszyid → zynr → isDeleted。
  const params: UploadFormParams = {
    xszyid: plan.studentHomeworkId,
    zynr: plan.content,
    isDeleted: plan.removeAttachment ? '1' : '0'
  };
  const spec: UploadSpec = { url: url, params: params, requestId: requestId };
  if (file !== undefined) {
    spec.file = file;
  }
  return spec;
}

/**
 * 一次提交（读取附件字节 → 组装 → 发送）。
 *
 * **不发请求的情形**由调用方（`AssignmentSubmitter.submit`）判掉；这里假定 plan 是要发的。
 */
export class SubmitAssignment {
  private readonly port: FetchPort;
  private readonly files: AttachmentBytesSource;
  private readonly logger: Logger;

  constructor(port: FetchPort, files: AttachmentBytesSource, logger: Logger) {
    this.port = port;
    this.files = files;
    this.logger = logger;
  }

  /** 发一次提交；返回原始结果（会话判定在 `AssignmentSubmitter`）。 */
  async send(session: Session, plan: SubmissionPlan, requestId: string,
    onProgress?: UploadProgressSink): Promise<SubmitOutcome> {
    const url: string = withCsrf(LEARN_ORIGIN + SUBMIT_ASSIGNMENT_PATH, session.csrfToken);
    // 无附件时**不写文件部分**（参考实现 filePath 未定义就不写文件）。
    let file: UploadFile | undefined = undefined;
    if (plan.attachment !== undefined) {
      const picked = plan.attachment;
      const data: Uint8Array = await this.files.read(picked.uri);
      file = makeUploadFile(picked.name, picked.mimeType, data, SUBMIT_FILE_FIELD);
    }
    const spec: UploadSpec = buildSubmissionSpec(url, plan, file, requestId);
    return this.post(session, spec, onProgress);
  }

  private async post(session: Session, spec: UploadSpec,
    onProgress?: UploadProgressSink): Promise<SubmitOutcome> {
    const fileName: string = spec.file === undefined ? '(none)' : spec.file.fileName;
    let contentType: string = '(none)';
    let byteCount: number = 0;
    if (spec.file !== undefined) {
      if (spec.file.contentType !== undefined) {
        contentType = spec.file.contentType;
      }
      byteCount = spec.file.data.length;
    }
    this.logger.info(SUBMIT_LOG_DOMAIN + ' sending xszyid=' + spec.params.xszyid
      + ' zynrChars=' + spec.params.zynr.length.toString()
      + ' isDeleted=' + spec.params.isDeleted
      + ' file=' + fileName
      + ' contentType=' + contentType
      + ' bytes=' + byteCount.toString()
      + ' csrf=' + (spec.url.includes('_csrf=') ? 'yes' : 'NO'));
    const outcome: HttpOutcome = await this.port.upload(session, spec, onProgress);
    if (!outcome.ok) {
      this.logger.warn(SUBMIT_LOG_DOMAIN + ' upload failed status=' + outcome.status.toString()
        + ' ' + (outcome.error === undefined ? '' : outcome.error));
      return SubmitOutcome.transportError(outcome.status,
        'status=' + outcome.status.toString());
    }
    const parsed: SubmitResponse = parseSubmitResponse(outcome.body);
    this.logger.info(SUBMIT_LOG_DOMAIN + ' response status=' + outcome.status.toString()
      + ' bytes=' + outcome.body.length.toString() + ' ok=' + parsed.ok.toString()
      + (parsed.message.length === 0 ? '' : ' msg=' + parsed.message));
    if (!parsed.ok) {
      return SubmitOutcome.serverError(outcome.status, parsed.message,
        'server rejected: ' + parsed.message);
    }
    return SubmitOutcome.success(outcome.status, 'status=' + outcome.status.toString());
  }
}

/** 任务执行器端口：设备侧就是 `AuthedTaskRunner`（形状逐字对齐，避免结构类型问题）。 */
export interface AuthedTaskExecutor {
  run(task: SessionTask): Promise<AuthedRunResult>;
}

/**
 * 提交的仓储出口：把"一次提交"包成 `AuthedTaskRunner` 的任务。
 *
 * 早退分支（参考实现 source.ts:161-163）在这里：`plan === undefined` ⇒ 一行日志、
 * **不发任何请求**、返回 `noop`。
 */
export class AssignmentSubmitter {
  private readonly executor: AuthedTaskExecutor;
  private readonly submitAssignment: SubmitAssignment;
  private readonly logger: Logger;

  constructor(executor: AuthedTaskExecutor, submitAssignment: SubmitAssignment, logger: Logger) {
    this.executor = executor;
    this.submitAssignment = submitAssignment;
    this.logger = logger;
  }

  async submit(plan: SubmissionPlan | undefined, requestId: string,
    onProgress?: UploadProgressSink): Promise<SubmitOutcome> {
    if (plan === undefined) {
      // 参考实现 source.ts:161-163：无正文、无附件、不移除 ⇒ 直接返回，不发请求。
      this.logger.info(SUBMIT_LOG_DOMAIN + ' nothing to submit: no request sent');
      return SubmitOutcome.noop('empty submission');
    }
    let last: SubmitOutcome = SubmitOutcome.transportError(0, 'not attempted');
    const run: AuthedRunResult = await this.executor.run(async (session: Session): Promise<TaskOutcome> => {
      last = await this.submitAssignment.send(session, plan, requestId, onProgress);
      // responseUrl 必须是请求 URL：SessionGate 的 noLogin 判据之一就是 status===403，
      // 而参考实现也把 `login_timeout` 写在 URL 上。
      return {
        status: last.status,
        body: last.ok ? 'submitted' : (last.serverRejected ? 'error' : ''),
        responseUrl: withCsrf(LEARN_ORIGIN + SUBMIT_ASSIGNMENT_PATH, session.csrfToken)
      };
    });
    if (!run.ok || run.requiresEnrollment) {
      this.logger.warn(SUBMIT_LOG_DOMAIN + ' degraded to enrollment: reason=' + run.reason
        + ' reAuth=' + run.reAuthAttempted.toString() + ' diag=' + run.diagnostic);
      return SubmitOutcome.degraded(run.reason, 'reAuth=' + run.reAuthAttempted.toString()
        + ' diag=' + run.diagnostic);
    }
    return last;
  }
}
