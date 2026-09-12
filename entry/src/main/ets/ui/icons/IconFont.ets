/*
 * 图标字体的注册与"就绪"判定（ticket 11.5）。
 *
 * ## 为什么要有"就绪"这个概念
 *
 * 私用区（PUA）码位在**缺字形时不报错**：系统只是渲染成空白或豆腐块，没有任何异常可捕获。
 * 参考实现那套"注册一次就假定能用"在这里是危险的——**门禁全绿 + 界面全空白**是完全可能的。
 * 所以本模块把"可用与否"变成一个显式状态，并且**两条路径都落 hilog**：
 *   - 不可用 ⇒ `error` 级日志 + 界面回退为**可读文本**（IconGlyph 的 else 分支）；
 *   - 可用   ⇒ `info` 级日志，含注册用的族名与实际字体来源。
 *
 * ## 判据：**rawfile 能不能打开**，不是 `getFontByName`
 *
 * 设备实测（模拟器 Pura 90 / HarmonyOS 6.1.0(23)，ticket 11.5）：
 * `font.registerFont` **不抛错**，但 `font.getFontByName('learnOHMaterialCommunityIcons')`
 * 返回 **undefined** —— 也就是说这个接口**不足以**用来判断"应用自己注册的字体是否可用"
 * （用它会得到"明明能用却全部回退成文字"的假阴性，本轮就踩过：
 * 日志 `icon font getFontByName FAILED: Cannot read property path of undefined`，
 * 界面上所有图标都退化成了文字）。因此本模块的判据改成
 * **先用 resourceManager 打开 rawfile**（打不开 ⇒ 字体文件根本不在包里 ⇒ 必然不可用），
 * 再用 `registerFont` 不抛错作为第二道。`getFontByName` 只作为**诊断回执**打进日志，
 * 不参与判定。
 *
 * ## 调用点
 *
 * `pages/Index.ets` 的 `aboutToAppear`（@Entry 根组件，早于任何子组件 build）。幂等。
 */
import { font } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';
import { Logger } from '../../core/log/Logger';
import { IconFamily } from './IconCatalog';

const logger: Logger = new Logger('ui.icons.font');

/** 注册到系统的族名：加 `learnOH` 前缀，避免与设备上的系统字体重名。 */
export const ICON_FONT_FAMILY_MATERIAL_COMMUNITY: string = 'learnOHMaterialCommunityIcons';
export const ICON_FONT_FAMILY_MATERIAL: string = 'learnOHMaterialIcons';

/** rawfile 里的字体路径（相对 resources/rawfile）。 */
export const FONT_SRC_MATERIAL_COMMUNITY: string = 'fonts/MaterialCommunityIcons.ttf';
export const FONT_SRC_MATERIAL: string = 'fonts/MaterialIcons.ttf';

let attempted: boolean = false;
let ready: boolean = false;

/** 图标字体是否可用（IconGlyph 用它二选一：字形 / 可读文本）。 */
export function iconFontReady(): boolean {
  return ready;
}

/** 供启动自证用（hilog 里那行 `icon font …`）。 */
export function describeIconFontState(): string {
  return 'attempted=' + attempted.toString() + ' ready=' + ready.toString()
    + ' mci=' + ICON_FONT_FAMILY_MATERIAL_COMMUNITY + ' material=' + ICON_FONT_FAMILY_MATERIAL
    + ' mciSrc=' + FONT_SRC_MATERIAL_COMMUNITY + ' materialSrc=' + FONT_SRC_MATERIAL;
}

/** 某个图标属于哪一族。 */
export function iconFontFamily(family: IconFamily): string {
  return family === IconFamily.MATERIAL ? ICON_FONT_FAMILY_MATERIAL : ICON_FONT_FAMILY_MATERIAL_COMMUNITY;
}

/**
 * rawfile 是否真的在包里（能拿到文件描述符就算在）。
 * 这是**可确定性制造失败**的那一环：把 `fonts/*.ttf` 改名/删掉 ⇒ 这里必然返回 false
 * ⇒ error 日志 + 界面回退可读文本（ticket 11.5 的回退证据就是这么做的）。
 */
function rawFilePresent(manager: resourceManager.ResourceManager, path: string): boolean {
  try {
    const fd: resourceManager.RawFileDescriptor = manager.getRawFdSync(path);
    const present: boolean = fd !== undefined && fd.fd >= 0 && fd.length > 0;
    try {
      manager.closeRawFdSync(path);
    } catch (closeError) {
      logger.warn('closeRawFdSync failed: ' + path + '（' + (closeError as Error).message + '）');
    }
    return present;
  } catch (error) {
    logger.error('rawfile unavailable: ' + path + '（' + (error as Error).message + '）');
    return false;
  }
}

/** `getFontByName` 的**诊断回执**（不参与判定，见文件头）。 */
function describeReceipt(familyName: string): string {
  try {
    const info: font.FontInfo = font.getFontByName(familyName);
    if (info === undefined || info === null) {
      return familyName + '=undefined';
    }
    return familyName + '=' + (info.path !== undefined && info.path.length > 0 ? info.path : '(empty)');
  } catch (error) {
    return familyName + '=(threw:' + (error as Error).message + ')';
  }
}

/**
 * 注册两族字体并判定是否可用。幂等；返回 `ready`。
 *
 * @param manager 应用的 resourceManager（用来确认 rawfile 真的在包里）；宿主单测环境可以传 null。
 */
export function registerIconFonts(manager: resourceManager.ResourceManager | null): boolean {
  if (attempted) {
    return ready;
  }
  attempted = true;

  if (manager === null) {
    logger.error('图标字体未注册：拿不到 resourceManager；界面回退为可读文本。' + describeIconFontState());
    ready = false;
    return ready;
  }
  const hasMci: boolean = rawFilePresent(manager, FONT_SRC_MATERIAL_COMMUNITY);
  const hasMaterial: boolean = rawFilePresent(manager, FONT_SRC_MATERIAL);
  if (!hasMci || !hasMaterial) {
    logger.error('图标字体未注册：rawfile 缺失（mci=' + hasMci.toString()
      + ' material=' + hasMaterial.toString() + '）；界面回退为可读文本。' + describeIconFontState());
    ready = false;
    return ready;
  }

  try {
    font.registerFont({
      familyName: ICON_FONT_FAMILY_MATERIAL_COMMUNITY,
      familySrc: $rawfile(FONT_SRC_MATERIAL_COMMUNITY)
    });
    font.registerFont({ familyName: ICON_FONT_FAMILY_MATERIAL, familySrc: $rawfile(FONT_SRC_MATERIAL) });
  } catch (error) {
    logger.error('icon font registerFont FAILED: ' + (error as Error).message
      + '；界面回退为可读文本（见 ui/icons/IconGlyph.ets）。' + describeIconFontState());
    ready = false;
    return ready;
  }

  ready = true;
  logger.info('icon font ready: ' + describeIconFontState()
    + ' receipt=[' + describeReceipt(ICON_FONT_FAMILY_MATERIAL_COMMUNITY)
    + ' ' + describeReceipt(ICON_FONT_FAMILY_MATERIAL) + ']');
  return ready;
}
