// SPDX-License-Identifier: GPL-3.0
// HarmonyOS Form Kit playback card (upstream reference: Android playback
// widgets, commit 86ad5f82 / #472 — features only; the Form Kit port is an
// independent design). Pure snapshot/payload/param helpers shared by the app
// process bridge, the FormExtensionAbility and unit tests.

import { SongItem } from '../model/SongItem';
import { PlaybackStatus } from '../player/PlaybackConstants';

/** 卡片展示快照：字段全部为字符串（FormBindingData 序列化后即 string）。 */
export class PlaybackCardSnapshot {
  title: string = '';
  artist: string = '';
  playing: string = 'false';
  hasSong: string = 'false';
  coverUrl: string = '';

  static fromSong(song: SongItem | null, status: PlaybackStatus): PlaybackCardSnapshot {
    const snapshot = new PlaybackCardSnapshot();
    if (song !== null) {
      snapshot.hasSong = 'true';
      snapshot.title = song.displayName;
      snapshot.artist = song.displayArtist;
      snapshot.coverUrl = song.effectiveCoverUrl;
    }
    snapshot.playing = status === PlaybackStatus.PLAYING ? 'true' : 'false';
    return snapshot;
  }

  /** 持久化形态（AppPreferences 跨进程交给 FormExtensionAbility 的 JSON）。 */
  toJson(): string {
    return JSON.stringify(this as Object);
  }

  static fromJson(raw: string): PlaybackCardSnapshot | null {
    try {
      const values = JSON.parse(raw) as Record<string, Object>;
      const snapshot = new PlaybackCardSnapshot();
      snapshot.title = String(values['title'] ?? '');
      snapshot.artist = String(values['artist'] ?? '');
      snapshot.playing = String(values['playing'] ?? 'false');
      snapshot.hasSong = String(values['hasSong'] ?? 'false');
      snapshot.coverUrl = String(values['coverUrl'] ?? '');
      return snapshot;
    } catch (_error) {
      return null;
    }
  }
}

/**
 * 卡片推送 payload：卡片页以 @LocalStorageProp 同名键接收（值全部转
 * string；封面经 formImages 的 memory://key 显示，这里只带 key）。
 */
export function buildPlaybackCardPayload(
  snapshot: PlaybackCardSnapshot,
  coverImageKey: string
): Record<string, Object> {
  const payload: Record<string, Object> = {};
  payload.title = snapshot.hasSong === 'true' ? snapshot.title : '未在播放';
  payload.artist = snapshot.artist;
  payload.playing = snapshot.playing;
  payload.hasSong = snapshot.hasSong;
  payload.coverKey = coverImageKey;
  payload.hasCover = coverImageKey.length > 0 ? 'true' : 'false';
  return payload;
}

/**
 * formImages 的 key 每次刷新必须不同（相同 key 不刷新）；以单调计数
 * 换代保证唯一。
 */
export function nextCoverImageKey(generation: number): string {
  return `cover${generation}`;
}

/** call 事件参数（卡片 postCardAction params 经 JSON 到达）。 */
export interface PlaybackCardControlParams {
  action?: string;
  formId?: string;
}

/** call 事件参数解析：{action: 'toggle'|'prev'|'next', formId}；非法返回 ''。 */
export function parsePlaybackCardControlAction(params: PlaybackCardControlParams): string {
  const action = params.action ?? '';
  if (action === 'toggle' || action === 'prev' || action === 'next') {
    return action;
  }
  return '';
}
