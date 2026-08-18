/**
 * Port of data/sync/github/SyncSongMetadataMergePolicy.kt.
 * Deterministic payload selection for merged songs: higher
 * syncMetadataVersion wins; ties are broken by the canonical payload key so
 * both endpoints converge on the same result regardless of input order.
 */
import { SyncSong, CURRENT_SYNC_METADATA_VERSION } from './SyncModels';

export function canonicalPayloadKey(song: SyncSong): string {
  const parts: string[] = [
    `${song.id}`,
    song.name,
    song.artist,
    song.album,
    `${song.albumId}`,
    `${song.durationMs}`,
    song.coverUrl === null ? '' : song.coverUrl,
    song.mediaUri === null ? '' : song.mediaUri,
    `${song.addedAt}`,
    song.matchedLyric === null ? '' : song.matchedLyric,
    song.matchedTranslatedLyric === null ? '' : song.matchedTranslatedLyric,
    song.matchedLyricSource === null ? '' : song.matchedLyricSource,
    song.matchedSongId === null ? '' : song.matchedSongId,
    `${song.userLyricOffsetMs}`,
    song.customCoverUrl === null ? '' : song.customCoverUrl,
    song.customName === null ? '' : song.customName,
    song.customArtist === null ? '' : song.customArtist,
    song.originalName === null ? '' : song.originalName,
    song.originalArtist === null ? '' : song.originalArtist,
    song.originalCoverUrl === null ? '' : song.originalCoverUrl,
    song.originalLyric === null ? '' : song.originalLyric,
    song.originalTranslatedLyric === null ? '' : song.originalTranslatedLyric,
    song.channelId === null ? '' : song.channelId,
    song.audioId === null ? '' : song.audioId,
    song.subAudioId === null ? '' : song.subAudioId,
    song.playlistContextId === null ? '' : song.playlistContextId,
    `${song.syncMetadataVersion}`
  ];
  let key = '';
  for (const value of parts) {
    key += `${value.length}:${value}`;
  }
  return key;
}

function comparePayloadCandidates(a: SyncSong, b: SyncSong): number {
  if (a.syncMetadataVersion !== b.syncMetadataVersion) {
    return a.syncMetadataVersion < b.syncMetadataVersion ? -1 : 1;
  }
  const keyA = canonicalPayloadKey(a);
  const keyB = canonicalPayloadKey(b);
  if (keyA < keyB) {
    return -1;
  }
  if (keyA > keyB) {
    return 1;
  }
  return 0;
}

/** maxWith(comparator): the first maximal element, like Kotlin. */
export function selectDeterministicPayload(candidates: SyncSong[]): SyncSong {
  let best = candidates[0];
  for (let i = 1; i < candidates.length; i++) {
    if (comparePayloadCandidates(candidates[i], best) > 0) {
      best = candidates[i];
    }
  }
  return best;
}

/** maxByOrNull(canonicalPayloadKey): the first maximal key, like Kotlin. */
function maxByCanonicalKey(candidates: SyncSong[]): SyncSong | null {
  let best: SyncSong | null = null;
  let bestKey = '';
  for (const candidate of candidates) {
    if (best === null) {
      best = candidate;
      bestKey = canonicalPayloadKey(candidate);
      continue;
    }
    const key = canonicalPayloadKey(candidate);
    if (key > bestKey) {
      best = candidate;
      bestKey = key;
    }
  }
  return best;
}

export function resolveSelectedPayload(selected: SyncSong, candidates: SyncSong[]): SyncSong {
  // Current payloads are authoritative and may intentionally clear fields;
  // legacy blanks must never refill them.
  if (selected.syncMetadataVersion >= CURRENT_SYNC_METADATA_VERSION) {
    return selected;
  }
  const currentPayloads: SyncSong[] = [];
  for (const candidate of candidates) {
    if (candidate.syncMetadataVersion >= CURRENT_SYNC_METADATA_VERSION) {
      currentPayloads.push(candidate);
    }
  }
  if (currentPayloads.length > 0) {
    const replacement = maxByCanonicalKey(currentPayloads);
    if (replacement !== null) {
      return replacement;
    }
  }
  return fillMissingLegacyMetadata(selected, candidates);
}

export function resolveAddedAt(selectedAddedAt: number, candidates: SyncSong[]): number {
  if (selectedAddedAt > 0) {
    return selectedAddedAt;
  }
  let max = 0;
  for (const candidate of candidates) {
    if (candidate.addedAt > max) {
      max = candidate.addedAt;
    }
  }
  return max;
}

