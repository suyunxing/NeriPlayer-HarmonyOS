/**
 * M7.3a event-factory tests. Upstream has no unit test for
 * ListenTogetherEventFactory.kt at all — it reads seven `PlayerManager` globals,
 * which is exactly why this port injects a snapshot instead. These cases are new
 * coverage for the file that decides the shape of every outbound room event, and
 * they pin the two rules that matter most for correctness and for safety:
 *
 * - a listener never publishes its own resolved stream urls, and the controller
 *   publishes only whitelisted hosts;
 * - a diagnostic message never carries a stream url, because a resolved url is a
 *   credential.
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  ListenTogetherEventFactory,
  ListenTogetherLocalPlaybackSnapshot
} from '../../../main/ets/listentogether/control/ListenTogetherEventFactory';
import { ListenTogetherPlaybackCommand } from '../../../main/ets/listentogether/control/ListenTogetherPlaybackCommand';
import { SongItem } from '../../../main/ets/model/SongItem';
import { ListenTogetherChannels } from '../../../main/ets/listentogether/protocol/ListenTogetherChannels';
import {
  ListenTogetherRoomState,
  createListenTogetherRoomState
} from '../../../main/ets/listentogether/protocol/ListenTogetherRoomModels';
import { ListenTogetherSocketEnvelope } from '../../../main/ets/listentogether/protocol/ListenTogetherSocketEnvelope';
import { createListenTogetherCause } from '../../../main/ets/listentogether/protocol/ListenTogetherEventModels';
import {
  ListenTogetherTrack,
  createListenTogetherTrack
} from '../../../main/ets/listentogether/protocol/ListenTogetherTrack';
import { MAX_LISTEN_TOGETHER_STREAM_URL_CANDIDATES } from '../../../main/ets/listentogether/mapping/ListenTogetherStreamUrlPolicy';

const CLOCK_MS: number = 1_700_000_000_000;
const CLIENT_INSTANCE_ID: string = 'client-1';
/** Whitelisted netease hosts, so the trust filter lets these through. */
const TRUSTED_URL_A: string = 'https://m701.music.126.net/a.mp3';
const TRUSTED_URL_B: string = 'https://m702.music.126.net/b.mp3';
const TRUSTED_URL_C: string = 'https://m703.music.126.net/c.mp3';
/** Not on any channel's whitelist, and must never reach the wire. */
const UNTRUSTED_URL: string = 'https://evil.example.com/x.mp3';

function neteaseSong(audioId: string): SongItem {
  const song = new SongItem(Number(audioId), `Song ${audioId}`, 'Artist', '', 0, 200_000, '');
  song.channelId = ListenTogetherChannels.NETEASE;
  song.audioId = audioId;
  return song;
}

/** A local file is deliberately unshareable: it maps onto no wire track. */
function localSong(): SongItem {
  const song = new SongItem(9001, 'Local', 'Artist', '', 0, 100_000, '');
  song.channelId = ListenTogetherChannels.LOCAL;
  return song;
}

/**
 * Holds the mutable state the factory's eight providers read, so each case can
 * pose the player and the room and then build one event against them.
 */
class FactoryHarness {
  roomState: ListenTogetherRoomState | null = null;
  isController: boolean = true;
  playback: ListenTogetherLocalPlaybackSnapshot = new ListenTogetherLocalPlaybackSnapshot();
  diagnostics: string[] = [];
  eventIdCount: number = 0;
  sequenceCount: number = 0;
  readonly factory: ListenTogetherEventFactory;

  constructor() {
    this.factory = new ListenTogetherEventFactory(
      () => this.roomState,
      () => this.isController,
      () => this.playback,
      () => {
        this.eventIdCount += 1;
        return `evt-${this.eventIdCount}`;
      },
      () => CLIENT_INSTANCE_ID,
      () => {
        this.sequenceCount += 1;
        return this.sequenceCount;
      },
      () => CLOCK_MS,
      (message: string) => {
        this.diagnostics.push(message);
      }
    );
  }

