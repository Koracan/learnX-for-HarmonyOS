/*
 * 沉浸式设置（data/settings）—— 开关 `immersiveMode` 的值与语义。
 * 纯逻辑，零平台依赖（持久化端口注入）。
 *
 * ## 参考实现出处
 *
 * 参考实现把布尔放在 redux 的 `settings` 里（`data/reducers/settings.ts:20` 默认 false），
 * 由 `screens/ImmersiveSettings.tsx` 的 `setSetting('immersiveMode', v)` 写，
 * 唯一的消费点是 `App.tsx:682-690` 的 `ImmersiveModeController`（`Immersive.setImmersive(immersiveMode)`）。
 *
 * ## 为什么只剩一个开关
 *
 * 参考实现的沉浸式子页还有第二个开关 `immersiveAvoidFrontCamera`：它唯一的用途是
 * `App.tsx:727` 的 `disableHeaderTopInsetFallback = immersiveMode && !immersiveAvoidFrontCamera`
 * （RN 的安全区回退）。本工程的自绘页头没有那套 inset 回退，移植时**没有把它的平台效果带过来**，
 * 于是它在本工程里只被持久化与显示 —— 拨动它不改变任何布局，是"拨了没有任何效果"的开关。
 * 处置：让这个开关**消失**（连同持久化字段与文案键），而不是就地补一套 inset 回退去兜住它。
 *
 * 随之删掉的还有两条**只为它存在**的语义（参考实现 `ImmersiveSettings.tsx:24-29,47-48`）：
 * 显示值 = `immersiveMode && immersiveAvoidFrontCamera`、以及关掉开关 1 时把开关 2 置假的联动。
 * `immersiveMode` 自己的行为一字未改：切换后写 preferences 并**立刻**应用到窗口
 * （见 `features/settings/repository/ImmersiveSettingsProvider` 与 `core/window/ImmersiveWindow`）。
 *
 * ## 与 `data/settings/FileSettings` 的关系
 *
 * 同一套形状（值接口 / 端口 / 内存实现 / store / 默认值），只是设置项只剩一个；
 * 持久化实现见 `PreferencesImmersiveSettings.ets`（旧沙箱里残留的第二个字段既不读也不删，见该文件头），
 * 组装点在 `features/settings/repository/ImmersiveSettingsProvider.ets`。
 */

/** 沉浸式设置值。 */
export interface ImmersiveSettings {
  /** true = 隐藏状态栏与导航栏（参考实现默认 false）。 */
  immersiveMode: boolean;
}

/** 参考实现的默认值（`data/reducers/settings.ts:20`）。 */
export const DEFAULT_IMMERSIVE_SETTINGS: ImmersiveSettings = { immersiveMode: false };

/** 取一份副本（避免调用方改到 store 内部状态）。 */
export function copyImmersiveSettings(value: ImmersiveSettings): ImmersiveSettings {
  return { immersiveMode: value.immersiveMode };
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

  /**
   * 切换沉浸式模式并写回；返回**持久化**是否成功（内存值一定已更新）。
   *
   * 界面唯一该调的写入口（启动恢复只读不写）。开关 2 移除后这里没有联动可做，
   * 写出去的就是调用方给的那一个值。
   */
  async setImmersiveMode(next: boolean): Promise<boolean> {
    return await this.write({ immersiveMode: next });
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

/** 一行自证串：**实际生效值**（必须被打进 hilog —— AGENTS.md 的开关自证口径）。 */
export function describeImmersiveSettings(settings: ImmersiveSettings): string {
  return 'immersive settings: immersiveMode=' + settings.immersiveMode.toString();
}
