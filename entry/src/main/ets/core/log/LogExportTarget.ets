/*
 * 日志导出的**目标选择与降级** —— 纯逻辑，不碰任何平台 API。
 *
 * 本轮把导出的落点从应用私有沙箱（`context.filesDir`）移到用户拿得到的公共目录。
 * "公共目录能不能用"取决于三件只有在设备上才知道的事：运行时权限、平台是否支持这个能力、
 * 目录当前是否可写。把这三件事压缩成**输入**（`LogExportPlanInput`），把"写到哪 + 现在是什么
 * 结局"压缩成**输出**（`LogExportPlan`），成功 / 权限被拒 / 平台不支持 / 用户取消四条分支
 * 就能在 Local Test 里离线钉住，不需要设备，也不需要平台 API —— 设备侧（探测公共目录、
 * 申请权限、真实写盘）在 `LogExport.ets`。
 *
 * 降级是**显式**的：公开目录不可用时绝不假装成功 —— 结局类别会变成"已导出到应用私有目录"
 * 并带上是哪一种原因，界面文案与 hilog 自证串都因此能把两种结局分开。
 */

import { I18nKey } from '../i18n/I18nKeys';

/** 公共目录的探测结果。 */
export enum LogExportDirState {
  /** 拿到路径，且目录存在。 */
  AVAILABLE = 0,
  /** 平台支持这条路，但要先拿到运行时权限才能拿到（并使用）它。 */
  NEEDS_PERMISSION = 1,
  /** 平台不支持这个能力（例如接口抛 801）。 */
  UNSUPPORTED = 2,
  /** 平台支持，但目录不存在 / 不可写。 */
  UNWRITABLE = 3
}

/** 运行时权限的实际授予状态。 */
export enum LogExportPermission {
  /** 已授予（也用于"这条路线根本不需要权限"）。 */
  GRANTED = 0,
  /** 这一次被用户拒绝（权限弹窗出现过）。 */
  DENIED = 1,
  /** 被永久拒绝 / 策略拦下：弹窗根本没出现，只能去系统设置里开。 */
  BLOCKED = 2,
  /**
   * 这次申请**根本没被受理**（平台回 authResults=2「请求无效」，或申请本身抛异常）。
   *
   * 与"被拒绝"是两件事：拒绝是用户的选择，必须尊重（不许再往公共目录写）；
   * 不受理是**平台条件**（例如目录权限在目标 API 上已不再需要/不再可申请），
   * 这时不做任何假设，直接**试着写**——写成功就是真的导出到了公共目录（有外部证据），
   * 写失败就按"公共目录不可写"降级，并把平台原话写进原因。
   */
  NOT_REQUESTABLE = 3
}

/** 文件最终落在哪。 */
export enum LogExportDestination {
  PUBLIC = 0,
  PRIVATE = 1,
  /** 什么都没写。 */
  NONE = 2
}

/** 结局类别（界面文案的大类）。 */
export enum LogExportOutcome {
  /** 写进了公共目录，用户能在应用外拿到。 */
  EXPORTED_PUBLIC = 0,
  /** 降级：写进了应用私有目录，应用外拿不到。 */
  EXPORTED_PRIVATE = 1,
  /** 用户主动取消（走系统文件选择器时才会有）。 */
  CANCELLED = 2,
  /** 没写任何文件。 */
  FAILED = 3
}

/** 落到私有目录（或彻底失败）的原因。 */
export enum LogExportFallback {
  NONE = 0,
  PERMISSION_DENIED = 1,
  PERMISSION_BLOCKED = 2,
  UNSUPPORTED = 3,
  UNWRITABLE = 4,
  NO_PRIVATE_DIR = 5
}

/** 公共目录探测结果（设备层产出，纯逻辑只消费）。 */
export interface LogExportPublicDir {
  state: LogExportDirState;
  /** `state = AVAILABLE` 时的公共目录绝对路径。 */
  path: string;
  /** 探测失败时的平台错误码/消息；只进 hilog 自证串与文案里的原因要点。 */
  error: string;
}

/** 决策的输入：三件设备上的事 + 宿主私有目录 + 时刻。 */
export interface LogExportPlanInput {
  publicDir: LogExportPublicDir;
  permission: LogExportPermission;
  /** 兜底用的应用私有目录（`context.filesDir`）；空串 = 没有兜底可用。 */
  privateDir: string;
  /** 导出时刻，决定文件名。 */
  timestamp: number;
  /** 用户在选择器里取消（只有 picker 路线才会是 true）。 */
  cancelled: boolean;
}

