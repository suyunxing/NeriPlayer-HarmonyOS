/**
 * Port of listentogether/playback/ListenTogetherListenerSafetyPausePolicy.kt.
 *
 * When member control is off, a listener's own transport must not be able to
 * start playback: the room decides. Rather than disabling the buttons and leaving
 * the user with a dead UI, the listener is allowed to press play and is then
 * immediately paused back, with the resume held until the room says so.
 */

/** Upstream `LISTEN_TOGETHER_LISTENER_SAFETY_RESUME_CAUSE`. */
export const LISTEN_TOGETHER_LISTENER_SAFETY_RESUME_CAUSE: string = 'LISTENER_SAFETY_RESUME';

/**
 * `allowMemberControl` is nullable on purpose: an unknown setting must not switch
 * the safety pause on, because a listener in a room whose settings have not
 * arrived yet would otherwise be pinned paused.
 */
export function shouldUseListenTogetherListenerSafetyPause(
  listenTogetherActive: boolean,
  isCurrentUserController: boolean,
  allowMemberControl: boolean | null
): boolean {
  return listenTogetherActive && !isCurrentUserController && allowMemberControl === false;
}

/**
 * True while a held resume must keep playback down. The resume the policy itself
 * issues is exempt, otherwise it would block the very thing it exists to release.
 */
export function shouldHoldListenTogetherPlaybackForSafetyPause(
  safetyPausePendingResume: boolean,
  causeType: string | null
): boolean {
  return safetyPausePendingResume && causeType !== LISTEN_TOGETHER_LISTENER_SAFETY_RESUME_CAUSE;
}
