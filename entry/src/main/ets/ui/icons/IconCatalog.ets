/*
 * 图标目录（**闭集**）：本工程用到的全部矢量图标，一处声明。
 *
 * ## 为什么是这份字体（ticket 11.5 的核心决定）
 *
 * 参考实现用 `react-native-vector-icons` 的 **MaterialCommunityIcons**（默认图标族，含 paper 的
 * `Icon`/`List.Icon`/`IconButton`）与 **MaterialIcons**（少量显式 import）两族字体图标。
 * 我们把**同一份 TTF** 内嵌进 hap（`resources/rawfile/fonts/`，逐字节拷自
 * `reference/learnOH-old/node_modules/react-native-vector-icons/Fonts/`），运行时注册后按**同一个码位表**渲染，
 * 因此"图标形状"与参考实现是**同源**的，而不是"看着差不多"的替代品。
 *
 * 码位逐条抄自 `react-native-vector-icons@10.2.0` 的 glyphmap
 * （`node_modules/react-native-vector-icons/glyphmaps/{MaterialCommunityIcons,MaterialIcons}.json`）。
 *
 * ## 为什么不用 SymbolGlyph
 *
 * 台账 `docs/accepted-deviations.md` 第 16 条（**改判·仍是约束**）：符号 id 随系统字体版本变化，
 * 拿名字猜 id 会得到"编译通过、运行时空格"的失败模式。字体图标没有这个问题：码位来自随包字体本身。
 *
 * ## 为什么码位要用 String.fromCodePoint
 *
 * MaterialCommunityIcons 的码位在 **U+F0000 起的补充私用区**（例如 attachment = U+F0066），
 * 大于 0xFFFF。`String.fromCharCode` 只接受 UTF-16 码元、会把它截断成 0x0066（'f'）；
 * 必须用 `String.fromCodePoint`。MaterialIcons 的码位在 BMP 私用区（U+E000–U+F8FF），两者都走同一个函数。
 */

/** 图标族：两族字体各自一个注册名（见 IconFont.ets）。 */
export enum IconFamily {
  MATERIAL_COMMUNITY = 'material-community',
  MATERIAL = 'material'
}

/**
 * 一个图标位使用到的全部资源。
 *
 * - `code`：随包字体里的码位（PUA／补充私用区），与参考实现**同一个值**；
 * - `fallback`：字体**没注册成功**时显示的可读文本（不是空白、不是"豆腐块"）；
 *   有 `label`（无障碍文案）时优先用 `label`，没有才用这里的短名。
 */
export interface IconSpec {
  family: IconFamily;
  code: number;
  fallback: string;
}

/**
 * 本工程用到的图标（**闭集**）。命名 = 参考实现的图标名（大写、`-` → `_`），
 * 便于把交付里的"参考图标名 → 我们的资源"对照表逐条核对。
 */
export enum AppIcon {
  /** MCI `attachment`：公告卡片 / 作业卡片 / 作业详情的附件标记。 */
  ATTACHMENT = 'attachment',
  /** MCI `flag`：公告卡片的重要标记。 */
  FLAG = 'flag',
  /** MCI `checkbox-blank-circle`：未读圆点（公告卡片 / 文件卡片的"新"标记）。 */
  CHECKBOX_BLANK_CIRCLE = 'checkbox-blank-circle',
  /** MCI `check`：已提交（作业卡片 / 作业详情段标题 / 课程详情 / 学期选择）。 */
  CHECK = 'check',
  /** MCI `key-variant`：有答案（作业卡片 / 作业详情段标题）。 */
  KEY_VARIANT = 'key-variant',
  /** MCI `medal`：优秀作业（作业卡片 / 作业详情段标题与条目）。 */
  MEDAL = 'medal',
  /** MaterialIcons `notifications`：底部 tab "公告" + 课程卡片的未读公告计数。 */
  NOTIFICATIONS = 'notifications',
  /** MaterialIcons `event`：底部 tab "作业" + 课程卡片的未完成作业计数。 */
  EVENT = 'event',
  /** MaterialIcons `folder`：底部 tab "文件" + 课程卡片的新文件计数。 */
  FOLDER = 'folder',
  /** MaterialIcons `apps`：底部 tab "课程"（参考实现的 tabBarIcon）。 */
  APPS = 'apps',
  /** MaterialIcons `settings`：底部 tab "设置"（参考实现的 tabBarIcon）。 */
  SETTINGS = 'settings',
  /** MaterialIcons `grade`：已评分（作业卡片 / 作业详情段标题）。 */
  GRADE = 'grade',
  /** MaterialIcons `insert-drive-file`：公告详情正文上方的附件行。 */
  INSERT_DRIVE_FILE = 'insert-drive-file',
  /** MaterialIcons `check-circle`：空态（参考实现 `components/Empty.tsx:15`，size 56）。 */
  CHECK_CIRCLE = 'check-circle',
  /** MaterialIcons `arrow-back`：详情页左上角的返回（参考实现是导航栈默认返回箭头）。 */
  ARROW_BACK = 'arrow-back',
  /** MaterialIcons `file-upload`：作业详情页页头右侧的「提交」入口（参考实现 AssignmentDetail.tsx:105-120）。 */
  FILE_UPLOAD = 'file-upload'
}

