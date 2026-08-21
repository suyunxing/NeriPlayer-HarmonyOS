/**
 * Port of listentogether/playback/ListenTogetherStreamPolicy.kt: when the
 * authoritative (room-supplied) direct stream must replace or hold back the
 * locally resolved one.
 */

/** Trims and keeps only http(s) direct links, case-insensitively. */
export function normalizedDirectStreamUrl(value: string | null): string | null {
  const candidate = value === null ? '' : value.trim();
  if (candidate.length === 0) {
    return null;
  }
  const lowered = candidate.toLowerCase();
  if (lowered.startsWith('https://') || lowered.startsWith('http://')) {
    return candidate;
  }
  return null;
}

export function shouldReloadListenTogetherAuthoritativeStream(
  remoteStreamUrl: string | null,
  localResolvedStreamUrl: string | null
): boolean {
  const remote = normalizedDirectStreamUrl(remoteStreamUrl);
  if (remote === null) {
    return false;
  }
  return remote !== normalizedDirectStreamUrl(localResolvedStreamUrl);
}

export function shouldWaitForListenTogetherAuthoritativeStreamPlayback(
  playerWaitingForAuthoritativeStream: boolean,
  localTrackMatchesTarget: boolean,
  localTrackStreamUrl: string | null,
  localResolvedStreamUrl: string | null
): boolean {
  if (!playerWaitingForAuthoritativeStream) {
    return false;
  }
  if (!localTrackMatchesTarget) {
    return true;
  }
  return normalizedDirectStreamUrl(localTrackStreamUrl) === null &&
    normalizedDirectStreamUrl(localResolvedStreamUrl) === null;
}
