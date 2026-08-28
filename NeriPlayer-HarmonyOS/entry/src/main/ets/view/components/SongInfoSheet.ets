import { SongItem } from '../../model/SongItem';
import { MusicPlatform } from '../../model/MusicPlatform';
import { Constants } from '../../app/Constants';
import { DownloadStorage } from '../../download/DownloadStorage';
import { extractYouTubeMusicVideoId } from '../../model/SongIdentity';
import { Theme } from '../Theme';
import { formatDuration, platformName } from './Ui';
import { BottomSheetPanel } from './BottomSheetPanel';

/** 「获取歌曲信息」面板：只读展示当前歌曲的元数据与本地状态。 */
@Component
export struct SongInfoSheet {
  songJson: string = '';
  onClose: () => void = () => {};
  @State downloadedPath: string = '';

  private song(): SongItem {
    return this.songJson.length > 0 ? SongItem.fromJson(this.songJson) : new SongItem();
  }

  async aboutToAppear(): Promise<void> {
    const entry = await DownloadStorage.findCatalogEntry(this.song());
    this.downloadedPath = entry !== null ? entry.audioPath : '';
  }

  private albumText(): string {
    const album = this.song().album.trim();
    // youtube_music is the YTM identity placeholder, not a real album name.
    if (album.length === 0 || album === Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM) {
      return '';
    }
    return album;
  }

  private sourceId(): string {
    const song = this.song();
    const videoId = extractYouTubeMusicVideoId(song.mediaUri);
    if (videoId.length > 0) {
      return videoId;
    }
    const audioId = song.audioId.trim();
    if (audioId.length > 0) {
      return audioId;
    }
    if (song.platform === MusicPlatform.NETEASE && song.id > 0) {
      return `${song.id}`;
    }
    return '';
  }

  @Builder
  infoRow(label: string, value: string) {
    Row({ space: 12 }) {
      Text(label)
        .fontSize(13)
        .fontColor(Theme.textSecondary(Theme.isDark()))
        .width(76)
      Text(value.length > 0 ? value : '—')
        .fontSize(14)
        .fontColor(Theme.textPrimary(Theme.isDark()))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .copyOption(CopyOptions.LocalDevice)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  build() {
    BottomSheetPanel({
      title: '歌曲信息',
      onClose: () => this.onClose()
    }) {
      Column() {
        this.infoRow('标题', this.song().displayName)
        this.infoRow('歌手', this.song().displayArtist)
        this.infoRow('专辑', this.albumText())
        if (this.song().durationMs > 0) {
          this.infoRow('时长', formatDuration(this.song().durationMs))
        }
        this.infoRow('平台', platformName(this.song().platform))
        if (this.sourceId().length > 0) {
          this.infoRow('来源 ID', this.sourceId())
        }
        this.infoRow('下载状态', this.downloadedPath.length > 0 ? '已下载' : '未下载')
        if (this.downloadedPath.length > 0) {
          this.infoRow('本地文件', this.downloadedPath)
        } else if (this.song().localFilePath.length > 0) {
          this.infoRow('本地文件', this.song().localFilePath)
        }
      }
      .width('100%')
    }
  }
}