/** 决策的输出：写到哪 + 结局类别 + 界面要用的路径。 */
export interface LogExportPlan {
  outcome: LogExportOutcome;
  destination: LogExportDestination;
  fallback: LogExportFallback;
  /** 写入目录；`destination = NONE` 时是空串。 */
  directory: string;
  /** 完整落盘路径 —— 写盘与界面文案共用同一个串。 */
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

/** 文件名 `learnOH-<时间戳>.log`（两个落点共用同一个命名）。 */
export function logExportFileName(timestamp: number): string {
  return 'learnOH-' + timestamp + '.log';
}

/**
 * 公共目录是否值得一试：拿到路径 + 目录存在，且权限**不是**明确被用户挡下的。
 *
 * GRANTED 当然放行；NOT_REQUESTABLE（平台不受理）也放行 —— 那条路到底行不行，
 * 只能由"真的去写一次"来回答，写不进去会走 UNWRITABLE 降级分支。
 * DENIED / BLOCKED 是用户的选择或明确的策略状态，不放行。
 */
export function publicDirUsable(publicDir: LogExportPublicDir, permission: LogExportPermission): boolean {
  if (publicDir.state !== LogExportDirState.AVAILABLE || publicDir.path.length === 0) {
    return false;
  }
  return permission === LogExportPermission.GRANTED || permission === LogExportPermission.NOT_REQUESTABLE;
}

/** 降级原因分类（顺序即优先级：先看权限，再看目录）。 */
export function classifyFallback(publicDir: LogExportPublicDir, permission: LogExportPermission): LogExportFallback {
  if (permission === LogExportPermission.DENIED) {
    return LogExportFallback.PERMISSION_DENIED;
  }
  if (permission === LogExportPermission.BLOCKED) {
    return LogExportFallback.PERMISSION_BLOCKED;
  }
  if (publicDir.state === LogExportDirState.UNSUPPORTED) {
    return LogExportFallback.UNSUPPORTED;
  }
  return LogExportFallback.UNWRITABLE;
}

/** 降级结局对应的文案键。 */
export function fallbackMessageKey(fallback: LogExportFallback): I18nKey {
  if (fallback === LogExportFallback.PERMISSION_DENIED) {
    return 'ui_export_private_denied';
  }
  if (fallback === LogExportFallback.PERMISSION_BLOCKED) {
    return 'ui_export_private_blocked';
  }
  if (fallback === LogExportFallback.UNSUPPORTED) {
    return 'ui_export_private_unsupported';
  }
  return 'ui_export_private_unwritable';
}

/** 文案里的原因要点：权限那两支交给文案本身说清，目录那两支把平台原话带上。 */
function fallbackReason(fallback: LogExportFallback, publicDir: LogExportPublicDir): string {
  if (fallback === LogExportFallback.UNSUPPORTED || fallback === LogExportFallback.UNWRITABLE) {
    return publicDir.error.length > 0 ? publicDir.error : 'public directory unusable';
  }
  return '';
}

/** 把探测结果与权限状态压成"写到哪 + 现在是什么结局"。 */
export function planLogExport(input: LogExportPlanInput): LogExportPlan {
  const fileName: string = logExportFileName(input.timestamp);
  const privateDir: string = logExportPrivateDir(input.privateDir);
  const privatePath: string = privateDir + '/' + fileName;

  if (input.cancelled) {
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

  if (publicDirUsable(input.publicDir, input.permission)) {
    return {
      outcome: LogExportOutcome.EXPORTED_PUBLIC,
      destination: LogExportDestination.PUBLIC,
      fallback: LogExportFallback.NONE,
      directory: input.publicDir.path,
      path: input.publicDir.path + '/' + fileName,
      messageKey: 'ui_exported',
      reason: ''
    };
  }

  const fallback: LogExportFallback = classifyFallback(input.publicDir, input.permission);
  if (input.privateDir.length === 0) {
    return {
      outcome: LogExportOutcome.FAILED,
      destination: LogExportDestination.NONE,
      fallback: LogExportFallback.NO_PRIVATE_DIR,
      directory: '',
      path: '',
      messageKey: 'ui_export_failed',
      reason: logExportFallbackName(fallback) + (input.publicDir.error.length > 0 ? ': ' + input.publicDir.error : '')
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
    reason: fallbackReason(fallback, input.publicDir)
  };
}

/**
 * 结局 + 计数 → 界面文案的键与参数。
 *
 * 成功（公共目录）用的是 ticket 18 那三条占位符的 `ui_exported`：记录数、字节数、完整路径。
 * 降级那几条同理带上完整路径，**并额外说清"外部拿不到"**，所以界面上两种结局一眼可辨。
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

export function logExportDirStateName(state: LogExportDirState): string {
  if (state === LogExportDirState.AVAILABLE) {
    return 'available';
  }
  if (state === LogExportDirState.NEEDS_PERMISSION) {
    return 'needs-permission';
  }
  if (state === LogExportDirState.UNSUPPORTED) {
    return 'unsupported';
  }
  return 'unwritable';
}

export function logExportPermissionName(permission: LogExportPermission): string {
  if (permission === LogExportPermission.GRANTED) {
    return 'granted';
  }
  if (permission === LogExportPermission.DENIED) {
    return 'denied';
  }
  if (permission === LogExportPermission.BLOCKED) {
    return 'blocked';
  }
  return 'not-requestable';
}

export function logExportDestinationName(destination: LogExportDestination): string {
  if (destination === LogExportDestination.PUBLIC) {
    return 'public';
  }
  if (destination === LogExportDestination.PRIVATE) {
    return 'private';
  }
  return 'none';
}

export function logExportOutcomeName(outcome: LogExportOutcome): string {
  if (outcome === LogExportOutcome.EXPORTED_PUBLIC) {
    return 'exported-public';
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
  if (fallback === LogExportFallback.PERMISSION_DENIED) {
    return 'permission-denied';
  }
  if (fallback === LogExportFallback.PERMISSION_BLOCKED) {
    return 'permission-blocked';
  }
  if (fallback === LogExportFallback.UNSUPPORTED) {
    return 'unsupported';
  }
  if (fallback === LogExportFallback.UNWRITABLE) {
    return 'unwritable';
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
