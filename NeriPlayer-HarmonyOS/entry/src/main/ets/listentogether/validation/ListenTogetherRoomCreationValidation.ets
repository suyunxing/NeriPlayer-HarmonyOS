/**
 * Port of listentogether/validation/ListenTogetherRoomCreationValidation.kt.
 *
 * A room is created around the song that is playing *now*, so the check makes
 * sure the current song is shareable and is still the one sitting at
 * `currentIndex` in the queue — otherwise the room would open on a track the
 * host is not actually playing.
 */
import { SongItem } from '../../model/SongItem';
import { songItemToListenTogetherTrackOrNull } from '../mapping/ListenTogetherTrackMapping';
import {
  ListenTogetherValidationCode,
  ListenTogetherValidationError,
  listenTogetherValidationError,
  throwListenTogetherValidation
} from './ListenTogetherValidationError';

export function validateListenTogetherRoomCreation(
  queue: SongItem[],
  currentIndex: number,
  currentSong: SongItem | null
): ListenTogetherValidationError | null {
  if (currentSong === null) {
    return listenTogetherValidationError(ListenTogetherValidationCode.CURRENT_TRACK_MISSING);
  }
  const currentTrack = songItemToListenTogetherTrackOrNull(currentSong);
  if (currentTrack === null) {
    return listenTogetherValidationError(ListenTogetherValidationCode.CURRENT_TRACK_NOT_SHAREABLE);
  }
  // Kotlin `queue.getOrNull(currentIndex)`.
  if (currentIndex < 0 || currentIndex >= queue.length) {
    return listenTogetherValidationError(ListenTogetherValidationCode.CURRENT_TRACK_UNAVAILABLE);
  }
  const queueTrack = songItemToListenTogetherTrackOrNull(queue[currentIndex]);
  if (queueTrack === null) {
    return listenTogetherValidationError(ListenTogetherValidationCode.CURRENT_TRACK_NOT_SHAREABLE);
  }
  if (queueTrack.stableKey === currentTrack.stableKey) {
    return null;
  }
  return listenTogetherValidationError(ListenTogetherValidationCode.CURRENT_TRACK_UNAVAILABLE);
}

export function requireValidListenTogetherRoomCreation(
  queue: SongItem[],
  currentIndex: number,
  currentSong: SongItem | null
): void {
  const error = validateListenTogetherRoomCreation(queue, currentIndex, currentSong);
  if (error !== null) {
    throwListenTogetherValidation(error);
  }
}
