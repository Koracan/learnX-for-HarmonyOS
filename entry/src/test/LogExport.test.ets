/*
 * core.LogExportTarget 单测：导出落点怎么选、什么时候降级。
 *
 * 本文件覆盖的是**纯决策**（core/log/LogExportTarget.ets），所以不碰任何平台 API：
 * 选择器这一趟的结果（选到位置 / 用户取消 / 平台不支持 / 平台报错）、写盘失败原因、
 * 宿主私有目录、时刻都是入参，四条结局在本地就能钉住 —— 设备上真正发生的是
 * 「这些入参从哪来」（core/log/LogExport.ets），那一层由 .scratch/ui-optimize/evidence
 * 里的设备侧证据（hdc ls -l + hdc file recv）负责，不是单测的判据。
 *
 * 口径与 FileDownload / LogFormat 同族：平台句柄不进单测，注入的替身进。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  LogExportDestination, LogExportFallback, LogExportMessage, LogExportOutcome, LogExportPickResult,
  LogExportPickState, LogExportPlan, LogExportPlanInput, USER_CANCELLED_CODES,
  classifyPickError, classifyPickedUris, describeLogExportPlan, logExportFileName, logExportMessage,
  logExportPrivateDir, parentOfUri, pickUsable, planLogExport
} from '../main/ets/core/log/LogExportTarget';

const TIMESTAMP: number = 1770000000000;
const FILE_NAME: string = 'learnOH-1770000000000.log';
const PICKED_URI: string = 'file://docs/storage/Users/currentUser/Download/' + FILE_NAME;
const PICKED_DIR: string = 'file://docs/storage/Users/currentUser/Download';
const FILES_DIR: string = '/data/storage/el2/base/haps/entry/files';
const PRIVATE_PATH: string = FILES_DIR + '/logs/' + FILE_NAME;
const PLATFORM_ERROR: string = '[13900001] Operation not permitted';

/** 选择结果构造器（省掉每个用例都写全三个字段）。 */
function pick(state: LogExportPickState, uri: string, error: string): LogExportPickResult {
  return { state: state, uri: uri, error: error };
}

function input(pickResult: LogExportPickResult, writeError: string, privateDir: string): LogExportPlanInput {
  return { pick: pickResult, writeError: writeError, privateDir: privateDir, timestamp: TIMESTAMP };
}

