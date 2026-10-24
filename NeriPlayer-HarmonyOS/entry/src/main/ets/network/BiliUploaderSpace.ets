// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer),
// commits e95b2ef9 (uploader profiles / series / collection archives) and
// 507c22d7 (archive uploader write-back).

import { SongItem } from '../model/SongItem';
import { MusicPlatform } from '../model/MusicPlatform';

/**
 * Pure parsers for the Bilibili uploader-space endpoints (Android
 * parseBiliUploader* top-level functions): x/space/wbi/acc/info,
 * x/space/wbi/arc/search, x/polymer/web-space/seasons_series_list,
 * x/series/archives and seasons_archives_list. Callers hand in the already
 * unwrapped `data` object (Android requireSuccessfulData), so tests can feed
 * bare payloads without the {code,message,data} envelope.
 */

export class BiliUploaderProfile {
  mid: number = 0;
  name: string = '';
  faceUrl: string = '';
  sign: string = '';
  topPhotoUrl: string = '';
}

export class BiliUploaderVideo {
  aid: number = 0;
  bvid: string = '';
  title: string = '';
  coverUrl: string = '';
  durationSec: number = 0;
  uploaderMid: number = 0;
  uploaderName: string = '';
  play: number = -1;
  pubdate: number = -1;
}

export class BiliUploaderVideoPage {
  page: number = 1;
  pageSize: number = 30;
  total: number = 0;
  items: BiliUploaderVideo[] = [];
  hasMore: boolean = false;
}

export enum BiliUploaderContentKind {
  COLLECTION = 'collection',
  SERIES = 'series'
}

export class BiliUploaderContent {
  id: number = 0;
  mid: number = 0;
  kind: BiliUploaderContentKind = BiliUploaderContentKind.COLLECTION;
  title: string = '';
  coverUrl: string = '';
  description: string = '';
  total: number = 0;
}

export class BiliUploaderContentPage {
  page: number = 1;
  pageSize: number = 20;
  collections: BiliUploaderContent[] = [];
  series: BiliUploaderContent[] = [];
  hasMore: boolean = false;
}

export class BiliCollectionMeta {
  seasonId: number = 0;
  mid: number = 0;
  title: string = '';
  coverUrl: string = '';
  description: string = '';
  total: number = 0;
}

export class BiliCollectionArchiveItem {
  aid: number = 0;
  bvid: string = '';
  title: string = '';
  coverUrl: string = '';
  durationSec: number = 0;
  pubdate: number = -1;
  play: number = -1;
}

export class BiliCollectionArchivePage {
  meta: BiliCollectionMeta = new BiliCollectionMeta();
  items: BiliCollectionArchiveItem[] = [];
  hasMore: boolean = false;
}

export class BiliSeriesArchivePage {
  items: BiliCollectionArchiveItem[] = [];
  total: number = 0;
  hasMore: boolean = false;
}

function numberOf(value: Object | undefined): number {
  return value === undefined || value === null || Number.isNaN(Number(value)) ? 0 : Number(value);
}

function textOf(value: Object | undefined): string {
  return value === undefined || value === null ? '' : String(value);
}

function optionalNumberOf(value: Object | undefined): number {
  return value === undefined || value === null ? -1 : Number(value);
}

function recordOf(value: Object | undefined | null): Record<string, Object> | null {
  if (value === undefined || value === null) {
    return null;
  }
  return value as Record<string, Object>;
}

/** Upstream normalizeBiliImageUrl: upgrades // and http:// images to https. */
export function normalizeBiliImageUrl(url: string): string {
  const value = url.trim();
  if (value.startsWith('//')) {
    return `https:${value}`;
  }
  if (value.startsWith('http://')) {
    return `https://${value.substring(7)}`;
  }
  return value;
}

function stripBiliSpaceHtml(value: string): string {
  return value.replace(/<[^>]+>/g, '');
}

/** Upstream parseBiliSpaceDurationSeconds: "h:mm:ss" / "mm:ss" -> seconds. */
export function parseBiliSpaceDurationSeconds(value: string): number {
  if (value.trim().length === 0) {
    return 0;
  }
  let duration = 0;
  for (const part of value.split(':')) {
    const seconds = Number(part);
    if (!Number.isFinite(seconds)) {
      return 0;
    }
    duration = duration * 60 + Math.floor(seconds);
  }
  return duration;
}

/** Upstream parseBiliUploaderProfile: mid falls back to the requested mid. */
export function parseBiliUploaderProfile(
  data: Record<string, Object>,
  fallbackMid: number
): BiliUploaderProfile {
  const profile = new BiliUploaderProfile();
  const mid = numberOf(data['mid']);
  profile.mid = mid > 0 ? mid : fallbackMid;
  profile.name = textOf(data['name']);
  profile.faceUrl = normalizeBiliImageUrl(textOf(data['face']));
  profile.sign = textOf(data['sign']);
  profile.topPhotoUrl = normalizeBiliImageUrl(textOf(data['top_photo']));
  return profile;
}

