/*
 * 日志导出的**目标选择与降级** —— 纯逻辑，不碰任何平台 API。
 *
 * 落点由**系统文件选择器**决定：用户自己挑位置，应用不再申请任何权限。
 * （上一版走 `Environment.getUserDownloadDir()` ＋ `ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY`；
 * 那条权限受 ACL 限制，而发布 Profile 的 `acls` 是空的，AGC 上传会直接报 `ACL permission consistency`。）
 *
 * 选择器这一趟的三件设备事实被压成**输入**（`LogExportPickResult`）：用户选没选、选到的 URI、
 * 平台报了什么错；「写到哪 ＋ 现在是什么结局」压成**输出**（`LogExportPlan`）。于是
 * 成功 / 用户取消 / 平台不支持 / 写入选中的位置失败四条分支都能在 Local Test 里离线钉住 ——
 * 真正拉起选择器、真往 URI 写盘的那一层在 `LogExport.ets`。
 *
 * 降级是**显式**的：选中的位置用不了时绝不假装成功 —— 结局类别会变成「已导出到应用私有目录」
 * 并带上是哪一种原因，界面文案与 hilog 自证串都因此能把两种结局分开。
 */

import { I18nKey } from '../i18n/I18nKeys';

/** 平台返回「能力不支持」的错误码。 */
const ERR_NOT_SUPPORTED: number = 801;

/**
 * 平台在「用户取消」时回的错误码。
 *
 * **实测补入**：当前设备实测取消走的是「返回空数组」这一条（`classifyPickedUris`），
 * 所以这里是空的。若哪天实测到取消会 reject，把那个码加进来 —— 单测里有一条会遍历本表，
 * 加进来就自动被覆盖。
 */
export const USER_CANCELLED_CODES: Array<number> = [];

/** 选择器这一趟的结局（设备层产出，纯逻辑只消费）。 */
export enum LogExportPickState {
  /** 用户选好了位置，拿到一个可写的 URI。 */
  PICKED = 0,
  /** 用户在系统选择器里主动取消（既不是成功也不是失败）。 */
  CANCELLED = 1,
  /** 平台不支持这个能力（例如接口抛 801）。 */
  UNSUPPORTED = 2,
  /** 平台报错（不是取消，也不是不支持）。 */
  FAILED = 3
}

/** 选择结果：状态 ＋ 选中的 URI ＋ 平台原话（只进 hilog 与降级原因）。 */
export interface LogExportPickResult {
  state: LogExportPickState;
  /** `state = PICKED` 时的 URI（形如 `file://docs/storage/Users/currentUser/Download/learnOH-<时刻>.log`）。 */
  uri: string;
  /** 选择失败 / 写入失败时的平台错误码与消息。 */
  error: string;
}

/** 文件最终落在哪。 */
export enum LogExportDestination {
  /** 写进了用户选中的位置（选择器给的 URI），用户能在应用外拿到。 */
  PICKED = 0,
  /** 降级：写进了应用私有目录，应用外拿不到。 */
  PRIVATE = 1,
  /** 什么都没写。 */
  NONE = 2
}

/** 结局类别（界面文案的大类）。 */
export enum LogExportOutcome {
  /** 写进了用户选中的位置。 */
  EXPORTED_PICKED = 0,
  /** 降级：写进了应用私有目录，应用外拿不到。 */
  EXPORTED_PRIVATE = 1,
  /** 用户主动取消：既不是成功也不是失败。 */
  CANCELLED = 2,
  /** 没写任何文件。 */
  FAILED = 3
}

/** 落到私有目录（或彻底失败）的原因。 */
export enum LogExportFallback {
  NONE = 0,
  /** 平台不支持系统文件选择器。 */
  UNSUPPORTED = 1,
  /** 选择器本身没走通（没选成）。 */
  PICK_FAILED = 2,
  /** 选成了，但往那个 URI 写不进去。 */
  WRITE_FAILED = 3,
  /** 连私有兜底目录都没有。 */
  NO_PRIVATE_DIR = 4
}

/** 决策的输入：选择器这一趟的结果 ＋ 写盘失败原因 ＋ 宿主私有目录 ＋ 时刻。 */
export interface LogExportPlanInput {
  pick: LogExportPickResult;
  /** 往选中 URI 写失败时的原因（设备层带着它重新决策一次）；空串 = 没试过或试成功了。 */
  writeError: string;
  /** 兜底用的应用私有目录（`context.filesDir`）；空串 = 没有兜底可用。 */
  privateDir: string;
  /** 导出时刻，决定文件名。 */
  timestamp: number;
}

