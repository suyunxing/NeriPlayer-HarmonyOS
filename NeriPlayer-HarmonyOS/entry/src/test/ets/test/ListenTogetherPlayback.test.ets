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
  ListenTogetherRoomState,
  createListenTogetherRoomState
} from '../../../main/ets/listentogether/protocol/ListenTogetherRoomModels';
import {
  ListenTogetherEvent,
  createListenTogetherEvent
} from '../../../main/ets/listentogether/protocol/ListenTogetherEventModels';
import {
  hasSameListenTogetherTrackSequence,
  indexOfListenTogetherTrack,
  listenTogetherCurrentStableKey,
  listenTogetherRequestedStableKey,
  listenTogetherTargetSongItem,
  sameListenTogetherTrack
} from '../../../main/ets/listentogether/playback/ListenTogetherPlaybackTrack';
import {
  normalizedDirectStreamUrl,
  shouldReloadListenTogetherAuthoritativeStream,
  shouldWaitForListenTogetherAuthoritativeStreamPlayback
} from '../../../main/ets/listentogether/playback/ListenTogetherStreamPolicy';

const REMOTE_STREAM_URL: string = 'https://m701.music.126.net/remote.mp3';
const LOCAL_STREAM_URL: string = 'https://m702.music.126.net/local.mp3';

function neteaseTrack(audioId: string): ListenTogetherTrack {
  return createListenTogetherTrack(
    `netease:${audioId}`,
    ListenTogetherChannels.NETEASE,
    audioId,
    `Song ${audioId}`,
    'Artist'
  );
}

function neteaseSong(audioId: string): SongItem {
  const song = new SongItem(Number(audioId), `Song ${audioId}`, 'Artist', '', 0, 269000, '');
  song.channelId = ListenTogetherChannels.NETEASE;
  song.audioId = audioId;
  return song;
}

function biliSong(bvid: string, cid: string): SongItem {
  const song = new SongItem(0, 'Bili Song', 'UP', `${Constants.BILIBILI_IDENTITY_HINT}|${cid}`,
    0, 240000, '', '', MusicPlatform.BILIBILI);
  song.channelId = ListenTogetherChannels.BILIBILI;
  song.audioId = bvid;
  return song;
}

function ytmSong(videoId: string, playlistId: string): SongItem {
  const song = new SongItem(0, 'YTM Song', 'Channel', '', 0, 200000, '',
    `ytmusic://video/${videoId}?playlistId=${playlistId}`, MusicPlatform.YOUTUBE_MUSIC);
  song.channelId = ListenTogetherChannels.YOUTUBE_MUSIC;
  song.audioId = videoId;
  return song;
}

/** Room state whose queue is authoritative and whose `track` field is unset. */
function roomStateWithQueue(currentIndex: number, audioIds: string[]): ListenTogetherRoomState {
  const state = createListenTogetherRoomState('room-1', 7);
  const queue: ListenTogetherTrack[] = [];
  for (const audioId of audioIds) {
    queue.push(neteaseTrack(audioId));
  }
  state.queue = queue;
  state.currentIndex = currentIndex;
  return state;
}

