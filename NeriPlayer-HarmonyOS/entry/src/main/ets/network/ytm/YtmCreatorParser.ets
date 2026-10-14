// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer),
// commit 4c085185 (YouTube Music creator profiles). Pure parsers and playback
// queue builders for the youtubei/v1 browse payloads behind creator detail,
// creator section "more" pages and the creators search filter.

import { Constants } from '../../app/Constants';
import { MusicPlatform } from '../../model/MusicPlatform';
import { SongItem } from '../../model/SongItem';
import { parseYtmDurationMs } from './YtmSearchParser';

export class YtmCreatorSummary {
  browseId: string = '';
  title: string = '';
  subtitle: string = '';
  coverUrl: string = '';
  channelId: string = '';
}

export class YtmCreatorHeader {
  browseId: string = '';
  title: string = '';
  subtitle: string = '';
  coverUrl: string = '';
  description: string = '';
  subscriberCountText: string = '';
  monthlyListenerCountText: string = '';
}

export enum YtmCreatorItemType {
  SONG = 'song',
  VIDEO = 'video',
  ALBUM = 'album',
  PLAYLIST = 'playlist',
  CREATOR = 'creator'
}

export class YtmCreatorItem {
  type: YtmCreatorItemType = YtmCreatorItemType.SONG;
  title: string = '';
  subtitle: string = '';
  coverUrl: string = '';
  videoId: string = '';
  browseId: string = '';
  playlistId: string = '';
  artist: string = '';
  album: string = '';
  durationMs: number = 0;
}

export class YtmCreatorBrowseEndpoint {
  browseId: string = '';
  params: string = '';
}

export class YtmCreatorSection {
  title: string = '';
  items: YtmCreatorItem[] = [];
  moreEndpoint: YtmCreatorBrowseEndpoint | null = null;
}

export class YtmCreatorDetail {
  header: YtmCreatorHeader = new YtmCreatorHeader();
  sections: YtmCreatorSection[] = [];
}

export class YtmCreatorItemsPage {
  title: string = '';
  items: YtmCreatorItem[] = [];
  continuation: string = '';
}

export class YtmCreatorPlaybackQueue {
  songs: SongItem[] = [];
  startIndex: number = 0;
}

function rec(value: Object | undefined | null): Record<string, Object> | null {
  if (value === undefined || value === null) {
    return null;
  }
  return value as Record<string, Object>;
}

function arr(value: Object | undefined | null): Object[] | null {
  if (value === undefined || value === null) {
    return null;
  }
  return value as Object[];
}

function textOf(value: Object | undefined | null): string {
  return value === undefined || value === null ? '' : String(value);
}

function firstNonBlank(values: string[]): string {
  for (const value of values) {
    if (value.trim().length > 0) {
      return value;
    }
  }
  return '';
}

/** Upstream upgradeYouTubeThumbnailUrl: raise Google image size params. */
export function upgradeYtmThumbnailUrl(url: string): string {
  if (url.trim().length === 0) {
    return url;
  }
  const sizeParam = /=w\d+(-h\d+)?(-[a-zA-Z0-9-]+)*$/;
  if (sizeParam.test(url)) {
    return url.replace(sizeParam, '=w1200-h1200');
  }
  if (url.indexOf('lh3.googleusercontent.com') >= 0 || url.indexOf('yt3.ggpht.com') >= 0) {
    return url.indexOf('=') >= 0 ? url : `${url}=w1200-h1200`;
  }
  return url;
}

/** Upstream extractText: runs joined, else simpleText; always trimmed. */
function extractText(node: Record<string, Object> | null): string {
  if (node === null) {
    return '';
  }
  const runs = arr(node['runs']);
  if (runs !== null) {
    let out = '';
    for (const runRaw of runs) {
      const run = rec(runRaw);
      out += run === null ? '' : textOf(run['text']);
    }
    return out.trim();
  }
  return textOf(node['simpleText']).trim();
}

/** Upstream extractTextParts: non-blank run texts (bullet separators dropped). */
function extractTextParts(node: Record<string, Object> | null): string[] {
  if (node === null) {
    return [];
  }
  const runs = arr(node['runs']);
  if (runs !== null) {
    const parts: string[] = [];
    for (const runRaw of runs) {
      const run = rec(runRaw);
      const text = run === null ? '' : textOf(run['text']).trim();
      if (text.length === 0) {
        continue;
      }
      let onlySeparators = true;
      for (const ch of text) {
        if (ch !== '•' && ch !== '·' && ch !== '|') {
          onlySeparators = false;
          break;
        }
      }
      if (onlySeparators) {
        continue;
      }
      parts.push(text);
    }
    return parts;
  }
  const parts: string[] = [];
  for (const piece of textOf(node['simpleText']).split('•').join('·').split('|').join('·').split('·')) {
    const text = piece.trim();
    if (text.length > 0) {
      parts.push(text);
    }
  }
  return parts;
}

function extractColumnText(
  columns: Object[] | null,
  index: number,
  rendererKey: string
): string {
  if (columns === null || index >= columns.length) {
    return '';
  }
  const column = rec(columns[index]);
  if (column === null) {
    return '';
  }
  const renderer = rec(column[rendererKey]);
  return extractText(renderer === null ? null : rec(renderer['text']));
}

/** Upstream extractMusicThumbnailUrl: last ladder entry, size upgraded. */
function extractMusicThumbnailUrl(node: Record<string, Object> | null): string {
  if (node === null) {
    return '';
  }
  let container = node;
  const music = rec(node['musicThumbnailRenderer']);
  const square = rec(node['croppedSquareThumbnailRenderer']);
  if (music !== null) {
    container = music;
  } else if (square !== null) {
    container = square;
  }
  let thumbnails: Object[] | null = null;
  const thumbnailRec = rec(container['thumbnail']);
  if (thumbnailRec !== null) {
    thumbnails = arr(thumbnailRec['thumbnails']);
  }
  if (thumbnails === null) {
    thumbnails = arr(container['thumbnails']);
  }
  if (thumbnails === null || thumbnails.length === 0) {
    return '';
  }
  const last = rec(thumbnails[thumbnails.length - 1]);
  return upgradeYtmThumbnailUrl(last === null ? '' : textOf(last['url']));
}

/** Upstream looksLikeDurationText: "m:ss" / "h:mm:ss" style only. */
export function looksLikeYtmDurationText(text: string): boolean {
  const trimmed = text.trim();
  if (trimmed.indexOf(':') < 0) {
    return false;
  }
  const parts = trimmed.split(':');
  for (const part of parts) {
    const value = Number(part.trim());
    if (!Number.isInteger(value) || value < 0) {
      return false;
    }
  }
  return parts.length > 0;
}

function normalizeTypeToken(token: string): string {
  return token.trim().toLowerCase().replace(/ /g, '');
}

