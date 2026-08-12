import { Constants } from '../app/Constants';
import { SongItem } from '../model/SongItem';
import { MusicPlatform } from '../model/MusicPlatform';
import { HttpClient } from './HttpClient';

interface BiliSearchItem {
  bvid: string;
  title: string;
  author: string;
  pic: string;
  duration: string;
}

interface BiliSearchResponse {
  code: number;
  data?: BiliSearchData;
}

interface BiliSearchData {
  result?: BiliSearchItem[];
}

interface BiliDashAudio {
  bandwidth: number;
  baseUrl?: string;
  backupUrl?: string[];
}

interface BiliPlayUrlResponse {
  code: number;
  data?: BiliPlayData;
}

interface BiliPlayData {
  dash?: BiliDash;
}

interface BiliDash {
  audio?: BiliDashAudio[];
}

/**
 * Bilibili client (video search + audio stream resolution), following the
 * bilibili-API-collect conventions used by the Android app.
 */
export class BiliApi {
  private static biliHeaders(): Record<string, string> {
    const headers: Record<string, string> = {};
    headers['Referer'] = 'https://www.bilibili.com';
    return headers;
  }

  static async search(keyword: string, limit: number = 20): Promise<SongItem[]> {
    const url =
      `${Constants.BILI_BASE}/x/web-interface/search/type?search_type=video&keyword=${encodeURIComponent(keyword)}`;
    const text = await HttpClient.getText(url, BiliApi.biliHeaders());
    const response = JSON.parse(text) as BiliSearchResponse;
    const results = response.data?.result ?? [];
    const items: SongItem[] = [];
    for (const item of results.slice(0, limit)) {
      const song = new SongItem(
        0,
        BiliApi.stripHtml(item.title),
        item.author,
        'Bilibili',
        0,
        BiliApi.parseDurationMs(item.duration),
        item.pic.startsWith('http://') ? `https://${item.pic.substring(7)}` : item.pic,
        '',
        MusicPlatform.BILIBILI
      );
      song.channelId = 'bilibili';
      song.audioId = item.bvid;
      items.push(song);
    }
    return items;
  }

  /**
   * Resolves the best DASH audio stream for a bvid.
   */
  static async resolveAudioUrl(bvid: string): Promise<string> {
    const url =
      `${Constants.BILI_BASE}/x/player/playurl?bvid=${bvid}&fnval=16&fourk=1`;
    const text = await HttpClient.getText(url, BiliApi.biliHeaders());
    const response = JSON.parse(text) as BiliPlayUrlResponse;
    const audioList = response.data?.dash?.audio ?? [];
    if (audioList.length === 0) {
      return '';
    }
    let best = audioList[0];
    for (const audio of audioList) {
      if (audio.bandwidth > best.bandwidth) {
        best = audio;
      }
    }
    let stream = best.baseUrl ?? '';
    if (stream.length === 0 && best.backupUrl !== undefined && best.backupUrl.length > 0) {
      stream = best.backupUrl[0];
    }
    if (stream.startsWith('http://')) {
      stream = `https://${stream.substring(7)}`;
    }
    return stream;
  }

  private static stripHtml(text: string): string {
    return text.replace(/<[^>]+>/g, '').replace(/&amp;/g, '&').trim();
  }

  private static parseDurationMs(duration: string): number {
    const parts = duration.split(':');
    if (parts.length !== 2) {
      return 0;
    }
    const minutes = Number(parts[0]);
    const seconds = Number(parts[1]);
    if (Number.isNaN(minutes) || Number.isNaN(seconds)) {
      return 0;
    }
    return (minutes * 60 + seconds) * 1000;
  }
}
