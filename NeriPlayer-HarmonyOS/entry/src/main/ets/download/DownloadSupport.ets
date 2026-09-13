import { SongItem } from '../model/SongItem';
import { stableKeyOf } from '../model/SongIdentity';
import { DownloadTransportKind } from './DownloadModels';

/**
 * Transient-failure retry policy, mirroring Android
 * resolveTransientDownloadRetryDelayMs / shouldRetryTransientDownloadFailure.
 */
export class DownloadRetryPolicy {
  static readonly MAX_ATTEMPTS: number = 6;

  /** 1s, 2s, 4s, then capped at 5s. */
  static retryDelayMs(attemptNumber: number): number {
    if (attemptNumber <= 1) {
      return 1000;
    }
    if (attemptNumber === 2) {
      return 2000;
    }
    if (attemptNumber === 3) {
      return 4000;
    }
    return 5000;
  }

  static isRetryableHttpError(code: number): boolean {
    if (code === 408 || code === 409 || code === 425 || code === 429) {
      return true;
    }
    return code >= 500 && code < 600;
  }

  static isRetryableMessage(message: string): boolean {
    const lowered = message.toLowerCase();
    return lowered.indexOf('unknownhost') >= 0
      || lowered.indexOf('connect') >= 0
      || lowered.indexOf('sockettimeout') >= 0
      || lowered.indexOf('interrupted') >= 0
      || lowered.indexOf(' eof') >= 0
      || lowered.indexOf('ssl') >= 0
      || lowered.indexOf('connection reset') >= 0;
  }
}

/**
 * Log-safe rendering of a resolved CDN URL: scheme and host only. Query
 * strings carry expiring signatures/token parameters (NetEase, Bilibili),
 * and even paths can embed opaque ticket segments, so neither may reach
 * hilog or collected diagnostics. Pure and unit-testable.
 */
export function redactUrlForLog(url: string): string {
  const schemeEnd = url.indexOf('://');
  if (schemeEnd < 0) {
    return `<no-scheme:${url.length}>`;
  }
  // The authority ends at the first '/', but also at '?'/'#': a query-only
  // URL (https://host?authKey=SECRET) has no path, and searching for '/'
  // alone would leak the whole query into the log.
  const authorityStart = schemeEnd + 3;
  let authorityEnd = url.length;
  for (let i = authorityStart; i < url.length; i++) {
    const ch = url[i];
    if (ch === '/' || ch === '?' || ch === '#') {
      authorityEnd = i;
      break;
    }
  }
  return `${url.substring(0, authorityEnd)}/<path:${url.length - authorityEnd}>`;
}

/**
 * Managed download file naming, mirroring ManagedDownloadNaming.kt.
 */
export class DownloadNaming {
  static readonly DEFAULT_TEMPLATE: string = '%source% - %artist% - %title%';
  static readonly LEGACY_TEMPLATE: string = '%artist% - %title%';

  /** Sanitizes a path segment: illegal path characters to '_', trimmed. */
  static sanitize(name: string): string {
    let cleaned = '';
    for (let i = 0; i < name.length; i++) {
      const ch = name[i];
      cleaned += '\\/:*?"<>|'.indexOf(ch) >= 0 ? '_' : ch;
    }
    const trimmed = cleaned.trim();
    return trimmed.length > 0 ? trimmed : 'audio';
  }

  /** Renders the filename template with song placeholders. */
  static render(template: string, song: SongItem): string {
    return DownloadNaming.sanitize(template
      .split('%title%').join(song.displayName)
      .split('%artist%').join(song.displayArtist)
      .split('%album%').join(song.album)
      .split('%source%').join(DownloadNaming.sourceOf(song))
      .split('%id%').join(`${song.id}`)
      .split('%audioId%').join(song.audioId)
      .split('%subAudioId%').join(song.subAudioId));
  }

  /** Falls back to the default template for degenerate render results. */
  static renderWithFallback(template: string, song: SongItem): string {
    const rendered = DownloadNaming.render(template, song);
    if (template !== DownloadNaming.DEFAULT_TEMPLATE && rendered.length < 2) {
      return DownloadNaming.render(DownloadNaming.DEFAULT_TEMPLATE, song);
    }
    return rendered;
  }

  static sourceOf(song: SongItem): string {
    const channel = song.channelId.trim();
    if (channel.length > 0) {
      return channel;
    }
    if (song.album.startsWith('bili')) {
      return 'bilibili';
    }
    if (song.mediaUri.indexOf('youtube') >= 0) {
      return 'youtube_music';
    }
    return 'netease';
  }

  /**
   * Staging file name for the working directory:
   * npdl_<hash8>_<prefix48>.<ext8>.download
   */
  static workingFileName(song: SongItem, baseName: string, ext: string): string {
    const hash = DownloadNaming.hashHex(stableKeyOf(song)).substring(0, 8);
    const prefix = DownloadNaming.asciiSafe(baseName).substring(0, 48) || 'track';
    const cleanExt = DownloadNaming.asciiSafe(ext).replace(/[^A-Za-z0-9]/g, '').substring(0, 8).toLowerCase();
    return `npdl_${hash}_${prefix}.${cleanExt.length > 0 ? cleanExt : 'bin'}.download`;
  }

  static asciiSafe(value: string): string {
    let out = '';
    for (let i = 0; i < value.length; i++) {
      const ch = value[i];
      out += ('A' <= ch && ch <= 'Z') || ('a' <= ch && ch <= 'z')
        || ('0' <= ch && ch <= '9') || ch === '.' || ch === '_' || ch === '-' ? ch : '_';
    }
    return out;
  }

  /** 32-bit FNV-1a of the string as lowercase hex. */
  static hashHex(value: string): string {
    let hash = 0x811c9dc5;
    for (let i = 0; i < value.length; i++) {
      hash ^= value.charCodeAt(i);
      hash = Math.imul(hash, 0x01000193) >>> 0;
    }
    return (hash >>> 0).toString(16).padStart(8, '0');
  }
}

/**
 * Transport selection, mirroring resolveDownloadTransportKind: HLS streams
 * download as HLS; everything else starts as DIRECT (chunked-range upgrade
 * is decided by the engine when the source advertises ranges).
 */
export class DownloadTransportSelector {
  static select(isHls: boolean, supportsRanges: boolean, hasExplicitRangeHeader: boolean): DownloadTransportKind {
    if (isHls) {
      return DownloadTransportKind.HLS;
    }
    if (supportsRanges && !hasExplicitRangeHeader) {
      return DownloadTransportKind.CHUNKED_RANGE;
    }
    return DownloadTransportKind.DIRECT;
  }
}