/** Upstream parseBiliUploaderVideoPage (x/space/wbi/arc/search data shape). */
export function parseBiliUploaderVideoPage(
  data: Record<string, Object>,
  requestedPage: number,
  requestedPageSize: number,
  fallbackMid: number
): BiliUploaderVideoPage {
  const out = new BiliUploaderVideoPage();
  const list = recordOf(data['list']);
  const vlistRaw = list === null ? undefined : list['vlist'];
  if (vlistRaw !== undefined && vlistRaw !== null) {
    const vlist = vlistRaw as Object[];
    for (const entryRaw of vlist) {
      const video = recordOf(entryRaw);
      if (video === null) {
        continue;
      }
      const aid = numberOf(video['aid']);
      const bvid = textOf(video['bvid']);
      const title = stripBiliSpaceHtml(textOf(video['title']));
      if (aid <= 0 || bvid.length === 0 || title.length === 0) {
        continue;
      }
      const item = new BiliUploaderVideo();
      item.aid = aid;
      item.bvid = bvid;
      item.title = title;
      item.coverUrl = normalizeBiliImageUrl(textOf(video['pic']));
      item.durationSec = parseBiliSpaceDurationSeconds(textOf(video['length']));
      const mid = numberOf(video['mid']);
      item.uploaderMid = mid > 0 ? mid : fallbackMid;
      item.uploaderName = textOf(video['author']);
      item.play = optionalNumberOf(video['play']);
      item.pubdate = optionalNumberOf(video['created']);
      out.items.push(item);
    }
  }
  const page = recordOf(data['page']);
  const pn = page === null ? requestedPage : numberOf(page['pn']);
  const ps = page === null ? requestedPageSize : numberOf(page['ps']);
  out.page = Math.max(1, pn > 0 ? pn : requestedPage);
  out.pageSize = Math.max(1, ps > 0 ? ps : requestedPageSize);
  const countRaw = page === null ? undefined : page['count'];
  const count = countRaw === undefined || countRaw === null ? out.items.length : numberOf(countRaw);
  out.total = Math.max(count, out.items.length);
  out.hasMore = out.page * out.pageSize < out.total;
  return out;
}

function parseBiliUploaderContents(
  items: Object[] | null,
  kind: BiliUploaderContentKind,
  fallbackMid: number
): BiliUploaderContent[] {
  const contents: BiliUploaderContent[] = [];
  if (items === null) {
    return contents;
  }
  const seen = new Set<number>();
  for (const entryRaw of items) {
    const entry = recordOf(entryRaw);
    if (entry === null) {
      continue;
    }
    const meta = recordOf(entry['meta']) ?? entry;
    const id = numberOf(kind === BiliUploaderContentKind.COLLECTION
      ? meta['season_id'] : meta['series_id']);
    let title = textOf(meta['name']);
    if (title.length === 0) {
      title = textOf(meta['title']);
    }
    if (id <= 0 || title.length === 0 || seen.has(id)) {
      continue;
    }
    seen.add(id);
    const content = new BiliUploaderContent();
    content.id = id;
    const mid = numberOf(meta['mid']);
    content.mid = mid > 0 ? mid : fallbackMid;
    content.kind = kind;
    content.title = title;
    content.coverUrl = normalizeBiliImageUrl(textOf(meta['cover']));
    content.description = textOf(meta['description']);
    content.total = numberOf(meta['total']);
    contents.push(content);
  }
  return contents;
}

/**
 * Upstream parseBiliUploaderContentPage
 * (x/polymer/web-space/seasons_series_list data shape): collections and
 * series stay separate lists.
 */
export function parseBiliUploaderContentPage(
  data: Record<string, Object>,
  requestedPage: number,
  requestedPageSize: number,
  fallbackMid: number
): BiliUploaderContentPage {
  const out = new BiliUploaderContentPage();
  const itemLists = recordOf(data['items_lists']) ?? {} as Record<string, Object>;
  const page = recordOf(itemLists['page']);
  const pageNum = page === null ? requestedPage : numberOf(page['page_num']);
  const pageSize = page === null ? requestedPageSize : numberOf(page['page_size']);
  out.page = Math.max(1, pageNum > 0 ? pageNum : requestedPage);
  out.pageSize = Math.max(1, pageSize > 0 ? pageSize : requestedPageSize);
  out.collections = parseBiliUploaderContents(
    itemLists['seasons_list'] === undefined || itemLists['seasons_list'] === null
      ? null : itemLists['seasons_list'] as Object[],
    BiliUploaderContentKind.COLLECTION,
    fallbackMid
  );
  out.series = parseBiliUploaderContents(
    itemLists['series_list'] === undefined || itemLists['series_list'] === null
      ? null : itemLists['series_list'] as Object[],
    BiliUploaderContentKind.SERIES,
    fallbackMid
  );
  const totalRaw = page === null ? undefined : page['total'];
  const total = totalRaw === undefined || totalRaw === null
    ? out.collections.length + out.series.length : numberOf(totalRaw);
  out.hasMore = total > out.page * out.pageSize;
  return out;
}

