/*
 * 主题令牌单测：深浅两套都必须取到值、无 undefined，且与参考实现的字面量一致。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  ColorTokens, TypeStyleTokens, ThemeTokens, PlainPalette,
  PLAIN_PALETTE, LIGHT_COLORS, DARK_COLORS, LIGHT_THEME, DARK_THEME, TYPOGRAPHY, SIZES, resolveTheme
} from '../main/ets/ui/theme/Tokens';

/** 一个颜色令牌的采样。 */
interface ColorPair {
  name: string;
  value: string;
}

/** 一条排版样式的采样。 */
interface StylePair {
  name: string;
  value: TypeStyleTokens;
}

/** 一条尺寸的采样。 */
interface SizePair {
  name: string;
  value: number;
}

const COLOR_LITERAL = /^(#[0-9A-Fa-f]{6}|#[0-9A-Fa-f]{8}|transparent)$/;

function colorPairs(colors: ColorTokens): ColorPair[] {
  return [
      { name: 'primary', value: colors.primary },
      { name: 'onPrimary', value: colors.onPrimary },
      { name: 'primaryContainer', value: colors.primaryContainer },
      { name: 'onPrimaryContainer', value: colors.onPrimaryContainer },
      { name: 'secondary', value: colors.secondary },
      { name: 'onSecondary', value: colors.onSecondary },
      { name: 'secondaryContainer', value: colors.secondaryContainer },
      { name: 'onSecondaryContainer', value: colors.onSecondaryContainer },
      { name: 'tertiary', value: colors.tertiary },
      { name: 'onTertiary', value: colors.onTertiary },
      { name: 'tertiaryContainer', value: colors.tertiaryContainer },
      { name: 'onTertiaryContainer', value: colors.onTertiaryContainer },
      { name: 'error', value: colors.error },
      { name: 'onError', value: colors.onError },
      { name: 'errorContainer', value: colors.errorContainer },
      { name: 'onErrorContainer', value: colors.onErrorContainer },
      { name: 'background', value: colors.background },
      { name: 'onBackground', value: colors.onBackground },
      { name: 'surface', value: colors.surface },
      { name: 'onSurface', value: colors.onSurface },
      { name: 'surfaceVariant', value: colors.surfaceVariant },
      { name: 'onSurfaceVariant', value: colors.onSurfaceVariant },
      { name: 'outline', value: colors.outline },
      { name: 'outlineVariant', value: colors.outlineVariant },
      { name: 'shadow', value: colors.shadow },
      { name: 'scrim', value: colors.scrim },
      { name: 'inverseSurface', value: colors.inverseSurface },
      { name: 'inverseOnSurface', value: colors.inverseOnSurface },
      { name: 'inversePrimary', value: colors.inversePrimary },
      { name: 'backdrop', value: colors.backdrop },
      { name: 'card', value: colors.card },
      { name: 'surfaceDisabled', value: colors.surfaceDisabled },
      { name: 'onSurfaceDisabled', value: colors.onSurfaceDisabled },
  ];
}

function typographyPairs(): StylePair[] {
  return [
      { name: 'displayLarge', value: TYPOGRAPHY.displayLarge },
      { name: 'displayMedium', value: TYPOGRAPHY.displayMedium },
      { name: 'displaySmall', value: TYPOGRAPHY.displaySmall },
      { name: 'headlineLarge', value: TYPOGRAPHY.headlineLarge },
      { name: 'headlineMedium', value: TYPOGRAPHY.headlineMedium },
      { name: 'headlineSmall', value: TYPOGRAPHY.headlineSmall },
      { name: 'titleLarge', value: TYPOGRAPHY.titleLarge },
      { name: 'titleMedium', value: TYPOGRAPHY.titleMedium },
      { name: 'titleSmall', value: TYPOGRAPHY.titleSmall },
      { name: 'labelLarge', value: TYPOGRAPHY.labelLarge },
      { name: 'labelMedium', value: TYPOGRAPHY.labelMedium },
      { name: 'labelSmall', value: TYPOGRAPHY.labelSmall },
      { name: 'bodyLarge', value: TYPOGRAPHY.bodyLarge },
      { name: 'bodyMedium', value: TYPOGRAPHY.bodyMedium },
      { name: 'bodySmall', value: TYPOGRAPHY.bodySmall },
  ];
}

function sizePairs(): SizePair[] {
  return [
      { name: 'space1', value: SIZES.space1 },
      { name: 'space2', value: SIZES.space2 },
      { name: 'space3', value: SIZES.space3 },
      { name: 'space4', value: SIZES.space4 },
      { name: 'space5', value: SIZES.space5 },
      { name: 'space6', value: SIZES.space6 },
      { name: 'contentPadding', value: SIZES.contentPadding },
      { name: 'borderWidth', value: SIZES.borderWidth },
      { name: 'radiusSmall', value: SIZES.radiusSmall },
      { name: 'radiusMedium', value: SIZES.radiusMedium },
      { name: 'radiusLarge', value: SIZES.radiusLarge },
      { name: 'controlHeight', value: SIZES.controlHeight },
      { name: 'listItemMinHeight', value: SIZES.listItemMinHeight },
      { name: 'iconSmall', value: SIZES.iconSmall },
      { name: 'iconMedium', value: SIZES.iconMedium },
      { name: 'iconLarge', value: SIZES.iconLarge },
  ];
}

function assertAllColors(themeName: string, colors: ColorTokens): void {
  const pairs: ColorPair[] = colorPairs(colors);
  expect(pairs.length).assertEqual(33);
  for (let i = 0; i < pairs.length; i++) {
    const pair: ColorPair = pairs[i];
    expect(pair.value !== undefined && pair.value.length > 0).assertTrue();
    expect(COLOR_LITERAL.test(pair.value)).assertTrue();
  }
  const elevation: string[] = [
    colors.elevation.level0, colors.elevation.level1, colors.elevation.level2,
    colors.elevation.level3, colors.elevation.level4, colors.elevation.level5
  ];
  expect(elevation.length).assertEqual(6);
  for (let i = 0; i < elevation.length; i++) {
    expect(elevation[i] !== undefined && elevation[i].length > 0).assertTrue();
  }
}

export default function tokensTest() {
  describe('ui.theme.Tokens', () => {
    it('resolves light and dark themes without undefined', 0, () => {
      const light: ThemeTokens = resolveTheme(false);
      const dark: ThemeTokens = resolveTheme(true);
      expect(light.dark).assertFalse();
      expect(dark.dark).assertTrue();
      expect(light === LIGHT_THEME).assertTrue();
      expect(dark === DARK_THEME).assertTrue();
      assertAllColors('LIGHT', light.colors);
      assertAllColors('DARK', dark.colors);
    });

    it('exposes the same token names in both schemes', 0, () => {
      const light: ColorPair[] = colorPairs(LIGHT_COLORS);
      const dark: ColorPair[] = colorPairs(DARK_COLORS);
      expect(light.length).assertEqual(dark.length);
      for (let i = 0; i < light.length; i++) {
        expect(dark[i].name).assertEqual(light[i].name);
      }
      const rolesThatMustDiffer: string[] = ['primary', 'onPrimary', 'background', 'surface', 'onSurface', 'onSurfaceVariant', 'outline', 'outlineVariant', 'surfaceVariant'];
      for (let i = 0; i < rolesThatMustDiffer.length; i++) {
        const name: string = rolesThatMustDiffer[i];
        let lightValue: string = '';
        let darkValue: string = '';
        for (let j = 0; j < light.length; j++) {
          if (light[j].name === name) {
            lightValue = light[j].value;
            darkValue = dark[j].value;
          }
        }
        expect(lightValue.length > 0 && darkValue.length > 0 && lightValue !== darkValue).assertTrue();
      }
      // 这几项参考实现两套同值（纯黑 / 半透明遮罩 / elevation0），显式固化以免被误改
      expect(DARK_COLORS.shadow).assertEqual(LIGHT_COLORS.shadow);
      expect(DARK_COLORS.scrim).assertEqual(LIGHT_COLORS.scrim);
      expect(DARK_COLORS.backdrop).assertEqual(LIGHT_COLORS.backdrop);
      expect(DARK_COLORS.elevation.level0).assertEqual(LIGHT_COLORS.elevation.level0);
    });

    it('takes colours from the reference implementation verbatim', 0, () => {
      const palette: PlainPalette = PLAIN_PALETTE;
      expect(palette.plainTheme).assertEqual('#9A25AE');
      expect(palette.red500).assertEqual('#f44336');
      expect(palette.blue500).assertEqual('#2196f3');
      expect(palette.green500).assertEqual('#4caf50');
      expect(palette.orange500).assertEqual('#ff9800');
      expect(palette.yellow500).assertEqual('#ffeb3b');
      expect(palette.grey500).assertEqual('#9e9e9e');

      expect(LIGHT_COLORS.primary).assertEqual('#9A25AE');
      expect(LIGHT_COLORS.primary).assertEqual(palette.plainTheme);
      expect(LIGHT_COLORS.surface).assertEqual('#FFFBFF');
      expect(DARK_COLORS.surface).assertEqual('#1E1A1D');
      expect(DARK_COLORS.primary).assertEqual('#F9ABFF');
    });

    it('exposes a complete MD3 typescale', 0, () => {
      const styles: StylePair[] = typographyPairs();
      expect(styles.length).assertEqual(15);
      for (let i = 0; i < styles.length; i++) {
        const style: TypeStyleTokens = styles[i].value;
        expect(style.fontSize > 0).assertTrue();
        expect(style.lineHeight > 0).assertTrue();
        expect(style.fontWeight >= 100 && style.fontWeight <= 900).assertTrue();
        expect(style.letterSpacing >= 0).assertTrue();
      }
      expect(TYPOGRAPHY.bodyMedium.fontSize).assertEqual(14);
      expect(TYPOGRAPHY.headlineMedium.fontSize).assertEqual(28);
      expect(TYPOGRAPHY.headlineMedium.lineHeight).assertEqual(36);
      expect(TYPOGRAPHY.headlineLarge.fontSize).assertEqual(32);
      expect(TYPOGRAPHY.displayLarge.fontSize).assertEqual(57);
    });

    it('exposes positive size tokens', 0, () => {
      const sizes: SizePair[] = sizePairs();
      expect(sizes.length).assertEqual(16);
      for (let i = 0; i < sizes.length; i++) {
        expect(sizes[i].value > 0).assertTrue();
      }
      expect(SIZES.space1).assertEqual(4);
      expect(SIZES.contentPadding).assertEqual(16);
    });
  });
}