function looksLikeSearchStatText(text: string): boolean {
  const normalized = text.trim().toLowerCase();
  if (normalized.trim().length === 0) {
    return false;
  }
  const markers: string[] = ['播放', '观看', 'views', 'view', 'listeners', 'listener',
    'monthly', '观众', '订阅者', 'subscriber'];
  for (const marker of markers) {
    if (normalized.indexOf(marker) >= 0) {
      return true;
    }
  }
  return false;
}

function looksLikeSearchTypeLabel(text: string, wantVideo: boolean, canSkip: boolean): boolean {
  if (!canSkip) {
    return false;
  }
  const token = normalizeTypeToken(text);
  if (token === 'song' || token === 'songs' || token === '歌曲' || token === '曲') {
    return !wantVideo;
  }
  if (token === 'video' || token === 'videos' || token === '视频' || token === 'mv') {
    return wantVideo;
  }
  return false;
}

function looksLikeHomeSongTypeLabel(text: string): boolean {
  const token = normalizeTypeToken(text);
  return token === 'song' || token === 'songs' || token === '歌曲' || token === '曲'
    || token === 'video' || token === 'videos' || token === '视频' || token === 'mv';
}

/** Upstream extractDurationText: whole-node text or first duration-like part. */
function extractDurationText(node: Record<string, Object> | null): string {
  if (node === null) {
    return '';
  }
  const direct = extractText(node);
  if (looksLikeYtmDurationText(direct)) {
    return direct;
  }
  for (const part of extractTextParts(node)) {
    if (looksLikeYtmDurationText(part)) {
      return part;
    }
  }
  return '';
}

function findDurationText(columns: Object[] | null, rendererKey: string): string {
  if (columns === null) {
    return '';
  }
  for (const columnRaw of columns) {
    const column = rec(columnRaw);
    if (column === null) {
      continue;
    }
    const renderer = rec(column[rendererKey]);
    const duration = extractDurationText(renderer === null ? null : rec(renderer['text']));
    if (duration.length > 0) {
      return duration;
    }
  }
  return '';
}

function extractSearchDurationText(renderer: Record<string, Object>): string {
  const fixed = findDurationText(arr(renderer['fixedColumns']),
    'musicResponsiveListItemFixedColumnRenderer');
  if (fixed.length > 0) {
    return fixed;
  }
  return findDurationText(arr(renderer['flexColumns']),
    'musicResponsiveListItemFlexColumnRenderer');
}

function extractSearchMetadataParts(renderer: Record<string, Object>): string[] {
  const columns = arr(renderer['flexColumns']);
  if (columns === null || columns.length < 2) {
    return [];
  }
  const column = rec(columns[1]);
  if (column === null) {
    return [];
  }
  const flexRenderer = rec(column['musicResponsiveListItemFlexColumnRenderer']);
  return extractTextParts(flexRenderer === null ? null : rec(flexRenderer['text']));
}

class ParsedSearchMetadata {
  artists: string[] = [];
  album: string = '';
  durationText: string = '';
}

/** Upstream parseSearchMetadata over flexColumns[1] runs (Song/Video flavour). */
function parseSearchMetadata(
  renderer: Record<string, Object>,
  wantVideo: boolean
): ParsedSearchMetadata {
  const out = new ParsedSearchMetadata();
  const columns = arr(renderer['flexColumns']);
  let runs: Object[] | null = null;
  if (columns !== null && columns.length >= 2) {
    const column = rec(columns[1]);
    if (column !== null) {
      const flexRenderer = rec(column['musicResponsiveListItemFlexColumnRenderer']);
      const textNode = flexRenderer === null ? null : rec(flexRenderer['text']);
      runs = textNode === null ? null : arr(textNode['runs']);
    }
  }
  if (runs === null) {
    for (const part of extractSearchMetadataParts(renderer)) {
      if (looksLikeYtmDurationText(part)) {
        continue;
      }
      out.artists.push(part);
      if (out.artists.length >= 1) {
        break;
      }
    }
    out.durationText = extractSearchDurationText(renderer);
    return out;
  }
  const entries: string[] = [];
  for (let index = 0; index < runs.length; index++) {
    if (index % 2 === 1) {
      continue;
    }
    const run = rec(runs[index]);
    if (run === null) {
      continue;
    }
    const text = textOf(run['text']).trim();
    if (text.length === 0) {
      continue;
    }
    if (looksLikeSearchTypeLabel(text, wantVideo, index === 0 && runs.length >= 3)) {
      continue;
    }
    if (looksLikeYtmDurationText(text)) {
      out.durationText = text;
      continue;
    }
    const navigation = rec(run['navigationEndpoint']);
    const browse = navigation === null ? null : rec(navigation['browseEndpoint']);
    const browseId = browse === null ? '' : textOf(browse['browseId']);
    if (browseId.startsWith('MPRE') || browseId.indexOf('release_detail') >= 0) {
      out.album = text;
    } else if (!looksLikeSearchStatText(text)) {
      entries.push(text);
    }
  }
  if (out.album.length === 0 && entries.length >= 2) {
    out.album = entries[entries.length - 1];
    entries.pop();
  }
  out.artists = entries;
  return out;
}

/**
 * Upstream resolveSearchResultType narrowed to the Song/Video pair.
 * Returns null when undetectable; callers default per renderer shape
 * (responsive rows default to Song, two-row cards to Video).
 */
function resolveSearchResultType(renderer: Record<string, Object>): boolean | null {
  const overlay = rec(renderer['overlay']);
  const overlayContent = overlay === null ? null : rec(overlay['musicItemThumbnailOverlayRenderer']);
  const overlayInner = overlayContent === null ? null : rec(overlayContent['content']);
  const playButton = overlayInner === null ? null : rec(overlayInner['musicPlayButtonRenderer']);
  const playNav = playButton === null ? null : rec(playButton['playNavigationEndpoint']);
  const overlayWatch = playNav === null ? null : rec(playNav['watchEndpoint']);
  const overlayCfg = overlayWatch === null
    ? null : rec(overlayWatch['watchEndpointMusicSupportedConfigs']);
  const overlayMusicCfg = overlayCfg === null ? null : rec(overlayCfg['watchEndpointMusicConfig']);
  const overlayType = overlayMusicCfg === null ? '' : textOf(overlayMusicCfg['musicVideoType']);
  const navigation = rec(renderer['navigationEndpoint']);
  const navWatch = navigation === null ? null : rec(navigation['watchEndpoint']);
  const navCfg = navWatch === null ? null : rec(navWatch['watchEndpointMusicSupportedConfigs']);
  const navMusicCfg = navCfg === null ? null : rec(navCfg['watchEndpointMusicConfig']);
  const navType = navMusicCfg === null ? '' : textOf(navMusicCfg['musicVideoType']);
  const musicVideoType = firstNonBlank([overlayType, navType]).toUpperCase();
  if (musicVideoType.indexOf('ATV') >= 0) {
    return false;
  }
  if (musicVideoType.indexOf('OMV') >= 0 || musicVideoType.indexOf('UGC') >= 0) {
    return true;
  }
  const parts = extractSearchMetadataParts(renderer);
  const firstToken = parts.length > 0 ? normalizeTypeToken(parts[0]) : '';
  if (firstToken === 'song' || firstToken === 'songs' || firstToken === '歌曲' || firstToken === '曲') {
    return false;
  }
  if (firstToken === 'video' || firstToken === 'videos' || firstToken === '视频' || firstToken === 'mv') {
    return true;
  }
  return null;
}

