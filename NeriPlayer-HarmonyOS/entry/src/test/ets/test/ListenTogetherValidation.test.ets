import { describe, it, expect } from '@ohos/hypium';
import { SongItem } from '../../../main/ets/model/SongItem';
import {
  ListenTogetherValidationCode,
  ListenTogetherValidationError,
  ListenTogetherValidationFailure
} from '../../../main/ets/listentogether/validation/ListenTogetherValidationError';
import {
  LISTEN_TOGETHER_JOIN_SECRET_MAX_LENGTH,
  LISTEN_TOGETHER_ROOM_ID_LENGTH,
  isListenTogetherHanCodePoint,
  normalizeListenTogetherRoomId,
  requireValidListenTogetherRoomId,
  requireValidListenTogetherUserUuid,
  sanitizeListenTogetherJoinSecretOrNull,
  sanitizeListenTogetherNicknameOrNull,
  validateListenTogetherJoinSecret,
  validateListenTogetherNickname,
  validateListenTogetherRoomId,
  validateListenTogetherUserUuid
} from '../../../main/ets/listentogether/validation/ListenTogetherFieldValidation';
import {
  requireValidListenTogetherRoomCreation,
  validateListenTogetherRoomCreation
} from '../../../main/ets/listentogether/validation/ListenTogetherRoomCreationValidation';
import {
  hasShareableListenTogetherTrackAt,
  isShareableForListenTogether
} from '../../../main/ets/listentogether/playback/ListenTogetherShareabilityPolicy';

const VALID_USER_UUID: string = '5458c5ab-1234-4321-8888-abcdefabcdef';

function songItem(channelId: string, audioId: string): SongItem {
  const song = new SongItem(Number(audioId), `Song ${audioId}`, 'Artist', '', 0, 180000);
  song.channelId = channelId;
  song.audioId = audioId;
  return song;
}

function codeOf(error: ListenTogetherValidationError | null): ListenTogetherValidationCode | null {
  return error === null ? null : error.code;
}

/** Runs `action` and returns the validation code it threw, or null. */
function thrownCode(action: () => void): ListenTogetherValidationCode | null {
  try {
    action();
    return null;
  } catch (error) {
    return (error as ListenTogetherValidationFailure).code;
  }
}

