// SPDX-License-Identifier: GPL-3.0

import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';
import { AppPreferences } from '../data/AppPreferences';
import { SettingsRepository } from '../data/SettingsRepository';
import { AutoSyncScheduler } from './AutoSyncScheduler';
import { SyncService } from './SyncService';
import { SyncReport } from './SyncReport';
import { Logger } from '../app/Logger';

/**
 * Background periodic sync entry (backlog §1.5): the system pulls this
 * extension process on the delayed-task cadence (>= 2h, network permitted,
 * 2-minute callback cap). Everything storage-related must be initialized
 * here first — this process never runs EntryAbility.onCreate.
 */
export default class SyncWorkSchedulerAbility extends WorkSchedulerExtensionAbility {
  onWorkStart(_work: workScheduler.WorkInfo): void {
    AppPreferences.init(this.context)
      .then(() => SettingsRepository.initialize(this.context))
      .then(() => {
        AutoSyncScheduler.setRunner((): Promise<SyncReport | null> => SyncService.syncConfigured());
        return AutoSyncScheduler.runScheduledWork();
      })
      .catch((error: Error) => {
        Logger.warn(`SyncWorkSchedulerAbility failed: ${error.message}`);
      });
  }

  onWorkStop(): void {
    // The system stops the extension after the callback window; nothing is
    // held open that needs explicit release here.
  }
}