/** 决策的输出：写到哪 ＋ 结局类别 ＋ 界面要用的路径。 */
export interface LogExportPlan {
  outcome: LogExportOutcome;
  destination: LogExportDestination;
  fallback: LogExportFallback;
  /** 写入目录（选中位置时是 URI 的父路径）；`destination = NONE` 时是空串。 */
  directory: string;
  /** 完整落盘位置 —— 写盘与界面文案共用同一个串（选中位置时它就是那个 URI）。 */
  path: string;
  /** 界面文案的 i18n 键。 */
  messageKey: I18nKey;
  /** 文案里的原因要点（成功与取消时是空串）。 */
  reason: string;
}

/** 界面文案的键与参数（纯函数产出，调用点只负责渲染）。 */
export interface LogExportMessage {
  key: I18nKey;
  /** 固定四项，缺的补空串：调用点按位置取，不用展开数组。 */
  args: Array<string | number>;
}

/** 私有兜底目录 = `<filesDir>/logs`。 */
export function logExportPrivateDir(filesDir: string): string {
  return filesDir + '/logs';
}

/** 文件名 `learnOH-<时间戳>.log`（选择器预填与私有兜底共用同一个命名）。 */
export function logExportFileName(timestamp: number): string {
  return 'learnOH-' + timestamp + '.log';
}

/**
 * 选择器返回的 URI 列表 → 结局。
 *
 * 空列表（或没有 URI）就是**用户取消** —— 这是取消在本工程实测里唯一出现过的形式。
 */
export function classifyPickedUris(uris: Array<string> | undefined): LogExportPickState {
  if (uris === undefined || uris.length === 0 || uris[0].length === 0) {
    return LogExportPickState.CANCELLED;
  }
  return LogExportPickState.PICKED;
}

/** 平台错误码 → 结局：801 = 能力不支持；表里的码 = 用户取消；其余按平台报错处理。 */
export function classifyPickError(code: number): LogExportPickState {
  if (code === ERR_NOT_SUPPORTED) {
    return LogExportPickState.UNSUPPORTED;
  }
  if (USER_CANCELLED_CODES.indexOf(code) >= 0) {
    return LogExportPickState.CANCELLED;
  }
  return LogExportPickState.FAILED;
}

/**
 * 选中的位置是否值得一试：选成了、URI 非空，且**上一次往它写没有失败**。
 *
 * 写失败后设备层会带着 `writeError` 重新决策一次 —— 那时不再重试同一个位置，直接降级。
 */
export function pickUsable(pick: LogExportPickResult, writeError: string): boolean {
  return pick.state === LogExportPickState.PICKED && pick.uri.length > 0 && writeError.length === 0;
}

/** 降级原因分类（顺序即优先级：先看平台是否支持，再看是没选成还是写不进）。 */
export function classifyFallback(pick: LogExportPickResult, writeError: string): LogExportFallback {
  if (pick.state === LogExportPickState.UNSUPPORTED) {
    return LogExportFallback.UNSUPPORTED;
  }
  if (writeError.length > 0) {
    return LogExportFallback.WRITE_FAILED;
  }
  return LogExportFallback.PICK_FAILED;
}

/** 降级结局对应的文案键。 */
export function fallbackMessageKey(fallback: LogExportFallback): I18nKey {
  if (fallback === LogExportFallback.UNSUPPORTED) {
    return 'ui_export_private_unsupported';
  }
  if (fallback === LogExportFallback.WRITE_FAILED) {
    return 'ui_export_private_write_failed';
  }
  return 'ui_export_private_pick_failed';
}

/** 文案里的原因要点：把平台原话带上（选成但写不进时带的是写盘错误）。 */
function fallbackReason(fallback: LogExportFallback, pick: LogExportPickResult, writeError: string): string {
  if (fallback === LogExportFallback.WRITE_FAILED) {
    return writeError;
  }
  return pick.error.length > 0 ? pick.error : 'file picker unusable';
}