function extractVideoIdFromTextRuns(runs: Object[] | null): string {
  if (runs === null) {
    return '';
  }
  for (const runRaw of runs) {
    const run = rec(runRaw);
    if (run === null) {
      continue;
    }
    const navigation = rec(run['navigationEndpoint']);
    const watch = navigation === null ? null : rec(navigation['watchEndpoint']);
    const videoId = watch === null ? '' : textOf(watch['videoId']);
    if (videoId.trim().length > 0) {
      return videoId;
    }
  }
  return '';
}

function extractVideoIdFromMenu(menu: Record<string, Object> | null): string {
  if (menu === null) {
    return '';
  }
  const menuRenderer = rec(menu['menuRenderer']);
  const items = menuRenderer === null ? null : arr(menuRenderer['items']);
  if (items === null) {
    return '';
  }
  for (const itemRaw of items) {
    const item = rec(itemRaw);
    if (item === null) {
      continue;
    }
    const navItem = rec(item['menuNavigationItemRenderer']);
    const nav = navItem === null ? null : rec(navItem['navigationEndpoint']);
    const navWatch = nav === null ? null : rec(nav['watchEndpoint']);
    const navVideoId = navWatch === null ? '' : textOf(navWatch['videoId']);
    if (navVideoId.trim().length > 0) {
      return navVideoId;
    }
    const serviceItem = rec(item['menuServiceItemRenderer']);
    const service = serviceItem === null ? null : rec(serviceItem['serviceEndpoint']);
    const queueAdd = service === null ? null : rec(service['queueAddEndpoint']);
    const queueTarget = queueAdd === null ? null : rec(queueAdd['queueTarget']);
    const queueVideoId = queueTarget === null ? '' : textOf(queueTarget['videoId']);
    if (queueVideoId.trim().length > 0) {
      return queueVideoId;
    }
    const onEmpty = queueTarget === null ? null : rec(queueTarget['onEmptyQueue']);
    const onEmptyWatch = onEmpty === null ? null : rec(onEmpty['watchEndpoint']);
    const onEmptyVideoId = onEmptyWatch === null ? '' : textOf(onEmptyWatch['videoId']);
    if (onEmptyVideoId.trim().length > 0) {
      return onEmptyVideoId;
    }
  }
  return '';
}

/** Upstream extractTrackVideoId: overlay play button, playlist data, runs, menu. */
function extractTrackVideoId(renderer: Record<string, Object>): string {
  const overlay = rec(renderer['overlay']);
  const overlayContent = overlay === null ? null : rec(overlay['musicItemThumbnailOverlayRenderer']);
  const overlayInner = overlayContent === null ? null : rec(overlayContent['content']);
  const playButton = overlayInner === null ? null : rec(overlayInner['musicPlayButtonRenderer']);
  const playNav = playButton === null ? null : rec(playButton['playNavigationEndpoint']);
  const playWatch = playNav === null ? null : rec(playNav['watchEndpoint']);
  const overlayVideoId = playWatch === null ? '' : textOf(playWatch['videoId']);
  if (overlayVideoId.trim().length > 0) {
    return overlayVideoId;
  }
  const playlistData = rec(renderer['playlistItemData']);
  const playlistVideoId = playlistData === null ? '' : textOf(playlistData['videoId']);
  if (playlistVideoId.trim().length > 0) {
    return playlistVideoId;
  }
  const columns = arr(renderer['flexColumns']);
  let runs: Object[] | null = null;
  if (columns !== null && columns.length > 0) {
    const column = rec(columns[0]);
    const flexRenderer = column === null ? null : rec(column['musicResponsiveListItemFlexColumnRenderer']);
    const textNode = flexRenderer === null ? null : rec(flexRenderer['text']);
    runs = textNode === null ? null : arr(textNode['runs']);
  }
  const runsVideoId = extractVideoIdFromTextRuns(runs);
  if (runsVideoId.length > 0) {
    return runsVideoId;
  }
  return extractVideoIdFromMenu(rec(renderer['menu']));
}

/** Upstream extractBrowseEndpoint: navigation, title runs, flex-column runs. */
function extractBrowseEndpoint(renderer: Record<string, Object>): Record<string, Object> | null {
  const navigation = rec(renderer['navigationEndpoint']);
  const direct = navigation === null ? null : rec(navigation['browseEndpoint']);
  if (direct !== null) {
    return direct;
  }
  const title = rec(renderer['title']);
  const titleRuns = title === null ? null : arr(title['runs']);
  if (titleRuns !== null) {
    for (const runRaw of titleRuns) {
      const run = rec(runRaw);
      if (run === null) {
        continue;
      }
      const runNav = rec(run['navigationEndpoint']);
      const endpoint = runNav === null ? null : rec(runNav['browseEndpoint']);
      if (endpoint !== null) {
        return endpoint;
      }
    }
  }
  const columns = arr(renderer['flexColumns']);
  if (columns !== null) {
    for (const columnRaw of columns) {
      const column = rec(columnRaw);
      if (column === null) {
        continue;
      }
      const flexRenderer = rec(column['musicResponsiveListItemFlexColumnRenderer']);
      const textNode = flexRenderer === null ? null : rec(flexRenderer['text']);
      const runs = textNode === null ? null : arr(textNode['runs']);
      if (runs === null) {
        continue;
      }
      for (const runRaw of runs) {
        const run = rec(runRaw);
        if (run === null) {
          continue;
        }
        const runNav = rec(run['navigationEndpoint']);
        const endpoint = runNav === null ? null : rec(runNav['browseEndpoint']);
        if (endpoint !== null) {
          return endpoint;
        }
      }
    }
  }
  return null;
}

function extractCreatorChannelId(renderer: Record<string, Object>, browseId: string): string {
  if (browseId.startsWith('UC')) {
    return browseId;
  }
  const menu = rec(renderer['menu']);
  const menuRenderer = menu === null ? null : rec(menu['menuRenderer']);
  const items = menuRenderer === null ? null : arr(menuRenderer['items']);
  if (items === null) {
    return '';
  }
  for (const itemRaw of items) {
    const item = rec(itemRaw);
    if (item === null) {
      continue;
    }
    const toggle = rec(item['toggleMenuServiceItemRenderer']);
    const service = toggle === null ? null : rec(toggle['defaultServiceEndpoint']);
    const subscribe = service === null ? null : rec(service['subscribeEndpoint']);
    const channelIds = subscribe === null ? null : arr(subscribe['channelIds']);
    if (channelIds !== null && channelIds.length > 0) {
      const channelId = textOf(channelIds[0]);
      if (channelId.trim().length > 0) {
        return channelId;
      }
    }
  }
  return '';
}

