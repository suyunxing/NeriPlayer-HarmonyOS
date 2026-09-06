/**
 * Port of data/sync/github/SyncPlaylistSongMergePolicy.kt.
 *
 * Two-way playlist song merge (local vs remote). The "third way" is the pair
 * of changedAfterSync flags derived from lastSyncTime. Matching keys in
 * priority order: exact membership token → identity → channel/audio →
 * fallback (id + normalized name/artist bucketed by source hint).
 */
import {
  SyncSong,
  SyncCausalToken,
  SongIdentityKey,
  syncSongIdentity,
  syncSongEquals,
  songWithNormalizedTokens,
  songWithResolvedPayload,
  causalTokenKey,
  normalizedSyncCausalTokens
} from './SyncModels';
import {
  selectDeterministicPayload,
  resolveSelectedPayload,
  resolveAddedAt
} from './SongMetadataMergePolicy';

export class PlaylistSongMergeResult {
  songs: SyncSong[];
  /** True when the merged result differs from the LOCAL snapshot (needs write-back). */
  isUpdated: boolean;

  constructor(songs: SyncSong[], isUpdated: boolean) {
    this.songs = songs;
    this.isUpdated = isUpdated;
  }
}

export function mergeSongs(
  localSongs: SyncSong[],
  remoteSongs: SyncSong[],
  localModifiedAt: number,
  remoteModifiedAt: number,
  localChangedAfterSync: boolean,
  remoteChangedAfterSync: boolean,
  lastSyncTime: number,
  isFavorites: boolean
): PlaylistSongMergeResult {
  const localIsEmpty = localSongs.length === 0;
  const remoteIsEmpty = remoteSongs.length === 0;
  const localHasMembershipTokens = hasMembershipTokens(localSongs);
  const remoteHasMembershipTokens = hasMembershipTokens(remoteSongs);
  const preferRemoteFavorites = isFavorites && localIsEmpty && !remoteIsEmpty && lastSyncTime <= 0;

  if (preferRemoteFavorites) {
    return new PlaylistSongMergeResult(deduplicateSongs(remoteSongs), true);
  }

  if (localIsEmpty && !remoteIsEmpty) {
    if (remoteHasMembershipTokens) {
      // Tokenized memberships are owned by the deletion policy, not by clears.
      return new PlaylistSongMergeResult(deduplicateSongs(remoteSongs), true);
    }
    const localClearWins = localChangedAfterSync && localModifiedAt >= remoteModifiedAt;
    return localClearWins
      ? new PlaylistSongMergeResult([], false)
      : new PlaylistSongMergeResult(deduplicateSongs(remoteSongs), true);
  }

  if (remoteIsEmpty && !localIsEmpty) {
    if (localHasMembershipTokens) {
      return new PlaylistSongMergeResult(deduplicateSongs(localSongs), false);
    }
    const remoteClearWins = remoteChangedAfterSync && remoteModifiedAt > localModifiedAt;
    return remoteClearWins
      ? new PlaylistSongMergeResult([], true)
      : new PlaylistSongMergeResult(deduplicateSongs(localSongs), false);
  }

  if (remoteChangedAfterSync && !localChangedAfterSync) {
    return new PlaylistSongMergeResult(
      mergeMembershipTokensIntoPrimary(remoteSongs, localSongs), true);
  }
  if (localChangedAfterSync && !remoteChangedAfterSync) {
    return new PlaylistSongMergeResult(
      mergeMembershipTokensIntoPrimary(localSongs, remoteSongs), false);
  }
  if (localChangedAfterSync && localModifiedAt > remoteModifiedAt) {
    return new PlaylistSongMergeResult(
      mergeConcurrentChanges(localSongs, remoteSongs), true);
  }
  if (localChangedAfterSync && remoteModifiedAt > localModifiedAt) {
    return new PlaylistSongMergeResult(
      mergeConcurrentChanges(remoteSongs, localSongs), true);
  }

  const uniqueLocalSongs = deduplicateSongs(localSongs);
  const uniqueRemoteSongs = deduplicateSongs(remoteSongs);
  const mergedSongs = mergeSongsWithDeterministicPayload(uniqueLocalSongs, uniqueRemoteSongs);
  return new PlaylistSongMergeResult(
    mergedSongs,
    !sameSongList(mergedSongs, uniqueLocalSongs) || !sameSongList(mergedSongs, uniqueRemoteSongs)
  );
}

