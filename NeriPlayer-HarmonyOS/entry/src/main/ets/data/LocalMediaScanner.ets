// SPDX-License-Identifier: GPL-3.0

import { picker, fileIo } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { common } from '@kit.AbilityKit';
import { Logger } from '../app/Logger';
import { SongItem } from '../model/SongItem';
import { MusicPlatform } from '../model/MusicPlatform';
import { DownloadedSongEntry, DownloadStorage } from '../download/DownloadStorage';

/**
 * Local audio import using the system audio picker + AVMetadataExtractor.
 *
 * API 24: the legacy mediaLibrary API is no longer available, so local audio is
 * selected by the user through AudioViewPicker (scoped access, no permission
 * needed) and metadata is read through AVMetadataExtractor (await + fdSrc).
 */

function stripFileScheme(path: string): string {
  return path.startsWith('file://') ? path.substring('file://'.length) : path;
}

/**
 * Pure matcher (backlog §1.2): links a locally imported file back to its
 * download-catalog entry so the original remote identity can be restored via
 * SongItem.sourceStableKey. Exact path match first (file:// schemes stripped),
 * then a same-filename fallback for picker URIs that reserialize differently.
 */
export function matchDownloadedEntry(song: SongItem, catalog: DownloadedSongEntry[]): DownloadedSongEntry | null {
  const filePath = stripFileScheme(song.localFilePath);
  if (filePath.length > 0) {
    for (const entry of catalog) {
      if (stripFileScheme(entry.audioPath) === filePath) {
        return entry;
      }
    }
  }
  const fileName = song.localFileName;
  if (fileName.length > 0) {
    for (const entry of catalog) {
      const base = entry.audioPath.substring(entry.audioPath.lastIndexOf('/') + 1);
      if (base === fileName) {
        return entry;
      }
    }
  }
  return null;
}

export class LocalMediaScanner {
  private static cached: SongItem[] = [];

  static async scan(context: common.Context, limit: number = 500): Promise<SongItem[]> {
    const songs: SongItem[] = [];
    try {
      const audioPicker = new picker.AudioViewPicker(context);
      const options = new picker.AudioSelectOptions();
      options.maxSelectNumber = limit;
      const uris: string[] = await audioPicker.select(options);
      const catalog = await DownloadStorage.getCatalog();
      for (const uri of uris) {
        const song = await LocalMediaScanner.inspect(uri);
        if (song !== null) {
          const downloaded = matchDownloadedEntry(song, catalog);
          if (downloaded !== null) {
            song.sourceStableKey = downloaded.stableKey;
          }
          songs.push(song);
        }
      }
    } catch (error) {
      const e = error as Error;
      Logger.warn(`LocalMediaScanner.scan failed: ${e.message}`);
    }
    if (songs.length > 0) {
      LocalMediaScanner.cached = songs;
    }
    return songs;
  }

  static async loadCached(): Promise<SongItem[]> {
    return LocalMediaScanner.cached;
  }

  private static async inspect(uri: string): Promise<SongItem | null> {
    let file: fileIo.File | null = null;
    let extractor: media.AVMetadataExtractor | null = null;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(uri);
      const song = new SongItem(0, file.name, '', '', 0, 0, '', uri, MusicPlatform.LOCAL);
      song.localFileName = file.name;
      song.localFilePath = uri;

      extractor = await media.createAVMetadataExtractor();
      const descriptor: media.AVFileDescriptor = { fd: file.fd, offset: 0, length: stat.size };
      extractor.fdSrc = descriptor;
      const metadata = await extractor.fetchMetadata();
      const title = metadata.title ?? '';
      if (title.length > 0) {
        song.name = title;
      }
      song.artist = metadata.artist ?? '';
      song.album = metadata.album ?? '';
      song.durationMs = Number(metadata.duration ?? 0);
      return song;
    } catch (error) {
      const e = error as Error;
      Logger.debug(`LocalMediaScanner.inspect metadata failed: ${e.message}`);
      return null;
    } finally {
      try {
        if (extractor !== null) {
          extractor.release();
        }
      } catch (error) {
        const e = error as Error;
        Logger.debug(`LocalMediaScanner.extractor.release failed: ${e.message}`);
      }
      try {
        if (file !== null) {
          fileIo.closeSync(file);
        }
      } catch (error) {
        const e = error as Error;
        Logger.debug(`LocalMediaScanner.file.close failed: ${e.message}`);
      }
    }
  }
}