function extractPlaylistId(renderer: Record<string, Object>, browseId: string): string {
  const navigation = rec(renderer['navigationEndpoint']);
  const watch = navigation === null ? null : rec(navigation['watchEndpoint']);
  const navPlaylist = watch === null ? '' : textOf(watch['playlistId']);
  if (navPlaylist.trim().length > 0) {
    return navPlaylist;
  }
  const overlay = rec(renderer['overlay']);
  const overlayContent = overlay === null ? null : rec(overlay['musicItemThumbnailOverlayRenderer']);
  const overlayInner = overlayContent === null ? null : rec(overlayContent['content']);
  const playButton = overlayInner === null ? null : rec(overlayInner['musicPlayButtonRenderer']);
  const playNav = playButton === null ? null : rec(playButton['playNavigationEndpoint']);
  const playWatch = playNav === null ? null : rec(playNav['watchEndpoint']);
  const overlayPlaylist = playWatch === null ? '' : textOf(playWatch['playlistId']);
  if (overlayPlaylist.trim().length > 0) {
    return overlayPlaylist;
  }
  if (browseId.startsWith('VL')) {
    return browseId.substring(2);
  }
  return '';
}

function resolveCreatorBrowseItemType(
  browseEndpoint: Record<string, Object> | null,
  browseId: string
): YtmCreatorItemType {
  let pageType = '';
  if (browseEndpoint !== null) {
    const configs = rec(browseEndpoint['browseEndpointContextSupportedConfigs']);
    const musicConfig = configs === null ? null : rec(configs['browseEndpointContextMusicConfig']);
    pageType = musicConfig === null ? '' : textOf(musicConfig['pageType']).toUpperCase();
  }
  if (pageType.indexOf('ARTIST') >= 0 || browseId.startsWith('UC')) {
    return YtmCreatorItemType.CREATOR;
  }
  if (pageType.indexOf('ALBUM') >= 0 || browseId.startsWith('MPRE')) {
    return YtmCreatorItemType.ALBUM;
  }
  if (pageType.indexOf('PLAYLIST') >= 0 || browseId.startsWith('VL')) {
    return YtmCreatorItemType.PLAYLIST;
  }
  return YtmCreatorItemType.PLAYLIST;
}

function extractCreatorBrowseEndpoint(
  browseEndpoint: Record<string, Object> | null
): YtmCreatorBrowseEndpoint | null {
  if (browseEndpoint === null) {
    return null;
  }
  const browseId = textOf(browseEndpoint['browseId']).trim();
  if (browseId.length === 0) {
    return null;
  }
  const endpoint = new YtmCreatorBrowseEndpoint();
  endpoint.browseId = browseId;
  endpoint.params = textOf(browseEndpoint['params']).trim();
  return endpoint;
}

function extractCreatorTitleBrowseEndpoint(
  titleNode: Record<string, Object> | null
): Record<string, Object> | null {
  if (titleNode === null) {
    return null;
  }
  const runs = arr(titleNode['runs']);
  if (runs === null) {
    return null;
  }
  for (const runRaw of runs) {
    const run = rec(runRaw);
    if (run === null) {
      continue;
    }
    const navigation = rec(run['navigationEndpoint']);
    const endpoint = navigation === null ? null : rec(navigation['browseEndpoint']);
    if (endpoint !== null) {
      return endpoint;
    }
  }
  return null;
}

function extractCreatorMoreEndpoint(
  renderer: Record<string, Object>,
  titleNode: Record<string, Object> | null,
  header: Record<string, Object> | null
): YtmCreatorBrowseEndpoint | null {
  const moreButton = rec(renderer['moreContentButton']);
  const moreRenderer = moreButton === null ? null : rec(moreButton['buttonRenderer']);
  const moreNav = moreRenderer === null ? null : rec(moreRenderer['navigationEndpoint']);
  const fromMoreButton = extractCreatorBrowseEndpoint(
    moreNav === null ? null : rec(moreNav['browseEndpoint']));
  if (fromMoreButton !== null) {
    return fromMoreButton;
  }
  if (header !== null) {
    const headerButton = rec(header['moreContentButton']);
    const headerRenderer = headerButton === null ? null : rec(headerButton['buttonRenderer']);
    const headerNav = headerRenderer === null ? null : rec(headerRenderer['navigationEndpoint']);
    const fromHeader = extractCreatorBrowseEndpoint(
      headerNav === null ? null : rec(headerNav['browseEndpoint']));
    if (fromHeader !== null) {
      return fromHeader;
    }
  }
  const bottom = rec(renderer['bottomEndpoint']);
  const fromBottom = extractCreatorBrowseEndpoint(
    bottom === null ? null : rec(bottom['browseEndpoint']));
  if (fromBottom !== null) {
    return fromBottom;
  }
  return extractCreatorBrowseEndpoint(extractCreatorTitleBrowseEndpoint(titleNode));
}

function extractContinuationToken(renderer: Record<string, Object> | null): string {
  if (renderer === null) {
    return '';
  }
  const continuations = arr(renderer['continuations']);
  if (continuations === null) {
    return '';
  }
  for (const continuationRaw of continuations) {
    const continuation = rec(continuationRaw);
    const next = continuation === null ? null : rec(continuation['nextContinuationData']);
    const token = next === null ? '' : textOf(next['continuation']);
    if (token.trim().length > 0) {
      return token;
    }
  }
  return '';
}

function extractContinuationTokenFromItems(contents: Object[] | null): string {
  if (contents === null) {
    return '';
  }
  for (const itemRaw of contents) {
    const item = rec(itemRaw);
    const continuationItem = item === null ? null : rec(item['continuationItemRenderer']);
    const endpoint = continuationItem === null ? null : rec(continuationItem['continuationEndpoint']);
    const command = endpoint === null ? null : rec(endpoint['continuationCommand']);
    const token = command === null ? '' : textOf(command['token']);
    if (token.trim().length > 0) {
      return token;
    }
  }
  return '';
}

function findSearchSectionListRenderer(root: Record<string, Object>): Record<string, Object> | null {
  const contents = rec(root['contents']);
  const tabbed = contents === null ? null : rec(contents['tabbedSearchResultsRenderer']);
  const tabs = tabbed === null ? null : arr(tabbed['tabs']);
  if (tabs === null || tabs.length === 0) {
    return null;
  }
  const tab = rec(tabs[0]);
  const tabRenderer = tab === null ? null : rec(tab['tabRenderer']);
  const tabContent = tabRenderer === null ? null : rec(tabRenderer['content']);
  return tabContent === null ? null : rec(tabContent['sectionListRenderer']);
}