export function deduplicateSongs(songs: SyncSong[]): SyncSong[] {
  if (songs.length === 0) {
    return songs;
  }
  const accumulator = new SongMergeAccumulator(false);
  for (const song of songs) {
    accumulator.addIfAbsent(song);
  }
  return accumulator.toList();
}

function mergeSongsWithDeterministicPayload(localSongs: SyncSong[], remoteSongs: SyncSong[]): SyncSong[] {
  if (remoteSongs.length === 0) {
    return localSongs;
  }
  const accumulator = new SongMergeAccumulator(true);
  for (const song of localSongs) {
    accumulator.addIfAbsent(song);
  }
  for (const song of remoteSongs) {
    accumulator.addIfAbsent(song);
  }
  return accumulator.toList();
}

function mergeMembershipTokensIntoPrimary(primarySongs: SyncSong[], secondarySongs: SyncSong[]): SyncSong[] {
  const accumulator = new SongMergeAccumulator(false);
  for (const song of primarySongs) {
    accumulator.addIfAbsent(song);
  }
  for (const song of secondarySongs) {
    accumulator.mergeMatchingMembershipTokens(song);
  }
  return accumulator.toList();
}

function mergeConcurrentChanges(primarySongs: SyncSong[], secondarySongs: SyncSong[]): SyncSong[] {
  const accumulator = new SongMergeAccumulator(false);
  for (const song of primarySongs) {
    accumulator.addIfAbsent(song);
  }
  for (const song of secondarySongs) {
    accumulator.addIfAbsent(song);
  }
  return accumulator.toList();
}

function hasMembershipTokens(songs: SyncSong[]): boolean {
  for (const song of songs) {
    if (song.syncMembershipTokens.length > 0) {
      return true;
    }
  }
  return false;
}

function sameSongList(left: SyncSong[], right: SyncSong[]): boolean {
  if (left.length !== right.length) {
    return false;
  }
  for (let i = 0; i < left.length; i++) {
    if (!syncSongEquals(songWithNormalizedTokens(left[i]), songWithNormalizedTokens(right[i]))) {
      return false;
    }
  }
  return true;
}

function normalizedText(value: string): string {
  return value.trim().toLowerCase();
}

function channelAudioKey(song: SyncSong): string | null {
  const channelRaw = song.channelId === null ? '' : song.channelId.trim().toLowerCase();
  const channel = channelRaw.length > 0 ? channelRaw : null;
  const audioRaw = song.audioId === null ? '' : song.audioId.trim();
  const audio = audioRaw.length > 0 ? audioRaw : null;
  if (channel === null || audio === null) {
    return null;
  }
  const subAudio = song.subAudioId === null ? '' : song.subAudioId.trim();
  return `${channel}|${audio}|${subAudio}`;
}

function sourceHint(song: SyncSong): string | null {
  const channelRaw = song.channelId === null ? '' : song.channelId.trim().toLowerCase();
  if (channelRaw.length > 0) {
    return channelRaw;
  }
  const album = song.album.trim().toLowerCase();
  if (album.startsWith('netease')) {
    return 'netease';
  }
  if (album.startsWith('bilibili')) {
    return 'bilibili';
  }
  if (song.mediaUri !== null && song.mediaUri.toLowerCase().indexOf('youtube') >= 0) {
    return 'youtube';
  }
  return null;
}

class SongMergeCandidate {
  readonly id: number;
  readonly identity: SongIdentityKey;
  readonly channelAudioKey: string | null;
  readonly sourceHint: string | null;
  readonly normalizedName: string;
  readonly normalizedArtist: string;
  readonly fallbackKey: string | null;

