/*
 * 附件选取（features 层，平台实现）：文件管理器与相册。
 *
 * 参考实现用两个 RN 库（`AssignmentSubmission.tsx:120-170`）：
 *   - 文件管理器：`DocumentPicker.pick({type: [allFiles]})`，取消走 `DocumentPicker.isCancel(err)`；
 *   - 相册：`launchImageLibrary({mediaType:'mixed', selectionLimit:1})`，取消是 `result.didCancel`。
 * 平台替换为 HarmonyOS 的两个系统 picker：
 *   - `picker.DocumentViewPicker(context).select({maxSelectNumber:1})` → `Promise<string[]>`；
 *   - `photoAccessHelper.PhotoViewPicker(context).select({MIMEType: IMAGE_VIDEO_TYPE, maxSelectNumber:1})`
 *     → `Promise<PhotoSelectResult>`（`photoUris`）。
 *
 * ## 取消的判定（见模拟器实测证据）
 *
 * 参考实现的取消是**不算失败**的（取消后什么都不做）。HarmonyOS 侧：
 *   - 用户取消时 `select` 多数版本**正常 resolve 成空数组**；
 *   - 也可能抛出错误。我们无法可靠区分「用户取消」与「真失败」，所以：
 *     空数组 / 取不到 URI ⇒ cancelled（不发 toast）；抛异常 ⇒ failed（发 `loh_file_pick_failed`）。
 *   若实测发现取消走的是抛异常那条路，界面会多一条失败提示 —— 这是**已知的平台差异**，
 *   在交付说明里按实测结果记录。
 *
 * 本文件只做「拿到 URI → PickedAttachment」；字节读取在 data/assignments/DeviceAttachmentReader。
 */
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { Logger } from '../../core/log/Logger';
import { i18nService } from '../../core/i18n/I18n';
import { PickedAttachment, pickedAttachmentFromUri } from '../../domain/assignments/SubmissionForm';

const logger: Logger = new Logger('features.assignments.pickers');

/** 一次选取的结果：选中 / 取消 / 失败三分，**取消不是失败**（参考实现 :131-133）。 */
export class PickOutcome {
  readonly picked: PickedAttachment | undefined;
  readonly cancelled: boolean;
  readonly failed: boolean;
  readonly message: string;

  private constructor(picked: PickedAttachment | undefined, cancelled: boolean, failed: boolean,
    message: string) {
    this.picked = picked;
    this.cancelled = cancelled;
    this.failed = failed;
    this.message = message;
  }

  static selected(picked: PickedAttachment): PickOutcome {
    return new PickOutcome(picked, false, false, '');
  }

  static cancelled(): PickOutcome {
    return new PickOutcome(undefined, true, false, '');
  }

  static failed(message: string): PickOutcome {
    return new PickOutcome(undefined, false, true, message);
  }
}

function hostContext(): common.Context | null {
  try {
    return getContext() as common.Context;
  } catch (error) {
    logger.error('no host context for the pickers: ' + (error as Error).message);
    return null;
  }
}

/** 两个系统的附件选取入口。 */
export class AttachmentPickers {
  /** 文件管理器（任意文件，单选）。 */
  async pickDocument(title: string): Promise<PickOutcome> {
    const context: common.Context | null = hostContext();
    if (context === null) {
      return PickOutcome.failed('no host context');
    }
    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      const uris: Array<string> = await documentPicker.select(options);
      if (uris === undefined || uris === null || uris.length === 0) {
        logger.info('document pick cancelled (empty uri list)');
        return PickOutcome.cancelled();
      }
      const picked: PickedAttachment = pickedAttachmentFromUri(uris[0], title, i18nService.isChinese());
      logger.info('document picked: name=' + picked.name + ' mime=' + picked.mimeType);
      return PickOutcome.selected(picked);
    } catch (error) {
      const message: string = (error as Error).message;
      logger.warn('document pick failed: ' + message);
      return PickOutcome.failed(message);
    }
  }

  /** 相册（图片 + 视频 = 参考实现的 mediaType:'mixed'，单选）。 */
  async pickPhoto(title: string): Promise<PickOutcome> {
    const context: common.Context | null = hostContext();
    if (context === null) {
      return PickOutcome.failed('no host context');
    }
    try {
      // 本 SDK 的 d.ts 里 photoAccessHelper.PhotoViewPicker **只有无参构造**
      // （带 context 的那个重载在 @ohos.file.picker 的旧 PhotoViewPicker 上）；
      // 单测/构建实测：带参构造报 Expected 0 arguments, but got 1。
      const photoPicker: photoAccessHelper.PhotoViewPicker =
        new photoAccessHelper.PhotoViewPicker();
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
      options.maxSelectNumber = 1;
      const result: photoAccessHelper.PhotoSelectResult = await photoPicker.select(options);
      const uris: Array<string> | undefined = result === undefined || result === null
        ? undefined : result.photoUris;
      if (uris === undefined || uris === null || uris.length === 0) {
        logger.info('photo pick cancelled (empty uri list)');
        return PickOutcome.cancelled();
      }
      const picked: PickedAttachment = pickedAttachmentFromUri(uris[0], title, i18nService.isChinese());
      logger.info('photo picked: name=' + picked.name + ' mime=' + picked.mimeType);
      return PickOutcome.selected(picked);
    } catch (error) {
      const message: string = (error as Error).message;
      logger.warn('photo pick failed: ' + message);
      return PickOutcome.failed(message);
    }
  }
}