/** 闭集 → 资源。没有 default 分支的"兜底语义"：未知枚举值按 attachment 渲染并保持可读。 */
export function iconSpec(icon: AppIcon): IconSpec {
  switch (icon) {
    case AppIcon.ATTACHMENT:
      return { family: IconFamily.MATERIAL_COMMUNITY, code: 0xF0066, fallback: '[att]' };
    case AppIcon.FLAG:
      return { family: IconFamily.MATERIAL_COMMUNITY, code: 0xF023B, fallback: '[flag]' };
    case AppIcon.CHECKBOX_BLANK_CIRCLE:
      return { family: IconFamily.MATERIAL_COMMUNITY, code: 0xF012F, fallback: '[new]' };
    case AppIcon.CHECK:
      return { family: IconFamily.MATERIAL_COMMUNITY, code: 0xF012C, fallback: '[ok]' };
    case AppIcon.KEY_VARIANT:
      return { family: IconFamily.MATERIAL_COMMUNITY, code: 0xF030B, fallback: '[key]' };
    case AppIcon.MEDAL:
      return { family: IconFamily.MATERIAL_COMMUNITY, code: 0xF0987, fallback: '[medal]' };
    case AppIcon.NOTIFICATIONS:
      return { family: IconFamily.MATERIAL, code: 0xE7F4, fallback: '[bell]' };
    case AppIcon.EVENT:
      return { family: IconFamily.MATERIAL, code: 0xE878, fallback: '[cal]' };
    case AppIcon.FOLDER:
      return { family: IconFamily.MATERIAL, code: 0xE2C7, fallback: '[dir]' };
    case AppIcon.APPS:
      return { family: IconFamily.MATERIAL, code: 0xE5C3, fallback: '[apps]' };
    case AppIcon.SETTINGS:
      return { family: IconFamily.MATERIAL, code: 0xE8B8, fallback: '[gear]' };
    case AppIcon.GRADE:
      return { family: IconFamily.MATERIAL, code: 0xE885, fallback: '[grade]' };
    case AppIcon.INSERT_DRIVE_FILE:
      return { family: IconFamily.MATERIAL, code: 0xE24D, fallback: '[file]' };
    case AppIcon.CHECK_CIRCLE:
      return { family: IconFamily.MATERIAL, code: 0xE86C, fallback: '[ok]' };
    case AppIcon.ARROW_BACK:
      return { family: IconFamily.MATERIAL, code: 0xE5C4, fallback: '[<]' };
    case AppIcon.FILE_UPLOAD:
      // 码位 58054 (0xE2C6) 抄自 react-native-vector-icons@10.2.0 的
      // glyphmaps/MaterialIcons.json 的 file-upload。
      return { family: IconFamily.MATERIAL, code: 0xE2C6, fallback: '[up]' };
    default:
      return { family: IconFamily.MATERIAL_COMMUNITY, code: 0xF0066, fallback: '[icon]' };
  }
}

/** 字形文本。**必须** fromCodePoint：MCI 的码位大于 0xFFFF（见文件头）。 */
export function iconGlyph(icon: AppIcon): string {
  return String.fromCodePoint(iconSpec(icon).code);
}
