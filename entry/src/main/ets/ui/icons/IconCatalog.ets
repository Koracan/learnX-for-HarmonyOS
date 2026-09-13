/*
 * 图标目录（**闭集**）：本工程用到的全部矢量图标，一处声明。
 *
 * ## 为什么是这份字体（核心决定）
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
 * 符号 id 随系统字体版本变化，
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
  FILE_UPLOAD = 'file-upload',
  /** MCI `heart`：滑动操作里的"收藏"（参考实现 CardWrapper.tsx:93-97）。 */
  HEART = 'heart',
  /** MCI `heart-off`：已收藏时那个按钮的另一态（CardWrapper.tsx:94）。 */
  HEART_OFF = 'heart-off',
  /** MCI `archive-arrow-down`：滑动操作里的"归档"（CardWrapper.tsx:110-114）。 */
  ARCHIVE_ARROW_DOWN = 'archive-arrow-down',
  /** MCI `archive-arrow-up`：已归档时那个按钮的另一态（CardWrapper.tsx:111）。 */
  ARCHIVE_ARROW_UP = 'archive-arrow-up',
  /** MaterialIcons `visibility`：已屏蔽的课程上那个"取消屏蔽"（CardWrapper.tsx:74-78）。 */
  VISIBILITY = 'visibility',
  /** MaterialIcons `visibility-off`：课程上那个"屏蔽"（CardWrapper.tsx:75）。 */
  VISIBILITY_OFF = 'visibility-off',
  /**
   * MaterialIcons `fullscreen`：文件详情页页头那个"全屏"（隐藏左栏），
   * 逐字对齐参考实现 `screens/FileDetail.tsx:110-111` 的 `icon="fullscreen"`。
   */
  FULLSCREEN = 'fullscreen',
  /** MaterialIcons `fullscreen-exit`：同一按钮的另一态（参考实现 :111）。 */
  FULLSCREEN_EXIT = 'fullscreen-exit',
  /**
   * MaterialIcons `search`：**四个 tab 页头右侧**的搜索入口
   * （参考实现 `App.tsx:137-158` 的 `headerRight`；设置页显式关掉）。
   */
  SEARCH = 'search',
  /** MaterialIcons `close`：搜索页页头左上角的关闭（参考实现 `App.tsx:113-121` 的 BackButton）。 */
  CLOSE = 'close',
  /* --- 设置与子页：**这一组全部来自 MaterialIcons**，与参考实现 `Settings.tsx` /
   * `TableCell.tsx` 的 `import MaterialIcons from 'react-native-vector-icons/MaterialIcons'` 同族。
   * 码位逐条抄自 `react-native-vector-icons@10.2.0` 的 glyphmaps/MaterialIcons.json
   * （每条的码位都写在下面的 `iconSpec` 里，便于复核）。 --- */
  /** MaterialIcons `person-remove`：设置页「退出登录」（参考实现 `Settings.tsx:69`）。 */
  PERSON_REMOVE = 'person-remove',
  /** MaterialIcons `loop`：设置页「学期选择」（参考实现 `Settings.tsx:84`）。 */
  LOOP = 'loop',
  /** MaterialIcons `rule-folder`：设置页「文件设置」（参考实现 `Settings.tsx:91`）。 */
  RULE_FOLDER = 'rule-folder',
  /** MaterialIcons `policy`：设置页「隐私政策」（参考实现 `Settings.tsx:98`）。 */
  POLICY = 'policy',
  /** MaterialIcons `help`：设置页「帮助与反馈」（参考实现 `Settings.tsx:109`）。 */
  HELP = 'help',
  /** MaterialIcons `copyright`：设置页「关于」（参考实现 `Settings.tsx:114`）。 */
  COPYRIGHT = 'copyright',
  /** MaterialIcons `center-focus-strong`：沉浸式设置页「避免前置摄像头」（参考实现 `ImmersiveSettings.tsx:44`）。 */
  CENTER_FOCUS_STRONG = 'center-focus-strong',
  /** MaterialIcons `keyboard-arrow-right`：`TableCell type="arrow"` 的行尾箭头（参考实现 `TableCell.tsx:116`）。 */
  KEYBOARD_ARROW_RIGHT = 'keyboard-arrow-right',
  /**
   * MaterialCommunityIcons `account`：**唯一一个 MCI 图标**，用于 `TableCell imageAlt` 的头像占位
   * （参考实现 `TableCell.tsx:72-77` 的 `Avatar.Icon icon="account"` 走 paper 的 MaterialCommunityIcons）。
   * **family 别搞错**：它不在 MaterialIcons 的码位表里。
   */
  ACCOUNT = 'account',
  /**
   * MaterialIcons `description`：设置页「导出日志」那一行。
   *
   * **这是本工程对参考实现的一处增补**（参考实现 Settings.tsx 没有这一项）：
   * `core/log/LogBuffer.ets` 明确把 `exportLogs()` 的调用方留给「settings 切片的「导出日志」」，
   * 而本工程也列了它。
   */
  DESCRIPTION = 'description',
  /* --- 文件详情顶栏与「详情 / 预览」切换用到的字形。
   * 码位按图标名查随包字体的 cmap 表得到（见下面的 iconSpec），因此 TTF 里一定有对应字形；
   * 字体形状本身与排版无关，命名跟随各自族的图标名。 --- */
  /** MaterialIcons `refresh`：重新下载当前文件。 */
  REFRESH = 'refresh',
  /** MaterialIcons `share`：把已落盘的文件交给系统分享。 */
  SHARE = 'share',
  /**
   * MaterialIcons `open-in-new`：离开本应用打开（外链）。平台在缺少对应应用时
   * 会失败，调用方要给可读的失败文案，不要假定系统总能接住。
   */
  OPEN_IN_NEW = 'open-in-new',
  /** MaterialCommunityIcons `eye`：查看文件预览。 */
  PREVIEW = 'eye',
  /** MaterialIcons `info`：查看文件信息（详情面板）。 */
  INFO = 'info'
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
    case AppIcon.HEART:
      return { family: IconFamily.MATERIAL_COMMUNITY, code: 0xF02D1, fallback: '[fav]' };
    case AppIcon.HEART_OFF:
      return { family: IconFamily.MATERIAL_COMMUNITY, code: 0xF0759, fallback: '[unfav]' };
    case AppIcon.ARCHIVE_ARROW_DOWN:
      return { family: IconFamily.MATERIAL_COMMUNITY, code: 0xF1259, fallback: '[arch]' };
    case AppIcon.ARCHIVE_ARROW_UP:
      return { family: IconFamily.MATERIAL_COMMUNITY, code: 0xF125B, fallback: '[unarch]' };
    case AppIcon.VISIBILITY:
      return { family: IconFamily.MATERIAL, code: 0xE8F4, fallback: '[show]' };
    case AppIcon.VISIBILITY_OFF:
      return { family: IconFamily.MATERIAL, code: 0xE8F5, fallback: '[hide]' };
    case AppIcon.FULLSCREEN:
      // 码位 58832 (0xE5D0) 抄自 react-native-vector-icons@10.2.0 的
      // glyphmaps/MaterialIcons.json 的 fullscreen。
      return { family: IconFamily.MATERIAL, code: 0xE5D0, fallback: '[fs]' };
    case AppIcon.FULLSCREEN_EXIT:
      // 码位 58833 (0xE5D1)，同上表的 fullscreen-exit。
      return { family: IconFamily.MATERIAL, code: 0xE5D1, fallback: '[fsx]' };
    case AppIcon.SEARCH:
      // 码位 59574 (0xE8B6)，同表的 search（页头搜索入口）。
      return { family: IconFamily.MATERIAL, code: 0xE8B6, fallback: '[?]' };
    case AppIcon.CLOSE:
      // 码位 58829 (0xE5CD)，同表的 close（搜索页的关闭按钮）。
      return { family: IconFamily.MATERIAL, code: 0xE5CD, fallback: '[x]' };
    case AppIcon.PERSON_REMOVE:
      // 码位 61286 (0xEF66) 抄自 glyphmaps/MaterialIcons.json 的 person-remove（Settings.tsx:69）。
      return { family: IconFamily.MATERIAL, code: 0xEF66, fallback: '[logout]' };
    case AppIcon.LOOP:
      // 码位 57384 (0xE028)，同表的 loop（Settings.tsx:84）。
      return { family: IconFamily.MATERIAL, code: 0xE028, fallback: '[loop]' };
    case AppIcon.RULE_FOLDER:
      // 码位 61897 (0xF1C9)，同表的 rule-folder（Settings.tsx:91）。
      return { family: IconFamily.MATERIAL, code: 0xF1C9, fallback: '[rules]' };
    case AppIcon.POLICY:
      // 码位 59927 (0xEA17)，同表的 policy（Settings.tsx:98）。
      return { family: IconFamily.MATERIAL, code: 0xEA17, fallback: '[policy]' };
    case AppIcon.HELP:
      // 码位 59527 (0xE887)，同表的 help（Settings.tsx:109）。
      return { family: IconFamily.MATERIAL, code: 0xE887, fallback: '[help]' };
    case AppIcon.COPYRIGHT:
      // 码位 59660 (0xE90C)，同表的 copyright（Settings.tsx:114）。
      return { family: IconFamily.MATERIAL, code: 0xE90C, fallback: '[c]' };
    case AppIcon.CENTER_FOCUS_STRONG:
      // 码位 58292 (0xE3B4)，同表的 center-focus-strong（ImmersiveSettings.tsx:44）。
      return { family: IconFamily.MATERIAL, code: 0xE3B4, fallback: '[focus]' };
    case AppIcon.KEYBOARD_ARROW_RIGHT:
      // 码位 58133 (0xE315)，同表的 keyboard-arrow-right（TableCell.tsx:116 的行尾箭头）。
      return { family: IconFamily.MATERIAL, code: 0xE315, fallback: '>' };
    case AppIcon.ACCOUNT:
      // 码位 983044 (0xF0004)，抄自 glyphmaps/MaterialCommunityIcons.json 的 account
      // （paper 的 Avatar.Icon 默认图标族是 MCI）。
      return { family: IconFamily.MATERIAL_COMMUNITY, code: 0xF0004, fallback: '[user]' };
    case AppIcon.DESCRIPTION:
      // 码位 59507 (0xE873)，同表的 description（本工程增补的「导出日志」行）。
      return { family: IconFamily.MATERIAL, code: 0xE873, fallback: '[log]' };
    case AppIcon.REFRESH:
      // 码位 58837 (0xE5D5)，glyphmaps/MaterialIcons.json 的 refresh。
      return { family: IconFamily.MATERIAL, code: 0xE5D5, fallback: '[refresh]' };
    case AppIcon.SHARE:
      // 码位 59405 (0xE80D)，同表的 share。
      return { family: IconFamily.MATERIAL, code: 0xE80D, fallback: '[share]' };
    case AppIcon.OPEN_IN_NEW:
      // 码位 59550 (0xE89E)，同表的 open-in-new。
      return { family: IconFamily.MATERIAL, code: 0xE89E, fallback: '[external]' };
    case AppIcon.PREVIEW:
      // 码位 983560 (0xF0208)，glyphmaps/MaterialCommunityIcons.json 的 eye
      // （MaterialIcons 没有 eye，只有语义已被「取消屏蔽」占用的 visibility）。
      return { family: IconFamily.MATERIAL_COMMUNITY, code: 0xF0208, fallback: '[preview]' };
    case AppIcon.INFO:
      // 码位 59534 (0xE88E)，同表的 info。
      return { family: IconFamily.MATERIAL, code: 0xE88E, fallback: '[info]' };
    default:
      return { family: IconFamily.MATERIAL_COMMUNITY, code: 0xF0066, fallback: '[icon]' };
  }
}

/** 字形文本。**必须** fromCodePoint：MCI 的码位大于 0xFFFF（见文件头）。 */
export function iconGlyph(icon: AppIcon): string {
  return String.fromCodePoint(iconSpec(icon).code);
}