export default function listenTogetherValidationTest(): void {
  describe('ListenTogetherNicknameValidation', () => {
    it('acceptsHanLettersAndDigits', 0, () => {
      expect(validateListenTogetherNickname('灵梦Alice123')).assertNull();
      expect(isListenTogetherHanCodePoint(0x7075)).assertTrue();
      expect(isListenTogetherHanCodePoint(0x0041)).assertFalse();
    });

    it('rejectsUnsupportedPunctuation', 0, () => {
      expect(codeOf(validateListenTogetherNickname('Alice_123')))
        .assertEqual(ListenTogetherValidationCode.NICKNAME_CHARS);
      expect(codeOf(validateListenTogetherNickname('   ')))
        .assertEqual(ListenTogetherValidationCode.NICKNAME_LENGTH);
    });

    it('trimsAValidNickname', 0, () => {
      expect(sanitizeListenTogetherNicknameOrNull('  测试123  ')).assertEqual('测试123');
      expect(sanitizeListenTogetherNicknameOrNull('  ')).assertNull();
      expect(sanitizeListenTogetherNicknameOrNull(null)).assertNull();
      expect(sanitizeListenTogetherNicknameOrNull('Alice_123')).assertNull();
    });
  });

  describe('ListenTogetherJoinSecretValidation', () => {
    it('requiresABoundedNonBlankValue', 0, () => {
      expect(codeOf(validateListenTogetherJoinSecret(null)))
        .assertEqual(ListenTogetherValidationCode.JOIN_SECRET_REQUIRED);
      expect(codeOf(validateListenTogetherJoinSecret('   ')))
        .assertEqual(ListenTogetherValidationCode.JOIN_SECRET_REQUIRED);
      expect(codeOf(validateListenTogetherJoinSecret('a'.repeat(257))))
        .assertEqual(ListenTogetherValidationCode.JOIN_SECRET_LENGTH);
      expect(validateListenTogetherJoinSecret('secret-value')).assertNull();
      expect(validateListenTogetherJoinSecret(
        'a'.repeat(LISTEN_TOGETHER_JOIN_SECRET_MAX_LENGTH)
      )).assertNull();
    });

    it('sanitizesToTheTrimmedSecret', 0, () => {
      expect(sanitizeListenTogetherJoinSecretOrNull(' secret-value ')).assertEqual('secret-value');
      expect(sanitizeListenTogetherJoinSecretOrNull('  ')).assertNull();
      expect(sanitizeListenTogetherJoinSecretOrNull(null)).assertNull();
    });
  });

  describe('ListenTogetherRoomIdValidation', () => {
    it('normalizesAndAcceptsTheReadableAlphabet', 0, () => {
      expect(normalizeListenTogetherRoomId('  p8baev ')).assertEqual('P8BAEV');
      expect(validateListenTogetherRoomId(' p8baev ')).assertNull();
      expect(requireValidListenTogetherRoomId(' p8baev ')).assertEqual('P8BAEV');
      expect(LISTEN_TOGETHER_ROOM_ID_LENGTH).assertEqual(6);
    });

    it('rejectsAmbiguousCharactersAndWrongLengths', 0, () => {
      expect(codeOf(validateListenTogetherRoomId('P8BAE')))
        .assertEqual(ListenTogetherValidationCode.ROOM_ID_LENGTH);
      // I, O, 0 and 1 are excluded so a room id survives being read aloud.
      expect(codeOf(validateListenTogetherRoomId('P8BAE0')))
        .assertEqual(ListenTogetherValidationCode.ROOM_ID_CHARS);
      expect(codeOf(validateListenTogetherRoomId('P8BAEI')))
        .assertEqual(ListenTogetherValidationCode.ROOM_ID_CHARS);
      expect(codeOf(validateListenTogetherRoomId('P8BA-V')))
        .assertEqual(ListenTogetherValidationCode.ROOM_ID_CHARS);
    });

    it('throwsACodedFailureFromTheRequireHelper', 0, () => {
      expect(thrownCode(() => {
        requireValidListenTogetherRoomId('P8BAE0');
      })).assertEqual(ListenTogetherValidationCode.ROOM_ID_CHARS);
    });
  });

  describe('ListenTogetherUserUuidValidation', () => {
    it('acceptsAV4UuidAndLowerCasesIt', 0, () => {
      expect(validateListenTogetherUserUuid(VALID_USER_UUID)).assertNull();
      expect(requireValidListenTogetherUserUuid(` ${VALID_USER_UUID.toUpperCase()} `))
        .assertEqual(VALID_USER_UUID);
    });

    it('rejectsBlankAndMalformedUuids', 0, () => {
      expect(codeOf(validateListenTogetherUserUuid('   ')))
        .assertEqual(ListenTogetherValidationCode.USER_UUID_REQUIRED);
      expect(codeOf(validateListenTogetherUserUuid('not-a-uuid')))
        .assertEqual(ListenTogetherValidationCode.USER_UUID_INVALID);
    });
  });

  describe('ListenTogetherRoomCreationValidation', () => {
    it('rejectsLocalCurrentSongEvenWithRemoteQueueEntries', 0, () => {
      const local = songItem('local', '1');
      const remote = songItem('netease', '2');

      expect(codeOf(validateListenTogetherRoomCreation([local, remote], 0, local)))
        .assertEqual(ListenTogetherValidationCode.CURRENT_TRACK_NOT_SHAREABLE);
      expect(validateListenTogetherRoomCreation([remote], 0, remote)).assertNull();
    });

    it('reportsAMissingCurrentSongSeparately', 0, () => {
      const remote = songItem('netease', '1');

      expect(codeOf(validateListenTogetherRoomCreation([remote], 0, null)))
        .assertEqual(ListenTogetherValidationCode.CURRENT_TRACK_MISSING);
    });

    it('rejectsACurrentSongThatIsNotAtTheCurrentIndex', 0, () => {
      const first = songItem('netease', '1');
      const second = songItem('netease', '2');

      expect(codeOf(validateListenTogetherRoomCreation([first, second], 1, first)))
        .assertEqual(ListenTogetherValidationCode.CURRENT_TRACK_UNAVAILABLE);
      expect(codeOf(validateListenTogetherRoomCreation([first], 3, first)))
        .assertEqual(ListenTogetherValidationCode.CURRENT_TRACK_UNAVAILABLE);
    });

    it('throwsFromTheRequireHelperOnly', 0, () => {
      const remote = songItem('netease', '1');

      expect(thrownCode(() => {
        requireValidListenTogetherRoomCreation([remote], 0, remote);
      })).assertNull();
      expect(thrownCode(() => {
        requireValidListenTogetherRoomCreation([remote], 0, null);
      })).assertEqual(ListenTogetherValidationCode.CURRENT_TRACK_MISSING);
    });
  });

  describe('ListenTogetherShareabilityPolicy', () => {
    it('rejectsLocalTracksRegardlessOfChannelCase', 0, () => {
      const remote = songItem('netease', '1');
      const local = songItem('LOCAL', '2');
      const resolvedRemote = songItem('netease', '1');
      resolvedRemote.streamUrl = 'https://cdn.example.com/1.m4a';

      expect(validateListenTogetherRoomCreation([remote], 0, resolvedRemote)).assertNull();
      expect(isShareableForListenTogether(remote)).assertTrue();
      expect(isShareableForListenTogether(local)).assertFalse();
      expect(isShareableForListenTogether(null)).assertFalse();
      expect(hasShareableListenTogetherTrackAt([remote, local], 1)).assertFalse();
      expect(hasShareableListenTogetherTrackAt([remote, local], 0)).assertTrue();
      expect(hasShareableListenTogetherTrackAt([remote], 5)).assertFalse();
      expect(hasShareableListenTogetherTrackAt([remote], -1)).assertFalse();
    });
  });
}
