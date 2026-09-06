import { describe, it, expect } from '@ohos/hypium';
import { Constants } from '../../../main/ets/app/Constants';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';
import {
  ListenTogetherChannels
} from '../../../main/ets/listentogether/protocol/ListenTogetherChannels';
import {
  ListenTogetherTrack,
  createListenTogetherTrack
} from '../../../main/ets/listentogether/protocol/ListenTogetherTrack';
import {
  ListenTogetherRoomSettings
} from '../../../main/ets/listentogether/protocol/ListenTogetherRoomModels';
import {
  listenTogetherTrackToSongItem,
  listenTogetherTrackWithStreamUrl,
  listenTogetherTrackWithStreamUrls,
  songItemToListenTogetherTrackOrNull
} from '../../../main/ets/listentogether/mapping/ListenTogetherTrackMapping';
import {
  MAX_LISTEN_TOGETHER_STREAM_URL_CANDIDATES,
  trustedListenTogetherStreamUrl,
  trustedListenTogetherStreamUrls
} from '../../../main/ets/listentogether/mapping/ListenTogetherStreamUrlPolicy';
import {
  extractListenTogetherYouTubeMusicPlaylistId,
  extractListenTogetherYouTubeMusicVideoId
} from '../../../main/ets/listentogether/mapping/ListenTogetherTrackIdentity';
import {
  LISTEN_TOGETHER_MAX_SHAREABLE_QUEUE_SIZE,
  boundedListenTogetherQueueAroundStableKey
} from '../../../main/ets/listentogether/playback/ListenTogetherQueuePolicy';
import {
  listenTogetherShareableQueueSnapshot,
  mergeListenTogetherCurrentTrack
} from '../../../main/ets/listentogether/playback/ListenTogetherShareableQueueSnapshot';

const PRIMARY_STREAM_URL: string = 'https://m701.music.126.net/primary.mp3';
const BACKUP_A_STREAM_URL: string = 'https://m702.music.126.net/backup-a.mp3';
const BACKUP_B_STREAM_URL: string = 'https://m703.music.126.net/backup-b.mp3';
const BACKUP_C_STREAM_URL: string = 'https://m704.music.126.net/backup-c.mp3';

function neteaseSong(audioId: string): SongItem {
  const song = new SongItem(Number(audioId), `Song ${audioId}`, 'Artist', '叶惠美', 0, 269000,
    'https://cover.example.com/1.jpg');
  song.channelId = ListenTogetherChannels.NETEASE;
  song.audioId = audioId;
  return song;
}

function localSong(audioId: string): SongItem {
  const song = new SongItem(Number(audioId), `Local ${audioId}`, 'Artist', '', 0, 120000, '',
    `file:///data/music/${audioId}.flac`, MusicPlatform.LOCAL);
  song.channelId = ListenTogetherChannels.LOCAL;
  song.audioId = audioId;
  return song;
}

function neteaseTrack(audioId: string): ListenTogetherTrack {
  return createListenTogetherTrack(
    `netease:${audioId}`,
    ListenTogetherChannels.NETEASE,
    audioId,
    `Song ${audioId}`,
    'Artist'
  );
}

function stableKeys(tracks: ListenTogetherTrack[]): string[] {
  const keys: string[] = [];
  for (const track of tracks) {
    keys.push(track.stableKey);
  }
  return keys;
}

