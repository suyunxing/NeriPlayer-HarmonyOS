import { AppPreferences } from './AppPreferences';
import { PersistedPlaybackState } from '../model/PersistedPlaybackState';

/**
 * Persists the playback session snapshot (queue, index, position, modes) in
 * the shared preferences store. Mirrors the Android persistence extensions:
 * debounce ~250ms on queue changes, 15s throttle on progress, immediate on
 * pause/background (the callers own that timing).
 */
export class PlaybackStateRepository {
  private static readonly KEY: string = 'playback_state';

  static async save(state: PersistedPlaybackState): Promise<void> {
    await AppPreferences.putString(PlaybackStateRepository.KEY, state.toJson());
  }

  /**
   * Returns the persisted snapshot, or null when nothing was stored or the
   * payload is corrupted (caller keeps defaults in that case).
   */
  static async load(): Promise<PersistedPlaybackState | null> {
    const json = await AppPreferences.getString(PlaybackStateRepository.KEY, '');
    if (json.length === 0) {
      return null;
    }
    try {
      return PersistedPlaybackState.fromJson(json);
    } catch (error) {
      return null;
    }
  }

  static async clear(): Promise<void> {
    await AppPreferences.putString(PlaybackStateRepository.KEY, '');
  }
}