function findSearchShelfRenderers(root: Record<string, Object>): Record<string, Object>[] {
  const sectionList = findSearchSectionListRenderer(root);
  const sections = sectionList === null ? null : arr(sectionList['contents']);
  if (sections === null) {
    return [];
  }
  const shelves: Record<string, Object>[] = [];
  for (const sectionRaw of sections) {
    const section = rec(sectionRaw);
    if (section === null) {
      continue;
    }
    const shelf = rec(section['musicShelfRenderer']);
    if (shelf !== null) {
      shelves.push(shelf);
    }
    const itemSection = rec(section['itemSectionRenderer']);
    const itemContents = itemSection === null ? null : arr(itemSection['contents']);
    if (itemContents === null) {
      continue;
    }
    for (const itemRaw of itemContents) {
      const item = rec(itemRaw);
      const nested = item === null ? null : rec(item['musicShelfRenderer']);
      if (nested !== null) {
        shelves.push(nested);
      }
    }
  }
  return shelves;
}

function findSearchResultContentArrays(root: Record<string, Object>): Object[][] {
  const arrays: Object[][] = [];
  for (const shelf of findSearchShelfRenderers(root)) {
    const contents = arr(shelf['contents']);
    if (contents !== null) {
      arrays.push(contents);
    }
  }
  const sectionList = findSearchSectionListRenderer(root);
  const sections = sectionList === null ? null : arr(sectionList['contents']);
  if (sections !== null) {
    for (const sectionRaw of sections) {
      const section = rec(sectionRaw);
      const itemSection = section === null ? null : rec(section['itemSectionRenderer']);
      const contents = itemSection === null ? null : arr(itemSection['contents']);
      if (contents !== null) {
        arrays.push(contents);
      }
    }
  }
  const continuationContents = rec(root['continuationContents']);
  const shelfContinuation = continuationContents === null
    ? null : rec(continuationContents['musicShelfContinuation']);
  const continuationItems = shelfContinuation === null ? null : arr(shelfContinuation['contents']);
  if (continuationItems !== null) {
    arrays.push(continuationItems);
  }
  return arrays;
}

function parseCreatorSearchItem(item: Record<string, Object>): YtmCreatorSummary | null {
  const twoRow = rec(item['musicTwoRowItemRenderer']);
  const renderer = twoRow !== null ? twoRow : rec(item['musicResponsiveListItemRenderer']);
  if (renderer === null) {
    return null;
  }
  const title = twoRow !== null
    ? extractText(rec(renderer['title']))
    : extractColumnText(arr(renderer['flexColumns']), 0, 'musicResponsiveListItemFlexColumnRenderer');
  const subtitle = twoRow !== null
    ? extractText(rec(renderer['subtitle']))
    : extractColumnText(arr(renderer['flexColumns']), 1, 'musicResponsiveListItemFlexColumnRenderer');
  const browseEndpoint = extractBrowseEndpoint(renderer);
  if (browseEndpoint === null) {
    return null;
  }
  const browseId = textOf(browseEndpoint['browseId']).trim();
  if (browseId.length === 0 || title.length === 0) {
    return null;
  }
  const summary = new YtmCreatorSummary();
  summary.browseId = browseId;
  summary.title = title;
  summary.subtitle = subtitle;
  summary.coverUrl = firstNonBlank([
    extractMusicThumbnailUrl(rec(renderer['thumbnailRenderer'])),
    extractMusicThumbnailUrl(rec(renderer['thumbnail']))
  ]);
  summary.channelId = extractCreatorChannelId(renderer, browseId);
  return summary;
}

/** Upstream parseCreatorSearchResults: shelves + item sections, browseId-deduped. */
export function parseYtmCreatorSearchResults(
  root: Record<string, Object>,
  limit: number
): YtmCreatorSummary[] {
  const items: YtmCreatorSummary[] = [];
  const seen = new Set<string>();
  for (const contents of findSearchResultContentArrays(root)) {
    for (const itemRaw of contents) {
      const item = rec(itemRaw);
      if (item === null) {
        continue;
      }
      const summary = parseCreatorSearchItem(item);
      if (summary === null || seen.has(summary.browseId)) {
        continue;
      }
      seen.add(summary.browseId);
      items.push(summary);
    }
  }
  const capped = Math.max(1, limit);
  return items.length > capped ? items.slice(0, capped) : items;
}

function findCreatorHeaderRenderer(root: Record<string, Object>): Record<string, Object> | null {
  const header = rec(root['header']);
  if (header === null) {
    return null;
  }
  const immersive = rec(header['musicImmersiveHeaderRenderer']);
  if (immersive !== null) {
    return immersive;
  }
  const visual = rec(header['musicVisualHeaderRenderer']);
  if (visual !== null) {
    return visual;
  }
  return rec(header['musicDetailHeaderRenderer']);
}

function findCreatorSectionContents(root: Record<string, Object>): Object[] {
  const contentsRoot = rec(root['contents']);
  const candidates: Object[][] = [];
  if (contentsRoot !== null) {
    const singleColumn = rec(contentsRoot['singleColumnBrowseResultsRenderer']);
    const singleTabs = singleColumn === null ? null : arr(singleColumn['tabs']);
    const sectionContents = tabSectionContents(singleTabs);
    if (sectionContents !== null) {
      candidates.push(sectionContents);
    }
    const directSectionList = rec(contentsRoot['sectionListRenderer']);
    const directContents = directSectionList === null ? null : arr(directSectionList['contents']);
    if (directContents !== null) {
      candidates.push(directContents);
    }
    const twoColumn = rec(contentsRoot['twoColumnBrowseResultsRenderer']);
    const twoTabs = twoColumn === null ? null : arr(twoColumn['tabs']);
    const twoContents = tabSectionContents(twoTabs);
    if (twoContents !== null) {
      candidates.push(twoContents);
    }
  }
  for (const candidate of candidates) {
    if (candidate.length > 0) {
      return candidate;
    }
  }
  return [];
}

function tabSectionContents(tabs: Object[] | null): Object[] | null {
  if (tabs === null || tabs.length === 0) {
    return null;
  }
  const tab = rec(tabs[0]);
  const tabRenderer = tab === null ? null : rec(tab['tabRenderer']);
  const tabContent = tabRenderer === null ? null : rec(tabRenderer['content']);
  const sectionList = tabContent === null ? null : rec(tabContent['sectionListRenderer']);
  return sectionList === null ? null : arr(sectionList['contents']);
}

