import { describe, it, expect } from '@ohos/hypium';
import {
  JsonRecord,
  jsonRecordFromText
} from '../../../main/ets/listentogether/protocol/ListenTogetherJson';
import {
  ListenTogetherChannels,
  isListenTogetherLocalChannel,
  normalizedListenTogetherChannelId
} from '../../../main/ets/listentogether/protocol/ListenTogetherChannels';
import {
  ListenTogetherTrack,
  createListenTogetherTrack,
  listenTogetherTrackEquals,
  listenTogetherTrackFromRecord,
  listenTogetherTrackToRecord
} from '../../../main/ets/listentogether/protocol/ListenTogetherTrack';
import {
  cloneListenTogetherEvent,
  createListenTogetherEvent,
  listenTogetherEventFromRecord,
  listenTogetherEventToRecord
} from '../../../main/ets/listentogether/protocol/ListenTogetherEventModels';
import {
  ListenTogetherMember,
  ListenTogetherRoomSettings,
  ListenTogetherRoomStatuses,
  createListenTogetherRoomState,
  listenTogetherRoomStateFromRecord,
  listenTogetherRoomStateToRecord
} from '../../../main/ets/listentogether/protocol/ListenTogetherRoomModels';
import {
  ListenTogetherSocketEnvelope,
  createListenTogetherSocketEnvelope,
  listenTogetherSocketEnvelopeFromJson,
  listenTogetherSocketEnvelopeToRecord
} from '../../../main/ets/listentogether/protocol/ListenTogetherSocketEnvelope';
import {
  LISTEN_TOGETHER_LEAVE_ROOM_REQUEST_JSON,
  ListenTogetherRoomResponse,
  listenTogetherResponseErrorOrNull,
  listenTogetherRoomResponseFromJson
} from '../../../main/ets/listentogether/protocol/ListenTogetherHttpMessages';

const PRIMARY_STREAM_URL: string = 'https://m701.music.126.net/primary.mp3';
const BACKUP_STREAM_URL: string = 'https://m702.music.126.net/backup.mp3';

/** Forces the record through real JSON text, the way the transport will. */
function reparse(record: JsonRecord): JsonRecord {
  const parsed = jsonRecordFromText(JSON.stringify(record));
  if (parsed === null) {
    throw new Error('record did not survive a JSON round trip');
  }
  return parsed;
}

function expectStrings(actual: string[], expected: string[]): void {
  expect(actual.length).assertEqual(expected.length);
  for (let i = 0; i < expected.length; i++) {
    expect(actual[i]).assertEqual(expected[i]);
  }
}

function neteaseTrack(stableKey: string, audioId: string): ListenTogetherTrack {
  return createListenTogetherTrack(
    stableKey,
    ListenTogetherChannels.NETEASE,
    audioId,
    `Song ${audioId}`,
    'Artist'
  );
}

