/*
 * 图标目录单测。
 *
 * 这里钉的是**码位表本身**：字形是不是真的从字体里取出来要在设备上看（PUA 码位缺字形时不报错，
 * 只空白 —— 所以截图是字形存在的唯一证据），但"我们抄的码位与参考实现的 glyphmap 一致"
 * 与"码位大于 0xFFFF 时没有被截断"这两条可以在 host 里钉死。
 *
 * 期望值逐条抄自 reference/learnOH-old/node_modules/react-native-vector-icons@10.2.0 的
 * glyphmaps/MaterialCommunityIcons.json 与 MaterialIcons.json（reference/ 被 gitignore，
 * 所以这里写死数值 —— 它同时是"我们抄了哪张表"的可核证据）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AppIcon, IconFamily, IconSpec, iconGlyph, iconSpec } from '../main/ets/ui/icons/IconCatalog';

interface ExpectedGlyph {
  icon: AppIcon;
  name: string;
  family: IconFamily;
  code: number;
}

const EXPECTED: ExpectedGlyph[] = [
  { icon: AppIcon.ATTACHMENT, name: 'attachment', family: IconFamily.MATERIAL_COMMUNITY, code: 0xF0066 },
  { icon: AppIcon.FLAG, name: 'flag', family: IconFamily.MATERIAL_COMMUNITY, code: 0xF023B },
  { icon: AppIcon.CHECKBOX_BLANK_CIRCLE, name: 'checkbox-blank-circle', family: IconFamily.MATERIAL_COMMUNITY, code: 0xF012F },
  { icon: AppIcon.CHECK, name: 'check', family: IconFamily.MATERIAL_COMMUNITY, code: 0xF012C },
  { icon: AppIcon.KEY_VARIANT, name: 'key-variant', family: IconFamily.MATERIAL_COMMUNITY, code: 0xF030B },
  { icon: AppIcon.MEDAL, name: 'medal', family: IconFamily.MATERIAL_COMMUNITY, code: 0xF0987 },
  { icon: AppIcon.NOTIFICATIONS, name: 'notifications', family: IconFamily.MATERIAL, code: 0xE7F4 },
  { icon: AppIcon.EVENT, name: 'event', family: IconFamily.MATERIAL, code: 0xE878 },
  { icon: AppIcon.FOLDER, name: 'folder', family: IconFamily.MATERIAL, code: 0xE2C7 },
  { icon: AppIcon.APPS, name: 'apps', family: IconFamily.MATERIAL, code: 0xE5C3 },
  { icon: AppIcon.SETTINGS, name: 'settings', family: IconFamily.MATERIAL, code: 0xE8B8 },
  { icon: AppIcon.GRADE, name: 'grade', family: IconFamily.MATERIAL, code: 0xE885 },
  { icon: AppIcon.INSERT_DRIVE_FILE, name: 'insert-drive-file', family: IconFamily.MATERIAL, code: 0xE24D },
  { icon: AppIcon.CHECK_CIRCLE, name: 'check-circle', family: IconFamily.MATERIAL, code: 0xE86C },
  { icon: AppIcon.ARROW_BACK, name: 'arrow-back', family: IconFamily.MATERIAL, code: 0xE5C4 },
  { icon: AppIcon.FILE_UPLOAD, name: 'file-upload', family: IconFamily.MATERIAL, code: 0xE2C6 },
  // 收藏 / 归档 / 隐藏课程的滑动操作按钮：参考实现 CardWrapper.tsx 用的两族图标。
  { icon: AppIcon.HEART, name: 'heart', family: IconFamily.MATERIAL_COMMUNITY, code: 0xF02D1 },
  { icon: AppIcon.HEART_OFF, name: 'heart-off', family: IconFamily.MATERIAL_COMMUNITY, code: 0xF0759 },
  { icon: AppIcon.ARCHIVE_ARROW_DOWN, name: 'archive-arrow-down', family: IconFamily.MATERIAL_COMMUNITY, code: 0xF1259 },
  { icon: AppIcon.ARCHIVE_ARROW_UP, name: 'archive-arrow-up', family: IconFamily.MATERIAL_COMMUNITY, code: 0xF125B },
  { icon: AppIcon.VISIBILITY, name: 'visibility', family: IconFamily.MATERIAL, code: 0xE8F4 },
  { icon: AppIcon.VISIBILITY_OFF, name: 'visibility-off', family: IconFamily.MATERIAL, code: 0xE8F5 },
  // 断点分栏：文件详情页头的全屏/退出全屏，参考实现 FileDetail.tsx:110-111。
  { icon: AppIcon.FULLSCREEN, name: 'fullscreen', family: IconFamily.MATERIAL, code: 0xE5D0 },
  { icon: AppIcon.FULLSCREEN_EXIT, name: 'fullscreen-exit', family: IconFamily.MATERIAL, code: 0xE5D1 },
  // 搜索：页头右侧的入口与搜索页的关闭，参考实现 App.tsx:113-121,137-158。
  { icon: AppIcon.SEARCH, name: 'search', family: IconFamily.MATERIAL, code: 0xE8B6 },
  { icon: AppIcon.CLOSE, name: 'close', family: IconFamily.MATERIAL, code: 0xE5CD },
  // 文件详情顶栏与「详情 / 预览」切换：MaterialIcons 的 refresh / share / open-in-new / info
  // 与 MaterialCommunityIcons 的 eye。
  { icon: AppIcon.REFRESH, name: 'refresh', family: IconFamily.MATERIAL, code: 0xE5D5 },
  { icon: AppIcon.SHARE, name: 'share', family: IconFamily.MATERIAL, code: 0xE80D },
  { icon: AppIcon.OPEN_IN_NEW, name: 'open-in-new', family: IconFamily.MATERIAL, code: 0xE89E },
  { icon: AppIcon.PREVIEW, name: 'eye', family: IconFamily.MATERIAL_COMMUNITY, code: 0xF0208 },
  { icon: AppIcon.INFO, name: 'info', family: IconFamily.MATERIAL, code: 0xE88E }
];

export default function iconCatalogTest() {
  describe('ui.icons.IconCatalog', () => {
    it('maps every icon to the reference glyphmap code point and family', 0, () => {
      expect(EXPECTED.length).assertEqual(31);
      for (let i = 0; i < EXPECTED.length; i++) {
        const expected: ExpectedGlyph = EXPECTED[i];
        const spec: IconSpec = iconSpec(expected.icon);
        expect(spec.code).assertEqual(expected.code);
        expect(spec.family).assertEqual(expected.family);
        expect(expected.icon).assertEqual(expected.name);
      }
    });

    it('always yields exactly one code point (never a truncated UTF-16 unit)', 0, () => {
      for (let i = 0; i < EXPECTED.length; i++) {
        const glyph: string = iconGlyph(EXPECTED[i].icon);
        // MCI 的码位在 U+F0000 起的补充私用区 ⇒ UTF-16 是两个码元（代理对）；
        // MaterialIcons 在 BMP 私用区 ⇒ 一个码元。用 fromCharCode 会把前者截断成 'f'，
        // 这一条断言就是这个失败模式的哨兵。
        const expectedUnits: number = EXPECTED[i].code > 0xFFFF ? 2 : 1;
        expect(glyph.length).assertEqual(expectedUnits);
        if (expectedUnits === 2) {
          // 代理对：首码元必须是高位代理（否则就是被截断的 BMP 字符）。
          const lead: number = glyph.charCodeAt(0);
          expect(lead >= 0xD800 && lead <= 0xDBFF).assertTrue();
        } else {
          expect(glyph.charCodeAt(0)).assertEqual(EXPECTED[i].code);
        }
      }
    });

    it('keeps every code point inside a private-use area', 0, () => {
      for (let i = 0; i < EXPECTED.length; i++) {
        const spec: IconSpec = iconSpec(EXPECTED[i].icon);
        // BMP 私用区 U+E000–U+F8FF，或补充私用区 A U+F0000–U+FFFFD。
        const inBmpPua: boolean = spec.code >= 0xE000 && spec.code <= 0xF8FF;
        const inSupplementaryPua: boolean = spec.code >= 0xF0000 && spec.code <= 0xFFFFD;
        expect(inBmpPua || inSupplementaryPua).assertTrue();
      }
    });

    it('gives every icon a readable fallback token', 0, () => {
      for (let i = 0; i < EXPECTED.length; i++) {
        const spec: IconSpec = iconSpec(EXPECTED[i].icon);
        expect(spec.fallback.length > 0).assertTrue();
        expect(spec.fallback.startsWith('[')).assertTrue();
      }
    });

    it('maps each icon to its own (family, code point) pair', 0, () => {
      // 同名 / 同码位就是"两个图标画成同一个形状"——闭集里不该出现，这里逐个钉住。
      const seen: string[] = [];
      for (let i = 0; i < EXPECTED.length; i++) {
        const spec: IconSpec = iconSpec(EXPECTED[i].icon);
        const key: string = spec.family + ':' + spec.code.toString();
        expect(seen.indexOf(key)).assertEqual(-1);
        seen.push(key);
      }
      expect(seen.length).assertEqual(EXPECTED.length);
    });
  });
}
