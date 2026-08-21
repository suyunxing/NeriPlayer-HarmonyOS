import { Constants } from '../../app/Constants';
import { MusicPlatform } from '../../model/MusicPlatform';
import { SongItem } from '../../model/SongItem';

interface YtmRun {
  text?: string;
}

interface YtmText {
  runs?: YtmRun[];
}

interface YtmFlexColumnRenderer {
  text?: YtmText;
}

interface YtmFlexColumn {
  musicResponsiveListItemFlexColumnRenderer?: YtmFlexColumnRenderer;
}

interface YtmFixedColumnRenderer {
  text?: YtmText;
}

interface YtmFixedColumn {
  musicResponsiveListItemFixedColumnRenderer?: YtmFixedColumnRenderer;
}

interface YtmPlaylistItemData {
  videoId?: string;
}

interface YtmListItemRenderer {
  playlistItemData?: YtmPlaylistItemData;
  flexColumns?: YtmFlexColumn[];
  fixedColumns?: YtmFixedColumn[];
}

interface YtmListItem {
  musicResponsiveListItemRenderer?: YtmListItemRenderer;
}

interface YtmShelf {
  contents?: YtmListItem[];
}

interface YtmSection {
  musicShelfRenderer?: YtmShelf;
  itemSectionRenderer?: YtmShelf;
  musicCardShelfRenderer?: YtmShelf;
}

interface YtmSectionListRenderer {
  contents?: YtmSection[];
}

interface YtmTabContent {
  sectionListRenderer?: YtmSectionListRenderer;
}

interface YtmTabRenderer {
  content?: YtmTabContent;
}

interface YtmTab {
  tabRenderer?: YtmTabRenderer;
}

interface YtmTabbedSearchResults {
  tabs?: YtmTab[];
}

interface YtmSearchContents {
  tabbedSearchResultsRenderer?: YtmTabbedSearchResults;
}

export interface YtmSearchResponseNode {
  contents?: YtmSearchContents;
}

/**
 * Parse both the retired music/search shelf shape and the current generic
 * search shape. The generic endpoint may repeat the best-match card in the
 * item section, so video ids are de-duplicated while preserving response order.
 */
export function parseYtmSearchResponse(text: string, limit: number): SongItem[] {
  if (limit <= 0) {
    return [];
  }
  const response = JSON.parse(text) as YtmSearchResponseNode;
  const sections = response.contents?.tabbedSearchResultsRenderer?.tabs?.[0]
    ?.tabRenderer?.content?.sectionListRenderer?.contents ?? [];
  const items: SongItem[] = [];
  const seenVideoIds = new Set<string>();
  for (const section of sections) {
    const rows: YtmListItem[] = [];
    rows.push(
      ...(section.musicShelfRenderer?.contents ?? []),
      ...(section.itemSectionRenderer?.contents ?? []),
      ...(section.musicCardShelfRenderer?.contents ?? [])
    );
    for (const row of rows) {
      const renderer = row.musicResponsiveListItemRenderer;
      if (renderer === undefined) {
        continue;
      }
      const videoId = renderer.playlistItemData?.videoId ?? '';
      if (videoId.length === 0 || seenVideoIds.has(videoId)) {
        continue;
      }
      const title = renderer.flexColumns?.[0]
        ?.musicResponsiveListItemFlexColumnRenderer?.text?.runs?.[0]?.text ?? '';
      const metaRuns = renderer.flexColumns?.[1]
        ?.musicResponsiveListItemFlexColumnRenderer?.text?.runs ?? [];
      let durationText = renderer.fixedColumns?.[0]
        ?.musicResponsiveListItemFixedColumnRenderer?.text?.runs?.[0]?.text ?? '';
      if (durationText.length === 0) {
        durationText = pickDurationFromMeta(metaRuns);
      }
      const song = new SongItem(
        0,
        title,
        pickArtist(metaRuns),
        '',
        0,
        parseYtmDurationMs(durationText),
        '',
        `${Constants.YOUTUBE_MUSIC_MEDIA_PREFIX}${videoId}`,
        MusicPlatform.YOUTUBE_MUSIC
      );
      song.channelId = Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM;
      song.audioId = videoId;
      items.push(song);
      seenVideoIds.add(videoId);
      if (items.length >= limit) {
        return items;
      }
    }
  }
  return items;
}

/**
 * Item rows use ['Song', 'bullet', 'Artist']; card rows commonly use
 * ['Artist', 'bullet', 'view count', 'bullet', 'duration'].
 */
function pickArtist(metaRuns: YtmRun[]): string {
  const segments: string[] = [];
  for (const run of metaRuns) {
    const text = (run.text ?? '').trim();
    if (text.length > 0 && text !== 'bullet' && text !== '•' && text !== '·') {
      segments.push(text);
    }
  }
  if (segments.length === 0) {
    return '';
  }
  const first = segments[0];
  if (first === 'Song' || first === 'Video' || first === 'Single' || first === 'Album') {
    return segments.length > 1 ? segments[1] : '';
  }
  return first;
}

function pickDurationFromMeta(metaRuns: YtmRun[]): string {
  for (let i = metaRuns.length - 1; i >= 0; i--) {
    const text = (metaRuns[i].text ?? '').trim();
    if (text.match(/^\d{1,3}(:\d{2})+$/) !== null) {
      return text;
    }
  }
  return '';
}

export function parseYtmDurationMs(duration: string): number {
  const parts = duration.split(':');
  let total = 0;
  for (const part of parts) {
    const value = Number(part);
    if (!Number.isInteger(value) || value < 0) {
      return 0;
    }
    total = total * 60 + value;
  }
  return total * 1000;
}