  constructor(song: SyncSong) {
    this.id = song.id;
    this.identity = syncSongIdentity(song);
    this.channelAudioKey = channelAudioKey(song);
    this.sourceHint = sourceHint(song);
    this.normalizedName = normalizedText(song.name);
    this.normalizedArtist = normalizedText(song.artist);
    this.fallbackKey = this.id !== 0 && this.normalizedName.length > 0
      ? `${this.id}\u0000${this.normalizedName}\u0000${this.normalizedArtist}`
      : null;
  }
}

class SourceBucket {
  private unknownSourceIndex: number | null = null;
  private sourceIndices: Map<string, number> = new Map<string, number>();

  findAll(source: string | null): Set<number> {
    const result = new Set<number>();
    if (this.unknownSourceIndex !== null) {
      result.add(this.unknownSourceIndex);
    }
    if (source === null) {
      this.sourceIndices.forEach((index: number) => {
        result.add(index);
      });
    } else {
      const index = this.sourceIndices.get(source);
      if (index !== undefined) {
        result.add(index);
      }
    }
    return result;
  }

  add(source: string | null, index: number): void {
    if (source === null) {
      if (this.unknownSourceIndex === null) {
        this.unknownSourceIndex = index;
      }
    } else if (!this.sourceIndices.has(source)) {
      this.sourceIndices.set(source, index);
    }
  }
}

class SongMergeIndex {
  private membershipTokenIndices: Map<string, number> = new Map<string, number>();
  private identityIndices: Map<string, number> = new Map<string, number>();
  private channelAudioIndices: Map<string, number> = new Map<string, number>();
  private fallbackSourcesByKey: Map<string, SourceBucket> = new Map<string, SourceBucket>();

  findMatchingIndices(song: SyncSong): Set<number> {
    const candidate = new SongMergeCandidate(song);
    const result = new Set<number>();
    for (const token of song.syncMembershipTokens) {
      const index = this.membershipTokenIndices.get(causalTokenKey(token));
      if (index !== undefined) {
        result.add(index);
      }
    }
    const identityIndex = this.identityIndices.get(candidate.identity.mapKey());
    if (identityIndex !== undefined) {
      result.add(identityIndex);
    }
    if (candidate.channelAudioKey !== null) {
      const channelIndex = this.channelAudioIndices.get(candidate.channelAudioKey);
      if (channelIndex !== undefined) {
        result.add(channelIndex);
      }
    }
    if (candidate.fallbackKey !== null) {
      const bucket = this.fallbackSourcesByKey.get(candidate.fallbackKey);
      if (bucket !== undefined) {
        bucket.findAll(candidate.sourceHint).forEach((index: number) => {
          result.add(index);
        });
      }
    }
    return result;
  }

  register(song: SyncSong, index: number): void {
    const candidate = new SongMergeCandidate(song);
    for (const token of song.syncMembershipTokens) {
      const key = causalTokenKey(token);
      if (!this.membershipTokenIndices.has(key)) {
        this.membershipTokenIndices.set(key, index);
      }
    }
    const identityKey = candidate.identity.mapKey();
    if (!this.identityIndices.has(identityKey)) {
      this.identityIndices.set(identityKey, index);
    }
    if (candidate.channelAudioKey !== null &&
      !this.channelAudioIndices.has(candidate.channelAudioKey)) {
      this.channelAudioIndices.set(candidate.channelAudioKey, index);
    }
    if (candidate.fallbackKey === null) {
      return;
    }
    let bucket = this.fallbackSourcesByKey.get(candidate.fallbackKey);
    if (bucket === undefined) {
      bucket = new SourceBucket();
      this.fallbackSourcesByKey.set(candidate.fallbackKey, bucket);
    }
    bucket.add(candidate.sourceHint, index);
  }
}

class SongMergeEntry {
  song: SyncSong;
  aliases: SyncSong[];

  constructor(song: SyncSong, aliases: SyncSong[]) {
    this.song = song;
    this.aliases = aliases;
  }
}

function containsSong(list: SyncSong[], song: SyncSong): boolean {
  for (const entry of list) {
    if (syncSongEquals(entry, song)) {
      return true;
    }
  }
  return false;
}