function findCreatorDescription(root: Record<string, Object>): string {
  for (const sectionRaw of findCreatorSectionContents(root)) {
    const section = rec(sectionRaw);
    const shelf = section === null ? null : rec(section['musicDescriptionShelfRenderer']);
    const description = shelf === null ? null : rec(shelf['description']);
    const text = extractText(description);
    if (text.length > 0) {
      return text;
    }
  }
  return '';
}

function parseCreatorSectionItems(contents: Object[] | null): YtmCreatorItem[] {
  const items: YtmCreatorItem[] = [];
  if (contents === null) {
    return items;
  }
  for (const itemRaw of contents) {
    const item = rec(itemRaw);
    if (item === null) {
      continue;
    }
    const responsive = rec(item['musicResponsiveListItemRenderer']);
    if (responsive !== null) {
      const parsed = parseCreatorResponsiveItem(responsive);
      if (parsed !== null) {
        items.push(parsed);
      }
      continue;
    }
    const twoRow = rec(item['musicTwoRowItemRenderer']);
    if (twoRow !== null) {
      const parsed = parseCreatorTwoRowItem(twoRow);
      if (parsed !== null) {
        items.push(parsed);
      }
    }
  }
  return items;
}

function parseCreatorResponsiveItem(renderer: Record<string, Object>): YtmCreatorItem | null {
  const title = extractColumnText(arr(renderer['flexColumns']), 0,
    'musicResponsiveListItemFlexColumnRenderer');
  if (title.length === 0) {
    return null;
  }
  const videoId = extractTrackVideoId(renderer);
  const browseEndpoint = extractBrowseEndpoint(renderer);
  const browseId = browseEndpoint === null ? '' : textOf(browseEndpoint['browseId']).trim();
  if (videoId.trim().length === 0 && browseId.length === 0) {
    return null;
  }
  // 上游 ?: Song 兜底（responsive 行）。
  const detected = resolveSearchResultType(renderer);
  const wantVideo = videoId.trim().length > 0 && (detected === null ? false : detected);
  const type = videoId.trim().length > 0
    ? (wantVideo ? YtmCreatorItemType.VIDEO : YtmCreatorItemType.SONG)
    : resolveCreatorBrowseItemType(browseEndpoint, browseId);
  const metadata = parseSearchMetadata(renderer, wantVideo);
  const durationText = metadata.durationText.length > 0
    ? metadata.durationText : extractSearchDurationText(renderer);
  const item = new YtmCreatorItem();
  item.type = type;
  item.title = title;
  item.subtitle = extractColumnText(arr(renderer['flexColumns']), 1,
    'musicResponsiveListItemFlexColumnRenderer');
  item.coverUrl = extractMusicThumbnailUrl(rec(renderer['thumbnail']));
  item.videoId = videoId;
  item.browseId = browseId;
  item.playlistId = extractPlaylistId(renderer, browseId);
  item.artist = metadata.artists.join(' / ');
  item.album = metadata.album;
  item.durationMs = parseYtmDurationMs(durationText);
  return item;
}

function parseCreatorTwoRowItem(renderer: Record<string, Object>): YtmCreatorItem | null {
  const title = extractText(rec(renderer['title']));
  if (title.length === 0) {
    return null;
  }
  const navigation = rec(renderer['navigationEndpoint']);
  const watch = navigation === null ? null : rec(navigation['watchEndpoint']);
  const watchVideoId = watch === null ? '' : textOf(watch['videoId']);
  const videoId = firstNonBlank([watchVideoId, extractTrackVideoId(renderer)]);
  const browseEndpoint = extractBrowseEndpoint(renderer);
  const browseId = browseEndpoint === null ? '' : textOf(browseEndpoint['browseId']).trim();
  if (videoId.trim().length === 0 && browseId.length === 0) {
    return null;
  }
  // 上游 ?: Video 兜底（two-row 卡）。
  const detected = resolveSearchResultType(renderer);
  const wantVideo = videoId.trim().length === 0 ? true : (detected === null ? true : detected);
  const type = videoId.trim().length > 0
    ? (wantVideo ? YtmCreatorItemType.VIDEO : YtmCreatorItemType.SONG)
    : resolveCreatorBrowseItemType(browseEndpoint, browseId);
  const subtitleNode = rec(renderer['subtitle']);
  const subtitle = extractText(subtitleNode);
  const durationText = extractDurationText(subtitleNode);
  let artist = '';
  for (const part of extractTextParts(subtitleNode)) {
    if (looksLikeYtmDurationText(part) || looksLikeHomeSongTypeLabel(part)) {
      continue;
    }
    artist = part;
    break;
  }
  const item = new YtmCreatorItem();
  item.type = type;
  item.title = title;
  item.subtitle = subtitle;
  item.coverUrl = firstNonBlank([
    extractMusicThumbnailUrl(rec(renderer['thumbnailRenderer'])),
    extractMusicThumbnailUrl(rec(renderer['thumbnail']))
  ]);
  item.videoId = videoId;
  item.browseId = browseId;
  item.playlistId = extractPlaylistId(renderer, browseId);
  item.artist = artist;
  item.durationMs = parseYtmDurationMs(durationText);
  return item;
}

function parseCreatorShelf(renderer: Record<string, Object>): YtmCreatorSection | null {
  const title = extractText(rec(renderer['title']));
  if (title.length === 0) {
    return null;
  }
  const section = new YtmCreatorSection();
  section.title = title;
  section.items = parseCreatorSectionItems(arr(renderer['contents']));
  section.moreEndpoint = extractCreatorMoreEndpoint(renderer, rec(renderer['title']), null);
  return section;
}

function parseCreatorCarousel(renderer: Record<string, Object>): YtmCreatorSection | null {
  const header = rec(renderer['header']);
  const basicHeader = header === null ? null : rec(header['musicCarouselShelfBasicHeaderRenderer']);
  const basicTitle = basicHeader === null ? null : rec(basicHeader['title']);
  const title = firstNonBlank([
    extractText(basicTitle),
    extractText(header === null ? null : rec(header['title'])),
    extractText(rec(renderer['title']))
  ]);
  if (title.length === 0) {
    return null;
  }
  const section = new YtmCreatorSection();
  section.title = title;
  section.items = parseCreatorSectionItems(arr(renderer['contents']));
  section.moreEndpoint = extractCreatorMoreEndpoint(renderer,
    basicTitle !== null ? basicTitle : (header === null ? null : rec(header['title'])),
    basicHeader);
  return section;
}