type StringSelector = (song: SyncSong) => string | null;
type NumberSelector = (song: SyncSong) => number;

function firstNonBlank(candidates: SyncSong[], selector: StringSelector): string {
  for (const song of candidates) {
    const value = selector(song);
    if (value !== null && value.trim().length > 0) {
      return value;
    }
  }
  return '';
}

function firstNonZero(candidates: SyncSong[], selector: NumberSelector): number {
  for (const song of candidates) {
    const value = selector(song);
    if (value !== 0) {
      return value;
    }
  }
  return 0;
}

function firstPositive(candidates: SyncSong[], selector: NumberSelector): number {
  for (const song of candidates) {
    const value = selector(song);
    if (value > 0) {
      return value;
    }
  }
  return 0;
}

function nonBlankOrElse(
  selectedValue: string | null,
  candidates: SyncSong[],
  selector: StringSelector
): string | null {
  if (selectedValue !== null && selectedValue.trim().length > 0) {
    return selectedValue;
  }
  for (const song of candidates) {
    const value = selector(song);
    if (value !== null && value.trim().length > 0) {
      return value;
    }
  }
  return null;
}

function fillMissingLegacyMetadata(selected: SyncSong, candidates: SyncSong[]): SyncSong {
  return new SyncSong(
    selected.id !== 0 ? selected.id : firstNonZero(candidates, (song: SyncSong): number => song.id),
    selected.name.trim().length > 0 ? selected.name : firstNonBlank(candidates, (song: SyncSong): string => song.name),
    selected.artist.trim().length > 0 ? selected.artist : firstNonBlank(candidates, (song: SyncSong): string => song.artist),
    selected.album.trim().length > 0 ? selected.album : firstNonBlank(candidates, (song: SyncSong): string => song.album),
    selected.albumId !== 0 ? selected.albumId : firstNonZero(candidates, (song: SyncSong): number => song.albumId),
    selected.durationMs > 0 ? selected.durationMs : firstPositive(candidates, (song: SyncSong): number => song.durationMs),
    nonBlankOrElse(selected.coverUrl, candidates, (song: SyncSong): string | null => song.coverUrl),
    nonBlankOrElse(selected.mediaUri, candidates, (song: SyncSong): string | null => song.mediaUri),
    selected.addedAt,
    nonBlankOrElse(selected.matchedLyric, candidates, (song: SyncSong): string | null => song.matchedLyric),
    nonBlankOrElse(selected.matchedTranslatedLyric, candidates, (song: SyncSong): string | null => song.matchedTranslatedLyric),
    nonBlankOrElse(selected.matchedLyricSource, candidates, (song: SyncSong): string | null => song.matchedLyricSource),
    nonBlankOrElse(selected.matchedSongId, candidates, (song: SyncSong): string | null => song.matchedSongId),
    selected.userLyricOffsetMs !== 0
      ? selected.userLyricOffsetMs
      : firstNonZero(candidates, (song: SyncSong): number => song.userLyricOffsetMs),
    nonBlankOrElse(selected.customCoverUrl, candidates, (song: SyncSong): string | null => song.customCoverUrl),
    nonBlankOrElse(selected.customName, candidates, (song: SyncSong): string | null => song.customName),
    nonBlankOrElse(selected.customArtist, candidates, (song: SyncSong): string | null => song.customArtist),
    nonBlankOrElse(selected.originalName, candidates, (song: SyncSong): string | null => song.originalName),
    nonBlankOrElse(selected.originalArtist, candidates, (song: SyncSong): string | null => song.originalArtist),
    nonBlankOrElse(selected.originalCoverUrl, candidates, (song: SyncSong): string | null => song.originalCoverUrl),
    nonBlankOrElse(selected.originalLyric, candidates, (song: SyncSong): string | null => song.originalLyric),
    nonBlankOrElse(selected.originalTranslatedLyric, candidates, (song: SyncSong): string | null => song.originalTranslatedLyric),
    nonBlankOrElse(selected.channelId, candidates, (song: SyncSong): string | null => song.channelId),
    nonBlankOrElse(selected.audioId, candidates, (song: SyncSong): string | null => song.audioId),
    nonBlankOrElse(selected.subAudioId, candidates, (song: SyncSong): string | null => song.subAudioId),
    nonBlankOrElse(selected.playlistContextId, candidates, (song: SyncSong): string | null => song.playlistContextId),
    selected.syncMembershipTokens,
    selected.syncMetadataVersion,
    selected.legacyAddedAt
  );
}