class SongMergeAccumulator {
  private readonly resolvePayloadDeterministically: boolean;
  private mergeIndex: SongMergeIndex = new SongMergeIndex();
  private entries: SongMergeEntry[] = [];

  constructor(resolvePayloadDeterministically: boolean) {
    this.resolvePayloadDeterministically = resolvePayloadDeterministically;
  }

  addIfAbsent(song: SyncSong): void {
    const normalizedSong = songWithNormalizedTokens(song);
    const matchingIndices = this.mergeIndex.findMatchingIndices(normalizedSong);
    if (matchingIndices.size > 0) {
      this.mergeMembershipComponents(matchingIndices, normalizedSong);
      return;
    }
    this.mergeIndex.register(normalizedSong, this.entries.length);
    this.entries.push(new SongMergeEntry(normalizedSong, [normalizedSong]));
  }

  mergeMatchingMembershipTokens(song: SyncSong): void {
    const normalizedSong = songWithNormalizedTokens(song);
    const matchingIndices = this.mergeIndex.findMatchingIndices(normalizedSong);
    if (matchingIndices.size === 0) {
      return;
    }
    this.mergeMembershipComponents(matchingIndices, normalizedSong);
  }

  toList(): SyncSong[] {
    const result: SyncSong[] = [];
    for (const entry of this.entries) {
      result.push(entry.song);
    }
    return result;
  }

  private mergeMembershipComponents(matchingIndices: Set<number>, other: SyncSong): void {
    let primaryIndex = -1;
    matchingIndices.forEach((index: number) => {
      if (primaryIndex === -1 || index < primaryIndex) {
        primaryIndex = index;
      }
    });
    const primaryEntry = this.entries[primaryIndex];

    const tokenBuffer: SyncCausalToken[] = [];
    matchingIndices.forEach((index: number) => {
      for (const token of this.entries[index].song.syncMembershipTokens) {
        tokenBuffer.push(token);
      }
    });
    for (const token of other.syncMembershipTokens) {
      tokenBuffer.push(token);
    }
    const mergedTokens = normalizedSyncCausalTokens(tokenBuffer);

    const payloadCandidates: SyncSong[] = [];
    matchingIndices.forEach((index: number) => {
      payloadCandidates.push(this.entries[index].song);
    });
    payloadCandidates.push(other);

    const selectedPayload = this.resolvePayloadDeterministically
      ? selectDeterministicPayload(payloadCandidates)
      : primaryEntry.song;
    const resolvedPayload = resolveSelectedPayload(selectedPayload, payloadCandidates);
    primaryEntry.song = songWithResolvedPayload(
      resolvedPayload,
      resolveAddedAt(selectedPayload.addedAt, payloadCandidates),
      mergedTokens
    );

    matchingIndices.forEach((index: number) => {
      if (index === primaryIndex) {
        return;
      }
      for (const alias of this.entries[index].aliases) {
        if (!containsSong(primaryEntry.aliases, alias)) {
          primaryEntry.aliases.push(alias);
        }
      }
    });
    if (!containsSong(primaryEntry.aliases, other)) {
      primaryEntry.aliases.push(other);
    }

    if (matchingIndices.size === 1) {
      this.mergeIndex.register(primaryEntry.song, primaryIndex);
      this.mergeIndex.register(other, primaryIndex);
      return;
    }

    const toRemove: number[] = [];
    matchingIndices.forEach((index: number) => {
      if (index !== primaryIndex) {
        toRemove.push(index);
      }
    });
    toRemove.sort((a: number, b: number): number => b - a);
    for (const index of toRemove) {
      this.entries.splice(index, 1);
    }
    this.rebuildMergeIndex();
  }

  private rebuildMergeIndex(): void {
    this.mergeIndex = new SongMergeIndex();
    for (let index = 0; index < this.entries.length; index++) {
      const entry = this.entries[index];
      this.mergeIndex.register(entry.song, index);
      for (const alias of entry.aliases) {
        this.mergeIndex.register(alias, index);
      }
    }
  }
}
