/**
 * The local playback command the event factory turns into a room event.
 *
 * **Divergence: this type is declared here, not in the player.** Upstream's
 * `PlaybackCommand` lives in `core/player/policy/command/PlayerPlaybackPolicy.kt`,
 * where the player's own policy layer already routes every transport action
 * through it, and listen-together simply consumes that type. This project's
 * `PlayerManager` has no command object at all — `play()`, `pause()`, `seekTo()`
 * and friends are direct method calls — so there is nothing to consume. Rather
 * than invent a command bus for the whole player (a much larger change, and not
 * what M7.3 is for), the shape listen-together needs is declared inside
 * listen-together. M7.3b's integration point synthesizes a command from the
 * `PlayerListener` callback it received; if the player ever grows a real command
 * layer, this file becomes a re-export.
 *
 * `queue`, `currentIndex`, `positionMs`, `shouldPlay`, `repeatMode` and
 * `shuffleEnabled` are all nullable because a command carries only what it
 * actually decided — absent means "keep whatever is current", which is not the
 * same as a zero or a false.
 */
import { SongItem } from '../../model/SongItem';

export enum ListenTogetherPlaybackCommandSource {
  /** The user acted on this device. */
  LOCAL = 'local',
  /** The listener safety pause acted on the user's behalf. */
  LOCAL_SAFETY = 'local_safety',
  /** The room told us to. Never published back, or two clients would ping-pong. */
  REMOTE_SYNC = 'remote_sync'
}

export class ListenTogetherPlaybackCommand {
  type: string = '';
  source: ListenTogetherPlaybackCommandSource = ListenTogetherPlaybackCommandSource.LOCAL;
  timestampMs: number = 0;
  queue: SongItem[] | null = null;
  currentIndex: number | null = null;
  positionMs: number | null = null;
  shouldPlay: boolean | null = null;
  repeatMode: number | null = null;
  shuffleEnabled: boolean | null = null;
  /** Bypasses the "nothing changed" short-circuits in the player policy. */
  force: boolean = false;
}

/** Convenience for the common case: a bare command with only a type and a source. */
export function createListenTogetherPlaybackCommand(
  type: string,
  source: ListenTogetherPlaybackCommandSource,
  timestampMs: number
): ListenTogetherPlaybackCommand {
  const command = new ListenTogetherPlaybackCommand();
  command.type = type;
  command.source = source;
  command.timestampMs = timestampMs;
  return command;
}
