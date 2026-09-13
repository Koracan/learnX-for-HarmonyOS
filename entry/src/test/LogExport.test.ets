/*
 * core.LogExportTarget 单测：导出落点怎么选、什么时候降级。
 *
 * 本文件覆盖的是**纯决策**（core/log/LogExportTarget.ets），所以不碰任何平台 API：
 * 公共目录的探测结果、权限授予状态、宿主私有目录、时刻都是入参，四条结局
 * （成功 / 权限被拒 / 平台不支持 / 用户取消）在本地就能钉住 —— 设备上真正发生的是
 * "这些入参从哪来"（core/log/LogExport.ets），那一层由 .scratch/ui-optimize/evidence
 * 里的设备侧证据（hdc ls -l + hdc file recv）负责，不是单测的判据。
 *
 * 口径与 FileDownload / LogFormat 同族：平台句柄不进单测，注入的替身进。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  LogExportDestination, LogExportDirState, LogExportFallback, LogExportMessage, LogExportOutcome,
  LogExportPermission, LogExportPlan, LogExportPlanInput, LogExportPublicDir,
  classifyFallback, describeLogExportPlan, logExportFileName, logExportMessage, logExportPrivateDir,
  planLogExport, publicDirUsable
} from '../main/ets/core/log/LogExportTarget';

const TIMESTAMP: number = 1770000000000;
const FILE_NAME: string = 'learnOH-1770000000000.log';
const PUBLIC_DIR: string = '/storage/Users/currentUser/Download';
const FILES_DIR: string = '/data/storage/el2/base/haps/entry/files';
const PLATFORM_ERROR: string = '[801] Capability not supported';

/** 探测结果构造器（省掉每个用例都写全三个字段）。 */
function dir(state: LogExportDirState, path: string, error: string): LogExportPublicDir {
  return { state: state, path: path, error: error };
}

function input(publicDir: LogExportPublicDir, permission: LogExportPermission,
  privateDir: string, cancelled: boolean): LogExportPlanInput {
  return { publicDir: publicDir, permission: permission, privateDir: privateDir, timestamp: TIMESTAMP, cancelled: cancelled };
}