  /** Loads `queue` locally and points the player at `currentIndex` of it. */
  loadQueue(queue: SongItem[], currentIndex: number = 0): SongItem[] {
    this.playback.queue = queue;
    this.playback.currentSong = currentIndex >= 0 && currentIndex < queue.length
      ? queue[currentIndex]
      : null;
    return queue;
  }

  lastDiagnostic(): string {
    return this.diagnostics.length === 0 ? '' : this.diagnostics[this.diagnostics.length - 1];
  }

  /** No diagnostic may ever carry a url: a resolved url is a credential. */
  noDiagnosticLeaksAUrl(): boolean {
    for (const message of this.diagnostics) {
      if (message.indexOf('http') >= 0) {
        return false;
      }
    }
    return true;
  }
}

function playbackCommand(type: string): ListenTogetherPlaybackCommand {
  const command = new ListenTogetherPlaybackCommand();
  command.type = type;
  return command;
}

function forwardedRequest(requestType: string | null): ListenTogetherSocketEnvelope {
  const message = new ListenTogetherSocketEnvelope();
  message.type = 'member_control_requested';
  message.causedBy = requestType === null
    ? null
    : createListenTogetherCause('listener-1', requestType, 'incoming-event-id');
  return message;
}

export default function listenTogetherEventFactoryTest() {
  describe('ListenTogetherEventFactory', () => {
    it('stamps the four envelope fields on every event', 0, () => {
      const harness = new FactoryHarness();
      harness.loadQueue([neteaseSong('1001')]);

      const first = harness.factory.buildPlayEvent(0);
      const second = harness.factory.buildPauseEvent(0);

      expect(first.eventId).assertEqual('evt-1');
      expect(first.clientTimeMs).assertEqual(CLOCK_MS);
      expect(first.clientInstanceId).assertEqual(CLIENT_INSTANCE_ID);
      expect(first.clientSequence).assertEqual(1);
      // A fresh identity per event, or a peer's dedupe would drop the second one.
      expect(second.eventId).assertEqual('evt-2');
      expect(second.clientSequence).assertEqual(2);
    });

    it('builds SET_TRACK with the controller resolved url folded in', 0, () => {
      const harness = new FactoryHarness();
      const queue = harness.loadQueue([neteaseSong('1001'), neteaseSong('1002'), neteaseSong('1003')], 1);
      harness.playback.shareableStreamUrls = [TRUSTED_URL_A];

      const event = harness.factory.buildSetTrackEvent(queue, 1, -5, true);

      expect(event.type).assertEqual('SET_TRACK');
      // A negative position is floored rather than published as a rewind.
      expect(event.positionMs).assertEqual(0);
      expect(event.currentIndex).assertEqual(1);
      expect(event.shouldPlay).assertTrue();
      const track = event.track;
      expect(track === null).assertFalse();
      if (track !== null) {
        expect(track.stableKey).assertEqual('netease:1002');
        expect(track.streamUrl).assertEqual(TRUSTED_URL_A);
        expect(track.streamUrls.length).assertEqual(1);
      }
      const wireQueue = event.queue;
      expect(wireQueue === null).assertFalse();
      if (wireQueue !== null) {
        expect(wireQueue.length).assertEqual(3);
        // Only the playing track carries a url: the others have not been resolved.
        expect(wireQueue[0].streamUrls.length).assertEqual(0);
        expect(wireQueue[1].streamUrls.length).assertEqual(1);
      }
    });

    it('drops unshareable queue entries and re-resolves the index', 0, () => {
      const harness = new FactoryHarness();
      const queue = harness.loadQueue([localSong(), neteaseSong('1001'), neteaseSong('1002')], 2);

      const event = harness.factory.buildSetTrackEvent(queue, 2, 0, true);

      const wireQueue = event.queue;
      expect(wireQueue === null).assertFalse();
      if (wireQueue !== null) {
        expect(wireQueue.length).assertEqual(2);
        expect(wireQueue[0].stableKey).assertEqual('netease:1001');
      }
      // The index must follow the track, not the original queue position.
      expect(event.currentIndex).assertEqual(1);
      const track = event.track;
      if (track !== null) {
        expect(track.stableKey).assertEqual('netease:1002');
      }
    });

    it('never publishes a listener own resolved urls', 0, () => {
      const harness = new FactoryHarness();
      harness.isController = false;
      const queue = harness.loadQueue([neteaseSong('1001')]);
      harness.playback.shareableStreamUrls = [TRUSTED_URL_A];

      const event = harness.factory.buildRequestSetTrackEvent(queue, 0, 1_000, false);

      expect(event.type).assertEqual('REQUEST_SET_TRACK');
      expect(event.positionMs).assertEqual(1_000);
      expect(event.shouldPlay).assertFalse();
      const track = event.track;
      expect(track === null).assertFalse();
      if (track !== null) {
        // Only the controller's stream is authoritative; a listener sharing its own
        // would hand the room a url resolved for a different account.
        expect(track.streamUrls.length).assertEqual(0);
        expect(track.streamUrl === null).assertTrue();
      }
    });

    it('states the intention for PLAY and PAUSE and reports reality otherwise', 0, () => {
      const harness = new FactoryHarness();
      harness.loadQueue([neteaseSong('1001')]);
      harness.playback.playbackStateName = 'paused';
      harness.playback.repeatMode = 2;
      harness.playback.shuffleEnabled = true;

      const play = harness.factory.buildPlayEvent(1_000);
      expect(play.state).assertEqual('playing');
      expect(play.shouldPlay).assertTrue();
      // The player's own modes ride along on every transport event.
      expect(play.repeatMode).assertEqual(2);
      expect(play.shuffleEnabled).assertTrue();

      const pause = harness.factory.buildPauseEvent(-1);
      expect(pause.state).assertEqual('paused');
      expect(pause.shouldPlay).assertFalse();
      expect(pause.positionMs).assertEqual(0);

      // A seek says nothing about transport, so it reports what the player is doing.
      const seekWhilePaused = harness.factory.buildSeekEvent(5_000);
      expect(seekWhilePaused.state).assertEqual('paused');
      expect(seekWhilePaused.shouldPlay).assertFalse();

      harness.playback.playbackStateName = 'playing';
      const seekWhilePlaying = harness.factory.buildSeekEvent(5_000);
      expect(seekWhilePlaying.state).assertEqual('playing');
      expect(seekWhilePlaying.shouldPlay).assertTrue();
    });

    it('resolves a request state from the bare command type', 0, () => {
      const harness = new FactoryHarness();
      harness.loadQueue([neteaseSong('1001')]);
      harness.playback.playbackStateName = 'paused';

      const requestPlay = harness.factory.buildRequestPlayEvent(0);
      expect(requestPlay.type).assertEqual('REQUEST_PLAY');
      // REQUEST_PLAY still asks to play, even though the local player is paused.
      expect(requestPlay.state).assertEqual('playing');
      expect(requestPlay.shouldPlay).assertTrue();

      const requestPause = harness.factory.buildRequestPauseEvent(0);
      expect(requestPause.type).assertEqual('REQUEST_PAUSE');
      expect(requestPause.state).assertEqual('paused');

      const requestSeek = harness.factory.buildRequestSeekEvent(2_000);
      expect(requestSeek.type).assertEqual('REQUEST_SEEK');
      expect(requestSeek.state).assertEqual('paused');
      // A request carries the track it applies to, so a peer can discard a stale one.
      const track = requestSeek.track;
      if (track !== null) {
        expect(track.stableKey).assertEqual('netease:1001');
      }
    });

    it('sends the playback mode at the current position', 0, () => {
      const harness = new FactoryHarness();
      harness.loadQueue([neteaseSong('1001')]);
      harness.playback.positionMs = 7_500;
      harness.playback.repeatMode = 2;
      harness.playback.shuffleEnabled = false;

      const event = harness.factory.buildPlaybackModeEvent(1, true);

      expect(event.type).assertEqual('PLAYBACK_MODE');
      // Nothing about repeat or shuffle moves the playhead, so re-stating where it
      // already is keeps peers from seeking.
      expect(event.positionMs).assertEqual(7_500);
      // The arguments win over the snapshot: they are what the user just chose.
      expect(event.repeatMode).assertEqual(1);
      expect(event.shuffleEnabled).assertTrue();

      harness.isController = false;
      expect(harness.factory.buildPlaybackModeEvent(1, true).type)
        .assertEqual('REQUEST_PLAYBACK_MODE');

      harness.playback.positionMs = -20;
      expect(harness.factory.buildPlaybackModeEvent(0, false).positionMs).assertEqual(0);
    });

    it('omits the heartbeat queue when the caller asks it to', 0, () => {
      const harness = new FactoryHarness();
      harness.loadQueue([neteaseSong('1001'), neteaseSong('1002')], 1);

      const withQueue = harness.factory.buildHeartbeatEvent('playing', -3);
      expect(withQueue.type).assertEqual('HEARTBEAT');
      expect(withQueue.state).assertEqual('playing');
      expect(withQueue.positionMs).assertEqual(0);
      expect(withQueue.currentIndex).assertEqual(1);
      const wireQueue = withQueue.queue;
      expect(wireQueue === null).assertFalse();
      if (wireQueue !== null) {
        expect(wireQueue.length).assertEqual(2);
      }

      // An absent queue means "do not touch it", which is how a listener keeps a
      // 22-second heartbeat cheap.
      const withoutQueue = harness.factory.buildHeartbeatEvent('paused', 1_000, false);
      expect(withoutQueue.queue === null).assertTrue();
      expect(withoutQueue.positionMs).assertEqual(1_000);
      const track = withoutQueue.track;
      expect(track === null).assertFalse();
      if (track !== null) {
        expect(track.stableKey).assertEqual('netease:1002');
      }
    });

    it('sends forceRefresh on a link request only when it is true', 0, () => {
      const harness = new FactoryHarness();
      const wanted: ListenTogetherTrack = createListenTogetherTrack(
        'netease:1001', ListenTogetherChannels.NETEASE, '1001', 'Song 1001', 'Artist'
      );

      const plain = harness.factory.buildRequestLinkEvent('netease:1001');
      expect(plain.type).assertEqual('REQUEST_LINK');
      expect(plain.requestTrackStableKey).assertEqual('netease:1001');
      expect(plain.currentIndex === null).assertTrue();
      expect(plain.track === null).assertTrue();
      // A `false` on the wire would read as a deliberate "do not refresh" to a
      // server that supports the flag, which an ordinary request does not mean.
      expect(plain.forceRefresh === null).assertTrue();

      const forced = harness.factory.buildRequestLinkEvent('netease:1001', 3, wanted, true);
      expect(forced.currentIndex).assertEqual(3);
      expect(forced.track === wanted).assertTrue();
      expect(forced.forceRefresh).assertTrue();
    });

    it('publishes LINK_READY with the room transport state', 0, () => {
      const harness = new FactoryHarness();
      harness.loadQueue([neteaseSong('1001'), neteaseSong('1002')]);
      harness.playback.shareableStreamUrls = [TRUSTED_URL_A];
      const room = createListenTogetherRoomState('room-1', 1);
      room.playback.state = 'playing';
      harness.roomState = room;

      const event = harness.factory.buildLinkReadyEvent('netease:1001', 12_345);

      expect(event === null).assertFalse();
      if (event !== null) {
        expect(event.type).assertEqual('LINK_READY');
        expect(event.currentIndex).assertEqual(0);
        expect(event.positionMs).assertEqual(12_345);
        expect(event.requestTrackStableKey).assertEqual('netease:1001');
        expect(event.state).assertEqual('playing');
        const track = event.track;
        expect(track === null).assertFalse();
        if (track !== null) {
          expect(track.stableKey).assertEqual('netease:1001');
          expect(track.streamUrls.length).assertEqual(1);
          expect(track.streamUrls[0]).assertEqual(TRUSTED_URL_A);
        }
        // The queue's own entry must carry the same authoritative track.
        const wireQueue = event.queue;
        if (wireQueue !== null) {
          expect(wireQueue[0].streamUrls.length).assertEqual(1);
        }
      }

      // A paused room with a quiet local player publishes a paused link.
      room.playback.state = 'paused';
      const paused = harness.factory.buildLinkReadyEvent('netease:1001', 0);
      if (paused !== null) {
        expect(paused.state).assertEqual('paused');
      }
      // A local transport that has been told to play outranks the stale room state.
      harness.playback.transportActive = true;
      const resuming = harness.factory.buildLinkReadyEvent('netease:1001', 0);
      if (resuming !== null) {
        expect(resuming.state).assertEqual('playing');
      }
    });

    it('trusts the freshest resolved urls first', 0, () => {
      const harness = new FactoryHarness();
      harness.loadQueue([neteaseSong('1001')]);
      harness.playback.shareableStreamUrls = [TRUSTED_URL_A];

      const event = harness.factory.buildLinkReadyEvent(
        'netease:1001', 0, TRUSTED_URL_C, [TRUSTED_URL_B]
      );

      expect(event === null).assertFalse();
      if (event !== null) {
        const track = event.track;
        expect(track === null).assertFalse();
        if (track !== null) {
          // Candidate order is the trust order: what the caller just resolved, then
          // its single-url form, then what the player holds.
          expect(track.streamUrls[0]).assertEqual(TRUSTED_URL_B);
          expect(track.streamUrls[1]).assertEqual(TRUSTED_URL_C);
          expect(track.streamUrls[2]).assertEqual(TRUSTED_URL_A);
          expect(track.streamUrls.length).assertEqual(MAX_LISTEN_TOGETHER_STREAM_URL_CANDIDATES);
          expect(track.streamUrl).assertEqual(TRUSTED_URL_B);
        }
      }
    });

    it('refuses to publish an untrusted host and never logs a url', 0, () => {
      const harness = new FactoryHarness();
      harness.loadQueue([neteaseSong('1001')]);
      harness.playback.shareableStreamUrls = [UNTRUSTED_URL];

      const event = harness.factory.buildLinkReadyEvent('netease:1001', 0);

      // Every candidate was filtered out, so there is nothing to publish. Sending
      // the track without urls would tell the room a direct link exists.
      expect(event === null).assertTrue();
      expect(harness.lastDiagnostic().indexOf('direct stream urls missing') > 0).assertTrue();
      expect(harness.noDiagnosticLeaksAUrl()).assertTrue();
    });

    it('reports every reason a link ready event cannot be built', 0, () => {
      const harness = new FactoryHarness();

      // Nothing loaded locally.
      harness.playback.currentSong = null;
      expect(harness.factory.buildLinkReadyEvent('netease:1001', 0) === null).assertTrue();
      expect(harness.lastDiagnostic().indexOf('currentSong missing') > 0).assertTrue();

      // A local file cannot be shared at all.
      harness.playback.currentSong = localSong();
      expect(harness.factory.buildLinkReadyEvent('netease:1001', 0) === null).assertTrue();
      expect(harness.lastDiagnostic().indexOf('not shareable') > 0).assertTrue();

      // The room asked for a track this device has already moved off.
      harness.loadQueue([neteaseSong('1001')]);
      expect(harness.factory.buildLinkReadyEvent('netease:9999', 0) === null).assertTrue();
      expect(harness.lastDiagnostic().indexOf('current stableKey mismatch') > 0).assertTrue();

      // Loaded, but the local queue does not contain it, so the snapshot centres on
      // the wrong entry.
      harness.playback.queue = [neteaseSong('1002')];
      harness.playback.currentSong = neteaseSong('1001');
      expect(harness.factory.buildLinkReadyEvent('netease:1001', 0) === null).assertTrue();
      expect(harness.lastDiagnostic().indexOf('(): stableKey mismatch') > 0).assertTrue();

      // An empty local queue leaves the snapshot with nothing to publish.
      harness.playback.queue = [];
      expect(harness.factory.buildLinkReadyEvent('netease:1001', 0) === null).assertTrue();
      expect(harness.lastDiagnostic().indexOf('shareableTrack missing') > 0).assertTrue();
      expect(harness.noDiagnosticLeaksAUrl()).assertTrue();
    });

    it('lets the controller name the next track on TRACK_FINISHED', 0, () => {
      const harness = new FactoryHarness();
      const queue = harness.loadQueue([neteaseSong('1001'), neteaseSong('1002')]);
      harness.playback.shareableStreamUrls = [TRUSTED_URL_A];
      const command = playbackCommand('TRACK_FINISHED');
      command.currentIndex = 1;
      command.shouldPlay = true;

      const event = harness.factory.buildTrackFinishedEvent(command, queue, queue[0], 200_000);

      expect(event === null).assertFalse();
      if (event !== null) {
        expect(event.type).assertEqual('TRACK_FINISHED');
        expect(event.positionMs).assertEqual(200_000);
        expect(event.currentIndex).assertEqual(1);
        expect(event.nextIndex).assertEqual(1);
        expect(event.shouldPlay).assertTrue();
        expect(event.finishedTrackStableKey).assertEqual('netease:1001');
        const track = event.track;
        expect(track === null).assertFalse();
        if (track !== null) {
          expect(track.stableKey).assertEqual('netease:1002');
        }
        const wireQueue = event.queue;
        expect(wireQueue === null).assertFalse();
        if (wireQueue !== null) {
          // Never a resolved url: the next track has not been prepared here, so any
          // url in this queue would be stale.
          expect(wireQueue[1].streamUrls.length).assertEqual(0);
        }
      }

      // Not advancing means not naming a track, only reporting the position.
      command.shouldPlay = false;
      const stopping = harness.factory.buildTrackFinishedEvent(command, queue, queue[0], 200_000);
      if (stopping !== null) {
        expect(stopping.track === null).assertTrue();
        expect(stopping.shouldPlay).assertFalse();
        expect(stopping.currentIndex).assertEqual(1);
      }
    });

    it('has a listener report only the bare fact of a finished track', 0, () => {
      const harness = new FactoryHarness();
      harness.isController = false;
      const queue = harness.loadQueue([neteaseSong('1001'), neteaseSong('1002')]);
      const command = playbackCommand('TRACK_FINISHED');
      command.currentIndex = 1;
      command.shouldPlay = true;

      const event = harness.factory.buildTrackFinishedEvent(command, queue, queue[0], 5_000);

      expect(event === null).assertFalse();
      if (event !== null) {
        // Only the controller may say what plays next, so every payload field but
        // the finished key is withheld.
        expect(event.currentIndex === null).assertTrue();
        expect(event.nextIndex === null).assertTrue();
        expect(event.track === null).assertTrue();
        expect(event.queue === null).assertTrue();
        expect(event.shouldPlay === null).assertTrue();
        expect(event.finishedTrackStableKey).assertEqual('netease:1001');
        expect(event.positionMs).assertEqual(5_000);
      }
    });

    it('withholds TRACK_FINISHED when there is nothing shareable to report', 0, () => {
      const harness = new FactoryHarness();
      const command = playbackCommand('TRACK_FINISHED');
      const song = neteaseSong('1001');

      expect(harness.factory.buildTrackFinishedEvent(command, [], song, 0) === null).assertTrue();
      expect(harness.factory.buildTrackFinishedEvent(command, [song], null, 0) === null).assertTrue();
      // A local file has no wire identity to report as finished.
      expect(harness.factory.buildTrackFinishedEvent(command, [localSong()], localSong(), 0) === null)
        .assertTrue();
      // No index given and the current song is not in the queue, so index 0 is
      // proposed — and it is unshareable.
      expect(harness.factory.buildTrackFinishedEvent(command, [localSong()], song, 0) === null)
        .assertTrue();
    });

    it('commits a forwarded request with its payload verbatim', 0, () => {
      const harness = new FactoryHarness();
      const requested = createListenTogetherTrack(
        'netease:1002', ListenTogetherChannels.NETEASE, '1002', 'Song 1002', 'Artist'
      );
      const message = forwardedRequest('REQUEST_SEEK');
      message.positionMs = 9_000;
      message.currentIndex = 2;
      message.track = requested;
      message.queue = [requested];
      message.shouldPlay = true;
      message.stateName = 'playing';
      message.repeatMode = 1;
      message.shuffleEnabled = true;
      message.requestTrackStableKey = 'netease:1002';

      const event = harness.factory.buildControllerCommitEventFromForwardedRequest(message);

      expect(event === null).assertFalse();
      if (event !== null) {
        // The REQUEST_ prefix is stripped: the controller is granting the ask.
        expect(event.type).assertEqual('SEEK');
        expect(event.positionMs).assertEqual(9_000);
        expect(event.currentIndex).assertEqual(2);
        expect(event.track === requested).assertTrue();
        expect(event.shouldPlay).assertTrue();
        expect(event.state).assertEqual('playing');
        expect(event.repeatMode).assertEqual(1);
        expect(event.shuffleEnabled).assertTrue();
        expect(event.requestTrackStableKey).assertEqual('netease:1002');
        // A fresh identity: this is the controller's event, not a relay of the
        // listener's, and the room must not dedupe it against the request.
        expect(event.eventId).assertEqual('evt-1');
        expect(event.clientInstanceId).assertEqual(CLIENT_INSTANCE_ID);
      }

      // Falls back to the expected position, then to zero, and never goes negative.
      const expected = forwardedRequest('REQUEST_PLAY');
      expected.expectedPositionMs = 4_000;
      const fromExpected = harness.factory.buildControllerCommitEventFromForwardedRequest(expected);
      if (fromExpected !== null) {
        expect(fromExpected.type).assertEqual('PLAY');
        expect(fromExpected.positionMs).assertEqual(4_000);
      }
      const bare = harness.factory.buildControllerCommitEventFromForwardedRequest(
        forwardedRequest('REQUEST_PAUSE')
      );
      if (bare !== null) {
        expect(bare.positionMs).assertEqual(0);
      }
      const rewound = forwardedRequest('REQUEST_SEEK');
      rewound.positionMs = -1;
      const floored = harness.factory.buildControllerCommitEventFromForwardedRequest(rewound);
      if (floored !== null) {
        expect(floored.positionMs).assertEqual(0);
      }
    });

    it('refuses to commit anything that was not a request', 0, () => {
      const harness = new FactoryHarness();

      expect(harness.factory.buildControllerCommitEventFromForwardedRequest(
        forwardedRequest(null)
      ) === null).assertTrue();
      expect(harness.factory.buildControllerCommitEventFromForwardedRequest(
        forwardedRequest('')
      ) === null).assertTrue();
      // Committing an already-authoritative event would re-broadcast it.
      expect(harness.factory.buildControllerCommitEventFromForwardedRequest(
        forwardedRequest('PLAY')
      ) === null).assertTrue();
      expect(harness.factory.buildControllerCommitEventFromForwardedRequest(
        forwardedRequest('TRACK_FINISHED')
      ) === null).assertTrue();
    });

    it('routes a local command to the event the role warrants', 0, () => {
      const harness = new FactoryHarness();
      const queue = harness.loadQueue([neteaseSong('1001'), neteaseSong('1002')]);
      harness.playback.positionMs = 3_000;
      harness.playback.transportActive = true;

      const start = playbackCommand('PLAY_PLAYLIST');
      start.queue = queue;
      start.currentIndex = 1;
      const asController = harness.factory.buildEventForPlaybackCommand(start);
      expect(asController === null).assertFalse();
      if (asController !== null) {
        expect(asController.type).assertEqual('SET_TRACK');
        expect(asController.currentIndex).assertEqual(1);
        // An absent shouldPlay is inferred from the local transport for the
        // transport-driven command types.
        expect(asController.shouldPlay).assertTrue();
        // No position on the command: the player's own is used.
        expect(asController.positionMs).assertEqual(3_000);
      }

      harness.isController = false;
      const asListener = harness.factory.buildEventForPlaybackCommand(start);
      if (asListener !== null) {
        expect(asListener.type).assertEqual('REQUEST_SET_TRACK');
      }

      harness.isController = true;
      const pause = playbackCommand('PAUSE');
      pause.positionMs = 8_000;
      const paused = harness.factory.buildEventForPlaybackCommand(pause);
      if (paused !== null) {
        expect(paused.type).assertEqual('PAUSE');
        expect(paused.positionMs).assertEqual(8_000);
      }

      // A mode change with nothing decided falls back to the player's own modes.
      harness.playback.repeatMode = 2;
      harness.playback.shuffleEnabled = true;
      const mode = harness.factory.buildEventForPlaybackCommand(playbackCommand('PLAYBACK_MODE'));
      if (mode !== null) {
        expect(mode.type).assertEqual('PLAYBACK_MODE');
        expect(mode.repeatMode).assertEqual(2);
        expect(mode.shuffleEnabled).assertTrue();
      }
    });

    it('re-states which track a seek applies to', 0, () => {
      const harness = new FactoryHarness();
      harness.loadQueue([neteaseSong('1001'), neteaseSong('1002')], 1);
      const seek = playbackCommand('SEEK');
      seek.positionMs = 42_000;

      const event = harness.factory.buildEventForPlaybackCommand(seek);

      expect(event === null).assertFalse();
      if (event !== null) {
        expect(event.type).assertEqual('SEEK');
        expect(event.positionMs).assertEqual(42_000);
        // A seek that lands on a peer after a track switch must be discardable, so
        // it names its own track.
        expect(event.currentIndex).assertEqual(1);
        const track = event.track;
        expect(track === null).assertFalse();
        if (track !== null) {
          expect(track.stableKey).assertEqual('netease:1002');
        }
      }
    });

    it('publishes nothing for an unshareable song or an unknown command', 0, () => {
      const harness = new FactoryHarness();
      harness.loadQueue([localSong()]);

      expect(harness.factory.buildEventForPlaybackCommand(playbackCommand('PLAY')) === null)
        .assertTrue();
      expect(harness.factory.buildEventForPlaybackCommand(playbackCommand('PAUSE')) === null)
        .assertTrue();
      expect(harness.factory.buildEventForPlaybackCommand(playbackCommand('SEEK')) === null)
        .assertTrue();
      expect(harness.factory.buildEventForPlaybackCommand(playbackCommand('NEXT')) === null)
        .assertTrue();

      // A command type the room has no wire form for is simply not published.
      harness.loadQueue([neteaseSong('1001')]);
      expect(harness.factory.buildEventForPlaybackCommand(playbackCommand('STOP')) === null)
        .assertTrue();
      expect(harness.factory.buildEventForPlaybackCommand(playbackCommand('')) === null)
        .assertTrue();
    });
  });
}
