/*
 * 回到前台时的静默重登单测（纯逻辑，无平台依赖）。
 *
 * 覆盖：闲置判据的两侧边界（阈值、从未进过后台）、动作只发起一次、重登失败只进日志
 * 而不把异常抛回 onForeground。阈值出处见 features/auth/ForegroundReAuth（参考实现
 * App.tsx:796 的 10 分钟）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { SessionRestoreResult } from '../main/ets/data/auth/SessionRestore';
import {
  IDLE_REAUTH_THRESHOLD_MILLIS, reAuthAfterIdle, shouldReAuthAfterIdle
} from '../main/ets/features/auth/ForegroundReAuth';

/** 记录调用次数的重登替身；`fail` 让它 reject（真实实现不抛，但调用方必须扛得住）。 */
class CountingRefresh {
  calls: number = 0;
  private fail: boolean;

  constructor(fail: boolean) {
    this.fail = fail;
  }

  refresh = async (): Promise<SessionRestoreResult> => {
    this.calls++;
    if (this.fail) {
      throw new Error('boom');
    }
    return SessionRestoreResult.noCredentials('stub');
  };
}

function tick(): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, 0);
  });
}

export default function foregroundReAuthTest() {
  describe('features.auth.ForegroundReAuth', () => {
    it('keepsTheReferenceThresholdAndSkipsColdStart', 0, () => {
      // 阈值逐字照参考实现 App.tsx:796 的 10 分钟
      expect(IDLE_REAUTH_THRESHOLD_MILLIS).assertEqual(600000);
      // 从未进过后台（冷启动那次 onForeground）：不发起 —— 冷启动的重登由 AuthStore / 数据路径负责
      expect(shouldReAuthAfterIdle(0, 1000000)).assertFalse();
      // 阈值两侧
      expect(shouldReAuthAfterIdle(1000000, 1000000 + IDLE_REAUTH_THRESHOLD_MILLIS - 1)).assertFalse();
      expect(shouldReAuthAfterIdle(1000000, 1000000 + IDLE_REAUTH_THRESHOLD_MILLIS)).assertTrue();
      expect(shouldReAuthAfterIdle(1000000, 1000000 + 11 * 60 * 1000)).assertTrue();
    });

    it('refreshesOnlyAfterALongEnoughBackground', 0, async () => {
      const short: CountingRefresh = new CountingRefresh(false);
      expect(reAuthAfterIdle(1000000, 1000000 + 5 * 60 * 1000, short.refresh)).assertFalse();
      expect(short.calls).assertEqual(0);

      const long: CountingRefresh = new CountingRefresh(false);
      expect(reAuthAfterIdle(1000000, 1000000 + IDLE_REAUTH_THRESHOLD_MILLIS, long.refresh)).assertTrue();
      expect(long.calls).assertEqual(1);
      // 动作是 fire-and-forget：等一拍让结果落日志
      await tick();
      expect(long.calls).assertEqual(1);
    });

    it('swallowsARefreshFailureInsteadOfThrowingIntoOnForeground', 0, async () => {
      const failing: CountingRefresh = new CountingRefresh(true);
      expect(reAuthAfterIdle(1000000, 1000000 + IDLE_REAUTH_THRESHOLD_MILLIS, failing.refresh)).assertTrue();
      // 失败不许逃逸成未处理的 rejection（onForeground 是同步回调，没人接得住）
      await tick();
      expect(failing.calls).assertEqual(1);
    });
  });
}
