/*
 * 文件设置（data/settings）——"保存打开的文件到文档"与"文件名不包含课程名"两个开关，
 * 以及它们的**脚本可驱动覆盖**。纯逻辑，零平台依赖（持久化端口注入）。
 *
 * ## 参考实现出处
 *
 * `reference/learnOH-old/src/data/reducers/settings.ts:22` 的两个默认值都是 `false`；
 * `src/screens/FileSettings.tsx` 用 `setSetting('fileUseDocumentDir'|'fileOmitCourseName', value)` 写；
 * 两个值唯一的消费点是 `src/helpers/fs.ts:26-33,59-63`（落盘根目录与文件名形状）。
 * 本文件把"值 + 语义"收在一处，UI 入口归全局设置页。
 *
 * ## 为什么还带一个运行时覆盖
 *
 * 与 `data/courses/SemesterOverride` 同一理由：要求"两个设置均生效"是
 * **可复现**的，而应用在模拟器上每一次切换设置都要走界面点击（15–35s/次，且截图易退化）。
 * 覆盖只服务取证，被设置时就是权威值，并且**实际生效值每次都进 hilog**
 * （AGENTS.md：开关必须自证生效，且要打在**消费点**）。
 */

/** 两个设置项的键（与参考实现的 `setSetting` 同名字段）。 */
export enum FileSettingsKey {
  USE_DOCUMENT_DIR = 'useDocumentDir',
  OMIT_COURSE_NAME = 'omitCourseName'
}

/** 文件设置值。 */
export interface FileSettings {
  /** true = 落盘到应用"文档"；false = 落到"缓存"（参考实现默认 false）。 */
  useDocumentDir: boolean;
  /** true = 文件名只有 `文件名`；false = `课程名-文件名`（参考实现默认 false）。 */
  omitCourseName: boolean;
}

/** 参考实现的默认值（settings.ts:22）。 */
export const DEFAULT_FILE_SETTINGS: FileSettings = { useDocumentDir: false, omitCourseName: false };

/** 取一份副本（避免调用方改到 store 内部状态）。 */
export function copyFileSettings(value: FileSettings): FileSettings {
  return { useDocumentDir: value.useDocumentDir, omitCourseName: value.omitCourseName };
}

/** 持久化端口（设备侧是 preferences，测试里是内存替身）。 */
export interface FileSettingsPort {
  /** 读上次保存的值；没有时返回 null。 */
  load(): Promise<FileSettings | null>;
  /** 写回；返回是否成功（失败不抛）。 */
  save(value: FileSettings): Promise<boolean>;
}

/** 内存实现（默认 / 测试 / Context 不可用时的降级：值仍然按默认值生效）。 */
export class InMemoryFileSettingsPort implements FileSettingsPort {
  private value: FileSettings | null = null;

  async load(): Promise<FileSettings | null> {
    return this.value === null ? null : copyFileSettings(this.value);
  }

  async save(value: FileSettings): Promise<boolean> {
    this.value = copyFileSettings(value);
    return true;
  }
}

/** 设置来源（下载编排层只需要 `current()`，于是它不必知道持久化）。 */
export interface FileSettingsSource {
  /** 当前**实际生效**的设置（含运行时覆盖）。 */
  current(): FileSettings;
}

/** 设置项读写 + 持久化。 */
export class FileSettingsStore implements FileSettingsSource {
  private readonly port: FileSettingsPort;
  private value: FileSettings = copyFileSettings(DEFAULT_FILE_SETTINGS);
  private loaded: boolean = false;
  private loadPromise: Promise<void> | null = null;

  constructor(port: FileSettingsPort) {
    this.port = port;
  }

  /** 当前实际生效值（持久化值 + 运行时覆盖）。 */
  current(): FileSettings {
    return applyFileSettingsOverride(this.value);
  }

  /** 内存里的持久化值（不含覆盖；诊断与单测用）。 */
  stored(): FileSettings {
    return copyFileSettings(this.value);
  }

  /** 从持久层读一次（失败保留默认值，绝不抛）。 */
  async load(): Promise<FileSettings> {
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
      const stored: FileSettings | null = await this.port.load();
      if (stored !== null) {
        this.value = copyFileSettings(stored);
      }
      this.loaded = true;
    } catch (error) {
      this.loaded = false;
      this.loadPromise = null;
    }
  }

  /** 改一项并写回；返回**持久化**是否成功（内存值一定已更新）。 */
  async set(key: FileSettingsKey, value: boolean): Promise<boolean> {
    const next: FileSettings = copyFileSettings(this.value);
    if (key === FileSettingsKey.USE_DOCUMENT_DIR) {
      next.useDocumentDir = value;
    } else {
      next.omitCourseName = value;
    }
    this.value = next;
    this.loaded = true;
    try {
      return await this.port.save(next);
    } catch (error) {
      return false;
    }
  }
}

