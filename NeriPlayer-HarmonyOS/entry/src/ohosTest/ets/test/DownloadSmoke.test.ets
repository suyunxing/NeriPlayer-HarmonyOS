import { describe, it, expect } from '@ohos/hypium';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NeteaseApi } from '../../../main/ets/network/NeteaseApi';
import { AppPreferences } from '../../../main/ets/data/AppPreferences';
import { DownloadEngine } from '../../../main/ets/download/DownloadEngine';
import { DownloadStorage } from '../../../main/ets/download/DownloadStorage';
import { DownloadStatus, DownloadTask } from '../../../main/ets/download/DownloadModels';
import { SongItem } from '../../../main/ets/model/SongItem';
import { stableKeyOf } from '../../../main/ets/model/SongIdentity';

function ensureEngineReady(): void {
  // Initialized lazily inside the test: running engine startup from
  // TestAbility.onCreate disturbs the hypium/delegator lifecycle.
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  const context = delegator.getAppContext() as common.Context;
  DownloadEngine.init(context);
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => setTimeout(resolve, ms));
}

function findTask(songKey: string): DownloadTask | undefined {
  return DownloadEngine.getTasks().find((task: DownloadTask) => stableKeyOf(task.song) === songKey);
}

async function waitTerminal(songKey: string, timeoutMs: number): Promise<DownloadStatus | null> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const task = findTask(songKey);
    if (task === undefined) {
      return null;
    }
    if (task.status === DownloadStatus.COMPLETED || task.status === DownloadStatus.FAILED
      || task.status === DownloadStatus.CANCELLED) {
      return task.status;
    }
    await sleep(2000);
  }
  const task = findTask(songKey);
  return task === undefined ? null : task.status;
}

/** Removes leftovers of previous runs so each run exercises a fresh transfer. */
function purgeDownloadDirs(): void {
  const dirs = [DownloadStorage.downloadDir(), DownloadStorage.stagingDir()];
  for (const dir of dirs) {
    try {
      for (const name of fileIo.listFileSync(dir)) {
        fileIo.unlinkSync(`${dir}/${String(name)}`);
      }
    } catch (error) {
      // Directory may not exist yet on a fresh install.
    }
  }
}

export default function downloadSmokeTest(): void {
  describe('ActsDownloadSmokeTest', () => {
    it('neteaseSongDownloadsCommitsAndReplaysFromCatalog', 0, async () => {
      ensureEngineReady();
      // Real network path: search -> enqueue -> transfer -> commit -> catalog.
      const results = await NeteaseApi.search('晴天 周杰伦', 5);
      expect(results.length > 0).assertTrue();
      const song = results[0];
      const songKey = stableKeyOf(song);
      hilog.info(0x0000, 'downloadSmoke', 'song=%{public}s key=%{public}s',
        song.displayName, songKey);

      purgeDownloadDirs();
      await DownloadStorage.removeCatalogEntry(song);
      DownloadEngine.clearAllTasks();

      DownloadEngine.enqueue([song]);
      const status = await waitTerminal(songKey, 180000);
      hilog.info(0x0000, 'downloadSmoke', 'final status=%{public}d', status === null ? -1 : status);
      expect(status).assertEqual(DownloadStatus.COMPLETED);

      const rawCatalog = await AppPreferences.getString('downloaded_catalog', '');
      hilog.info(0x0000, 'downloadSmoke', 'raw catalog len=%{public}d head=%{public}s',
        rawCatalog.length, rawCatalog.substring(0, 100));
      const entriesNow = await DownloadStorage.getCatalog();
      hilog.info(0x0000, 'downloadSmoke', 'catalog size=%{public}d first=%{public}s',
        entriesNow.length, entriesNow.length > 0 ? `${entriesNow[0].stableKey} -> ${entriesNow[0].audioPath}` : 'none');

      const entry = await DownloadStorage.findCatalogEntry(song);
      hilog.info(0x0000, 'downloadSmoke', 'catalog entry=%{public}s',
        entry === null ? 'null' : `${entry.stableKey} -> ${entry.audioPath}`);
      expect(entry !== null).assertTrue();
      expect(entry!.audioPath.length > 0).assertTrue();
      const entrySize = entry === null ? -1 : DownloadStorage.fileSize(entry!.audioPath);
      hilog.info(0x0000, 'downloadSmoke', 'catalog file size=%{public}d', entrySize);
      expect(entrySize > 0).assertTrue();
      // The committed file opens read-only, i.e. the offline playback channel.
      const file = fileIo.openSync(entry!.audioPath, fileIo.OpenMode.READ_ONLY);
      fileIo.closeSync(file);

      // Re-enqueue short-circuits through the catalog: no re-transfer.
      DownloadEngine.enqueue([song]);
      const again = await waitTerminal(songKey, 30000);
      expect(again).assertEqual(DownloadStatus.COMPLETED);
      DownloadEngine.clearAllTasks();
    });
  });
}