export default function logExportTest() {
  describe('core.LogExportTarget', () => {
    it('names the exported file after the timestamp', 0, () => {
      expect(logExportFileName(TIMESTAMP)).assertEqual(FILE_NAME);
      expect(logExportPrivateDir(FILES_DIR)).assertEqual(FILES_DIR + '/logs');
    });

    it('exports to the public download directory when it is writable and granted', 0, () => {
      const plan: LogExportPlan = planLogExport(
        input(dir(LogExportDirState.AVAILABLE, PUBLIC_DIR, ''), LogExportPermission.GRANTED, FILES_DIR, false));
      expect(plan.outcome).assertEqual(LogExportOutcome.EXPORTED_PUBLIC);
      expect(plan.destination).assertEqual(LogExportDestination.PUBLIC);
      expect(plan.fallback).assertEqual(LogExportFallback.NONE);
      expect(plan.directory).assertEqual(PUBLIC_DIR);
      expect(plan.path).assertEqual(PUBLIC_DIR + '/' + FILE_NAME);
      expect(plan.messageKey).assertEqual('ui_exported');
      expect(plan.reason).assertEqual('');
      // 成功提示仍旧给**确切路径**（ticket 18 的三占位符文案：条数 / 字节数 / 路径）。
      const message: LogExportMessage = logExportMessage(plan, 12, 3456);
      expect(message.key).assertEqual('ui_exported');
      expect(message.args[0]).assertEqual(12);
      expect(message.args[1]).assertEqual(3456);
      expect(message.args[2]).assertEqual(PUBLIC_DIR + '/' + FILE_NAME);
    });

    it('only skips the public directory when the permission is a real user denial', 0, () => {
      const available: LogExportPublicDir = dir(LogExportDirState.AVAILABLE, PUBLIC_DIR, '');
      expect(publicDirUsable(available, LogExportPermission.GRANTED)).assertTrue();
      // 平台没受理这次申请 ≠ 用户拒绝：它只说明"能不能写"要靠写一次来回答。
      expect(publicDirUsable(available, LogExportPermission.NOT_REQUESTABLE)).assertTrue();
      // 用户明确挡下的两条必须尊重：不许再往公共目录写。
      expect(publicDirUsable(available, LogExportPermission.DENIED)).assertFalse();
      expect(publicDirUsable(available, LogExportPermission.BLOCKED)).assertFalse();
      // 路径为空同样不算可用（探测拿到了状态却没拿到路径）。
      expect(publicDirUsable(dir(LogExportDirState.AVAILABLE, '', ''), LogExportPermission.GRANTED)).assertFalse();
      // 目录状态本身不是 available 时，权限再好也没用。
      expect(publicDirUsable(dir(LogExportDirState.UNSUPPORTED, PUBLIC_DIR, ''), LogExportPermission.GRANTED))
        .assertFalse();
    });

    it('attempts the public directory when the platform did not process the request', 0, () => {
      const plan: LogExportPlan = planLogExport(
        input(dir(LogExportDirState.AVAILABLE, PUBLIC_DIR, ''), LogExportPermission.NOT_REQUESTABLE, FILES_DIR, false));
      expect(plan.outcome).assertEqual(LogExportOutcome.EXPORTED_PUBLIC);
      expect(plan.destination).assertEqual(LogExportDestination.PUBLIC);
      expect(plan.path).assertEqual(PUBLIC_DIR + '/' + FILE_NAME);
      // 试写失败后设备层会带着 UNWRITABLE 重新决策一次：那时才降级。
      expect(classifyFallback(dir(LogExportDirState.UNWRITABLE, PUBLIC_DIR, ''), LogExportPermission.NOT_REQUESTABLE))
        .assertEqual(LogExportFallback.UNWRITABLE);
    });

    it('falls back to the private directory with an explicit reason when permission is denied', 0, () => {
      const plan: LogExportPlan = planLogExport(
        input(dir(LogExportDirState.NEEDS_PERMISSION, '', ''), LogExportPermission.DENIED, FILES_DIR, false));
      expect(plan.outcome).assertEqual(LogExportOutcome.EXPORTED_PRIVATE);
      expect(plan.destination).assertEqual(LogExportDestination.PRIVATE);
      expect(plan.fallback).assertEqual(LogExportFallback.PERMISSION_DENIED);
      // 降级落点与旧口径一致：filesDir/logs/learnOH-<时间戳>.log。
      expect(plan.directory).assertEqual(FILES_DIR + '/logs');
      expect(plan.path).assertEqual(FILES_DIR + '/logs/' + FILE_NAME);
      // **两种结局的文案必须不同**：这一条说的是"外部拿不到"。
      expect(plan.messageKey).assertEqual('ui_export_private_denied');
      const message: LogExportMessage = logExportMessage(plan, 12, 3456);
      expect(message.key).assertEqual(plan.messageKey);
      expect(message.args[2]).assertEqual(FILES_DIR + '/logs/' + FILE_NAME);
    });

    it('distinguishes a permanent denial from an ordinary one', 0, () => {
      const plan: LogExportPlan = planLogExport(
        input(dir(LogExportDirState.NEEDS_PERMISSION, '', ''), LogExportPermission.BLOCKED, FILES_DIR, false));
      expect(plan.fallback).assertEqual(LogExportFallback.PERMISSION_BLOCKED);
      // 永久拒绝要告诉用户去系统设置里开，所以不能复用"被拒绝"那条文案。
      expect(plan.messageKey).assertEqual('ui_export_private_blocked');
    });

    it('reports an unsupported platform on its own, with the platform error carried through', 0, () => {
      const plan: LogExportPlan = planLogExport(
        input(dir(LogExportDirState.UNSUPPORTED, '', PLATFORM_ERROR), LogExportPermission.GRANTED, FILES_DIR, false));
      expect(plan.outcome).assertEqual(LogExportOutcome.EXPORTED_PRIVATE);
      expect(plan.fallback).assertEqual(LogExportFallback.UNSUPPORTED);
      expect(plan.messageKey).assertEqual('ui_export_private_unsupported');
      expect(plan.reason).assertEqual(PLATFORM_ERROR);
      const message: LogExportMessage = logExportMessage(plan, 3, 100);
      expect(message.args[3]).assertEqual(PLATFORM_ERROR);
    });

    it('reports an unwritable public directory separately from an unsupported platform', 0, () => {
      const plan: LogExportPlan = planLogExport(
        input(dir(LogExportDirState.UNWRITABLE, PUBLIC_DIR, 'read-only file system'),
          LogExportPermission.GRANTED, FILES_DIR, false));
      expect(plan.fallback).assertEqual(LogExportFallback.UNWRITABLE);
      expect(plan.messageKey).assertEqual('ui_export_private_unwritable');
      // 权限与目录两件事都坏掉时，先报权限（用户能自己做的那一件）。
      expect(classifyFallback(dir(LogExportDirState.UNWRITABLE, PUBLIC_DIR, ''), LogExportPermission.DENIED))
        .assertEqual(LogExportFallback.PERMISSION_DENIED);
    });

    it('treats a user cancellation as neither success nor failure', 0, () => {
      const plan: LogExportPlan = planLogExport(
        input(dir(LogExportDirState.AVAILABLE, PUBLIC_DIR, ''), LogExportPermission.GRANTED, FILES_DIR, true));
      expect(plan.outcome).assertEqual(LogExportOutcome.CANCELLED);
      expect(plan.destination).assertEqual(LogExportDestination.NONE);
      expect(plan.path).assertEqual('');
      expect(plan.directory).assertEqual('');
      expect(plan.messageKey).assertEqual('ui_export_cancelled');
      const message: LogExportMessage = logExportMessage(plan, 0, 0);
      expect(message.key).assertEqual('ui_export_cancelled');
      expect(message.args.length).assertEqual(4);
    });

    it('fails outright when there is no private fallback either', 0, () => {
      const plan: LogExportPlan = planLogExport(
        input(dir(LogExportDirState.UNSUPPORTED, '', PLATFORM_ERROR), LogExportPermission.GRANTED, '', false));
      expect(plan.outcome).assertEqual(LogExportOutcome.FAILED);
      expect(plan.destination).assertEqual(LogExportDestination.NONE);
      expect(plan.fallback).assertEqual(LogExportFallback.NO_PRIVATE_DIR);
      expect(plan.messageKey).assertEqual('ui_export_failed');
      const message: LogExportMessage = logExportMessage(plan, 0, 0);
      expect(message.key).assertEqual('ui_export_failed');
      // ui_export_failed 的 {0} 是原因，必须非空 —— 不许出现"导出失败："后面什么都没有。
      const reason: string | number = message.args[0];
      expect(String(reason).length > 0).assertTrue();
    });

    it('describes the decision in one line for hilog', 0, () => {
      const plan: LogExportPlan = planLogExport(
        input(dir(LogExportDirState.AVAILABLE, PUBLIC_DIR, ''), LogExportPermission.GRANTED, FILES_DIR, false));
      const line: string = describeLogExportPlan(plan);
      expect(line.indexOf('outcome=exported-public') >= 0).assertTrue();
      expect(line.indexOf('destination=public') >= 0).assertTrue();
      expect(line.indexOf('path=' + PUBLIC_DIR + '/' + FILE_NAME) >= 0).assertTrue();
    });
  });
}
