import { SongItem } from '../../model/SongItem';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { DownloadEngine } from '../../download/DownloadEngine';
import { Theme } from '../Theme';
import { formatDuration, platformName } from './Ui';

@Component
export struct SongRow {
  @Prop songJson: string;
  @Prop index: number = -1;
  @Prop showPlatform: boolean = false;
  onPlay: () => void = () => {};

  @State menuOpen: boolean = false;
  @State favorite: boolean = false;

  private song(): SongItem {
    return this.songJson.length > 0 ? SongItem.fromJson(this.songJson) : new SongItem();
  }

  async aboutToAppear(): Promise<void> {
    this.favorite = await LocalPlaylistRepository.isFavorite(this.song());
  }

  private async toggleFavorite(): Promise<void> {
    const song = this.song();
    if (this.favorite) {
      await LocalPlaylistRepository.removeFavorite(song);
      this.favorite = false;
    } else {
      await LocalPlaylistRepository.addFavorite(song);
      this.favorite = true;
    }
    this.menuOpen = false;
  }

  private download(): void {
    DownloadEngine.enqueue([this.song()]);
    this.menuOpen = false;
  }

  build() {
    Column({ space: 2 }) {
      Row({ space: 12 }) {
        Stack() {
          if (this.song().effectiveCoverUrl.length > 0) {
            Image(this.song().effectiveCoverUrl)
              .width(52)
              .height(52)
              .borderRadius(8)
              .objectFit(ImageFit.Cover)
              .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          } else {
            Text('♫')
              .fontSize(20)
              .width(52)
              .height(52)
              .textAlign(TextAlign.Center)
              .fontColor(Theme.primary(Theme.isDark()))
              .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
              .borderRadius(8)
          }
          if (this.index >= 0) {
            Text(`${this.index + 1}`)
              .fontSize(11)
              .fontColor(Theme.textSecondary(Theme.isDark()))
              .padding({ left: 4, right: 4, top: 2, bottom: 2 })
              .backgroundColor(Theme.scrim(Theme.isDark()))
              .borderRadius(6)
              .position({ x: '72%', y: '2%' })
          }
        }

        Column({ space: 3 }) {
          Row({ space: 6 }) {
            Text(this.song().displayName)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary(Theme.isDark()))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.showPlatform) {
              Text(platformName(this.song().platform))
                .fontSize(10)
                .fontColor(Theme.primary(Theme.isDark()))
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor(Theme.primaryContainer(Theme.isDark()))
                .borderRadius(6)
            }
          }
          .width('100%')

          Text(this.song().displayArtist)
            .fontSize(12)
            .fontColor(Theme.textSecondary(Theme.isDark()))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.song().durationMs > 0) {
          Text(formatDuration(this.song().durationMs))
            .fontSize(12)
            .fontColor(Theme.textSecondary(Theme.isDark()))
        }

        Text('⋯')
          .fontSize(18)
          .fontColor(Theme.textSecondary(Theme.isDark()))
          .padding(8)
          .onClick(() => {
            this.menuOpen = !this.menuOpen;
          })
      }
      .width('100%')
      .padding({ left: 10, right: 6, top: 7, bottom: 7 })
      .onClick(() => this.onPlay())

      if (this.menuOpen) {
        Column({ space: 2 }) {
          MenuItemRow({
            label: this.favorite ? '取消收藏' : '收藏',
            onTap: () => this.toggleFavorite()
          })
          MenuItemRow({
            label: '加入歌单',
            onTap: () => {
              this.menuOpen = false;
            }
          })
          MenuItemRow({
            label: '下载',
            onTap: () => this.download()
          })
          MenuItemRow({
            label: '分享',
            onTap: () => {
              this.menuOpen = false;
            }
          })
        }
        .width('100%')
        .padding(8)
        .backgroundColor(Theme.surfaceHigh(Theme.isDark()))
        .borderRadius(12)
        .shadow(Theme.shadow(Theme.isDark()))
        .margin({ bottom: 6 })
      }
    }
    .width('100%')
  }
}

@Component
struct MenuItemRow {
  label: string = '';
  onTap: () => void = () => {};

  build() {
    Text(this.label)
      .fontSize(14)
      .fontColor(Theme.textPrimary(Theme.isDark()))
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .onClick(() => this.onTap())
  }
}