export default function listenTogetherProtocolJsonTest(): void {
  describe('ListenTogetherTrackCodec', () => {
    it('roundTripsStreamCandidatesThroughJson', 0, () => {
      const track = neteaseTrack('netease:1', '1');
      track.subAudioId = 'sub-1';
      track.playlistContextId = 'playlist-1';
      track.mediaUri = 'netease://1';
      track.streamUrl = PRIMARY_STREAM_URL;
      track.streamUrls = [PRIMARY_STREAM_URL, BACKUP_STREAM_URL];
      track.album = '叶惠美';
      track.durationMs = 269000;
      track.coverUrl = 'https://cover.example.com/1.jpg';

      const decoded = listenTogetherTrackFromRecord(reparse(listenTogetherTrackToRecord(track)));

      expect(listenTogetherTrackEquals(track, decoded)).assertTrue();
      expectStrings(decoded.streamUrls, [PRIMARY_STREAM_URL, BACKUP_STREAM_URL]);
      expect(decoded.streamUrl).assertEqual(PRIMARY_STREAM_URL);
    });

    it('keepsLegacyPrimaryOnlyPayload', 0, () => {
      const legacyJson = `{"stableKey":"netease:1","channelId":"netease","audioId":"1",` +
        `"streamUrl":"${PRIMARY_STREAM_URL}","name":"Song 1","artist":"Artist"}`;
      const raw = jsonRecordFromText(legacyJson);
      expect(raw !== null).assertTrue();
      const legacy = listenTogetherTrackFromRecord(raw as JsonRecord);

      expect(legacy.streamUrl).assertEqual(PRIMARY_STREAM_URL);
      expect(legacy.streamUrls.length).assertEqual(0);
      expect(legacy.durationMs).assertEqual(0);
      expect(legacy.album).assertNull();
      expect(legacy.mediaUri).assertNull();
    });

    it('omitsAbsentOptionalStringsInsteadOfEmittingNull', 0, () => {
      const encoded = JSON.stringify(listenTogetherTrackToRecord(neteaseTrack('netease:1', '1')));

      expect(encoded.includes('"album"')).assertFalse();
      expect(encoded.includes('"coverUrl"')).assertFalse();
      expect(encoded.includes('"mediaUri"')).assertFalse();
      expect(encoded.includes('"streamUrl"')).assertFalse();
      expect(encoded.includes('"subAudioId"')).assertFalse();
      expect(encoded.includes('"playlistContextId"')).assertFalse();
      expect(encoded.includes('null')).assertFalse();
    });
  });

  describe('ListenTogetherChannelIds', () => {
    it('normalizesLocalAliasesOntoWireValues', 0, () => {
      expect(normalizedListenTogetherChannelId('youtube_music'))
        .assertEqual(ListenTogetherChannels.YOUTUBE_MUSIC);
      expect(normalizedListenTogetherChannelId(' YTMusic '))
        .assertEqual(ListenTogetherChannels.YOUTUBE_MUSIC);
      expect(normalizedListenTogetherChannelId('NETEASE'))
        .assertEqual(ListenTogetherChannels.NETEASE);
      expect(normalizedListenTogetherChannelId('Bilibili'))
        .assertEqual(ListenTogetherChannels.BILIBILI);
      expect(normalizedListenTogetherChannelId('local'))
        .assertEqual(ListenTogetherChannels.LOCAL);
    });

    it('passesUnknownChannelsThroughAndDropsBlanks', 0, () => {
      expect(normalizedListenTogetherChannelId(' soundcloud ')).assertEqual('soundcloud');
      expect(normalizedListenTogetherChannelId('   ')).assertNull();
      expect(normalizedListenTogetherChannelId(null)).assertNull();
      expect(isListenTogetherLocalChannel('LOCAL')).assertTrue();
      expect(isListenTogetherLocalChannel('netease')).assertFalse();
    });
  });

  describe('ListenTogetherEventCodec', () => {
    it('carriesClientSequenceThroughJson', 0, () => {
      const event = createListenTogetherEvent('PLAY');
      event.eventId = 'event-play';
      event.clientInstanceId = 'client-instance';
      event.clientSequence = 42;

      const decoded = listenTogetherEventFromRecord(reparse(listenTogetherEventToRecord(event)));

      expect(decoded.type).assertEqual('PLAY');
      expect(decoded.eventId).assertEqual('event-play');
      expect(decoded.clientInstanceId).assertEqual('client-instance');
      expect(decoded.clientSequence).assertEqual(42);
    });

    it('roundTripsUpdateSettingsRoomSettings', 0, () => {
      // backlog §4.1: the controller's UPDATE_SETTINGS carries the whole
      // permission triple through the same event envelope.
      const event = createListenTogetherEvent('UPDATE_SETTINGS');
      event.eventId = 'event-settings';
      const settings = new ListenTogetherRoomSettings();
      settings.allowMemberControl = false;
      settings.autoPauseOnMemberChange = false;
      settings.shareAudioLinks = true;
      event.roomSettings = settings;

      const record = listenTogetherEventToRecord(event);
      const wire = JSON.stringify(record);
      expect(wire.includes('"allowMemberControl":false')).assertTrue();
      expect(wire.includes('"shareAudioLinks":true')).assertTrue();
      const decoded = listenTogetherEventFromRecord(reparse(record));
      expect(decoded.type).assertEqual('UPDATE_SETTINGS');
      expect(decoded.roomSettings === null).assertFalse();
      expect(decoded.roomSettings!.allowMemberControl).assertFalse();
      expect(decoded.roomSettings!.autoPauseOnMemberChange).assertFalse();
      expect(decoded.roomSettings!.shareAudioLinks).assertTrue();
    });

    it('distinguishesAnAbsentQueueFromAnEmptyQueue', 0, () => {
      const untouched = createListenTogetherEvent('REQUEST_SEEK');
      untouched.positionMs = 12000;
      const untouchedDecoded = listenTogetherEventFromRecord(
        reparse(listenTogetherEventToRecord(untouched))
      );
      expect(untouchedDecoded.queue).assertNull();
      expect(untouchedDecoded.positionMs).assertEqual(12000);

      const cleared = createListenTogetherEvent('SET_QUEUE');
      cleared.queue = [];
      const clearedDecoded = listenTogetherEventFromRecord(
        reparse(listenTogetherEventToRecord(cleared))
      );
      expect(clearedDecoded.queue !== null).assertTrue();
      expect((clearedDecoded.queue as ListenTogetherTrack[]).length).assertEqual(0);
    });

    it('clonesTrackAndQueueDeeply', 0, () => {
      const event = createListenTogetherEvent('SET_TRACK');
      event.track = neteaseTrack('netease:1', '1');
      event.queue = [neteaseTrack('netease:1', '1'), neteaseTrack('netease:2', '2')];

      const copy = cloneListenTogetherEvent(event);
      (copy.track as ListenTogetherTrack).name = 'mutated';
      (copy.queue as ListenTogetherTrack[]).pop();

      expect((event.track as ListenTogetherTrack).name).assertEqual('Song 1');
      expect((event.queue as ListenTogetherTrack[]).length).assertEqual(2);
      expect((copy.queue as ListenTogetherTrack[]).length).assertEqual(1);
    });
  });

  describe('ListenTogetherRoomStateCodec', () => {
    it('roundTripsNestedRoomState', 0, () => {
      const state = createListenTogetherRoomState('ABC234', 7);
      state.controllerUserUuid = 'controller-uuid';
      state.settings.shareAudioLinks = false;
      const member = new ListenTogetherMember();
      member.userUuid = 'controller-uuid';
      member.nickname = 'Neri猫';
      member.role = 'controller';
      member.joinedAt = 1700000000000;
      state.members = [member];
      state.queue = [neteaseTrack('netease:1', '1'), neteaseTrack('netease:2', '2')];
      state.currentIndex = 1;
      state.track = state.queue[1];
      state.playback.state = 'playing';
      state.playback.basePositionMs = 30000;
      state.playback.baseTimestampMs = 1700000001000;
      state.playback.repeatMode = 2;
      state.playback.shuffleEnabled = true;
      state.updatedAt = 1700000002000;

      const decoded = listenTogetherRoomStateFromRecord(
        reparse(listenTogetherRoomStateToRecord(state))
      );

      expect(decoded.roomId).assertEqual('ABC234');
      expect(decoded.version).assertEqual(7);
      expect(decoded.controllerUserUuid).assertEqual('controller-uuid');
      expect(decoded.settings.shareAudioLinks).assertFalse();
      expect(decoded.settings.allowMemberControl).assertTrue();
      expect(decoded.members.length).assertEqual(1);
      expect(decoded.members[0].nickname).assertEqual('Neri猫');
      expect(decoded.queue.length).assertEqual(2);
      expect(decoded.currentIndex).assertEqual(1);
      expect(listenTogetherTrackEquals(decoded.track, state.queue[1])).assertTrue();
      expect(decoded.playback.state).assertEqual('playing');
      expect(decoded.playback.basePositionMs).assertEqual(30000);
      expect(decoded.playback.repeatMode).assertEqual(2);
      expect(decoded.playback.shuffleEnabled).assertTrue();
      expect(decoded.updatedAt).assertEqual(1700000002000);
    });

    it('appliesDefaultsForALegacyStatePayload', 0, () => {
      const raw = jsonRecordFromText('{"roomId":"ABC234","version":3}');
      expect(raw !== null).assertTrue();
      const state = listenTogetherRoomStateFromRecord(raw as JsonRecord);

      expect(state.schemaVersion).assertEqual(1);
      expect(state.settings.allowMemberControl).assertTrue();
      expect(state.settings.autoPauseOnMemberChange).assertTrue();
      expect(state.settings.shareAudioLinks).assertTrue();
      expect(state.members.length).assertEqual(0);
      expect(state.queue.length).assertEqual(0);
      expect(state.currentIndex).assertEqual(0);
      expect(state.track).assertNull();
      expect(state.playback.state).assertEqual('paused');
      expect(state.playback.playbackRate).assertEqual(1.0);
      expect(state.playback.repeatMode).assertNull();
      expect(state.playback.shuffleEnabled).assertNull();
      expect(state.roomStatus).assertEqual(ListenTogetherRoomStatuses.ACTIVE);
      expect(state.closedReason).assertNull();
    });
  });

  describe('ListenTogetherSocketEnvelopeCodec', () => {
    it('parsesAStateBroadcastFrame', 0, () => {
      const envelope = createListenTogetherSocketEnvelope('STATE');
      envelope.roomId = 'ABC234';
      envelope.version = 9;
      envelope.expectedPositionMs = 45000;
      envelope.nowMs = 1700000003000;
      envelope.state = createListenTogetherRoomState('ABC234', 9);
      envelope.state.playback.state = 'playing';

      const frame = JSON.stringify(listenTogetherSocketEnvelopeToRecord(envelope));
      const decoded = listenTogetherSocketEnvelopeFromJson(frame);

      expect(decoded !== null).assertTrue();
      const parsed = decoded as ListenTogetherSocketEnvelope;
      expect(parsed.type).assertEqual('STATE');
      expect(parsed.roomId).assertEqual('ABC234');
      expect(parsed.version).assertEqual(9);
      expect(parsed.expectedPositionMs).assertEqual(45000);
      expect(parsed.state !== null).assertTrue();
      expect(parsed.autoPauseOnJoin).assertFalse();
    });

    it('rejectsMalformedOrTypelessFrames', 0, () => {
      expect(listenTogetherSocketEnvelopeFromJson('not json {')).assertNull();
      expect(listenTogetherSocketEnvelopeFromJson('[]')).assertNull();
      expect(listenTogetherSocketEnvelopeFromJson('{"roomId":"ABC234"}')).assertNull();
      expect(listenTogetherSocketEnvelopeFromJson('{"type":""}')).assertNull();
    });
  });

  describe('ListenTogetherHttpMessages', () => {
    it('readsARoomResponseBody', 0, () => {
      const response = listenTogetherRoomResponseFromJson(
        '{"ok":true,"roomId":"ABC234","userUuid":"member-uuid","role":"controller",' +
        '"autoPauseOnJoin":true,"wsUrl":"wss://listen.example.com/api/rooms/ABC234/ws",' +
        '"state":{"roomId":"ABC234","version":1}}'
      );

      expect(response !== null).assertTrue();
      const parsed = response as ListenTogetherRoomResponse;
      expect(parsed.ok).assertTrue();
      expect(parsed.roomId).assertEqual('ABC234');
      expect(parsed.role).assertEqual('controller');
      expect(parsed.autoPauseOnJoin).assertTrue();
      expect(parsed.state !== null).assertTrue();
      expect(parsed.error).assertNull();
      expect(LISTEN_TOGETHER_LEAVE_ROOM_REQUEST_JSON).assertEqual('{}');
    });

    it('reportsAFallbackErrorForAFailedResponse', 0, () => {
      expect(listenTogetherResponseErrorOrNull(true, 'ignored')).assertNull();
      expect(listenTogetherResponseErrorOrNull(false, ' room_closed '))
        .assertEqual('room_closed');
      expect(listenTogetherResponseErrorOrNull(false, '   '))
        .assertEqual('一起听服务端返回了未知错误');
      expect(listenTogetherResponseErrorOrNull(false, null))
        .assertEqual('一起听服务端返回了未知错误');
    });
  });
}
