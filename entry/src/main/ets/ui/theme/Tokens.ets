/*
 * learnOH 主题令牌：颜色 / 排版 / 尺寸。
 *
 * 颜色来源（逐值取自参考实现，未凭印象编造）：
 *   - reference/learnOH-old/src/constants/Colors.ts            —— plainTheme 与 500 系调色板
 *   - reference/learnOH-old/src/App.tsx  lightThemeColors      —— MD3 浅色主题实际用色
 *   - reference/learnOH-old/src/App.tsx  darkThemeColors       —— MD3 深色主题实际用色
 *   参考实现用 `rgb()/rgba()` 书写，此处逐值转成 ArkUI 的 `#RRGGBB` / `#AARRGGBB`(ARGB)。
 *
 * 排版来源：react-native-paper 5.15.0 的 MD3 typescale
 *   reference/learnOH-old/node_modules/react-native-paper/src/styles/themes/v3/tokens.tsx
 *
 * 尺寸来源：reference/learnOH-old/src/constants/Styles.ts 的基准间距 4vp，按 4 的倍数展开。
 *
 * 界面不得出现硬编码色值：一律 {`resolveTheme(...)`} 取令牌。
 */

/** 参考实现 src/constants/Colors.ts 的调色板（原样迁移）。 */
export interface PlainPalette {
  /** 品牌主色，等同于参考实现的 `theme`。 */
  plainTheme: string;
  red500: string;
  blue500: string;
  green500: string;
  orange500: string;
  yellow500: string;
  grey500: string;
}

export const PLAIN_PALETTE: PlainPalette = {
  plainTheme: '#9A25AE',
  red500: '#f44336',
  blue500: '#2196f3',
  green500: '#4caf50',
  orange500: '#ff9800',
  yellow500: '#ffeb3b',
  grey500: '#9e9e9e'
};

/** MD3 elevation 层色（参考实现 App.tsx 的 elevation 表）。 */
export interface ElevationTokens {
  level0: string;
  level1: string;
  level2: string;
  level3: string;
  level4: string;
  level5: string;
}

/** MD3 颜色角色（参考实现 App.tsx 实际使用的全部键）。 */
export interface ColorTokens {
  primary: string;
  onPrimary: string;
  primaryContainer: string;
  onPrimaryContainer: string;
  secondary: string;
  onSecondary: string;
  secondaryContainer: string;
  onSecondaryContainer: string;
  tertiary: string;
  onTertiary: string;
  tertiaryContainer: string;
  onTertiaryContainer: string;
  error: string;
  onError: string;
  errorContainer: string;
  onErrorContainer: string;
  background: string;
  onBackground: string;
  surface: string;
  onSurface: string;
  surfaceVariant: string;
  onSurfaceVariant: string;
  outline: string;
  outlineVariant: string;
  shadow: string;
  scrim: string;
  inverseSurface: string;
  inverseOnSurface: string;
  inversePrimary: string;
  backdrop: string;
  card: string;
  surfaceDisabled: string;
  onSurfaceDisabled: string;
  elevation: ElevationTokens;
}

/** 单条排版样式。数值单位：fontSize/lineHeight/letterSpacing 为 fp，fontWeight 为 100–900。 */
export interface TypeStyleTokens {
  fontSize: number;
  lineHeight: number;
  letterSpacing: number;
  fontWeight: number;
}

/** MD3 typescale。 */
export interface TypographyTokens {
  displayLarge: TypeStyleTokens;
  displayMedium: TypeStyleTokens;
  displaySmall: TypeStyleTokens;
  headlineLarge: TypeStyleTokens;
  headlineMedium: TypeStyleTokens;
  headlineSmall: TypeStyleTokens;
  titleLarge: TypeStyleTokens;
  titleMedium: TypeStyleTokens;
  titleSmall: TypeStyleTokens;
  labelLarge: TypeStyleTokens;
  labelMedium: TypeStyleTokens;
  labelSmall: TypeStyleTokens;
  bodyLarge: TypeStyleTokens;
  bodyMedium: TypeStyleTokens;
  bodySmall: TypeStyleTokens;
}

/** 间距 / 圆角 / 控件尺寸，单位 vp。 */
export interface SizeTokens {
  space1: number;
  space2: number;
  space3: number;
  space4: number;
  space5: number;
  space6: number;
  contentPadding: number;
  borderWidth: number;
  radiusSmall: number;
  radiusMedium: number;
  radiusLarge: number;
  controlHeight: number;
  listItemMinHeight: number;
  iconSmall: number;
  iconMedium: number;
  iconLarge: number;
}

/** 一套完整主题：深浅两套由 resolveTheme 解析。 */
export interface ThemeTokens {
  dark: boolean;
  colors: ColorTokens;
  typography: TypographyTokens;
  sizes: SizeTokens;
}

/** 浅色主题颜色令牌。 */
export const LIGHT_COLORS: ColorTokens = {
  primary: '#9A25AE',
  onPrimary: '#FFFFFF',
  primaryContainer: '#FFD6FE',
  onPrimaryContainer: '#35003F',
  secondary: '#6B586B',
  onSecondary: '#FFFFFF',
  secondaryContainer: '#F4DBF1',
  onSecondaryContainer: '#251626',
  tertiary: '#82524A',
  onTertiary: '#FFFFFF',
  tertiaryContainer: '#FFDAD4',
  onTertiaryContainer: '#33110C',
  error: '#BA1A1A',
  onError: '#FFFFFF',
  errorContainer: '#FFDAD6',
  onErrorContainer: '#410002',
  background: '#FFFBFF',
  onBackground: '#1E1A1D',
  surface: '#FFFBFF',
  onSurface: '#1E1A1D',
  surfaceVariant: '#ECDFE8',
  onSurfaceVariant: '#4D444C',
  outline: '#7F747D',
  outlineVariant: '#D0C3CC',
  shadow: '#000000',
  scrim: '#000000',
  inverseSurface: '#332F32',
  inverseOnSurface: '#F7EEF3',
  inversePrimary: '#F9ABFF',
  backdrop: '#66362E35',
  card: '#FFFBFF',
  surfaceDisabled: '#1F1E1A1D',
  onSurfaceDisabled: '#611E1A1D',
  elevation: {
    level0: 'transparent',
    level1: '#FAF0FB',
    level2: '#F7EAF9',
    level3: '#F4E4F6',
    level4: '#F3E1F5',
    level5: '#F1DDF4',
  }
};

