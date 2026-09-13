/*
 * 「交给系统打开方式」的纯规则单测。
 *
 * 钉两件**输入 → 输出**：按钮的可用判定、want 的参数构造。**不**断言"调用了哪个系统 API"——
 * 那一步（`startAbility`）只有设备能给答案，主机侧断言一个桩等于什么都没验。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  canOpenExternally, EXTERNAL_OPEN_ACTION, EXTERNAL_OPEN_READ_FLAG, ExternalOpenIntent,
  externalOpenIntent, hasLocalCopy
} from '../main/ets/domain/files/ExternalOpen';

export default function externalOpenTest() {
  describe('ExternalOpen', () => {
    it('treatsOnlyNonBlankPathsAsALocalCopy', 0, () => {
      expect(hasLocalCopy('/data/storage/el2/base/cache/learnX-files/c/a.pdf')).assertTrue();
      expect(hasLocalCopy('')).assertFalse();
      expect(hasLocalCopy('   ')).assertFalse();
      expect(hasLocalCopy(undefined)).assertFalse();
    });

    it('offersOpenOnlyForAFinishedDownloadWithALocalCopy', 0, () => {
      // 参考实现的判据是 `!error && path`：两者缺一不可（失败态即便残留路径也不能点）。
      expect(canOpenExternally(true, '/tmp/a.zip')).assertTrue();
      expect(canOpenExternally(false, '/tmp/a.zip')).assertFalse();
      expect(canOpenExternally(true, '')).assertFalse();
      expect(canOpenExternally(false, '')).assertFalse();
    });

    it('buildsAViewDataIntentWithoutTheBrowserEntity', 0, () => {
      const intent: ExternalOpenIntent =
        externalOpenIntent('file://com.koracan.learnOH/data/storage/el2/base/cache/learnX-files/c/a.zip',
          'general.file');
      expect(intent.action).assertEqual(EXTERNAL_OPEN_ACTION);
      expect(intent.action).assertEqual('ohos.want.action.viewData');
      expect(intent.type).assertEqual('general.file');
      expect(intent.flags).assertEqual(EXTERNAL_OPEN_READ_FLAG);
      // 本地文件交给"能读它的应用"，而不是交给浏览器。
      expect(intent.entities.length).assertEqual(0);
    });

    it('trimsTheTypeAndReportsAnEmptyOne', 0, () => {
      expect(externalOpenIntent('file:///a', '  general.image  ').type).assertEqual('general.image');
      // 空 type 如实交出去（调用方据此决定不放进 Want），不在这里编一个默认值。
      expect(externalOpenIntent('file:///a', '').type).assertEqual('');
      expect(externalOpenIntent('file:///a', undefined).type).assertEqual('');
    });

    it('keepsTheUriVerbatim', 0, () => {
      // uri 的转义由平台按路径生成，这里不做二次加工（中文与空格必须原样带到接收方）。
      const uri: string = 'file://com.koracan.learnOH/data/storage/el2/base/cache/learnX-files/%E8%AF%BE%E7%A8%8B/a%20b.zip';
      expect(externalOpenIntent(uri, 'general.file').uri).assertEqual(uri);
    });
  });
}
