// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

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
  localResolvedStreamUrl: string | null,
  localPlaybackRequiresAuthoritativeStream: boolean = true,
  localPlaybackResolutionPending: boolean = false,
  pendingAuthoritativeStreamUrl: string | null = null
): boolean {
  // A local resolution still in flight may yet land on the authoritative url;
  // reloading under it would race two loads of the same track.
  if (localPlaybackResolutionPending) {
    return false;
  }
  const remote = normalizedDirectStreamUrl(remoteStreamUrl);
  if (remote === null) {
    return false;
  }
  const local = normalizedDirectStreamUrl(localResolvedStreamUrl);
  if (remote === local) {
    return false;
  }
  // The local url only stays put when the room is not sharing links; when the
  // listener depends on the controller's link, any other local url is a
  // temporary stand-in that the authoritative one must replace.
  if (local !== null && !localPlaybackRequiresAuthoritativeStream) {
    return false;
  }
  return remote !== normalizedDirectStreamUrl(pendingAuthoritativeStreamUrl);
}

/**
 * Upstream #359 `hasListenTogetherAuthoritativeStreamUrl`: the local player is
 * already playing one of the room's whitelisted urls, so no reload is needed.
 */
export function hasListenTogetherAuthoritativeStreamUrl(
  authoritativeStreamUrls: string[],
  localResolvedStreamUrl: string | null
): boolean {
  const local = normalizedDirectStreamUrl(localResolvedStreamUrl);
  if (local === null) {
    return false;
  }
  for (const candidate of authoritativeStreamUrls) {
    if (normalizedDirectStreamUrl(candidate) === local) {
      return true;
    }
  }
  return false;
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

// ---------- upstream #359 (squashed 3cfd7037) link lifecycle predicates ----------

/**
 * The controller confirmed (twice) it has no shareable link: the listener may
 * stop waiting and reload through its own resolution — once per track.
 */
export function shouldReloadForListenTogetherLinkUnavailable(
  isController: boolean,
  localPlaybackRequiresAuthoritativeStream: boolean,
  controllerLinkConfirmedUnavailable: boolean = true,
  alreadyReloadedForStableKey: boolean = false
): boolean {
  return !isController &&
    controllerLinkConfirmedUnavailable &&
    localPlaybackRequiresAuthoritativeStream &&
    !alreadyReloadedForStableKey;
}

/**
 * A confirmed-unavailable link stops further REQUEST_LINK traffic for that
 * track unless the caller forces it (e.g. a track change re-opens the case).
 */
export function shouldRequestListenTogetherControllerLink(
  force: boolean,
  controllerLinkUnavailable: boolean
): boolean {
  return force || !controllerLinkUnavailable;
}

/**
 * The controller's own playback is still resolving the requested track: a link
 * published now would describe a half-loaded state, so resolution defers.
 */
export function shouldDeferControllerLinkResolution(
  playbackResolutionPending: boolean,
  currentTrackStableKey: string | null,
  requestedStableKey: string
): boolean {
  if (!playbackResolutionPending) {
    return false;
  }
  const current = currentTrackStableKey === null ? '' : currentTrackStableKey.trim();
  const requested = requestedStableKey.trim();
  return current.length > 0 && requested.length > 0 && current === requested;
}

export function shouldRetryControllerLinkResolution(
  attempt: number,
  maximumAttempts: number,
  hasShareableStream: boolean,
  playbackResolutionPending: boolean
): boolean {
  if (maximumAttempts <= 0) {
    return false;
  }
  return !hasShareableStream && !playbackResolutionPending && attempt + 1 < maximumAttempts;
}

export function shouldPublishControllerLinkUnavailable(
  attempt: number,
  maximumAttempts: number,
  hasShareableStream: boolean,
  playbackResolutionPending: boolean
): boolean {
  if (maximumAttempts <= 0) {
    return false;
  }
  return !hasShareableStream && !playbackResolutionPending && attempt + 1 >= maximumAttempts;
}

/**
 * The listener's own resolution failed (or only found a preview), but the room
 * shares links and the controller has not said unavailable: keep waiting
 * instead of falling back to a degraded stream.
 */
export function shouldAwaitListenTogetherSharedStreamFallback(
  listenerAudioLinkSharingActive: boolean,
  localResolutionRequiresSharedStream: boolean,
  controllerLinkConfirmedUnavailable: boolean,
  hasAuthoritativeStream: boolean
): boolean {
  return listenerAudioLinkSharingActive &&
    localResolutionRequiresSharedStream &&
    !controllerLinkConfirmedUnavailable &&
    !hasAuthoritativeStream;
}

/**
 * While waiting for the controller's link, a local resolution error is not the
 * user's problem yet — the room may still deliver a playable url.
 */
export function shouldSuppressListenTogetherResolverError(
  listenerAudioLinkSharingActive: boolean,
  controllerLinkConfirmedUnavailable: boolean
): boolean {
  return listenerAudioLinkSharingActive && !controllerLinkConfirmedUnavailable;
}

/**
 * While sharing links, the listener prefers the room's platform url over the
 * netease auto-fallback (a fallback link only this device can play is
 * useless to the room and may be region-locked for others).
 */
export function shouldPreferListenTogetherSourceBeforeNeteaseFallback(
  listenerAudioLinkSharingActive: boolean
): boolean {
  return listenerAudioLinkSharingActive;
}

/**
 * A preview-clip notice is noise while the room is expected to hand over a
 * full link; only surface it once that hope is confirmed gone.
 */
export function shouldShowListenTogetherPreviewClipNotice(
  isPreviewClip: boolean,
  listenerAudioLinkSharingActive: boolean,
  controllerLinkConfirmedUnavailable: boolean
): boolean {
  return !isPreviewClip ||
    !listenerAudioLinkSharingActive ||
    controllerLinkConfirmedUnavailable;
}
