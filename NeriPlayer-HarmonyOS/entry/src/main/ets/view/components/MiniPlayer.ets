import { SongItem } from '../../model/SongItem';
import { PlaybackStatus } from '../../player/PlaybackConstants';
import { PlayerManager } from '../../player/PlayerManager';
import { Router } from '../Router';
import { Theme } from '../Theme';
import { platformName } from './Ui';

@Component
export struct MiniPlayer {
  @StorageLink('player.currentSong') currentSongJson: string = '';
  @StorageLink('player.status') status: number = PlaybackStatus.IDLE;
  @StorageLink('player.positionMs') positionMs: number = 0;
  @StorageLink('player.durationMs') durationMs: number = 0;

  private song(): SongItem {
    return this.currentSongJson.length > 0 ? SongItem.fromJson(this.currentSongJson) : new SongItem();
  }

  build() {
    Column() {
      Progress({
        value: this.durationMs > 0 ? this.positionMs / this.durationMs : 0,
        type: ProgressType.Linear
      })
        .width('100%')
        .height(2)
        .color(Theme.primary(Theme.isDark()))
        .backgroundColor('#22000000')

      Row({ space: 12 }) {
        Stack() {
          if (this.song().effectiveCoverUrl.length > 0) {
            Image(this.song().effectiveCoverUrl)
              .width(44)
              .height(44)
              .borderRadius(8)
              .objectFit(ImageFit.Cover)
          } else {
            Text('♫')
              .width(44)
              .height(44)
              .textAlign(TextAlign.Center)
              .fontSize(18)
              .fontColor(Theme.primary(Theme.isDark()))
              .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
              .borderRadius(8)
          }
        }

        Column({ space: 2 }) {
          Row({ space: 6 }) {
            Text(this.song().displayName)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary(Theme.isDark()))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(platformName(this.song().platform))
              .fontSize(9)
              .fontColor(Theme.primary(Theme.isDark()))
              .padding({ left: 5, right: 5, top: 1, bottom: 1 })
              .backgroundColor(Theme.primaryContainer(Theme.isDark()))
              .borderRadius(5)
          }
          .width('100%')

          Text(this.song().displayArtist)
            .fontSize(11)
            .fontColor(Theme.textSecondary(Theme.isDark()))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button() {
          Image(this.status === PlaybackStatus.PLAYING
            ? $r('app.media.round_pause_24')
            : $r('app.media.round_play_arrow_24'))
            .width(22)
            .height(22)
            .fillColor('#FFFFFF')
        }
        .width(40)
        .height(40)
        .type(ButtonType.Circle)
        .backgroundColor(Theme.primary(Theme.isDark()))
        .onClick(() => {
          PlayerManager.togglePlayPause();
        })

        Button() {
          Image($r('app.media.round_skip_next_24'))
            .width(22)
            .height(22)
            .fillColor(Theme.textPrimary(Theme.isDark()))
        }
        .width(36)
        .height(36)
        .type(ButtonType.Circle)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          PlayerManager.next(false);
        })
      }
      .width('100%')
      .height(60)
      .padding({ left: 12, right: 8 })
      .onClick(() => {
        Router.push(Router.NOW_PLAYING);
      })
    }
    .width('100%')
    .backgroundColor(Theme.surface(Theme.isDark()))
    .borderRadius(16)
    .clip(true)
    .margin({ left: 10, right: 10, bottom: 8 })
    .shadow({ radius: 12, color: '#22000000', offsetY: 2 })
  }
}
