// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer),
// commit bf50094e (util/search/SongSearchValues). Field biases follow the
// upstream TITLE/ARTIST/ALBUM/ORIGINAL/FILE/IDENTIFIER ladder so that title
// hits outrank artist hits outrank album hits, etc.

import { SongItem } from '../../model/SongItem';
import { NO_SEARCH_MATCH, SearchTextMatcher, SearchValue } from './SearchTextMatcher';

const TITLE_BIAS: number = 0;
const TITLE_VARIANT_BIAS: number = 4;
const ARTIST_BIAS: number = 24;
const ARTIST_VARIANT_BIAS: number = 28;
const ALBUM_BIAS: number = 40;
const ALBUM_VARIANT_BIAS: number = 44;
const ORIGINAL_TITLE_BIAS: number = 52;
const ORIGINAL_ARTIST_BIAS: number = 56;
const FILE_NAME_BIAS: number = 64;
const FILE_PATH_BIAS: number = 72;
const IDENTIFIER_BIAS: number = 84;

function value(text: string, bias: number): SearchValue {
  return SearchTextMatcher.value(text, bias);
}

/** 上游 SongItem.searchValues() 的鸿蒙字段子集（无 neteaseArtists 列表字段）。 */
export function songSearchValues(song: SongItem): SearchValue[] {
  const values: SearchValue[] = [];
  values.push(value(song.displayName, TITLE_BIAS));
  values.push(value(song.name, TITLE_VARIANT_BIAS));
  values.push(value(song.customName, TITLE_VARIANT_BIAS));
  values.push(value(song.displayArtist, ARTIST_BIAS));
  values.push(value(song.artist, ARTIST_VARIANT_BIAS));
  values.push(value(song.customArtist, ARTIST_VARIANT_BIAS));
  values.push(value(song.album, ALBUM_BIAS));
  values.push(value(song.originalName, ORIGINAL_TITLE_BIAS));
  values.push(value(song.originalArtist, ORIGINAL_ARTIST_BIAS));
  values.push(value(song.localFileName, FILE_NAME_BIAS));
  values.push(value(song.localFilePath, FILE_PATH_BIAS));
  values.push(value(song.channelId, IDENTIFIER_BIAS));
  values.push(value(song.audioId, IDENTIFIER_BIAS));
  values.push(value(song.subAudioId, IDENTIFIER_BIAS));
  return values;
}

class RankedSongSearchResult {
  readonly song: SongItem;
  readonly index: number;
  readonly score: number;

  constructor(song: SongItem, index: number, score: number) {
    this.song = song;
    this.index = index;
    this.score = score;
  }
}

/**
 * 上游 rankExploreSongSearchResults：按用户查询重排搜索结果——匹配项按
 * 分数升序在前，未匹配项保序垫底；无任何匹配或单曲时原样返回。
 */
export function rankExploreSongSearchResults(query: string, songs: SongItem[]): SongItem[] {
  const normalizedQuery = query.trim();
  if (normalizedQuery.length === 0 || songs.length <= 1) {
    return songs;
  }
  const scored: RankedSongSearchResult[] = [];
  const unscored: SongItem[] = [];
  for (let index = 0; index < songs.length; index++) {
    const score = SearchTextMatcher.score(normalizedQuery, songSearchValues(songs[index]));
    if (score === NO_SEARCH_MATCH) {
      unscored.push(songs[index]);
    } else {
      scored.push(new RankedSongSearchResult(songs[index], index, score));
    }
  }
  if (scored.length === 0) {
    return songs;
  }
  scored.sort((a: RankedSongSearchResult, b: RankedSongSearchResult): number => {
    if (a.score !== b.score) {
      return a.score - b.score;
    }
    return a.index - b.index;
  });
  const out: SongItem[] = [];
  for (const entry of scored) {
    out.push(entry.song);
  }
  for (const song of unscored) {
    out.push(song);
  }
  return out;
}

function songMergeKey(song: SongItem): string {
  return `${song.platform}_${song.audioId.length > 0 ? song.audioId : song.mediaUri}`;
}

/** 上游 mergeExploreSearchResults 的歌曲形态：按 platform+audioId 去重保序合并。 */
export function mergeSongItemsDeduped(existing: SongItem[], incoming: SongItem[]): SongItem[] {
  const seen = new Set<string>();
  for (const song of existing) {
    seen.add(songMergeKey(song));
  }
  const out: SongItem[] = [...existing];
  for (const song of incoming) {
    const key = songMergeKey(song);
    if (!seen.has(key)) {
      seen.add(key);
      out.push(song);
    }
  }
  return out;
}
