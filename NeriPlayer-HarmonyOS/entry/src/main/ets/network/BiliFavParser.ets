import { SongItem } from '../model/SongItem';
import { MusicPlatform } from '../model/MusicPlatform';

/**
 * Pure parsers for the Bilibili favorite-folder endpoints, following the
 * field shapes read by Android BiliClient (parseFavFolder + fav/resource/list
 * mapping). No platform imports: unit-testable in the local hypium
 * environment. Business codes are NOT treated as errors here (Android getJson
 * parses the body blindly); callers see empty results instead.
 */

export class BiliFavFolderSummary {
  mediaId: number = 0;
  fid: number = 0;
  mid: number = 0;
  title: string = '';
  coverUrl: string = '';
  mediaCount: number = 0;
}

export class BiliFavMedia {
  type: number = 0;
  id: number = 0;
  bvid: string = '';
  title: string = '';
  coverUrl: string = '';
  intro: string = '';
  durationSec: number = 0;
  upperMid: number = 0;
  upperName: string = '';
}

export class BiliFavFolderListResult {
  folders: BiliFavFolderSummary[] = [];
  totalCount: number = 0;
}

export class BiliFavPage {
  info: BiliFavFolderSummary | null = null;
  items: BiliFavMedia[] = [];
  hasMore: boolean = false;
  totalCount: number = 0;
}

/** Upgrades http:// and protocol-relative covers to https (Android ensureHttps). */
export function ensureBiliHttps(url: string): string {
  if (url.startsWith('//')) {
    return `https:${url}`;
  }
  if (url.startsWith('http://')) {
    return `https://${url.substring(7)}`;
  }
  return url;
}

function numberOf(value: Object | undefined): number {
  return value === undefined || value === null || Number.isNaN(Number(value)) ? 0 : Number(value);
}

function textOf(value: Object | undefined): string {
  return value === undefined || value === null ? '' : String(value);
}

/** Parses one fav-folder entry (list-all/list/info shapes share the fields). */
function parseFolderSummary(raw: Record<string, Object>): BiliFavFolderSummary {
  const out = new BiliFavFolderSummary();
  out.mediaId = numberOf(raw['id']);
  out.fid = numberOf(raw['fid']);
  out.mid = numberOf(raw['mid']);
  out.title = textOf(raw['title']);
  if (out.title.length === 0) {
    out.title = textOf(raw['name']);
  }
  out.coverUrl = ensureBiliHttps(textOf(raw['cover']));
  const mediaCount = raw['media_count'];
  out.mediaCount = mediaCount !== undefined && mediaCount !== null
    ? numberOf(mediaCount)
    : numberOf(raw['total']);
  return out;
}

/**
 * Parses /x/v3/fav/folder/created/list-all (and created/list pages): entries
 * with mediaId 0 or blank titles are dropped (Android mergeFavFolders).
 */
export function parseBiliFavFolderList(json: string): BiliFavFolderListResult {
  const result = new BiliFavFolderListResult();
  try {
    const root = JSON.parse(json) as Record<string, Object>;
    const dataRaw = root['data'];
    if (dataRaw === undefined || dataRaw === null) {
      return result;
    }
    const data = dataRaw as Record<string, Object>;
    result.totalCount = numberOf(data['count']);
    const listRaw = data['list'];
    if (listRaw === undefined || listRaw === null) {
      return result;
    }
    const list = listRaw as Object[];
    const seen = new Set<number>();
    for (const entryRaw of list) {
      if (entryRaw === undefined || entryRaw === null) {
        continue;
      }
      const folder = parseFolderSummary(entryRaw as Record<string, Object>);
      if (folder.mediaId === 0 || folder.title.length === 0 || seen.has(folder.mediaId)) {
        continue;
      }
      seen.add(folder.mediaId);
      result.folders.push(folder);
    }
  } catch (error) {
    // Malformed body degrades to an empty list (Android never throws here).
  }
  return result;
}

/** Parses /x/v3/fav/resource/list: folder info + media page + has_more. */
export function parseBiliFavResourcePage(json: string): BiliFavPage {
  const page = new BiliFavPage();
  try {
    const root = JSON.parse(json) as Record<string, Object>;
    const dataRaw = root['data'];
    if (dataRaw === undefined || dataRaw === null) {
      return page;
    }
    const data = dataRaw as Record<string, Object>;
    const infoRaw = data['info'];
    if (infoRaw !== undefined && infoRaw !== null) {
      const info = parseFolderSummary(infoRaw as Record<string, Object>);
      if (info.mediaId !== 0) {
        page.info = info;
        page.totalCount = info.mediaCount;
      }
    }
    if (page.info === null) {
      page.totalCount = numberOf(data['count']);
    }
    const hasMore = data['has_more'];
    page.hasMore = hasMore !== undefined && hasMore !== null && Boolean(hasMore);
    const mediasRaw = data['medias'];
    if (mediasRaw === undefined || mediasRaw === null) {
      return page;
    }
    const medias = mediasRaw as Object[];
    for (const mediaRaw of medias) {
      if (mediaRaw === undefined || mediaRaw === null) {
        continue;
      }
      const media = mediaRaw as Record<string, Object>;
      const item = new BiliFavMedia();
      item.type = numberOf(media['type']);
      item.id = numberOf(media['id']);
      item.bvid = textOf(media['bvid']);
      if (item.bvid.length === 0) {
        item.bvid = textOf(media['bv_id']);
      }
      item.title = stripBiliEm(textOf(media['title']));
      item.coverUrl = ensureBiliHttps(textOf(media['cover']));
      item.intro = textOf(media['intro']);
      item.durationSec = numberOf(media['duration']);
      const upperRaw = media['upper'];
      if (upperRaw !== undefined && upperRaw !== null) {
        const upper = upperRaw as Record<string, Object>;
        item.upperMid = numberOf(upper['mid']);
        item.upperName = textOf(upper['name']);
      }
      if (item.bvid.length > 0 && item.title.length > 0) {
        page.items.push(item);
      }
    }
  } catch (error) {
    // Malformed body degrades to an empty page.
  }
  return page;
}

/** Search titles carry <em class="keyword"> highlights; folder titles may too. */
export function stripBiliEm(text: string): string {
  return text.replace(/<[^>]+>/g, '').replace(/&amp;/g, '&').trim();
}

/** Maps a fav-folder media entry to the app SongItem model (audioId = bvid). */
export function biliFavMediaToSongItem(media: BiliFavMedia): SongItem {
  const song = new SongItem(
    media.id,
    media.title,
    media.upperName.length > 0 ? media.upperName : 'Bilibili',
    'Bilibili',
    0,
    media.durationSec * 1000,
    media.coverUrl,
    '',
    MusicPlatform.BILIBILI
  );
  song.channelId = 'bilibili';
  song.audioId = media.bvid;
  return song;
}

/** Dedup key used by the Android full-fetch loop ("type:id:bvid"). */
export function biliFavMediaDedupKey(media: BiliFavMedia): string {
  return `${media.type}:${media.id}:${media.bvid}`;
}
