import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { DownloadTask } from '../model/DownloadTask';
import { Logger } from '../app/Logger';

/**
 * Sandbox file management for the download pipeline. Downloads are stored in
 * filesDir/downloads until the directory-picker migration is implemented.
 */
export class DownloadFileStore {
  static readonly DIR_NAME: string = 'downloads';

  static ensureDirSync(context: common.Context): string {
    const dir = `${context.filesDir}/${DownloadFileStore.DIR_NAME}`;
    let exists = false;
    try {
      exists = fileIo.accessSync(dir);
    } catch (error) {
      exists = false;
    }
    if (!exists) {
      try {
        fileIo.mkdirSync(dir);
      } catch (mkdirError) {
        const e = mkdirError as Error;
        Logger.warn(`DownloadFileStore.ensureDirSync failed: ${e.message}`);
      }
    }
    return dir;
  }

  static finalPath(task: DownloadTask): string {
    return task.filePath;
  }

  static partialPath(task: DownloadTask): string {
    const base = DownloadFileStore.finalPath(task);
    return base.length === 0 ? '' : `${base}.part`;
  }

  static buildFinalPath(dir: string, task: DownloadTask): string {
    return `${dir}/${task.id}_${task.fileName}`;
  }

  static partialSize(task: DownloadTask): number {
    const path = DownloadFileStore.partialPath(task);
    if (path.length === 0) {
      return 0;
    }
    try {
      const stat = fileIo.statSync(path);
      return stat.size;
    } catch (error) {
      return 0;
    }
  }

  static deleteTaskFiles(task: DownloadTask): void {
    const partial = DownloadFileStore.partialPath(task);
    const final = DownloadFileStore.finalPath(task);
    if (partial.length > 0) {
      try {
        fileIo.unlinkSync(partial);
      } catch (error) {
        Logger.debug(`DownloadFileStore delete partial failed: ${partial}`);
      }
    }
    if (final.length > 0) {
      try {
        fileIo.unlinkSync(final);
      } catch (error) {
        Logger.debug(`DownloadFileStore delete final failed: ${final}`);
      }
    }
  }

  static resetPartial(task: DownloadTask): void {
    const path = DownloadFileStore.partialPath(task);
    if (path.length === 0) {
      return;
    }
    try {
      fileIo.unlinkSync(path);
    } catch (error) {
      // Missing file is the expected state when starting from zero.
    }
  }

  static writeChunk(task: DownloadTask, offset: number, body: ArrayBuffer): void {
    const path = DownloadFileStore.partialPath(task);
    if (path.length === 0 || body.byteLength === 0) {
      return;
    }
    let file: fileIo.File | null = null;
    try {
      if (offset === 0) {
        DownloadFileStore.resetPartial(task);
      }
      file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      fileIo.writeSync(file.fd, body, { offset: offset, length: body.byteLength });
    } catch (error) {
      const e = error as Error;
      Logger.warn(`DownloadFileStore.writeChunk failed: ${e.message}`);
      throw new Error(`Write chunk failed: ${e.message}`);
    } finally {
      if (file !== null) {
        try {
          fileIo.closeSync(file);
        } catch (closeError) {
          const e = closeError as Error;
          Logger.debug(`DownloadFileStore.close failed: ${e.message}`);
        }
      }
    }
  }

  static commitPartial(task: DownloadTask): void {
    const partial = DownloadFileStore.partialPath(task);
    const final = DownloadFileStore.finalPath(task);
    if (partial.length === 0 || final.length === 0) {
      return;
    }
    try {
      fileIo.unlinkSync(final);
    } catch (error) {
      // Missing previous final file is fine.
    }
    try {
      fileIo.copyFileSync(partial, final);
    } catch (error) {
      const e = error as Error;
      Logger.warn(`DownloadFileStore.commitPartial failed: ${e.message}`);
      throw new Error(`Commit partial failed: ${e.message}`);
    }
    try {
      fileIo.unlinkSync(partial);
    } catch (error) {
      Logger.debug('DownloadFileStore.commitPartial: partial cleanup failed');
    }
  }

  static writeText(path: string, content: string): void {
    if (path.length === 0 || content.length === 0) {
      return;
    }
    try {
      fileIo.unlinkSync(path);
    } catch (error) {
      // Missing file is fine.
    }
    let file: fileIo.File | null = null;
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      fileIo.writeSync(file.fd, content);
    } catch (error) {
      const e = error as Error;
      Logger.warn(`DownloadFileStore.writeText failed: ${e.message}`);
      throw new Error(`Write text failed: ${e.message}`);
    } finally {
      if (file !== null) {
        try {
          fileIo.closeSync(file);
        } catch (closeError) {
          const e = closeError as Error;
          Logger.debug(`DownloadFileStore.close text failed: ${e.message}`);
        }
      }
    }
  }
}
