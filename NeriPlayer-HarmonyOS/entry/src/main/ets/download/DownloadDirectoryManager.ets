// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { picker, fileShare } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../app/Logger';
import { SettingsRepository } from '../data/SettingsRepository';
import { DownloadDirectory } from './DownloadDirectory';

export enum DownloadDirectoryPickCode {
  APPLIED = 0,
  CANCELLED = 1,
  UNSUPPORTED = 2,
  FAILED = 3
}

export class DownloadDirectoryPickResult {
  code: DownloadDirectoryPickCode = DownloadDirectoryPickCode.FAILED;
  label: string = '';
  message: string = '';
}

/**
 * Device glue for the managed download directory (Android
 * OpenDocumentTree + takePersistableUriPermission): pick a folder with
 * DocumentViewPicker (FOLDER mode), persist the URI grant through fileShare,
 * and re-activate persisted grants on cold start. Pure rules live in
 * DownloadDirectory so they stay unit-testable.
 */
export class DownloadDirectoryManager {
  /**
   * Folder selection is gated by a system capability and only reaches Phone
   * devices from 26.0.0 (official picker guide). Since this build targets
   * 26.0.0 it should always be available; the probe is kept so the settings
   * row still degrades gracefully on devices trimmed of the syscap.
   */
  static folderPickerSupported(): boolean {
    return canIUse('SystemCapability.FileManagement.UserFileService.FolderSelection');
  }

  static currentUri(): string {
    return SettingsRepository.getString(SettingsRepository.KEY_DOWNLOAD_DIRECTORY_URI, '');
  }

  static describeCurrent(): string {
    return DownloadDirectory.describeDirectory(
      DownloadDirectoryManager.currentUri(),
      SettingsRepository.getString(SettingsRepository.KEY_DOWNLOAD_DIRECTORY_LABEL, ''));
  }

  static async pickAndApply(context: common.UIAbilityContext): Promise<DownloadDirectoryPickResult> {
    const result = new DownloadDirectoryPickResult();
    if (!DownloadDirectoryManager.folderPickerSupported()) {
      result.code = DownloadDirectoryPickCode.UNSUPPORTED;
      result.message = '当前系统不支持选择下载目录';
      return result;
    }
    try {
      const options = new picker.DocumentSelectOptions();
      options.selectMode = picker.DocumentSelectMode.FOLDER;
      options.maxSelectNumber = 1;
      const documentPicker = new picker.DocumentViewPicker(context);
      const uris: string[] = await documentPicker.select(options);
      if (uris.length === 0 || uris[0].length === 0) {
        result.code = DownloadDirectoryPickCode.CANCELLED;
        return result;
      }
      const uri = uris[0];
      // Persist the grant before saving the URI: without it the directory is
      // unreadable after the process exits.
      const policy: fileShare.PolicyInfo = {
        uri: uri,
        operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE
      };
      await fileShare.persistPermission([policy]);
      const label = DownloadDirectory.labelFromUri(uri);
      SettingsRepository.setString(SettingsRepository.KEY_DOWNLOAD_DIRECTORY_URI, uri);
      SettingsRepository.setString(SettingsRepository.KEY_DOWNLOAD_DIRECTORY_LABEL, label);
      result.code = DownloadDirectoryPickCode.APPLIED;
      result.label = label;
      return result;
    } catch (error) {
      const e = error as BusinessError;
      Logger.warn(`DownloadDirectoryManager.pickAndApply failed: ${e.code} ${e.message}`);
      result.code = DownloadDirectoryPickCode.FAILED;
      result.message = '设置下载目录失败，请重试';
      return result;
    }
  }

  /**
   * Cold start: persisted grants must be re-activated before any fs access
   * (official fileShare guide). Best-effort: committed files' playability
   * depends on it, but a failure must not block startup.
   */
  static activatePersisted(): void {
    const uri = DownloadDirectoryManager.currentUri();
    if (!DownloadDirectory.isCustomUri(uri)) {
      return;
    }
    const policy: fileShare.PolicyInfo = {
      uri: uri,
      operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE
    };
    fileShare.activatePermission([policy]).catch((error: BusinessError) => {
      Logger.warn(`activate download directory permission failed: ${error.code} ${error.message}`);
    });
  }

  /**
   * Back to the sandbox default. The old directory's persisted grant is kept
   * on purpose: catalog entries still point there and must stay playable.
   */
  static resetToDefault(): void {
    SettingsRepository.setString(SettingsRepository.KEY_DOWNLOAD_DIRECTORY_URI, '');
    SettingsRepository.setString(SettingsRepository.KEY_DOWNLOAD_DIRECTORY_LABEL, '');
  }
}
