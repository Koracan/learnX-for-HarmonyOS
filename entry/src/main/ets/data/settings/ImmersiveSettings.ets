/*
 * 沉浸式设置（data/settings）—— 两个开关的值与语义：`immersiveMode` / `immersiveAvoidFrontCamera`。
 * 纯逻辑，零平台依赖（持久化端口注入）。
 *
 * ## 参考实现出处
 *
 * 参考实现把这两个布尔放在 redux 的 `settings` 里（`data/reducers/settings.ts:20-21` 默认都是 false），
 * 由 `screens/ImmersiveSettings.tsx` 的 `setSetting('immersiveMode'|'immersiveAvoidFrontCamera', v)` 写，
 * 唯一的消费点是 `App.tsx:682-690` 的 `ImmersiveModeController`（`Immersive.setImmersive(immersiveMode)`）
 * 与 `App.tsx:727` 的 `disableHeaderTopInsetFallback = immersiveMode && !immersiveAvoidFrontCamera`。
 *
 * ## 两条**必须照抄**的语义（工单里点名"容易漏"的那条）
 *
 * 1. 第二个开关的**显示值** = `immersiveMode && immersiveAvoidFrontCamera`，且 **`immersiveMode` 关着时它禁用**
 *    （`ImmersiveSettings.tsx:47-48`）；
 * 2. 关掉第一个开关时，若第二个为真，**联动把它置假**（`ImmersiveSettings.tsx:24-29`）。
 *
 * 注意第二条的**持久化形态**与显示形态不同：参考实现持久化的是 `immersiveAvoidFrontCamera` 的原值，
 * 界面显示的是它与 `immersiveMode` 的**与**。本文件把这两个量分开提供
 * （`stored()` = 持久化值，`effectiveAvoidFrontCamera()` = 显示值），避免下游把两者搞混。
 *
 * ## 与 `data/settings/FileSettings` 的关系
 *
 * 同一套形状（键枚举 / 值接口 / 端口 / 内存实现 / store / 默认值），只是设置项不同；
 * 持久化实现见 `PreferencesImmersiveSettings.ets`，组装点在
 * `features/settings/repository/ImmersiveSettingsProvider.ets`。
 */

/** 两个设置项的键（与参考实现的 `setSetting` 同名字段）。 */
export enum ImmersiveSettingsKey {
  IMMERSIVE_MODE = 'immersiveMode',
  AVOID_FRONT_CAMERA = 'immersiveAvoidFrontCamera'
}

/** 沉浸式设置值。 */
export interface ImmersiveSettings {
  /** true = 隐藏状态栏与导航栏（参考实现默认 false）。 */
  immersiveMode: boolean;
  /** true = 避免遮挡前置摄像头（只在前一个为 true 时有意义；参考实现默认 false）。 */
  immersiveAvoidFrontCamera: boolean;
}

/** 参考实现的默认值（`data/reducers/settings.ts:20-21`）。 */
export const DEFAULT_IMMERSIVE_SETTINGS: ImmersiveSettings = {
  immersiveMode: false,
  immersiveAvoidFrontCamera: false
};

/** 取一份副本（避免调用方改到 store 内部状态）。 */
export function copyImmersiveSettings(value: ImmersiveSettings): ImmersiveSettings {
  return {
    immersiveMode: value.immersiveMode,
    immersiveAvoidFrontCamera: value.immersiveAvoidFrontCamera
  };
}

/**
 * 第二个开关的**显示值**：`immersiveMode && immersiveAvoidFrontCamera`
 * （`ImmersiveSettings.tsx:47` 的 `switchValue`）。
 */
export function effectiveAvoidFrontCamera(value: ImmersiveSettings): boolean {
  return value.immersiveMode && value.immersiveAvoidFrontCamera;
}

/** 第二个开关是否**可用**：`immersiveMode` 关着时禁用（`ImmersiveSettings.tsx:48` 的 `switchDisabled`）。 */
export function avoidFrontCameraEnabled(value: ImmersiveSettings): boolean {
  return value.immersiveMode;
}

/**
 * 切换第一个开关的**联动规则**（`ImmersiveSettings.tsx:24-29` 的四行）：
 * 关掉沉浸式时，若"避免前置摄像头"为真则一并置假；打开时不动它。
 *
 * 这是**纯函数**，单测直接钉住；界面只负责把返回值写回 store。
 */
export function applyImmersiveToggle(value: ImmersiveSettings, next: boolean): ImmersiveSettings {
  const updated: ImmersiveSettings = copyImmersiveSettings(value);
  updated.immersiveMode = next;
  if (!next && updated.immersiveAvoidFrontCamera) {
    updated.immersiveAvoidFrontCamera = false;
  }
  return updated;
}