export default function listenTogetherPlaybackTest(): void {
  describe('ListenTogetherPlaybackTrackStableKey', () => {
    it('prefersTheAuthoritativeTrackOverTheQueueEntry', 0, () => {
      const state = roomStateWithQueue(1, ['1', '2', '3']);
      state.track = neteaseTrack('9');

      expect(listenTogetherCurrentStableKey(state)).assertEqual('netease:9');
      // Without the authoritative field the queue position decides.
      state.track = null;
      expect(listenTogetherCurrentStableKey(state)).assertEqual('netease:2');
    });

    it('returnsNullWhenTheQueueIndexIsOutOfRange', 0, () => {
      expect(listenTogetherCurrentStableKey(roomStateWithQueue(3, ['1', '2', '3']))).assertNull();
      expect(listenTogetherCurrentStableKey(roomStateWithQueue(-1, ['1']))).assertNull();
      expect(listenTogetherCurrentStableKey(roomStateWithQueue(0, []))).assertNull();
    });

    it('keepsAnExplicitlyEmptyStableKeyInsteadOfFallingBackToTheQueue', 0, () => {
      // Kotlin `track?.stableKey ?: queue…` only falls through on null, so an
      // empty string is a value, not a miss. Falling back here would silently
      // play the queue entry while the room says "no track".
      const state = roomStateWithQueue(1, ['1', '2']);
      state.track = createListenTogetherTrack(
        '', ListenTogetherChannels.NETEASE, '9', 'Song 9', 'Artist');

      expect(listenTogetherCurrentStableKey(state)).assertEqual('');
    });
  });

  describe('ListenTogetherRequestedStableKey', () => {
    it('walksTheThreeSourcesInOrder', 0, () => {
      const event: ListenTogetherEvent = createListenTogetherEvent('seekTo');
      event.queue = [neteaseTrack('1'), neteaseTrack('2')];
      event.currentIndex = 1;
      event.track = neteaseTrack('5');
      event.requestTrackStableKey = 'netease:7';

      expect(listenTogetherRequestedStableKey(event)).assertEqual('netease:7');
      event.requestTrackStableKey = null;
      expect(listenTogetherRequestedStableKey(event)).assertEqual('netease:5');
      event.track = null;
      expect(listenTogetherRequestedStableKey(event)).assertEqual('netease:2');
    });

    it('treatsAMissingCurrentIndexAsNoQueueEntry', 0, () => {
      const event: ListenTogetherEvent = createListenTogetherEvent('seekTo');
      event.queue = [neteaseTrack('1')];

      // Kotlin `getOrNull(currentIndex ?: -1)`: a null index must not read [0].
      expect(event.currentIndex).assertNull();
      expect(listenTogetherRequestedStableKey(event)).assertNull();
      event.currentIndex = 0;
      expect(listenTogetherRequestedStableKey(event)).assertEqual('netease:1');
      event.currentIndex = 9;
      expect(listenTogetherRequestedStableKey(event)).assertNull();
    });

    it('returnsNullForAnEventCarryingNoTrackInformation', 0, () => {
      const event: ListenTogetherEvent = createListenTogetherEvent('pause');

      expect(event.queue).assertNull();
      expect(listenTogetherRequestedStableKey(event)).assertNull();
    });
  });

  describe('ListenTogetherTargetSongItem', () => {
    it('mapsTheAuthoritativeTrackAndThenTheQueueEntry', 0, () => {
      const state = roomStateWithQueue(1, ['1', '2']);
      state.track = neteaseTrack('9');

      const fromTrack = listenTogetherTargetSongItem(state);
      expect(fromTrack !== null).assertTrue();
      expect((fromTrack as SongItem).audioId).assertEqual('9');
      expect((fromTrack as SongItem).platform).assertEqual(MusicPlatform.NETEASE);

      state.track = null;
      expect((listenTogetherTargetSongItem(state) as SongItem).audioId).assertEqual('2');
    });

    it('neverCarriesAPeerSuppliedStreamUrlIntoTheSongItem', 0, () => {
      const state = roomStateWithQueue(0, ['1']);
      state.track = neteaseTrack('1');
      state.track.streamUrl = 'https://evil.example.com/payload.mp3';
      state.track.streamUrls = ['https://evil.example.com/payload.mp3'];

      expect((listenTogetherTargetSongItem(state) as SongItem).streamUrl).assertEqual('');
    });

    it('returnsNullWhenTheRoomPointsAtNothing', 0, () => {
      expect(listenTogetherTargetSongItem(roomStateWithQueue(0, []))).assertNull();
      expect(listenTogetherTargetSongItem(roomStateWithQueue(5, ['1']))).assertNull();
    });
  });

  describe('ListenTogetherSameTrack', () => {
    it('ignoresMetadataAndComparesIdentityOnly', 0, () => {
      const song = neteaseSong('2');
      const renamed = neteaseSong('2');
      renamed.name = 'Different title';
      renamed.coverUrl = 'https://cover.example.com/other.jpg';
      renamed.streamUrl = REMOTE_STREAM_URL;
      renamed.durationMs = 1;

      expect(sameListenTogetherTrack(song, renamed)).assertTrue();
      expect(sameListenTogetherTrack(song, neteaseSong('3'))).assertFalse();
    });

    it('separatesBilibiliPartsByTheSubAudioId', 0, () => {
      expect(sameListenTogetherTrack(biliSong('BV1abc', 'c1'), biliSong('BV1abc', 'c1')))
        .assertTrue();
      // Two parts of one video are different tracks.
      expect(sameListenTogetherTrack(biliSong('BV1abc', 'c1'), biliSong('BV1abc', 'c2')))
        .assertFalse();
    });

    it('separatesYouTubeMusicTracksByThePlaylistContext', 0, () => {
      expect(sameListenTogetherTrack(ytmSong('abc123', 'PL9'), ytmSong('abc123', 'PL9')))
        .assertTrue();
      expect(sameListenTogetherTrack(ytmSong('abc123', 'PL9'), ytmSong('abc123', 'PL8')))
        .assertFalse();
    });

    it('distinguishesTheSameAudioIdOnDifferentChannels', 0, () => {
      const netease = neteaseSong('2');
      const bilibili = neteaseSong('2');
      bilibili.channelId = ListenTogetherChannels.BILIBILI;

      expect(sameListenTogetherTrack(netease, bilibili)).assertFalse();
    });
  });

  describe('ListenTogetherTrackSequence', () => {
    it('comparesLengthThenOrder', 0, () => {
      const queue: SongItem[] = [neteaseSong('1'), neteaseSong('2')];

      expect(hasSameListenTogetherTrackSequence(queue, [neteaseSong('1'), neteaseSong('2')]))
        .assertTrue();
      expect(hasSameListenTogetherTrackSequence(queue, [neteaseSong('2'), neteaseSong('1')]))
        .assertFalse();
      expect(hasSameListenTogetherTrackSequence(queue, [neteaseSong('1')])).assertFalse();
      expect(hasSameListenTogetherTrackSequence([], [])).assertTrue();
    });

    it('findsTheFirstMatchingPositionOrMinusOne', 0, () => {
      const queue: SongItem[] = [neteaseSong('1'), neteaseSong('2'), neteaseSong('2')];

      expect(indexOfListenTogetherTrack(queue, neteaseSong('2'))).assertEqual(1);
      expect(indexOfListenTogetherTrack(queue, neteaseSong('9'))).assertEqual(-1);
      expect(indexOfListenTogetherTrack(queue, null)).assertEqual(-1);
      expect(indexOfListenTogetherTrack([], neteaseSong('1'))).assertEqual(-1);
    });
  });

  describe('ListenTogetherStreamPolicy', () => {
    it('trimsAndAcceptsOnlyHttpSchemesCaseInsensitively', 0, () => {
      expect(normalizedDirectStreamUrl(`  ${REMOTE_STREAM_URL}  `)).assertEqual(REMOTE_STREAM_URL);
      expect(normalizedDirectStreamUrl('http://cdn.example.com/a.mp3'))
        .assertEqual('http://cdn.example.com/a.mp3');
      // The scheme match ignores case but the URL keeps its original casing.
      expect(normalizedDirectStreamUrl('HTTPS://Cdn.Example.com/A.mp3'))
        .assertEqual('HTTPS://Cdn.Example.com/A.mp3');
      expect(normalizedDirectStreamUrl('file:///data/music/1.mp3')).assertNull();
      expect(normalizedDirectStreamUrl('netease://2')).assertNull();
      expect(normalizedDirectStreamUrl('   ')).assertNull();
      expect(normalizedDirectStreamUrl('')).assertNull();
      expect(normalizedDirectStreamUrl(null)).assertNull();
    });

    it('reloadsOnlyWhenTheRoomOffersADifferentUsableUrl', 0, () => {
      expect(shouldReloadListenTogetherAuthoritativeStream(REMOTE_STREAM_URL, LOCAL_STREAM_URL))
        .assertTrue();
      expect(shouldReloadListenTogetherAuthoritativeStream(REMOTE_STREAM_URL, null)).assertTrue();
      // Whitespace alone is not a change: both sides normalize first.
      expect(shouldReloadListenTogetherAuthoritativeStream(
        ` ${REMOTE_STREAM_URL} `, REMOTE_STREAM_URL)).assertFalse();
      // An unusable remote URL never triggers a reload, whatever we hold locally.
      expect(shouldReloadListenTogetherAuthoritativeStream(null, LOCAL_STREAM_URL)).assertFalse();
      expect(shouldReloadListenTogetherAuthoritativeStream('file:///x.mp3', null)).assertFalse();
    });

    it('waitsForTheRoomUrlOnlyWhileNoUsableUrlIsKnown', 0, () => {
      // Not waiting: the local resolution is authoritative enough.
      expect(shouldWaitForListenTogetherAuthoritativeStreamPlayback(
        false, false, null, null)).assertFalse();
      // Waiting on a track that is not even the room's target: always hold.
      expect(shouldWaitForListenTogetherAuthoritativeStreamPlayback(
        true, false, REMOTE_STREAM_URL, LOCAL_STREAM_URL)).assertTrue();
      // Right track, no usable URL from either side: keep holding.
      expect(shouldWaitForListenTogetherAuthoritativeStreamPlayback(
        true, true, null, 'file:///data/music/1.mp3')).assertTrue();
      // Either side supplying a usable URL releases the hold.
      expect(shouldWaitForListenTogetherAuthoritativeStreamPlayback(
        true, true, REMOTE_STREAM_URL, null)).assertFalse();
      expect(shouldWaitForListenTogetherAuthoritativeStreamPlayback(
        true, true, null, LOCAL_STREAM_URL)).assertFalse();
    });
  });
}
