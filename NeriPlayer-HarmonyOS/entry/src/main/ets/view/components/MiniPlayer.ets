import { SongItem } from '../../model/SongItem';
import { PlaybackStatus } from '../../player/PlaybackConstants';
import { PlayerManager } from '../../player/PlayerManager';
import { Router } from '../Router';
import { Theme } from '../Theme';
import { platformName } from './Ui';

@Component
export struct MiniPlayer {
  @StorageProp('theme.isDark') isDark: boolean = false; // see Theme.IS_DARK_KEY
  @StorageLink('player.currentSong') currentSongJson: string = '';
  @StorageLink('player.status') status: number = PlaybackStatus.IDLE;
  @StorageLink('player.positionMs') positionMs: number = 0;
  @StorageLink('player.durationMs') durationMs: number = 0;
  // Mirror the cover seed into @State and read it directly in the accent
  // expressions: AppStorage reads hidden inside Theme.* calls are invisible
  // to minimal-update tracking (M7.4 pitfall), so the raw copy is required.
  @StorageProp('player.coverSeedHex') @Watch('onCoverSeedChanged') coverSeedHex: string = '';
  @StorageProp('np.glass_effect') glassEffect: boolean = true;
  @State seedHex: string = '';
  // Horizontal swipe-to-skip (Android NeriMiniPlayer: 72vp raw threshold,
  // visual offset eased with exponential resistance peaking at 52vp).
  @State swipeOffset: number = 0;
  @State swiping: boolean = false;

  private static readonly SWIPE_TRIGGER_VP = 72;
  private static readonly SWIPE_MAX_OFFSET_VP = 52;

  private resistedOffset(rawOffset: number): number {
    const direction = rawOffset >= 0 ? 1 : -1;
    const magnitude = MiniPlayer.SWIPE_MAX_OFFSET_VP * (1 - Math.exp(-Math.abs(rawOffset) / 160));
    return direction * magnitude;
  }

  private song(): SongItem {
    return this.currentSongJson.length > 0 ? SongItem.fromJson(this.currentSongJson) : new SongItem();
  }

  private onCoverSeedChanged(): void {
    this.seedHex = this.coverSeedHex;
  }

  build() {
    Column() {
      Progress({
        value: this.durationMs > 0 ? this.positionMs / this.durationMs : 0,
        type: ProgressType.Linear
      })
        .width('100%')
        .height(2)
        .color(this.seedHex.length > 0
          ? Theme.primaryFor(this.seedHex, this.isDark)
          : Theme.primary(this.isDark))
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
            Image($r('app.media.ic_music_note_24'))
              .width(22)
              .height(22)
              .fillColor(Theme.primary(this.isDark))
              .margin({ left: 11, right: 11, top: 11, bottom: 11 })
              .backgroundColor(Theme.surfaceVariant(this.isDark))
              .borderRadius(8)
          }
        }

        Column({ space: 2 }) {
          Row({ space: 6 }) {
            Text(this.song().displayName)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary(this.isDark))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(platformName(this.song().platform))
              .fontSize(9)
              .fontColor(Theme.primary(this.isDark))
              .padding({ left: 5, right: 5, top: 1, bottom: 1 })
              .backgroundColor(Theme.primaryContainer(this.isDark))
              .borderRadius(5)
          }
          .width('100%')

          Text(this.song().displayArtist)
            .fontSize(11)
            .fontColor(Theme.textSecondary(this.isDark))
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
        .backgroundColor(this.seedHex.length > 0
          ? Theme.primaryFor(this.seedHex, this.isDark)
          : Theme.primary(this.isDark))
        // Icon-only control: without an explicit label a screen reader reads
        // nothing at all (device audit 2026-08-24 found 9 such buttons).
        .accessibilityText(this.status === PlaybackStatus.PLAYING ? '暂停' : '播放')
        .onClick(() => {
          PlayerManager.togglePlayPause();
        })

        Button() {
          Image($r('app.media.round_skip_next_24'))
            .width(22)
            .height(22)
            .fillColor(Theme.textPrimary(this.isDark))
        }
        // 36vp measured on device; 40vp is the touch-target floor this port holds to.
        .width(40)
        .height(40)
        .type(ButtonType.Circle)
        .backgroundColor(Color.Transparent)
        .accessibilityText('下一首')
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
      .gesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
          .onActionStart(() => {
            this.swiping = true;
          })
          .onActionUpdate((event: GestureEvent) => {
            this.swipeOffset = this.resistedOffset(event.offsetX);
          })
          .onActionEnd((event: GestureEvent) => {
            if (event.offsetX >= MiniPlayer.SWIPE_TRIGGER_VP) {
              PlayerManager.previous();
            } else if (event.offsetX <= -MiniPlayer.SWIPE_TRIGGER_VP) {
              PlayerManager.next(false);
            }
            animateTo({ duration: 180, curve: Curve.Friction }, () => {
              this.swipeOffset = 0;
              this.swiping = false;
            });
          })
          .onActionCancel(() => {
            animateTo({ duration: 180, curve: Curve.Friction }, () => {
              this.swipeOffset = 0;
              this.swiping = false;
            });
          })
      )
      .translate({ x: this.swipeOffset })
      .scale(this.swiping ? { x: 0.975, y: 0.975 } : { x: 1, y: 1 })
    }
    .width('100%')
    .backgroundColor(this.glassEffect ? Theme.surfaceGlass(this.isDark) : Theme.surface(this.isDark))
    .backgroundBlurStyle(this.glassEffect ? BlurStyle.COMPONENT_THICK : BlurStyle.NONE)
    .borderRadius(16)
    .clip(true)
    .margin({ left: 10, right: 10, bottom: 8 })
    .shadow({ radius: 12, color: '#22000000', offsetY: 2 })
  }
}