/** 持久化端口（设备侧是 preferences，测试里是内存替身）。 */
export interface ImmersiveSettingsPort {
  /** 读上次保存的值；没有时返回 null。 */
  load(): Promise<ImmersiveSettings | null>;
  /** 写回；返回是否成功（失败不抛）。 */
  save(value: ImmersiveSettings): Promise<boolean>;
}

/** 内存实现（默认 / 测试 / Context 不可用时的降级：值仍然按默认值生效）。 */
export class InMemoryImmersiveSettingsPort implements ImmersiveSettingsPort {
  private value: ImmersiveSettings | null = null;

  async load(): Promise<ImmersiveSettings | null> {
    return this.value === null ? null : copyImmersiveSettings(this.value);
  }

  async save(value: ImmersiveSettings): Promise<boolean> {
    this.value = copyImmersiveSettings(value);
    return true;
  }
}

/** 设置来源（只看"当前生效值"的调用方用它）。 */
export interface ImmersiveSettingsSource {
  /** 当前**实际生效**的设置。 */
  current(): ImmersiveSettings;
}

/** 设置项读写 + 持久化。 */
export class ImmersiveSettingsStore implements ImmersiveSettingsSource {
  private readonly port: ImmersiveSettingsPort;
  private value: ImmersiveSettings = copyImmersiveSettings(DEFAULT_IMMERSIVE_SETTINGS);
  private loaded: boolean = false;
  private loadPromise: Promise<void> | null = null;

  constructor(port: ImmersiveSettingsPort) {
    this.port = port;
  }

  current(): ImmersiveSettings {
    return copyImmersiveSettings(this.value);
  }

  /** 第二个开关的显示值（= `immersiveMode && immersiveAvoidFrontCamera`）。 */
  effectiveAvoidFrontCamera(): boolean {
    return effectiveAvoidFrontCamera(this.value);
  }

  /** 内存里的持久化值（诊断与单测用）。 */
  stored(): ImmersiveSettings {
    return copyImmersiveSettings(this.value);
  }

  /** 从持久层读一次（失败保留默认值，绝不抛）。 */
  async load(): Promise<ImmersiveSettings> {
    if (!this.loaded) {
      if (this.loadPromise === null) {
        this.loadPromise = this.doLoad();
      }
      await this.loadPromise;
    }
    return this.current();
  }

  private async doLoad(): Promise<void> {
    try {
      const stored: ImmersiveSettings | null = await this.port.load();
      if (stored !== null) {
        this.value = copyImmersiveSettings(stored);
      }
      this.loaded = true;
    } catch (error) {
      this.loaded = false;
      this.loadPromise = null;
    }
  }

  /** 改一项并写回；返回**持久化**是否成功（内存值一定已更新）。 */
  async set(key: ImmersiveSettingsKey, value: boolean): Promise<boolean> {
    const next: ImmersiveSettings = copyImmersiveSettings(this.value);
    if (key === ImmersiveSettingsKey.IMMERSIVE_MODE) {
      next.immersiveMode = value;
    } else {
      next.immersiveAvoidFrontCamera = value;
    }
    return await this.write(next);
  }

  /**
   * 第一个开关的**联动**切换（`ImmersiveSettings.tsx:24-29`）：关掉沉浸式时把
   * "避免前置摄像头"一并置假。界面调这个而不是 `set(IMMERSIVE_MODE, …)`，
   * 于是那条容易漏的规则只有一处实现。
   */
  async setImmersiveMode(next: boolean): Promise<boolean> {
    return await this.write(applyImmersiveToggle(this.value, next));
  }

  private async write(next: ImmersiveSettings): Promise<boolean> {
    this.value = copyImmersiveSettings(next);
    this.loaded = true;
    try {
      return await this.port.save(this.value);
    } catch (error) {
      return false;
    }
  }
}

/** 一行自证串：**实际生效值** + 显示值（必须被打进 hilog —— AGENTS.md 的开关自证口径）。 */
export function describeImmersiveSettings(settings: ImmersiveSettings): string {
  return 'immersive settings: immersiveMode=' + settings.immersiveMode.toString()
    + ' immersiveAvoidFrontCamera=' + settings.immersiveAvoidFrontCamera.toString()
    + ' effectiveAvoidFrontCamera=' + effectiveAvoidFrontCamera(settings).toString()
    + ' avoidSwitchEnabled=' + avoidFrontCameraEnabled(settings).toString();
}