/** Upstream parseBiliSpaceArchiveItem: shared by series and collection lists. */
function parseBiliSpaceArchiveItem(item: Record<string, Object>): BiliCollectionArchiveItem | null {
  const aid = numberOf(item['aid']);
  const bvid = textOf(item['bvid']);
  const title = textOf(item['title']);
  if (aid <= 0 || bvid.length === 0 || title.length === 0) {
    return null;
  }
  const out = new BiliCollectionArchiveItem();
  out.aid = aid;
  out.bvid = bvid;
  out.title = title;
  out.coverUrl = normalizeBiliImageUrl(textOf(item['pic']));
  out.durationSec = numberOf(item['duration']);
  out.pubdate = optionalNumberOf(item['pubdate']);
  const stat = recordOf(item['stat']);
  out.play = stat === null ? -1 : optionalNumberOf(stat['view']);
  return out;
}

/** Upstream parseBiliSeriesArchivePage (x/series/archives data shape). */
export function parseBiliSeriesArchivePage(
  data: Record<string, Object>,
  requestedPage: number,
  requestedPageSize: number
): BiliSeriesArchivePage {
  const out = new BiliSeriesArchivePage();
  const archivesRaw = data['archives'];
  if (archivesRaw !== undefined && archivesRaw !== null) {
    const archives = archivesRaw as Object[];
    for (const entryRaw of archives) {
      const entry = recordOf(entryRaw);
      if (entry === null) {
        continue;
      }
      const item = parseBiliSpaceArchiveItem(entry);
      if (item !== null) {
        out.items.push(item);
      }
    }
  }
  const page = recordOf(data['page']);
  const num = page === null ? requestedPage : numberOf(page['num']);
  const size = page === null ? requestedPageSize : numberOf(page['size']);
  const resolvedPage = Math.max(1, num > 0 ? num : requestedPage);
  const resolvedPageSize = Math.max(1, size > 0 ? size : requestedPageSize);
  const totalRaw = page === null ? undefined : page['total'];
  const total = totalRaw === undefined || totalRaw === null
    ? out.items.length : numberOf(totalRaw);
  out.total = Math.max(total, out.items.length);
  out.hasMore = resolvedPage * resolvedPageSize < out.total;
  return out;
}

/**
 * seasons_archives_list data shape (Android getCollectionArchives inline
 * parse): meta falls back to the requested seasonId/mid when absent.
 */
export function parseBiliCollectionArchivePage(
  data: Record<string, Object>,
  seasonId: number,
  mid: number
): BiliCollectionArchivePage {
  const out = new BiliCollectionArchivePage();
  const meta = recordOf(data['meta']) ?? {} as Record<string, Object>;
  const page = recordOf(data['page']);
  const metaTotal = numberOf(meta['total']);
  const pageTotal = page === null ? 0 : numberOf(page['total']);
  const total = pageTotal > 0 ? pageTotal : metaTotal;
  out.meta.seasonId = numberOf(meta['season_id']);
  if (out.meta.seasonId <= 0) {
    out.meta.seasonId = seasonId;
  }
  out.meta.mid = numberOf(meta['mid']);
  if (out.meta.mid <= 0) {
    out.meta.mid = mid;
  }
  out.meta.title = textOf(meta['name']);
  out.meta.coverUrl = normalizeBiliImageUrl(textOf(meta['cover']));
  out.meta.description = textOf(meta['description']);
  out.meta.total = total;
  const archivesRaw = data['archives'];
  if (archivesRaw !== undefined && archivesRaw !== null) {
    const archives = archivesRaw as Object[];
    for (const entryRaw of archives) {
      const entry = recordOf(entryRaw);
      if (entry === null) {
        continue;
      }
      const item = parseBiliSpaceArchiveItem(entry);
      if (item !== null) {
        out.items.push(item);
      }
    }
  }
  out.hasMore = out.meta.total > out.items.length;
  return out;
}

/** Maps an uploader video to the app SongItem model (audioId = bvid). */
export function biliUploaderVideoToSongItem(video: BiliUploaderVideo): SongItem {
  const song = new SongItem(
    video.aid,
    video.title,
    video.uploaderName.length > 0 ? video.uploaderName : 'Bilibili',
    'Bilibili',
    0,
    video.durationSec * 1000,
    video.coverUrl,
    '',
    MusicPlatform.BILIBILI
  );
  song.channelId = 'bilibili';
  song.audioId = video.bvid;
  return song;
}

/** Maps a series/collection archive entry to the app SongItem model. */
export function biliArchiveItemToSongItem(
  item: BiliCollectionArchiveItem,
  uploaderName: string
): SongItem {
  const song = new SongItem(
    item.aid,
    item.title,
    uploaderName.length > 0 ? uploaderName : 'Bilibili',
    'Bilibili',
    0,
    item.durationSec * 1000,
    item.coverUrl,
    '',
    MusicPlatform.BILIBILI
  );
  song.channelId = 'bilibili';
  song.audioId = item.bvid;
  return song;
}