/** 把选择结果与写盘结果压成「写到哪 ＋ 现在是什么结局」。 */
export function planLogExport(input: LogExportPlanInput): LogExportPlan {
  const fileName: string = logExportFileName(input.timestamp);
  const privateDir: string = logExportPrivateDir(input.privateDir);
  const privatePath: string = privateDir + '/' + fileName;

  if (input.pick.state === LogExportPickState.CANCELLED) {
    return {
      outcome: LogExportOutcome.CANCELLED,
      destination: LogExportDestination.NONE,
      fallback: LogExportFallback.NONE,
      directory: '',
      path: '',
      messageKey: 'ui_export_cancelled',
      reason: ''
    };
  }

  if (pickUsable(input.pick, input.writeError)) {
    return {
      outcome: LogExportOutcome.EXPORTED_PICKED,
      destination: LogExportDestination.PICKED,
      fallback: LogExportFallback.NONE,
      directory: parentOfUri(input.pick.uri),
      path: input.pick.uri,
      messageKey: 'ui_exported',
      reason: ''
    };
  }

  const fallback: LogExportFallback = classifyFallback(input.pick, input.writeError);
  const reason: string = fallbackReason(fallback, input.pick, input.writeError);
  if (input.privateDir.length === 0) {
    return {
      outcome: LogExportOutcome.FAILED,
      destination: LogExportDestination.NONE,
      fallback: LogExportFallback.NO_PRIVATE_DIR,
      directory: '',
      path: '',
      messageKey: 'ui_export_failed',
      reason: logExportFallbackName(fallback) + (reason.length > 0 ? ': ' + reason : '')
        + '; no private fallback directory'
    };
  }
  return {
    outcome: LogExportOutcome.EXPORTED_PRIVATE,
    destination: LogExportDestination.PRIVATE,
    fallback: fallback,
    directory: privateDir,
    path: privatePath,
    messageKey: fallbackMessageKey(fallback),
    reason: reason
  };
}

/** URI 的父路径（只给 hilog 自证串用；URI 不是文件系统路径，别拿它去 open）。 */
export function parentOfUri(uri: string): string {
  const cut: number = uri.lastIndexOf('/');
  return cut > 0 ? uri.substring(0, cut) : '';
}

/**
 * 结局 ＋ 计数 → 界面文案的键与参数。
 *
 * 成功用的是三条占位符的 `ui_exported`：记录数、字节数、完整位置（选中位置时是 URI）。
 * 降级那三条同理带上完整路径，**并额外说清「外部拿不到」**，所以界面上两种结局一眼可辨。
 * `byteLength` 必须是**落盘后的真实字节数**（外部 `ls -l` 会看到的那个数），不是文本长度。
 */
export function logExportMessage(plan: LogExportPlan, recordCount: number, byteLength: number): LogExportMessage {
  if (plan.outcome === LogExportOutcome.CANCELLED) {
    return { key: plan.messageKey, args: ['', '', '', ''] };
  }
  if (plan.outcome === LogExportOutcome.FAILED) {
    return { key: plan.messageKey, args: [plan.reason, '', '', ''] };
  }
  return { key: plan.messageKey, args: [recordCount, byteLength, plan.path, plan.reason] };
}

/* ------------------------------------------------------------------ *
 * 自证用的名字与一行串（进 hilog 的那条必须能读出输入与输出）
 * ------------------------------------------------------------------ */

export function logExportPickStateName(state: LogExportPickState): string {
  if (state === LogExportPickState.PICKED) {
    return 'picked';
  }
  if (state === LogExportPickState.CANCELLED) {
    return 'cancelled';
  }
  if (state === LogExportPickState.UNSUPPORTED) {
    return 'unsupported';
  }
  return 'pick-failed';
}

export function logExportDestinationName(destination: LogExportDestination): string {
  if (destination === LogExportDestination.PICKED) {
    return 'picked';
  }
  if (destination === LogExportDestination.PRIVATE) {
    return 'private';
  }
  return 'none';
}

export function logExportOutcomeName(outcome: LogExportOutcome): string {
  if (outcome === LogExportOutcome.EXPORTED_PICKED) {
    return 'exported-picked';
  }
  if (outcome === LogExportOutcome.EXPORTED_PRIVATE) {
    return 'exported-private';
  }
  if (outcome === LogExportOutcome.CANCELLED) {
    return 'cancelled';
  }
  return 'failed';
}

export function logExportFallbackName(fallback: LogExportFallback): string {
  if (fallback === LogExportFallback.UNSUPPORTED) {
    return 'unsupported';
  }
  if (fallback === LogExportFallback.PICK_FAILED) {
    return 'pick-failed';
  }
  if (fallback === LogExportFallback.WRITE_FAILED) {
    return 'write-failed';
  }
  if (fallback === LogExportFallback.NO_PRIVATE_DIR) {
    return 'no-private-dir';
  }
  return 'none';
}

/** 一条能进 hilog 的自证行：决策的输入（在调用点的日志里）与输出都在里面。 */
export function describeLogExportPlan(plan: LogExportPlan): string {
  return 'outcome=' + logExportOutcomeName(plan.outcome)
    + ' destination=' + logExportDestinationName(plan.destination)
    + ' fallback=' + logExportFallbackName(plan.fallback)
    + ' dir=' + plan.directory
    + ' path=' + plan.path;
}
