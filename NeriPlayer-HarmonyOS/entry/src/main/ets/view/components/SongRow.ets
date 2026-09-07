import { SongItem } from '../../model/SongItem';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { DownloadEngine } from '../../download/DownloadEngine';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';

import { formatDuration, platformName } from './Ui';

@Component
export struct SongRow {
  /**
   * S5: 订阅封面配色（M7.4：build 里读成员才追得上换歌重染色）。
   */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @Prop songJson: string;
  @Prop index: number = -1;
  @Prop showPlatform: boolean = false;
  /** >= 0 时在行尾展示播放次数（播放历史页）。 */
  @Prop playCount: number = -1;
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


  private schemeSurface(): string {
    const hasScheme = this.coverScheme.light.background.length > 0;
    return hasScheme ? Theme.surfaceHigh(Theme.isDark()) : Theme.surfaceHigh(Theme.isDark());
  }
  build() {
    Column({ space: 2 }) {
      Row({ space: 12 }) {
        // The badge used a percentage .position(), which resolves against the
        // Stack's measured width; at 1.45x system font that width grew and the
        // badge landed on top of the duration text (device audit 2026-08-24).
        // Pinning the box and aligning to a corner is font-size independent.
        Stack({ alignContent: Alignment.TopEnd }) {
          if (this.song().effectiveCoverUrl.length > 0) {
            Image(this.song().effectiveCoverUrl)
              .width(52)
              .height(52)
              .borderRadius(8)
              .objectFit(ImageFit.Cover)
              .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          } else {
            Image($r('app.media.ic_music_note_24'))
              .width(22)
              .height(22)
              .fillColor(Theme.primary(Theme.isDark()))
              .margin({ left: 15, right: 15, top: 15, bottom: 15 })
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
              .margin({ top: 2, right: 2 })
          }
        }
        .width(52)
        .height(52)

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

        if (this.playCount >= 0) {
          Row({ space: 2 }) {
            Text(`${this.playCount}`)
              .fontSize(12)
              .fontColor(Theme.textSecondary(Theme.isDark()))
            Image($r('app.media.round_play_arrow_24'))
              .width(12)
              .height(12)
              .fillColor(Theme.textSecondary(Theme.isDark()))
          }
          .margin({ left: 4 })
        }

        if (this.song().durationMs > 0) {
          Text(formatDuration(this.song().durationMs))
            .fontSize(12)
            .fontColor(Theme.textSecondary(Theme.isDark()))
        }

        Image($r('app.media.ic_more_horiz_24'))
          // 18vp glyph inside a 40vp box: padding keeps the icon the same size
          // while the tap area reaches the 40vp floor.
          .width(40)
          .height(40)
          .fillColor(Theme.textSecondary(Theme.isDark()))
          .padding(11)
          .accessibilityText('更多操作')
          .onClick(() => {
            this.menuOpen = !this.menuOpen;
          })
      }
      .width('100%')
      .padding({ left: 10, right: 6, top: 7, bottom: 7 })
      .backgroundColor(this.schemeSurface())
      .onClick(() => this.onPlay())
      .clickEffect({ level: ClickEffectLevel.LIGHT })

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
