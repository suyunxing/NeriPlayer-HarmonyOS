import { describe, it, expect } from '@ohos/hypium';
import { buildDownloadRows } from '../../../main/ets/download/DownloadRow';
import { DownloadStatus, DownloadTask } from '../../../main/ets/download/DownloadModels';
import { DownloadedSongEntry } from '../../../main/ets/download/DownloadStorage';
import { SongItem } from '../../../main/ets/model/SongItem';

function neteaseSong(id: number, name: string): SongItem {
  const song = new SongItem(id, name, 'Artist', 'netease', 0, 200000);
  song.channelId = 'netease';
  song.audioId = `${id}`;
  return song;
}

function catalogEntryOf(song: SongItem): DownloadedSongEntry {
  return new DownloadedSongEntry(
    // stableKeyOf is computed by callers of the catalog API; mirror it here.
    `${song.audioId}|netease|`,
    `/data/fake/${song.audioId}.mp3`,
    song.toJson(),
    0
  );
}

export default function downloadRowTest(): void {
  describe('DownloadRow', () => {
    it('taskRowsCarryMatchingCatalogEntry', 0, () => {
      const song = neteaseSong(1, 'A');
      const task = new DownloadTask(song, DownloadStatus.COMPLETED, 1);
      const rows = buildDownloadRows([task], [catalogEntryOf(song)]);
      expect(rows.length).assertEqual(1);
      expect(rows[0].status).assertEqual(DownloadStatus.COMPLETED);
      expect(rows[0].entry !== null).assertTrue();
      expect(rows[0].entry!.audioPath).assertEqual(`/data/fake/1.mp3`);
    });

    it('catalogOnlyEntriesStayVisibleAfterClearingRecords', 0, () => {
      // 清空记录 removes task rows; the committed download must still render
      // as a manageable row or the library count cannot be reconciled.
      const song = neteaseSong(2, 'B');
      const rows = buildDownloadRows([], [catalogEntryOf(song)]);
      expect(rows.length).assertEqual(1);
      expect(rows[0].stableKey).assertEqual(`${song.audioId}|netease|`);
      expect(rows[0].status).assertEqual(DownloadStatus.COMPLETED);
      expect(rows[0].entry !== null).assertTrue();
      expect(rows[0].song.displayName).assertEqual('B');
    });

    it('taskAndCatalogAreMergedWithoutDuplicates', 0, () => {
      const shared = neteaseSong(3, 'C');
      const extra = neteaseSong(4, 'D');
      const task = new DownloadTask(shared, DownloadStatus.DOWNLOADING, 2);
      const rows = buildDownloadRows([task], [catalogEntryOf(shared), catalogEntryOf(extra)]);
      expect(rows.length).assertEqual(2);
      expect(rows[0].status).assertEqual(DownloadStatus.DOWNLOADING);
      expect(rows[0].entry !== null).assertTrue();
      expect(rows[1].song.displayName).assertEqual('D');
    });

    it('activeTaskWithoutEntryHasNoDeleteableDownload', 0, () => {
      const song = neteaseSong(5, 'E');
      const task = new DownloadTask(song, DownloadStatus.QUEUED, 3);
      const rows = buildDownloadRows([task], []);
      expect(rows.length).assertEqual(1);
      expect(rows[0].entry === null).assertTrue();
    });
  });
}
