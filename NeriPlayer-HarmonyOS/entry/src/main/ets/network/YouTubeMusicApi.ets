import { Constants } from '../app/Constants';
import { SongItem } from '../model/SongItem';
import { MusicPlatform } from '../model/MusicPlatform';
import { SettingsRepository } from '../data/SettingsRepository';
import { HttpClient } from './HttpClient';
import { YtmStreamResolver } from './ytm/YtmStreamResolver';

interface YtmRun {
  text?: string;
}

interface YtmText {
  runs?: YtmRun[];
}

interface YtmFlexColumn {
  musicResponsiveListItemFlexColumnRenderer?: YtmFlexColumnRenderer;
}

interface YtmFlexColumnRenderer {
  text?: YtmText;
}

interface YtmFixedColumn {
  musicResponsiveListItemFixedColumnRenderer?: YtmFixedColumnRenderer;
}

interface YtmFixedColumnRenderer {
  text?: YtmText;
}

interface YtmPlaylistItemData {
  videoId?: string;
}

interface YtmListItem {
  musicResponsiveListItemRenderer?: YtmListItemRenderer;
}

interface YtmListItemRenderer {
  playlistItemData?: YtmPlaylistItemData;
  flexColumns?: YtmFlexColumn[];
  fixedColumns?: YtmFixedColumn[];
}

interface YtmShelf {
  contents?: YtmListItem[];
}

interface YtmSection {
  musicShelfRenderer?: YtmShelf;
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

interface YtmSearchResponse {
  contents?: YtmSearchContents;
}

interface YtmSearchContents {
  tabbedSearchResultsRenderer?: YtmTabbedSearchResults;
}

interface YtmClient {
  clientName: string;
  clientVersion: string;
  hl: string;
  gl: string;
}

interface YtmContext {
  client: YtmClient;
}

interface YtmSearchRequest {
  context: YtmContext;
  params: string;
  query: string;
}

/**
 * YouTube Music client. Stream resolution uses the M6.1 primary path: the
 * anonymous IOS player client returns direct URLs (D2 decision, no JS
 * runtime); ciphered fallbacks are deferred to M6.2+.
 */
export class YouTubeMusicApi {
  static async search(keyword: string, limit: number = 20): Promise<SongItem[]> {
    const url =
      `${Constants.YTM_BASE}/youtubei/v1/music/search?key=${Constants.YTM_WEB_API_KEY}&prettyPrint=false`;
    const client: YtmClient = {
      clientName: 'WEB_REMIX',
      clientVersion: '1.20250203.00.00',
      hl: 'en',
      gl: 'US'
    };
    const context: YtmContext = { client: client };
    const body: YtmSearchRequest = {
      context: context,
      params: 'EgWKAQIIAWoKEAoQCRADEAA%3D',
      query: keyword
    };
    const text = await HttpClient.postJson(url, JSON.stringify(body));
    const response = JSON.parse(text) as YtmSearchResponse;
    const items: SongItem[] = [];
    const sections = response.contents?.tabbedSearchResultsRenderer?.tabs?.[0]?.tabRenderer?.content?.sectionListRenderer?.contents ?? [];
    for (const section of sections) {
      const rows = section.musicShelfRenderer?.contents ?? [];
      for (const row of rows) {
        const renderer = row.musicResponsiveListItemRenderer;
        if (renderer === undefined) {
          continue;
        }
        const videoId = renderer.playlistItemData?.videoId ?? '';
        if (videoId.length === 0) {
          continue;
        }
        const title = renderer.flexColumns?.[0]?.musicResponsiveListItemFlexColumnRenderer?.text?.runs?.[0]?.text ?? '';
        const metaRuns = renderer.flexColumns?.[1]?.musicResponsiveListItemFlexColumnRenderer?.text?.runs ?? [];
        let artist = '';
        let album = '';
        if (metaRuns.length > 0) {
          artist = metaRuns[0].text ?? '';
        }
        if (metaRuns.length >= 3) {
          album = metaRuns[2].text ?? '';
        }
        const durationText = renderer.fixedColumns?.[0]?.musicResponsiveListItemFixedColumnRenderer?.text?.runs?.[0]?.text ?? '';
        const song = new SongItem(
          0,
          title,
          artist,
          album,
          0,
          YouTubeMusicApi.parseDurationMs(durationText),
          '',
          `${Constants.YOUTUBE_MUSIC_MEDIA_PREFIX}${videoId}`,
          MusicPlatform.YOUTUBE_MUSIC
        );
        song.channelId = Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM;
        song.audioId = videoId;
        items.push(song);
        if (items.length >= limit) {
          break;
        }
      }
      if (items.length >= limit) {
        break;
      }
    }
    return items;
  }

  /** M6.1 primary path: IOS client direct stream (see network/ytm/). */
  static async resolveStream(videoId: string): Promise<string> {
    const quality = SettingsRepository.getString(SettingsRepository.KEY_AUDIO_QUALITY, 'standard');
    return YtmStreamResolver.resolveStreamUrl(videoId, quality);
  }

  private static parseDurationMs(duration: string): number {
    const parts = duration.split(':');
    let total = 0;
    for (let i = 0; i < parts.length; i++) {
      const value = Number(parts[i]);
      if (Number.isNaN(value)) {
        return 0;
      }
      total = total * 60 + value;
    }
    return total * 1000;
  }
}