export default function listenTogetherMappingTest(): void {
  describe('ListenTogetherSongItemToTrack', () => {
    it('mapsARemoteSongOntoTheWireModel', 0, () => {
      const song = neteaseSong('2');
      song.mediaUri = 'netease://2';
      song.streamUrl = PRIMARY_STREAM_URL;

      const track = songItemToListenTogetherTrackOrNull(song);

      expect(track !== null).assertTrue();
      const mapped = track as ListenTogetherTrack;
      expect(mapped.stableKey).assertEqual('netease:2');
      expect(mapped.channelId).assertEqual(ListenTogetherChannels.NETEASE);
      expect(mapped.audioId).assertEqual('2');
      expect(mapped.name).assertEqual('Song 2');
      expect(mapped.artist).assertEqual('Artist');
      expect(mapped.album).assertEqual('叶惠美');
      expect(mapped.durationMs).assertEqual(269000);
      expect(mapped.coverUrl).assertEqual('https://cover.example.com/1.jpg');
      expect(mapped.mediaUri).assertEqual('netease://2');
      expect(mapped.streamUrl).assertEqual(PRIMARY_STREAM_URL);
      expect(mapped.streamUrls.length).assertEqual(1);
      expect(mapped.streamUrls[0]).assertEqual(PRIMARY_STREAM_URL);
    });

    it('dropsLocalSongsUnlessTheyAreExplicitlyIncluded', 0, () => {
      const song = localSong('7');

      expect(songItemToListenTogetherTrackOrNull(song)).assertNull();

      const included = songItemToListenTogetherTrackOrNull(song, true);
      expect(included !== null).assertTrue();
      expect((included as ListenTogetherTrack).stableKey).assertEqual('local:7');
    });

    it('derivesTheBilibiliSubAudioIdFromTheAlbumTag', 0, () => {
      const song = new SongItem(0, 'Bili Song', 'UP', `${Constants.BILIBILI_IDENTITY_HINT}|c1`,
        0, 240000, '', '', MusicPlatform.BILIBILI);
      song.channelId = ListenTogetherChannels.BILIBILI;
      song.audioId = 'BV1abc';

      const track = songItemToListenTogetherTrackOrNull(song) as ListenTogetherTrack;

      expect(track.stableKey).assertEqual('bilibili:BV1abc:c1');
      expect(track.subAudioId).assertEqual('c1');
      expect(track.playlistContextId).assertNull();
    });

    it('acceptsBothYouTubeMusicMediaUriForms', 0, () => {
      const androidForm = new SongItem(0, 'YTM Song', 'Channel', '', 0, 200000, '',
        'ytmusic://video/abc123?playlistId=PL9', MusicPlatform.YOUTUBE_MUSIC);
      const nativeForm = new SongItem(0, 'YTM Song', 'Channel', '', 0, 200000, '',
        `${Constants.YOUTUBE_MUSIC_MEDIA_PREFIX}abc123`, MusicPlatform.YOUTUBE_MUSIC);

      expect(extractListenTogetherYouTubeMusicVideoId(androidForm.mediaUri)).assertEqual('abc123');
      expect(extractListenTogetherYouTubeMusicPlaylistId(androidForm.mediaUri)).assertEqual('PL9');
      expect(extractListenTogetherYouTubeMusicVideoId(nativeForm.mediaUri)).assertEqual('abc123');
      expect(extractListenTogetherYouTubeMusicPlaylistId(nativeForm.mediaUri)).assertNull();

      const fromAndroid = songItemToListenTogetherTrackOrNull(androidForm) as ListenTogetherTrack;
      expect(fromAndroid.channelId).assertEqual(ListenTogetherChannels.YOUTUBE_MUSIC);
      expect(fromAndroid.stableKey).assertEqual('youtubeMusic:abc123:PL9');
      expect(fromAndroid.playlistContextId).assertEqual('PL9');
      // The media URI is omitted so the receiver rebuilds it in its own format.
      expect(fromAndroid.mediaUri).assertNull();

      const fromNative = songItemToListenTogetherTrackOrNull(nativeForm) as ListenTogetherTrack;
      expect(fromNative.stableKey).assertEqual('youtubeMusic:abc123');
      expect(fromNative.mediaUri).assertNull();
    });
  });

  describe('ListenTogetherTrackToSongItem', () => {
    it('neverWritesAPeerSuppliedStreamUrlIntoTheSongItem', 0, () => {
      const track = neteaseTrack('2');
      track.streamUrl = 'https://evil.example.com/payload.mp3';
      track.streamUrls = ['https://evil.example.com/payload.mp3'];
      track.album = '叶惠美';
      track.durationMs = 269000;

      const song = listenTogetherTrackToSongItem(track);

      expect(song.streamUrl).assertEqual('');
      expect(song.channelId).assertEqual(ListenTogetherChannels.NETEASE);
      expect(song.audioId).assertEqual('2');
      expect(song.name).assertEqual('Song 2');
      expect(song.album).assertEqual('叶惠美');
      expect(song.durationMs).assertEqual(269000);
      expect(song.platform).assertEqual(MusicPlatform.NETEASE);
    });

    it('roundTripsTheStableKeyBackThroughTheSongItem', 0, () => {
      const track = neteaseTrack('2');
      const reMapped = songItemToListenTogetherTrackOrNull(listenTogetherTrackToSongItem(track));

      expect((reMapped as ListenTogetherTrack).stableKey).assertEqual('netease:2');
    });

    it('rebuildsTheYouTubeMusicMediaUriInThisAppsFormat', 0, () => {
      const track = createListenTogetherTrack(
        'youtubeMusic:abc123:PL9',
        ListenTogetherChannels.YOUTUBE_MUSIC,
        'abc123',
        'YTM Song',
        'Channel'
      );
      track.playlistContextId = 'PL9';

      const song = listenTogetherTrackToSongItem(track);

      expect(song.mediaUri).assertEqual(`${Constants.YOUTUBE_MUSIC_MEDIA_PREFIX}abc123`);
      expect(song.channelId).assertEqual(Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM);
      expect(song.playlistContextId).assertEqual('PL9');
      expect(song.platform).assertEqual(MusicPlatform.YOUTUBE_MUSIC);
    });

    it('rebuildsTheBilibiliAlbumTag', 0, () => {
      const track = createListenTogetherTrack(
        'bilibili:BV1abc:c1',
        ListenTogetherChannels.BILIBILI,
        'BV1abc',
        'Bili Song',
        'UP'
      );
      track.subAudioId = 'c1';

      const song = listenTogetherTrackToSongItem(track);

      expect(song.album).assertEqual(`${Constants.BILIBILI_IDENTITY_HINT}|c1`);
      expect(song.subAudioId).assertEqual('c1');
      expect(song.platform).assertEqual(MusicPlatform.BILIBILI);
      expect(songItemToListenTogetherTrackOrNull(song) !== null).assertTrue();
    });
  });

  describe('ListenTogetherStreamUrlPolicy', () => {
    it('keepsAWhitelistedHostPerChannel', 0, () => {
      expect(trustedListenTogetherStreamUrl(
        ListenTogetherChannels.BILIBILI,
        'https://upos-sz-mirror.bilivideo.com/x.m4s'
      )).assertEqual('https://upos-sz-mirror.bilivideo.com/x.m4s');
      expect(trustedListenTogetherStreamUrl(ListenTogetherChannels.NETEASE, PRIMARY_STREAM_URL))
        .assertEqual(PRIMARY_STREAM_URL);
      // A netease URL is not trusted on the bilibili channel and vice versa.
      expect(trustedListenTogetherStreamUrl(ListenTogetherChannels.BILIBILI, PRIMARY_STREAM_URL))
        .assertNull();
    });

    it('blocksNonHttpSchemesAndUntrustedHosts', 0, () => {
      expect(trustedListenTogetherStreamUrl(
        ListenTogetherChannels.NETEASE,
        'file:///data/music/1.mp3'
      )).assertNull();
      expect(trustedListenTogetherStreamUrl(ListenTogetherChannels.NETEASE, null)).assertNull();
      expect(trustedListenTogetherStreamUrl(ListenTogetherChannels.NETEASE, '   ')).assertNull();
      expect(trustedListenTogetherStreamUrl(ListenTogetherChannels.LOCAL, PRIMARY_STREAM_URL))
        .assertNull();
    });

    it('readsTheHostAfterTheLastAtSoUserinfoCannotSpoofIt', 0, () => {
      const blocked: string[] = [];
      const result = trustedListenTogetherStreamUrl(
        ListenTogetherChannels.NETEASE,
        'https://music.126.net@evil.com/x',
        (channelId: string, host: string): void => {
          blocked.push(`${channelId}/${host}`);
        }
      );

      expect(result).assertNull();
      expect(blocked.length).assertEqual(1);
      // Only the channel and the host are reported: never the signed URL.
      expect(blocked[0]).assertEqual('netease/evil.com');
    });

    it('dedupesAndCapsTheCandidateList', 0, () => {
      const trusted = trustedListenTogetherStreamUrls(
        ListenTogetherChannels.NETEASE,
        [PRIMARY_STREAM_URL, BACKUP_A_STREAM_URL, PRIMARY_STREAM_URL, BACKUP_B_STREAM_URL,
          BACKUP_C_STREAM_URL]
      );

      expect(MAX_LISTEN_TOGETHER_STREAM_URL_CANDIDATES).assertEqual(3);
      expect(trusted.length).assertEqual(3);
      expect(trusted[0]).assertEqual(PRIMARY_STREAM_URL);
      expect(trusted[1]).assertEqual(BACKUP_A_STREAM_URL);
      expect(trusted[2]).assertEqual(BACKUP_B_STREAM_URL);
    });

    it('appendsTheLegacySingleUrlLast', 0, () => {
      const trusted = trustedListenTogetherStreamUrls(
        ListenTogetherChannels.NETEASE,
        [BACKUP_A_STREAM_URL],
        PRIMARY_STREAM_URL
      );

      expect(trusted.length).assertEqual(2);
      expect(trusted[0]).assertEqual(BACKUP_A_STREAM_URL);
      expect(trusted[1]).assertEqual(PRIMARY_STREAM_URL);
      expect(trustedListenTogetherStreamUrls(
        ListenTogetherChannels.NETEASE, [PRIMARY_STREAM_URL], null, 0
      ).length).assertEqual(0);
    });

    it('reusesTheTrackWhenNothingMoved', 0, () => {
      const track = neteaseTrack('2');
      track.streamUrl = PRIMARY_STREAM_URL;
      track.streamUrls = [PRIMARY_STREAM_URL];

      expect(listenTogetherTrackWithStreamUrls(track, [PRIMARY_STREAM_URL]) === track).assertTrue();

      const blockedOnly = listenTogetherTrackWithStreamUrl(track, 'https://evil.com/x.mp3');
      expect(blockedOnly === track).assertFalse();
      expect(blockedOnly.streamUrl).assertNull();
      expect(blockedOnly.streamUrls.length).assertEqual(0);
      // The input track is left untouched.
      expect(track.streamUrl).assertEqual(PRIMARY_STREAM_URL);
    });
  });

  describe('ListenTogetherShareableQueue', () => {
    it('attachesResolvedStreamUrlsToTheCurrentTrackOnly', 0, () => {
      const queue: SongItem[] = [neteaseSong('1'), neteaseSong('2'), neteaseSong('3')];

      const snapshot = listenTogetherShareableQueueSnapshot(queue, 1, [PRIMARY_STREAM_URL]);

      expect(snapshot.currentIndex).assertEqual(1);
      expect(stableKeys(snapshot.tracks).join(',')).assertEqual('netease:1,netease:2,netease:3');
      expect(snapshot.tracks[1].streamUrls.length).assertEqual(1);
      expect(snapshot.tracks[1].streamUrl).assertEqual(PRIMARY_STREAM_URL);
      expect(snapshot.tracks[0].streamUrls.length).assertEqual(0);
      expect(snapshot.tracks[2].streamUrls.length).assertEqual(0);
    });

    it('honoursShareAudioLinksAndTheIncludeFlag', 0, () => {
      const queue: SongItem[] = [neteaseSong('1'), neteaseSong('2')];
      const settings = new ListenTogetherRoomSettings();
      settings.shareAudioLinks = false;

      const withoutLinks = listenTogetherShareableQueueSnapshot(
        queue, 1, [PRIMARY_STREAM_URL], settings);
      expect(withoutLinks.tracks[1].streamUrls.length).assertEqual(0);
      expect(withoutLinks.tracks[1].streamUrl).assertNull();

      const withoutResolved = listenTogetherShareableQueueSnapshot(
        queue, 1, [PRIMARY_STREAM_URL], null, false);
      expect(withoutResolved.tracks[1].streamUrls.length).assertEqual(0);
    });

    it('dropsUnshareableEntriesAndRecomputesTheCurrentIndex', 0, () => {
      const queue: SongItem[] = [localSong('9'), neteaseSong('1'), neteaseSong('2')];

      const snapshot = listenTogetherShareableQueueSnapshot(queue, 2, []);

      expect(stableKeys(snapshot.tracks).join(',')).assertEqual('netease:1,netease:2');
      expect(snapshot.currentIndex).assertEqual(1);
      expect(listenTogetherShareableQueueSnapshot([], 0, []).tracks.length).assertEqual(0);
      // A current index past the end clamps onto the last entry.
      expect(listenTogetherShareableQueueSnapshot(queue, 99, []).currentIndex).assertEqual(1);
    });

    it('windowsAHugeQueueAroundThePlayingTrack', 0, () => {
      const queue: ListenTogetherTrack[] = [];
      for (let i = 0; i < 2500; i++) {
        queue.push(neteaseTrack(`${i}`));
      }

      const bounded = boundedListenTogetherQueueAroundStableKey(queue, 'netease:2100');

      expect(LISTEN_TOGETHER_MAX_SHAREABLE_QUEUE_SIZE).assertEqual(2000);
      expect(bounded.length).assertEqual(2000);
      expect(bounded[0].stableKey).assertEqual('netease:500');
      expect(bounded[1999].stableKey).assertEqual('netease:2499');
      expect(stableKeys(bounded).indexOf('netease:2100')).assertEqual(1600);
      // A queue inside the limit is returned as-is.
      const small: ListenTogetherTrack[] = [neteaseTrack('1')];
      expect(boundedListenTogetherQueueAroundStableKey(small, 'netease:1') === small).assertTrue();
    });

    it('mergesTheAuthoritativeCurrentTrack', 0, () => {
      const queue: ListenTogetherTrack[] = [neteaseTrack('1'), neteaseTrack('2')];
      const authoritative = neteaseTrack('2');
      authoritative.streamUrl = PRIMARY_STREAM_URL;

      const merged = mergeListenTogetherCurrentTrack(queue, 1, authoritative);
      expect(merged === queue).assertFalse();
      expect(merged[1].streamUrl).assertEqual(PRIMARY_STREAM_URL);
      expect(queue[1].streamUrl).assertNull();

      expect(mergeListenTogetherCurrentTrack(queue, 1, null) === queue).assertTrue();
      expect(mergeListenTogetherCurrentTrack(queue, 5, authoritative) === queue).assertTrue();
      expect(mergeListenTogetherCurrentTrack(queue, 1, neteaseTrack('2')) === queue).assertTrue();
    });
  });
}