/** 深色主题颜色令牌。 */
export const DARK_COLORS: ColorTokens = {
  primary: '#F9ABFF',
  onPrimary: '#570066',
  primaryContainer: '#7B008F',
  onPrimaryContainer: '#FFD6FE',
  secondary: '#D7BFD5',
  onSecondary: '#3B2B3C',
  secondaryContainer: '#534153',
  onSecondaryContainer: '#F4DBF1',
  tertiary: '#F6B8AD',
  onTertiary: '#4C251F',
  tertiaryContainer: '#673B34',
  onTertiaryContainer: '#FFDAD4',
  error: '#FFB4AB',
  onError: '#690005',
  errorContainer: '#93000A',
  onErrorContainer: '#FFB4AB',
  background: '#1E1A1D',
  onBackground: '#E9E0E4',
  surface: '#1E1A1D',
  onSurface: '#E9E0E4',
  surfaceVariant: '#4D444C',
  onSurfaceVariant: '#D0C3CC',
  outline: '#998D96',
  outlineVariant: '#4D444C',
  shadow: '#000000',
  scrim: '#000000',
  inverseSurface: '#E9E0E4',
  inverseOnSurface: '#332F32',
  inversePrimary: '#9A25AE',
  backdrop: '#66362E35',
  card: '#1E1A1D',
  surfaceDisabled: '#1FE9E0E4',
  onSurfaceDisabled: '#61E9E0E4',
  elevation: {
    level0: 'transparent',
    level1: '#292128',
    level2: '#30262F',
    level3: '#362A36',
    level4: '#382B38',
    level5: '#3D2E3D',
  }
};

/**
 * MD3 typescale（react-native-paper 5.15.0）。
 * 参考实现把 paper 的 fonts 原样交给 MD3LightTheme/MD3DarkTheme，故深浅两套共用同一份排版。
 */
export const TYPOGRAPHY: TypographyTokens = {
  displayLarge: { fontSize: 57, lineHeight: 64, letterSpacing: 0, fontWeight: 400 },
  displayMedium: { fontSize: 45, lineHeight: 52, letterSpacing: 0, fontWeight: 400 },
  displaySmall: { fontSize: 36, lineHeight: 44, letterSpacing: 0, fontWeight: 400 },
  headlineLarge: { fontSize: 32, lineHeight: 40, letterSpacing: 0, fontWeight: 400 },
  headlineMedium: { fontSize: 28, lineHeight: 36, letterSpacing: 0, fontWeight: 400 },
  headlineSmall: { fontSize: 24, lineHeight: 32, letterSpacing: 0, fontWeight: 400 },
  titleLarge: { fontSize: 22, lineHeight: 28, letterSpacing: 0, fontWeight: 400 },
  titleMedium: { fontSize: 16, lineHeight: 24, letterSpacing: 0.15, fontWeight: 500 },
  titleSmall: { fontSize: 14, lineHeight: 20, letterSpacing: 0.1, fontWeight: 500 },
  labelLarge: { fontSize: 14, lineHeight: 20, letterSpacing: 0.1, fontWeight: 500 },
  labelMedium: { fontSize: 12, lineHeight: 16, letterSpacing: 0.5, fontWeight: 500 },
  labelSmall: { fontSize: 11, lineHeight: 16, letterSpacing: 0.5, fontWeight: 500 },
  bodyLarge: { fontSize: 16, lineHeight: 24, letterSpacing: 0.15, fontWeight: 400 },
  bodyMedium: { fontSize: 14, lineHeight: 20, letterSpacing: 0.25, fontWeight: 400 },
  bodySmall: { fontSize: 12, lineHeight: 16, letterSpacing: 0.4, fontWeight: 400 },
};

/** 尺寸令牌。基准 4vp 取自参考实现 src/constants/Styles.ts 的 spacex1/spacey1。 */
export const SIZES: SizeTokens = {
  space1: 4,
  space2: 8,
  space3: 12,
  space4: 16,
  space5: 24,
  space6: 32,
  contentPadding: 16,
  borderWidth: 1,
  radiusSmall: 4,
  radiusMedium: 12,
  radiusLarge: 16,
  controlHeight: 40,
  listItemMinHeight: 56,
  iconSmall: 16,
  iconMedium: 24,
  iconLarge: 32
};

export const LIGHT_THEME: ThemeTokens = { dark: false, colors: LIGHT_COLORS, typography: TYPOGRAPHY, sizes: SIZES };
export const DARK_THEME: ThemeTokens = { dark: true, colors: DARK_COLORS, typography: TYPOGRAPHY, sizes: SIZES };

/**
 * 按深浅解析主题。这是界面取色的唯一入口。
 * @param isDark 是否深色（由系统 colorMode 判定）
 */
export function resolveTheme(isDark: boolean): ThemeTokens {
  return isDark ? DARK_THEME : LIGHT_THEME;
}
