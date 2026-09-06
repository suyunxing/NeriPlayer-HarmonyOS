import { SongItem } from '../model/SongItem';
import { MusicPlatform } from '../model/MusicPlatform';
import { extractYouTubeMusicVideoId } from '../model/SongIdentity';

/**
 * Best-effort public links and share text for a song's source platform. Pure
 * functions so link building stays unit-testable.
 */
export class ShareLinks {
  /** Public page of the song on its platform; '' when no id is known. */
  static songLink(song: SongItem): string {
    switch (song.platform) {
      case MusicPlatform.NETEASE: {
        const raw = song.audioId.trim();
        const id = Number(raw.length > 0 ? raw : `${song.id}`);
        return id > 0 ? `https://music.163.com/song/?id=${id}` : '';
      }
      case MusicPlatform.BILIBILI: {
        const id = song.audioId.trim();
        return id.length > 0 ? `https://www.bilibili.com/video/${id}` : '';
      }
      case MusicPlatform.YOUTUBE_MUSIC: {
        const videoId = extractYouTubeMusicVideoId(song.mediaUri);
        const id = videoId.length > 0 ? videoId : song.audioId.trim();
        return id.length > 0 ? `https://music.youtube.com/watch?v=${id}` : '';
      }
      default:
        return '';
    }
  }

  /** 'name - artist' share text (honors user-edited names). */
  static songText(song: SongItem): string {
    const artist = song.displayArtist.trim();
    return artist.length > 0 ? `${song.displayName} - ${artist}` : song.displayName;
  }
}
