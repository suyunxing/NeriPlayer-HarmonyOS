import { describe, it, expect } from '@ohos/hypium';
import { DownloadTaskStore } from '../../../main/ets/download/DownloadTaskStore';
import {
  DownloadProgress,
  DownloadStage,
  DownloadStatus,
  DownloadTask,
  downloadFailureText,
  isDownloadTaskClearable,
  shouldApplyTaskMutation
} from '../../../main/ets/download/DownloadModels';
import { DownloadRetryPolicy, DownloadNaming, DownloadTransportSelector } from '../../../main/ets/download/DownloadSupport';
import { DownloadTransportKind } from '../../../main/ets/download/DownloadModels';
import { HlsPlaylistParser } from '../../../main/ets/download/DownloadEngine';
import { ResumeFingerprint } from '../../../main/ets/download/DownloadStorage';
import { SongItem } from '../../../main/ets/model/SongItem';
import { stableKeyOf } from '../../../main/ets/model/SongIdentity';

function neteaseSong(id: number, name: string, artist: string): SongItem {
  const song = new SongItem(id, name, artist, 'netease', 0, 200000);
  song.channelId = 'netease';
  song.audioId = `${id}`;
  return song;
}

export default function downloadTaskStoreTest(): void {
  describe('DownloadTaskStore', () => {
    it('batchPrepareDeduplicatesAndIssuesUniqueAttemptIds', 0, () => {
      const store = new DownloadTaskStore();
      const batch: SongItem[] = [];
      for (let i = 0; i < 50; i++) {
        batch.push(neteaseSong(1000 + i, `Song ${i}`, 'Artist'));
      }
      batch.unshift(neteaseSong(1000, 'Song 0', 'Artist'));
      const queued = store.prepareBatch(batch);
      expect(queued.length).assertEqual(50);
      const ids = new Set<number>();
      for (const task of queued) {
        ids.add(task.attemptId);
      }
      expect(ids.size).assertEqual(50);
      expect(store.getTasks().length).assertEqual(50);
    });

    it('activeTasksAreKeptOnReprepare', 0, () => {
      const store = new DownloadTaskStore();
      const song = neteaseSong(1, 'A', 'X');
      const first = store.prepare(song);
      store.registerActive(stableKeyOf(song), first.attemptId);
      expect(store.getTask(stableKeyOf(song))!.status).assertEqual(DownloadStatus.DOWNLOADING);

      const second = store.prepare(song);
      expect(second.attemptId).assertEqual(first.attemptId);
    });

    it('reenterableTasksGetFreshAttemptId', 0, () => {
      const store = new DownloadTaskStore();
      const song = neteaseSong(2, 'B', 'X');
      const first = store.prepare(song);
      for (const status of [DownloadStatus.WAITING_NETWORK, DownloadStatus.FAILED,
        DownloadStatus.CANCELLED, DownloadStatus.COMPLETED]) {
        store.updateStatus(stableKeyOf(song), first.attemptId, status);
        const next = store.prepare(song);
        expect(next.attemptId > first.attemptId).assertTrue();
        expect(next.status).assertEqual(DownloadStatus.QUEUED);
      }
    });

    it('replaceExistingActiveTasksSupersedesActiveAttempt', 0, () => {
      const store = new DownloadTaskStore();
      const song = neteaseSong(3, 'C', 'X');
      const first = store.prepare(song);
      store.registerActive(stableKeyOf(song), first.attemptId);
      const next = store.prepare(song, true);
      expect(next.attemptId > first.attemptId).assertTrue();
      // The stale attempt can no longer mutate the task.
      expect(store.updateStatus(stableKeyOf(song), first.attemptId, DownloadStatus.FAILED)).assertFalse();
      expect(store.getTask(stableKeyOf(song))!.status).assertEqual(DownloadStatus.QUEUED);
    });

    it('mutationsAreGuardedByAttemptId', 0, () => {
      const store = new DownloadTaskStore();
      const song = neteaseSong(4, 'D', 'X');
      const task = store.prepare(song);
      const progress = new DownloadProgress();
      progress.attemptId = task.attemptId;
      progress.bytesRead = 10;
      progress.totalBytes = 100;
      expect(store.updateProgress(stableKeyOf(song), task.attemptId, progress)).assertTrue();
      expect(store.getTask(stableKeyOf(song))!.progress!.percentage()).assertEqual(10);
      expect(store.updateProgress(stableKeyOf(song), 999, progress)).assertFalse();
      expect(store.removeTask(stableKeyOf(song), 999)).assertFalse();
      expect(store.removeTask(stableKeyOf(song), task.attemptId)).assertTrue();
      expect(store.getTask(stableKeyOf(song))).assertNull();
    });

    it('waitingNetworkClearsProgressAndKeepsWorkingFiles', 0, () => {
      const store = new DownloadTaskStore();
      const song = neteaseSong(5, 'E', 'X');
      const task = store.prepare(song);
      store.applyWaitingNetwork(stableKeyOf(song), task.attemptId);
      const stored = store.getTask(stableKeyOf(song))!;
      expect(stored.status).assertEqual(DownloadStatus.WAITING_NETWORK);
      expect(stored.progress).assertNull();
      expect(isDownloadTaskClearable(stored.status)).assertFalse();
    });

    it('clearCompletedKeepsActiveAndWaitingTasks', 0, () => {
      const store = new DownloadTaskStore();
      const a = store.prepare(neteaseSong(6, 'F', 'X'));
      const b = store.prepare(neteaseSong(7, 'G', 'X'));
      const c = store.prepare(neteaseSong(8, 'H', 'X'));
      const d = store.prepare(neteaseSong(9, 'I', 'X'));
      store.registerActive(stableKeyOf(b.song), b.attemptId);
      store.updateStatus(stableKeyOf(c.song), c.attemptId, DownloadStatus.FAILED);
      store.updateStatus(stableKeyOf(d.song), d.attemptId, DownloadStatus.COMPLETED);
      store.clearCompleted();
      expect(store.getTasks().length).assertEqual(2);
      expect(store.getTask(stableKeyOf(a.song)) !== null).assertTrue();
      expect(store.getTask(stableKeyOf(b.song)) !== null).assertTrue();
    });

    it('percentageSemantics', 0, () => {
      const progress = new DownloadProgress();
      progress.totalBytes = 0;
      expect(progress.percentage()).assertEqual(-1);
      progress.totalBytes = 200;
      progress.bytesRead = 100;
      expect(progress.percentage()).assertEqual(50);
      progress.bytesRead = 200;
      expect(progress.percentage()).assertEqual(100);
      progress.stage = DownloadStage.FINALIZING;
      expect(progress.percentage()).assertEqual(100);
    });

    it('shouldApplyTaskMutationSemantics', 0, () => {
      const song = neteaseSong(10, 'J', 'X');
      const task = new DownloadTask(song, DownloadStatus.DOWNLOADING, 7);
      expect(shouldApplyTaskMutation(task, 7)).assertTrue();
      expect(shouldApplyTaskMutation(task, 8)).assertFalse();
      expect(shouldApplyTaskMutation(task, -1)).assertTrue();
    });

    it('failTaskRecordsReasonClearsProgressAndHonorsGuard', 0, () => {
      const store = new DownloadTaskStore();
      const song = neteaseSong(11, 'K', 'X');
      const task = store.prepare(song);
      const progress = new DownloadProgress();
      progress.attemptId = task.attemptId;
      progress.bytesRead = 10;
      progress.totalBytes = 100;
      store.updateProgress(stableKeyOf(song), task.attemptId, progress);
      expect(store.failTask(stableKeyOf(song), 999, 'stale attempt')).assertFalse();
      expect(store.failTask(stableKeyOf(song), task.attemptId, 'save to download directory failed')).assertTrue();
      const stored = store.getTask(stableKeyOf(song))!;
      expect(stored.status).assertEqual(DownloadStatus.FAILED);
      expect(stored.progress).assertNull();
      expect(stored.failureReason).assertEqual('save to download directory failed');
      // Requeueing issues a fresh attempt with a clean slate.
      const next = store.prepare(song);
      expect(store.getTask(stableKeyOf(song))!.failureReason).assertEqual('');
      expect(next.attemptId > task.attemptId).assertTrue();
    });
  });

  describe('DownloadFailureText', () => {
    it('mapsEngineReasonsToChineseForUsers', 0, () => {
      expect(downloadFailureText('no playable source')).assertEqual('未找到可下载的音源');
      expect(downloadFailureText('downloaded payload is not audio')).assertEqual('下载内容不是有效音频');
      expect(downloadFailureText('downloaded payload has filler corruption')).assertEqual('音源数据异常，已弃用损坏副本');
      expect(downloadFailureText('save to download directory failed'))
        .assertEqual('保存到下载目录失败，请检查目录是否可写');
      expect(downloadFailureText('retry attempts exhausted')).assertEqual('多次重试后仍失败');
      expect(downloadFailureText('unsupported HLS playlist')).assertEqual('不支持的音乐源格式');
      expect(downloadFailureText('HLS segment 3 failed')).assertEqual('分段下载失败');
      expect(downloadFailureText('HLS failed: socket hung up')).assertEqual('下载中断：socket hung up');
      expect(downloadFailureText('HTTP 403')).assertEqual('服务端返回 HTTP 403');
      expect(downloadFailureText('')).assertEqual('未知原因');
      expect(downloadFailureText('  ')).assertEqual('未知原因');
      expect(downloadFailureText('some raw net error')).assertEqual('some raw net error');
    });
  });

  describe('DownloadRetryPolicy', () => {
    it('delayScheduleAndRetryableClassification', 0, () => {
      expect(DownloadRetryPolicy.retryDelayMs(1)).assertEqual(1000);
      expect(DownloadRetryPolicy.retryDelayMs(2)).assertEqual(2000);
      expect(DownloadRetryPolicy.retryDelayMs(3)).assertEqual(4000);
      expect(DownloadRetryPolicy.retryDelayMs(4)).assertEqual(5000);
      expect(DownloadRetryPolicy.retryDelayMs(9)).assertEqual(5000);
      expect(DownloadRetryPolicy.isRetryableHttpError(429)).assertTrue();
      expect(DownloadRetryPolicy.isRetryableHttpError(503)).assertTrue();
      expect(DownloadRetryPolicy.isRetryableHttpError(404)).assertFalse();
      expect(DownloadRetryPolicy.isRetryableMessage('Connection reset by peer')).assertTrue();
      expect(DownloadRetryPolicy.isRetryableMessage('file not found')).assertFalse();
    });
  });

  describe('DownloadNaming', () => {
    it('rendersDefaultTemplate', 0, () => {
      const song = neteaseSong(1, '晴天', '周杰伦');
      expect(DownloadNaming.render(DownloadNaming.DEFAULT_TEMPLATE, song))
        .assertEqual('netease - 周杰伦 - 晴天');
    });

    it('rendersCustomTemplateAndSanitizesIllegalCharacters', 0, () => {
      const song = new SongItem(2, 'A/B:C', 'Artist?', 'Album', 0);
      expect(DownloadNaming.render('%album% - %title%', song)).assertEqual('Album - A_B_C');
      expect(DownloadNaming.sanitize('   ')).assertEqual('audio');
    });

    it('fallsBackToDefaultTemplateForDegenerateNames', 0, () => {
      const song = new SongItem(3, 'T', 'A', 'Album', 0);
      song.channelId = 'netease';
      // '%artist%' renders the single code point 'A': fall back to default.
      const rendered = DownloadNaming.renderWithFallback('%artist%', song);
      expect(rendered).assertEqual('netease - A - T');
    });

    it('infersSource', 0, () => {
      const netease = neteaseSong(4, 'N', 'A');
      expect(DownloadNaming.sourceOf(netease)).assertEqual('netease');
      const bili = new SongItem(5, 'B', 'A', 'bili收藏夹', 0);
      expect(DownloadNaming.sourceOf(bili)).assertEqual('bilibili');
      const ytm = new SongItem(6, 'Y', 'A', 'Album', 0);
      ytm.mediaUri = 'youtube_music|v=x';
      expect(DownloadNaming.sourceOf(ytm)).assertEqual('youtube_music');
    });

    it('workingFileNameShape', 0, () => {
      const song = neteaseSong(7, '晴 天', 'A');
      const name = DownloadNaming.workingFileName(song, 'netease - A - 晴 天', 'mp3');
      expect(name.startsWith('npdl_')).assertTrue();
      expect(name.endsWith('.mp3.download')).assertTrue();
      const parts = name.split('_');
      expect(parts.length >= 2).assertTrue();
      expect(parts[1].length).assertEqual(8);
    });
  });

  describe('DownloadTransportSelector', () => {
    it('selectsTransportByStreamShape', 0, () => {
      expect(DownloadTransportSelector.select(true, false, false)).assertEqual(DownloadTransportKind.HLS);
      expect(DownloadTransportSelector.select(false, true, false)).assertEqual(DownloadTransportKind.CHUNKED_RANGE);
      expect(DownloadTransportSelector.select(false, false, false)).assertEqual(DownloadTransportKind.DIRECT);
      expect(DownloadTransportSelector.select(false, true, true)).assertEqual(DownloadTransportKind.DIRECT);
    });
  });

  describe('HlsPlaylistParser', () => {
    it('parsesSegmentsAndFingerprintIsOrderSensitive', 0, () => {
      const text = '#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:9.5,\nseg1.ts\n#EXTINF:8.0,\nseg2.ts\n';
      const playlist = HlsPlaylistParser.parse(text);
      expect(playlist !== null).assertTrue();
      expect(playlist!.segmentUrls.length).assertEqual(2);
      expect(playlist!.segmentUrls[0]).assertEqual('seg1.ts');

      const reordered = '#EXTM3U\nseg2.ts\nseg1.ts\n';
      const other = HlsPlaylistParser.parse(reordered);
      expect(other!.fingerprint !== playlist!.fingerprint).assertTrue();
    });

    it('rejectsNonPlaylists', 0, () => {
      expect(HlsPlaylistParser.parse('not a playlist')).assertNull();
      expect(HlsPlaylistParser.parse('#EXTM3U\n#only comments\n')).assertNull();
    });
  });

  describe('ResumeFingerprint', () => {
    it('prefersEtagAsValidatorAndRoundTrips', 0, () => {
      const fp = new ResumeFingerprint();
      fp.sourceUrl = 'https://a/b.mp3';
      fp.etag = 'W/"abc"';
      fp.lastModified = 'Mon, 01 Jan 2026 00:00:00 GMT';
      fp.expectedContentLength = 123;
      expect(fp.validator()).assertEqual('W/"abc"');
      const restored = ResumeFingerprint.fromJson(fp.toJson());
      expect(restored !== null).assertTrue();
      expect(restored!.etag).assertEqual('W/"abc"');
      expect(restored!.expectedContentLength).assertEqual(123);
      restored!.etag = '';
      expect(restored!.validator()).assertEqual('Mon, 01 Jan 2026 00:00:00 GMT');
      expect(ResumeFingerprint.fromJson('bad {')).assertNull();
    });
  });
}


