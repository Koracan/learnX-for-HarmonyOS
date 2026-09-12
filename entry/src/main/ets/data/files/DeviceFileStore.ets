/*
 * `FileStore` 的设备实现：`@ohos.file.fs` + `common.Context` 的两个根目录。
 *
 * 只有本文件碰文件系统平台 API；路径规则全部来自 `domain/files/FilePath`。
 * 所有失败都不抛到调用方以外的地方（除 `openSink`/写失败，那两条必须让编排层知道）。
 */

import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';
import { FileRoots, FileSink, FileStore } from './FileStorePort';

/** 一条已打开的文件句柄。 */
class DeviceFileSink implements FileSink {
  private file: fs.File | null;

  constructor(file: fs.File) {
    this.file = file;
  }

  write(chunk: ArrayBuffer): void {
    const file: fs.File | null = this.file;
    if (file === null) {
      throw new Error('file sink already closed');
    }
    fs.writeSync(file.fd, chunk);
  }

  close(): void {
    const file: fs.File | null = this.file;
    if (file === null) {
      return;
    }
    this.file = null;
    fs.closeSync(file);
  }

  abort(): void {
    const file: fs.File | null = this.file;
    if (file === null) {
      return;
    }
    this.file = null;
    try {
      fs.closeSync(file);
    } catch (error) {
      // 句柄可能已被平台回收；这里只关心"别再往它写"。
    }
  }
}

/** 设备文件系统端口。 */
export class DeviceFileStore implements FileStore {
  private readonly context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  roots(): FileRoots {
    return { filesDir: this.context.filesDir, cacheDir: this.context.cacheDir };
  }

  ensureDir(dir: string): void {
    if (this.exists(dir)) {
      return;
    }
    fs.mkdirSync(dir, true);
  }

  exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (error) {
      return false;
    }
  }

  openSink(path: string): FileSink {
    const file: fs.File = fs.openSync(path,
      fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    return new DeviceFileSink(file);
  }

  remove(path: string): void {
    try {
      fs.unlinkSync(path);
    } catch (error) {
      // 不存在 / 已被删掉都算成功。
    }
  }

  removeTree(path: string): void {
    if (!this.exists(path)) {
      return;
    }
    let isDirectory: boolean = false;
    try {
      isDirectory = fs.statSync(path).isDirectory();
    } catch (error) {
      isDirectory = false;
    }
    if (!isDirectory) {
      this.remove(path);
      return;
    }
    // 平台 rmdirSync 对非空目录抛 13900032，所以自己递归（"清理缓存"必须真的删干净）。
    let names: string[] = [];
    try {
      names = fs.listFileSync(path);
    } catch (error) {
      names = [];
    }
    for (let i = 0; i < names.length; i++) {
      this.removeTree(path + '/' + names[i]);
    }
    try {
      fs.rmdirSync(path);
    } catch (error) {
      // 目录已被删掉 / 只读文件系统：留给调用方按"文件是否还在"判定。
    }
  }

  fileSize(path: string): number {
    try {
      const info: fs.Stat = fs.statSync(path);
      return info.isDirectory() ? 0 : info.size;
    } catch (error) {
      return 0;
    }
  }
}
