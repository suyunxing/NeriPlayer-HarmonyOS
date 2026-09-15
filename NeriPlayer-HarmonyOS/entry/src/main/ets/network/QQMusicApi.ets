// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { Logger } from '../app/Logger';
import { HttpClient } from './HttpClient';
import { decodeQQMusicLyricPayload, stripUntranslatedPlaceholderLines } from './QQMusicLyricCodec';

/*
 * QQ Music read-only client (search / song detail / lyrics), ported from
 * Android QQMusicSearchApi.kt. QQ is a metadata source only — songs are never
 * streamed from it — so this lives beside (not inside) MusicPlatform.
 *
 * Failure contract mirrors NeteaseApi: log + empty result, never throw to UI.
 */

interface QQMusicSearchResponse {
  data?: QQMusicSearchData;
}

interface QQMusicSearchData {
  song?: QQMusicSearchSong;
}

interface QQMusicSearchSong {
  list?: QQMusicSongSummary[];
}

interface QQMusicSongSummary {
  songmid?: string;
  songname?: string;
  singer?: QQMusicArtist[];
  albummid?: string;
  albumname?: string;
  interval?: number;
}

interface QQMusicArtist {
  name?: string;
}

interface QQMusicDetailEnvelope {
  songinfo?: QQMusicDetailResponse;
}

interface QQMusicDetailResponse {
  data?: QQMusicDetailData;
}

interface QQMusicDetailData {
  track_info?: QQMusicTrackInfo;
}

interface QQMusicTrackInfo {
  mid?: string;
  name?: string;
  singer?: QQMusicArtist[];
  album?: QQMusicAlbum;
  interval?: number;
}

interface QQMusicAlbum {
  name?: string;
  mid?: string;
}

interface QQMusicLyricContainer {
  req?: QQMusicLyricEnvelope;
}

interface QQMusicLyricEnvelope {
  code?: number;
  data?: QQMusicLyricResponse;
}

/** The lyric response may omit lyric/trans entirely when a song has none. */
interface QQMusicLyricResponse {
  lyric?: string;
  trans?: string;
}

/** Search result row (no lyrics — those come with the detail). */
export class QQMusicSong {
  songMid: string = '';
  name: string = '';
  artist: string = '';
  albumName: string = '';
  coverUrl: string = '';
  durationMs: number = 0;
}

/** Detail of a matched song: metadata plus decoded lyrics. */
export class QQMusicSongDetail {
  songMid: string = '';
  name: string = '';
  artist: string = '';
  albumName: string = '';
  coverUrl: string = '';
  lyric: string = '';
  translatedLyric: string = '';
}

export class QQMusicLyricPair {
  lyric: string = '';
  translatedLyric: string = '';
}

function qqCoverUrl(albumMid: string): string {
  return albumMid.length > 0 ? `https://y.qq.com/music/photo_new/T002R800x800M000${albumMid}.jpg` : '';
}

/** Escapes a value for embedding inside a JSON string literal we assemble by hand. */
function jsonEscape(value: string): string {
  return value.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

function joinArtistNames(singers: QQMusicArtist[] | undefined): string {
  if (singers === undefined) {
    return '';
  }
  const names: string[] = [];
  for (const singer of singers) {
    if (singer.name !== undefined && singer.name.length > 0) {
      names.push(singer.name);
    }
  }
  return names.join('/');
}

export class QQMusicApi {
  static async search(keyword: string, page: number = 1): Promise<QQMusicSong[]> {
    try {
      const url = 'https://c.y.qq.com/soso/fcgi-bin/client_search_cp'
        + `?format=json&n=20&p=${page}&w=${encodeURIComponent(keyword)}&cr=1&g_tk=5381`;
      const text = await HttpClient.getText(url);
      const response = JSON.parse(text) as QQMusicSearchResponse;
      const list = response.data?.song?.list ?? [];
      const songs: QQMusicSong[] = [];
      for (const song of list) {
        const item = new QQMusicSong();
        item.songMid = song.songmid ?? '';
        item.name = song.songname ?? '';
        item.artist = joinArtistNames(song.singer);
        item.albumName = song.albumname ?? '';
        item.coverUrl = qqCoverUrl(song.albummid ?? '');
        item.durationMs = (song.interval ?? 0) * 1000;
        if (item.songMid.length > 0) {
          songs.push(item);
        }
      }
      return songs;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`QQMusicApi.search failed: ${e.message}`);
      return [];
    }
  }

  /**
   * Song detail + lyrics for a songMid, mirroring Android getSongInfo: the
   * lyric fetch failing never blocks the metadata (it just comes back empty).
   */
  static async getSongInfo(songMid: string): Promise<QQMusicSongDetail | null> {
    try {
      const dataParam = `{"songinfo":{"method":"get_song_detail_yqq","module":"music.pf_song_detail_svr"`
        + `,"param":{"song_mid":"${jsonEscape(songMid)}"}}}`;
      const url = `https://u.y.qq.com/cgi-bin/musicu.fcg?data=${encodeURIComponent(dataParam)}`;
      const text = await HttpClient.getText(url);
      const envelope = JSON.parse(text) as QQMusicDetailEnvelope;
      const trackInfo = envelope.songinfo?.data?.track_info;
      if (trackInfo === undefined || (trackInfo.mid ?? '').length === 0) {
        Logger.warn(`QQMusicApi.getSongInfo: no track_info for ${songMid}`);
        return null;
      }
      const detail = new QQMusicSongDetail();
      detail.songMid = trackInfo.mid ?? '';
      detail.name = trackInfo.name ?? '';
      detail.artist = joinArtistNames(trackInfo.singer);
      detail.albumName = trackInfo.album?.name ?? '';
      detail.coverUrl = qqCoverUrl(trackInfo.album?.mid ?? '');
      const lyric = await QQMusicApi.fetchLyric(songMid);
      detail.lyric = lyric.lyric;
      detail.translatedLyric = lyric.translatedLyric;
      return detail;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`QQMusicApi.getSongInfo failed: ${e.message}`);
      return null;
    }
  }

  /** GetPlayLyricInfo; the Referer header is mandatory or the API rejects. */
  static async fetchLyric(songMid: string): Promise<QQMusicLyricPair> {
    const pair = new QQMusicLyricPair();
    try {
      const dataParam = `{"req":{"method":"GetPlayLyricInfo","module":"music.musichallSong.PlayLyricInfo"`
        + `,"param":{"songMID":"${jsonEscape(songMid)}","trans":1,"qrc":0,"crypt":0}}}`;
      const url = `https://u.y.qq.com/cgi-bin/musicu.fcg?format=json&data=${encodeURIComponent(dataParam)}`;
      const text = await HttpClient.getText(url, { 'Referer': 'https://y.qq.com' });
      const envelope = JSON.parse(text) as QQMusicLyricContainer;
      const req = envelope.req;
      if (req === undefined || req.code !== 0) {
        const code = req === undefined ? 'none' : `${req.code}`;
        Logger.warn(`QQMusicApi lyric rejected: songMid=${songMid} code=${code}`);
        return pair;
      }
      pair.lyric = decodeQQMusicLyricPayload(req.data?.lyric ?? '');
      pair.translatedLyric = stripUntranslatedPlaceholderLines(
        decodeQQMusicLyricPayload(req.data?.trans ?? '')
      );
      return pair;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`QQMusicApi.fetchLyric failed: ${e.message}`);
      return pair;
    }
  }
}