export default function logExportTest() {
  describe('core.LogExportTarget', () => {
    it('names the exported file after the timestamp', 0, () => {
      expect(logExportFileName(TIMESTAMP)).assertEqual(FILE_NAME);
      expect(logExportPrivateDir(FILES_DIR)).assertEqual(FILES_DIR + '/logs');
      // URI 的父路径只给 hilog 自证串用：它看着像路径，但不是文件系统路径。
      expect(parentOfUri(PICKED_URI)).assertEqual(PICKED_DIR);
      expect(parentOfUri(FILE_NAME)).assertEqual('');
    });

    it('exports to the location the user picked in the system picker', 0, () => {
      const plan: LogExportPlan = planLogExport(
        input(pick(LogExportPickState.PICKED, PICKED_URI, ''), '', FILES_DIR));
      expect(plan.outcome).assertEqual(LogExportOutcome.EXPORTED_PICKED);
      expect(plan.destination).assertEqual(LogExportDestination.PICKED);
      expect(plan.fallback).assertEqual(LogExportFallback.NONE);
      expect(plan.directory).assertEqual(PICKED_DIR);
      expect(plan.path).assertEqual(PICKED_URI);
      expect(plan.messageKey).assertEqual('ui_exported');
      expect(plan.reason).assertEqual('');
      // 成功提示仍旧给**确切位置**（三占位符文案：条数 / 字节数 / 位置）。
      const message: LogExportMessage = logExportMessage(plan, 12, 3456);
      expect(message.key).assertEqual('ui_exported');
      expect(message.args[0]).assertEqual(12);
      expect(message.args[1]).assertEqual(3456);
      expect(message.args[2]).assertEqual(PICKED_URI);
    });

    it('reads an empty uri list from the picker as a user cancellation', 0, () => {
      // 取消在实测里就长这样：选择器被关掉，返回空列表。
      expect(classifyPickedUris([])).assertEqual(LogExportPickState.CANCELLED);
      expect(classifyPickedUris(undefined)).assertEqual(LogExportPickState.CANCELLED);
      expect(classifyPickedUris([''])).assertEqual(LogExportPickState.CANCELLED);
      expect(classifyPickedUris([PICKED_URI])).assertEqual(LogExportPickState.PICKED);
    });

    it('treats a user cancellation as neither success nor failure', 0, () => {
      const cancelled: LogExportPickResult = pick(LogExportPickState.CANCELLED, '', '');
      const plan: LogExportPlan = planLogExport(input(cancelled, '', FILES_DIR));
      expect(plan.outcome).assertEqual(LogExportOutcome.CANCELLED);
      expect(plan.destination).assertEqual(LogExportDestination.NONE);
      expect(plan.path).assertEqual('');
      expect(plan.directory).assertEqual('');
      expect(plan.messageKey).assertEqual('ui_export_cancelled');
      // 取消之后绝不能再往私有目录写一份（用户没要这个文件）。
      expect(pickUsable(cancelled, '')).assertFalse();
      const message: LogExportMessage = logExportMessage(plan, 0, 0);
      expect(message.key).assertEqual('ui_export_cancelled');
      expect(message.args.length).assertEqual(4);
    });

    it('classifies 801 as unsupported and every other code as a platform failure', 0, () => {
      expect(classifyPickError(801)).assertEqual(LogExportPickState.UNSUPPORTED);
      expect(classifyPickError(13900001)).assertEqual(LogExportPickState.FAILED);
      expect(classifyPickError(0)).assertEqual(LogExportPickState.FAILED);
    });

    it('treats every code in the user-cancellation table as a cancellation', 0, () => {
      // 表当前是空的（取消走「返回空列表」那条），所以这个循环现在不转；
      // 一旦实测到取消会 reject、把码补进表里，这条用例立刻开始覆盖它。
      for (const code of USER_CANCELLED_CODES) {
        expect(classifyPickError(code)).assertEqual(LogExportPickState.CANCELLED);
      }
      // 801 永远只能是「不支持」，不能被登记成取消。
      expect(USER_CANCELLED_CODES.indexOf(801) < 0).assertTrue();
    });

    it('falls back to the private directory when the platform has no picker', 0, () => {
      const plan: LogExportPlan = planLogExport(
        input(pick(LogExportPickState.UNSUPPORTED, '', PLATFORM_ERROR), '', FILES_DIR));
      expect(plan.outcome).assertEqual(LogExportOutcome.EXPORTED_PRIVATE);
      expect(plan.destination).assertEqual(LogExportDestination.PRIVATE);
      expect(plan.fallback).assertEqual(LogExportFallback.UNSUPPORTED);
      // 降级落点与旧口径一致：filesDir/logs/learnOH-<时间戳>.log。
      expect(plan.directory).assertEqual(FILES_DIR + '/logs');
      expect(plan.path).assertEqual(PRIVATE_PATH);
      expect(plan.messageKey).assertEqual('ui_export_private_unsupported');
      expect(plan.reason).assertEqual(PLATFORM_ERROR);
      const message: LogExportMessage = logExportMessage(plan, 3, 100);
      expect(message.args[2]).assertEqual(PRIVATE_PATH);
      expect(message.args[3]).assertEqual(PLATFORM_ERROR);
    });

    it('falls back when the picker itself failed, carrying the platform error', 0, () => {
      const plan: LogExportPlan = planLogExport(
        input(pick(LogExportPickState.FAILED, '', PLATFORM_ERROR), '', FILES_DIR));
      expect(plan.outcome).assertEqual(LogExportOutcome.EXPORTED_PRIVATE);
      expect(plan.fallback).assertEqual(LogExportFallback.PICK_FAILED);
      expect(plan.messageKey).assertEqual('ui_export_private_pick_failed');
      expect(plan.reason).assertEqual(PLATFORM_ERROR);
      // 平台连一句话都没给时也要有非空原因，不许出现「（…（））」这种空括号。
      const bare: LogExportPlan = planLogExport(
        input(pick(LogExportPickState.FAILED, '', ''), '', FILES_DIR));
      expect(bare.reason.length > 0).assertTrue();
    });

    it('falls back when the picked location cannot be written, with the write error', 0, () => {
      const picked: LogExportPickResult = pick(LogExportPickState.PICKED, PICKED_URI, '');
      const writeError: string = 'picked=' + PICKED_URI + ' write=' + PLATFORM_ERROR;
      expect(pickUsable(picked, '')).assertTrue();
      // 同一个位置写失败之后不再重试它：带着 writeError 重新决策，直接降级。
      expect(pickUsable(picked, writeError)).assertFalse();
      const plan: LogExportPlan = planLogExport(input(picked, writeError, FILES_DIR));
      expect(plan.outcome).assertEqual(LogExportOutcome.EXPORTED_PRIVATE);
      expect(plan.fallback).assertEqual(LogExportFallback.WRITE_FAILED);
      expect(plan.messageKey).assertEqual('ui_export_private_write_failed');
      expect(plan.reason).assertEqual(writeError);
      expect(plan.path).assertEqual(PRIVATE_PATH);
      // 状态是「选中」但 URI 为空同样不算可用（拿到了状态却没拿到位置）。
      expect(pickUsable(pick(LogExportPickState.PICKED, '', ''), '')).assertFalse();
    });

    it('fails outright when there is no private fallback either', 0, () => {
      const plan: LogExportPlan = planLogExport(
        input(pick(LogExportPickState.UNSUPPORTED, '', PLATFORM_ERROR), '', ''));
      expect(plan.outcome).assertEqual(LogExportOutcome.FAILED);
      expect(plan.destination).assertEqual(LogExportDestination.NONE);
      expect(plan.fallback).assertEqual(LogExportFallback.NO_PRIVATE_DIR);
      expect(plan.messageKey).assertEqual('ui_export_failed');
      const message: LogExportMessage = logExportMessage(plan, 0, 0);
      expect(message.key).assertEqual('ui_export_failed');
      // ui_export_failed 的 {0} 是原因，必须非空 —— 不许出现「导出失败：」后面什么都没有。
      const reason: string | number = message.args[0];
      expect(String(reason).length > 0).assertTrue();
    });

    it('describes the decision in one line for hilog', 0, () => {
      const plan: LogExportPlan = planLogExport(
        input(pick(LogExportPickState.PICKED, PICKED_URI, ''), '', FILES_DIR));
      const line: string = describeLogExportPlan(plan);
      expect(line.indexOf('outcome=exported-picked') >= 0).assertTrue();
      expect(line.indexOf('destination=picked') >= 0).assertTrue();
      expect(line.indexOf('path=' + PICKED_URI) >= 0).assertTrue();
    });
  });
}