function parseCreatorSections(section: Record<string, Object>): YtmCreatorSection[] {
  const out: YtmCreatorSection[] = [];
  const shelf = rec(section['musicShelfRenderer']);
  if (shelf !== null) {
    const parsed = parseCreatorShelf(shelf);
    if (parsed !== null) {
      out.push(parsed);
    }
  }
  const carousel = rec(section['musicCarouselShelfRenderer']);
  if (carousel !== null) {
    const parsed = parseCreatorCarousel(carousel);
    if (parsed !== null) {
      out.push(parsed);
    }
  }
  const itemSection = rec(section['itemSectionRenderer']);
  const nestedContents = itemSection === null ? null : arr(itemSection['contents']);
  if (nestedContents === null) {
    return out;
  }
  for (const nestedRaw of nestedContents) {
    const nested = rec(nestedRaw);
    if (nested === null) {
      continue;
    }
    const nestedShelf = rec(nested['musicShelfRenderer']);
    if (nestedShelf !== null) {
      const parsed = parseCreatorShelf(nestedShelf);
      if (parsed !== null) {
        out.push(parsed);
      }
    }
    const nestedCarousel = rec(nested['musicCarouselShelfRenderer']);
    if (nestedCarousel !== null) {
      const parsed = parseCreatorCarousel(nestedCarousel);
      if (parsed !== null) {
        out.push(parsed);
      }
    }
  }
  return out;
}

/** Upstream parseCreatorDetail: header with fallbacks + flattened sections. */
export function parseYtmCreatorDetail(
  root: Record<string, Object>,
  fallback: YtmCreatorSummary
): YtmCreatorDetail {
  const headerRenderer = findCreatorHeaderRenderer(root);
  const header = new YtmCreatorHeader();
  header.browseId = fallback.browseId;
  const title = extractText(headerRenderer === null ? null : rec(headerRenderer['title']));
  header.title = title.length > 0 ? title : fallback.title;
  header.subtitle = firstNonBlank([
    extractText(headerRenderer === null ? null : rec(headerRenderer['subtitle'])),
    extractText(headerRenderer === null ? null : rec(headerRenderer['straplineTextOne'])),
    fallback.subtitle
  ]);
  header.coverUrl = firstNonBlank([
    extractMusicThumbnailUrl(headerRenderer === null ? null : rec(headerRenderer['thumbnail'])),
    extractMusicThumbnailUrl(headerRenderer === null ? null : rec(headerRenderer['thumbnailRenderer'])),
    fallback.coverUrl
  ]);
  header.description = firstNonBlank([
    extractText(headerRenderer === null ? null : rec(headerRenderer['description'])),
    findCreatorDescription(root)
  ]);
  header.subscriberCountText = extractText(
    headerRenderer === null ? null : rec(headerRenderer['shortSubscriberCountText']));
  header.monthlyListenerCountText = extractText(
    headerRenderer === null ? null : rec(headerRenderer['monthlyListenerCount']));
  const detail = new YtmCreatorDetail();
  detail.header = header;
  for (const sectionRaw of findCreatorSectionContents(root)) {
    const section = rec(sectionRaw);
    if (section === null) {
      continue;
    }
    for (const parsed of parseCreatorSections(section)) {
      if (parsed.items.length > 0) {
        detail.sections.push(parsed);
      }
    }
  }
  return detail;
}

/** Upstream extractSearchContinuation: first shelf token or shelf continuation. */
export function extractYtmSearchContinuation(root: Record<string, Object>): string {
  const shelves = findSearchShelfRenderers(root);
  if (shelves.length > 0) {
    const token = extractContinuationToken(shelves[0]);
    if (token.length > 0) {
      return token;
    }
  }
  const continuationContents = rec(root['continuationContents']);
  const shelf = continuationContents === null ? null : rec(continuationContents['musicShelfContinuation']);
  return extractContinuationToken(shelf);
}

class CreatorItemsSource {
  title: string = '';
  contents: Object[] | null = null;
  continuation: string = '';
}

function creatorItemsSource(
  title: string,
  renderer: Record<string, Object>,
  contents: Object[] | null
): CreatorItemsSource {
  const source = new CreatorItemsSource();
  source.title = title;
  source.contents = contents;
  const token = extractContinuationToken(renderer);
  source.continuation = token.length > 0 ? token : extractContinuationTokenFromItems(contents);
  return source;
}

function findCreatorItemsSource(section: Record<string, Object>): CreatorItemsSource | null {
  const grid = rec(section['gridRenderer']);
  if (grid !== null) {
    const gridHeader = rec(grid['header']);
    const headerRenderer = gridHeader === null ? null : rec(gridHeader['gridHeaderRenderer']);
    return creatorItemsSource(
      extractText(headerRenderer === null ? null : rec(headerRenderer['title'])),
      grid, arr(grid['items']));
  }
  const carousel = rec(section['musicCarouselShelfRenderer']);
  if (carousel !== null) {
    const header = rec(carousel['header']);
    const basicHeader = header === null ? null : rec(header['musicCarouselShelfBasicHeaderRenderer']);
    const title = firstNonBlank([
      extractText(basicHeader === null ? null : rec(basicHeader['title'])),
      extractText(header === null ? null : rec(header['title'])),
      extractText(rec(carousel['title']))
    ]);
    return creatorItemsSource(title, carousel, arr(carousel['contents']));
  }
  const playlistShelf = rec(section['musicPlaylistShelfRenderer']);
  if (playlistShelf !== null) {
    return creatorItemsSource(extractText(rec(playlistShelf['title'])),
      playlistShelf, arr(playlistShelf['contents']));
  }
  const shelf = rec(section['musicShelfRenderer']);
  if (shelf !== null) {
    return creatorItemsSource(extractText(rec(shelf['title'])), shelf, arr(shelf['contents']));
  }
  return null;
}

function findCreatorItemsPageSourceInSection(section: Record<string, Object>): CreatorItemsSource | null {
  const direct = findCreatorItemsSource(section);
  if (direct !== null) {
    return direct;
  }
  const itemSection = rec(section['itemSectionRenderer']);
  const nestedContents = itemSection === null ? null : arr(itemSection['contents']);
  if (nestedContents === null) {
    return null;
  }
  for (const nestedRaw of nestedContents) {
    const nested = rec(nestedRaw);
    if (nested === null) {
      continue;
    }
    const source = findCreatorItemsSource(nested);
    if (source !== null) {
      return source;
    }
  }
  return null;
}

function findCreatorItemsPageSource(root: Record<string, Object>): CreatorItemsSource | null {
  for (const sectionRaw of findCreatorSectionContents(root)) {
    const section = rec(sectionRaw);
    if (section === null) {
      continue;
    }
    const source = findCreatorItemsPageSourceInSection(section);
    if (source !== null) {
      return source;
    }
  }
  return null;
}

