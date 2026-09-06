/**
 * Port of listentogether/playback/ListenTogetherShareabilityPolicy.kt: a song is
 * shareable exactly when it maps onto a wire track (local files do not).
 */
import { SongItem } from '../../model/SongItem';
import { songItemToListenTogetherTrackOrNull } from '../mapping/ListenTogetherTrackMapping';

export function isShareableForListenTogether(song: SongItem | null): boolean {
  return song !== null && songItemToListenTogetherTrackOrNull(song) !== null;
}

export function hasShareableListenTogetherTrackAt(queue: SongItem[], index: number): boolean {
  if (index < 0 || index >= queue.length) {
    return false;
  }
  return isShareableForListenTogether(queue[index]);
}