/* ------------------------------------------------------------------ *
 * 运行时覆盖（只服务取证；提交态为空 = 不影响任何行为）
 * ------------------------------------------------------------------ */

/** `aa start --ps` 的键名。 */
export const FILE_USE_DOCUMENT_DIR_WANT_PARAM: string = 'lohFileUseDocumentDir';
export const FILE_OMIT_COURSE_NAME_WANT_PARAM: string = 'lohFileOmitCourseName';

/** 三态：undefined = 没有覆盖。 */
export interface FileSettingsOverride {
  useDocumentDir: boolean | undefined;
  omitCourseName: boolean | undefined;
}

let runtimeUseDocumentDir: boolean | undefined = undefined;
let runtimeOmitCourseName: boolean | undefined = undefined;

/** 解析一个布尔开关的文本形态；无法判定时返回 undefined（**不生效**，避免把打字错误当成生效）。 */
export function parseBooleanSwitch(raw: string): boolean | undefined {
  const text: string = raw === undefined || raw === null ? '' : raw.trim().toLowerCase();
  if (text === '1' || text === 'true' || text === 'yes' || text === 'on') {
    return true;
  }
  if (text === '0' || text === 'false' || text === 'no' || text === 'off') {
    return false;
  }
  return undefined;
}

/** 设置运行时覆盖；返回是否有任意一项被接受。 */
export function setRuntimeFileSettingsOverride(useDocumentDirRaw: string,
  omitCourseNameRaw: string): boolean {
  const useDocumentDir: boolean | undefined = parseBooleanSwitch(useDocumentDirRaw);
  const omitCourseName: boolean | undefined = parseBooleanSwitch(omitCourseNameRaw);
  if (useDocumentDir === undefined && omitCourseName === undefined) {
    return false;
  }
  if (useDocumentDir !== undefined) {
    runtimeUseDocumentDir = useDocumentDir;
  }
  if (omitCourseName !== undefined) {
    runtimeOmitCourseName = omitCourseName;
  }
  return true;
}

export function effectiveFileSettingsOverride(): FileSettingsOverride {
  return { useDocumentDir: runtimeUseDocumentDir, omitCourseName: runtimeOmitCourseName };
}

export function clearRuntimeFileSettingsOverride(): void {
  runtimeUseDocumentDir = undefined;
  runtimeOmitCourseName = undefined;
}

/** 把覆盖盖到持久化值上（覆盖优先，与学期覆盖同一优先级口径）。 */
export function applyFileSettingsOverride(base: FileSettings): FileSettings {
  return {
    useDocumentDir: runtimeUseDocumentDir === undefined ? base.useDocumentDir : runtimeUseDocumentDir,
    omitCourseName: runtimeOmitCourseName === undefined ? base.omitCourseName : runtimeOmitCourseName
  };
}

/** 一行自证串：只描述**覆盖**这一层（不掺持久化值，供启动期日志用）。 */
export function describeFileSettingsOverride(): string {
  return 'file settings override: runtimeUseDocumentDir='
    + (runtimeUseDocumentDir === undefined ? 'none' : runtimeUseDocumentDir.toString())
    + ' runtimeOmitCourseName='
    + (runtimeOmitCourseName === undefined ? 'none' : runtimeOmitCourseName.toString())
    + ' source=' + (runtimeUseDocumentDir === undefined && runtimeOmitCourseName === undefined
      ? 'none' : 'runtime-want-param');
}

/** 一行自证串：**实际生效值** + 覆盖来源（必须被打进 hilog）。 */
export function describeFileSettings(settings: FileSettings): string {
  return 'file settings: useDocumentDir=' + settings.useDocumentDir.toString()
    + ' omitCourseName=' + settings.omitCourseName.toString()
    + ' overrideUseDocumentDir=' + (runtimeUseDocumentDir === undefined ? 'none' : runtimeUseDocumentDir.toString())
    + ' overrideOmitCourseName=' + (runtimeOmitCourseName === undefined ? 'none' : runtimeOmitCourseName.toString())
    + ' source=' + (runtimeUseDocumentDir === undefined && runtimeOmitCourseName === undefined
      ? 'stored-default' : 'runtime-want-param');
}