function findCreatorItemsContinuationSource(root: Record<string, Object>): CreatorItemsSource | null {
  const continuationContents = rec(root['continuationContents']);
  if (continuationContents !== null) {
    const grid = rec(continuationContents['gridContinuation']);
    if (grid !== null) {
      return creatorItemsSource('', grid, arr(grid['items']));
    }
    const playlistShelf = rec(continuationContents['musicPlaylistShelfContinuation']);
    if (playlistShelf !== null) {
      return creatorItemsSource('', playlistShelf, arr(playlistShelf['contents']));
    }
    const shelf = rec(continuationContents['musicShelfContinuation']);
    if (shelf !== null) {
      return creatorItemsSource('', shelf, arr(shelf['contents']));
    }
    const carousel = rec(continuationContents['musicCarouselShelfContinuation']);
    if (carousel !== null) {
      return creatorItemsSource('', carousel, arr(carousel['contents']));
    }
  }
  const actions = arr(root['onResponseReceivedActions']);
  if (actions === null) {
    return null;
  }
  for (const actionRaw of actions) {
    const action = rec(actionRaw);
    const append = action === null ? null : rec(action['appendContinuationItemsAction']);
    const items = append === null ? null : arr(append['continuationItems']);
    if (items === null) {
      continue;
    }
    const source = new CreatorItemsSource();
    source.title = '';
    source.contents = items;
    source.continuation = extractContinuationTokenFromItems(items);
    return source;
  }
  return null;
}

function toCreatorItemsPage(source: CreatorItemsSource, fallbackTitle: string): YtmCreatorItemsPage {
  const page = new YtmCreatorItemsPage();
  page.title = source.title.length > 0 ? source.title : fallbackTitle;
  page.items = parseCreatorSectionItems(source.contents);
  page.continuation = page.items.length > 0 ? source.continuation : '';
  return page;
}

/** Upstream parseCreatorItemsPage: first grid/carousel/shelf source wins. */
export function parseYtmCreatorItemsPage(
  root: Record<string, Object>,
  fallbackTitle: string
): YtmCreatorItemsPage {
  const source = findCreatorItemsPageSource(root);
  if (source === null) {
    const page = new YtmCreatorItemsPage();
    page.title = fallbackTitle;
    return page;
  }
  return toCreatorItemsPage(source, fallbackTitle);
}

/** Upstream parseCreatorItemsContinuation: continuation payloads only. */
export function parseYtmCreatorItemsContinuation(root: Record<string, Object>): YtmCreatorItemsPage {
  const source = findCreatorItemsContinuationSource(root);
  if (source === null) {
    return new YtmCreatorItemsPage();
  }
  return toCreatorItemsPage(source, '');
}

/** Upstream youtubeMusicCreatorItemKey: videoId > browseId > playlistId > tuple. */
export function ytmCreatorItemKey(item: YtmCreatorItem): string {
  const videoId = item.videoId.trim();
  if (videoId.length > 0) {
    return videoId;
  }
  const browseId = item.browseId.trim();
  if (browseId.length > 0) {
    return browseId;
  }
  const playlistId = item.playlistId.trim();
  if (playlistId.length > 0) {
    return playlistId;
  }
  return `${item.type}|${item.title.trim()}|${item.subtitle.trim()}`;
}

/** Upstream mergeYouTubeMusicCreatorItems: key-deduped, order preserved. */
export function mergeYtmCreatorItems(items: YtmCreatorItem[]): YtmCreatorItem[] {
  const seen = new Set<string>();
  const out: YtmCreatorItem[] = [];
  for (const item of items) {
    const key = ytmCreatorItemKey(item);
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    out.push(item);
  }
  return out;
}

/** Upstream toCreatorSongItem: playable items become YTM SongItem rows. */
export function ytmCreatorItemToSongItem(item: YtmCreatorItem): SongItem | null {
  if (item.videoId.trim().length === 0) {
    return null;
  }
  const displayArtist = firstNonBlank([item.artist, item.subtitle, 'YouTube']);
  const displayAlbum = item.album.length > 0 ? item.album : 'YouTube Music';
  const cover = item.coverUrl.length > 0 ? item.coverUrl
    : `https://i.ytimg.com/vi/${item.videoId}/hqdefault.jpg`;
  const song = new SongItem(0, item.title, displayArtist, displayAlbum, 0,
    item.durationMs, cover, `${Constants.YOUTUBE_MUSIC_MEDIA_PREFIX}${item.videoId}`,
    MusicPlatform.YOUTUBE_MUSIC);
  song.channelId = Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM;
  song.audioId = item.videoId;
  return song;
}

/** Upstream buildYouTubeMusicCreatorPlaybackQueue (pure half). */
export function buildYtmCreatorPlaybackQueue(
  items: YtmCreatorItem[],
  selectedItem: YtmCreatorItem
): YtmCreatorPlaybackQueue | null {
  const songs: SongItem[] = [];
  const keyedItems: YtmCreatorItem[] = [];
  for (const item of mergeYtmCreatorItems(items)) {
    const song = ytmCreatorItemToSongItem(item);
    if (song !== null) {
      keyedItems.push(item);
      songs.push(song);
    }
  }
  if (songs.length === 0) {
    return null;
  }
  const selectedKey = ytmCreatorItemKey(selectedItem);
  let startIndex = 0;
  for (let index = 0; index < keyedItems.length; index++) {
    if (ytmCreatorItemKey(keyedItems[index]) === selectedKey) {
      startIndex = index;
      break;
    }
  }
  const queue = new YtmCreatorPlaybackQueue();
  queue.songs = songs;
  queue.startIndex = startIndex;
  return queue;
}

export const YTM_CREATOR_PLAYBACK_PAGE_LIMIT: number = 80;

/**
 * Upstream loadYouTubeMusicCreatorPlaybackQueue: local section items when the
 * section has no "more" endpoint, otherwise first page + continuations (dedup
 * guard against looping tokens), then the playable queue with start index.
 */
export async function loadYtmCreatorPlaybackQueue(
  section: YtmCreatorSection,
  selectedItem: YtmCreatorItem,
  fetchFirstPage: (endpoint: YtmCreatorBrowseEndpoint, fallbackTitle: string) => Promise<YtmCreatorItemsPage>,
  fetchContinuation: (continuation: string) => Promise<YtmCreatorItemsPage>,
  pageLimit: number = YTM_CREATOR_PLAYBACK_PAGE_LIMIT
): Promise<YtmCreatorPlaybackQueue | null> {
  const endpoint = section.moreEndpoint;
  if (endpoint === null) {
    return buildYtmCreatorPlaybackQueue(section.items, selectedItem);
  }
  const items: YtmCreatorItem[] = [...section.items];
  const firstPage = await fetchFirstPage(endpoint, section.title);
  items.push(...firstPage.items);
  const seenContinuations = new Set<string>();
  let continuation = firstPage.continuation.trim();
  let loadedPageCount = 1;
  const maxPageCount = Math.max(1, pageLimit);
  while (continuation.length > 0 && loadedPageCount < maxPageCount) {
    if (seenContinuations.has(continuation)) {
      break;
    }
    seenContinuations.add(continuation);
    const page = await fetchContinuation(continuation);
    items.push(...page.items);
    loadedPageCount++;
    continuation = page.continuation.trim();
  }
  return buildYtmCreatorPlaybackQueue(items, selectedItem);
}
