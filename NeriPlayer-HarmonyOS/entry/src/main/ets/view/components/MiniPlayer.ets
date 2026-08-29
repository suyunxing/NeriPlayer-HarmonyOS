import { SongItem } from '../../model/SongItem';
import { PlaybackStatus } from '../../player/PlaybackConstants';
import { PlayerManager } from '../../player/PlayerManager';
import { Router } from '../Router';
import { Theme } from '../Theme';
import { platformName } from './Ui';
import { MotionSpec } from '../theme/MotionSpec';
import { MotionCurves } from '../theme/MotionCurves';

@Component
export struct MiniPlayer {
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
  // Invalidates the onFinish chain of a release animation that a newer
  // gesture/release has interrupted, so a stale stage-two or track switch
  // never fires into unrelated state.
  private releaseGeneration: number = 0;

  private static readonly SWIPE_TRIGGER_VP = 72;
  private static readonly SWIPE_MAX_OFFSET_VP = 52;

  private resistedOffset(rawOffset: number): number {
    const direction = rawOffset >= 0 ? 1 : -1;
    const magnitude = MiniPlayer.SWIPE_MAX_OFFSET_VP * (1 - Math.exp(-Math.abs(rawOffset) / 160));
    return direction * magnitude;
  }

  /**
   * Two-stage release, porting NeriMiniPlayer.animateSwipeRelease: flick to
   * ±52vp over 120ms, fall back to 0 over 180ms, and switch the track only
   * after both stages complete — Android fires onPrevious/onNext from the
   * coroutine's end, after the whole motion.
   */
  private animateSwipeRelease(direction: number, onCompleted: () => void): void {
    this.releaseGeneration += 1;
    const generation = this.releaseGeneration;
    animateTo({
      duration: MotionSpec.SWIPE_RELEASE_STAGE_MS,
      curve: MotionCurves.fastOutSlowIn(),
      onFinish: () => {
        if (generation !== this.releaseGeneration) {
          return;
        }
        animateTo({
          duration: MotionSpec.SWIPE_RELEASE_RETURN_MS,
          curve: MotionCurves.fastOutSlowIn(),
          onFinish: () => {
            if (generation === this.releaseGeneration) {
              onCompleted();
            }
          }
        }, () => {
          this.swipeOffset = 0;
          this.swiping = false;
        });
      }
    }, () => {
      // swiping stays true through stage one: the 0.975 grip scale matches
      // Android's offsetRatio peak (52/52) at the flick apex.
      this.swipeOffset = direction * MiniPlayer.SWIPE_MAX_OFFSET_VP;
    });
  }

  /** Under-threshold or cancelled drag: plain spring-back to rest (Android 160ms tween). */
  private animateSwipeReturn(durationMs: number): void {
    this.releaseGeneration += 1;
    animateTo({ duration: durationMs, curve: MotionCurves.fastOutSlowIn() }, () => {
      this.swipeOffset = 0;
      this.swiping = false;
    });
  }

  private song(): SongItem {
    return this.currentSongJson.length > 0 ? SongItem.fromJson(this.currentSongJson) : new SongItem();
  }

  private onCoverSeedChanged(): void {
    this.seedHex = this.coverSeedHex;
  }

  build() {
    Column() {
      // Progress 的 total 不给就是 100，原来喂进去的是 0..1 的比例，播到一半也只
      // 有 0.5% 的填充（tablet 上像素采样实测：播放 11% 时整条都是轨道色）。改成
      // 直接把毫秒喂给 value/total，单位自洽（同 DownloadsPage 的 value+total 写法）。
      Progress({
        value: this.positionMs,
        total: this.durationMs > 0 ? this.durationMs : 1,
        type: ProgressType.Linear
      })
        .width('100%')
        .height(2)
        .color(this.seedHex.length > 0
          ? Theme.primaryFor(this.seedHex, Theme.isDark())
          : Theme.primary(Theme.isDark()))
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
              .fillColor(Theme.primary(Theme.isDark()))
              .margin({ left: 11, right: 11, top: 11, bottom: 11 })
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
        .backgroundColor(this.seedHex.length > 0
          ? Theme.primaryFor(this.seedHex, Theme.isDark())
          : Theme.primary(Theme.isDark()))
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
            .fillColor(Theme.textPrimary(Theme.isDark()))
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
            // A new finger invalidates any release animation still flying.
            this.releaseGeneration += 1;
          })
          .onActionUpdate((event: GestureEvent) => {
            this.swipeOffset = this.resistedOffset(event.offsetX);
          })
          .onActionEnd((event: GestureEvent) => {
            if (event.offsetX >= MiniPlayer.SWIPE_TRIGGER_VP) {
              this.animateSwipeRelease(1, () => PlayerManager.previous());
            } else if (event.offsetX <= -MiniPlayer.SWIPE_TRIGGER_VP) {
              this.animateSwipeRelease(-1, () => PlayerManager.next(false));
            } else {
              this.animateSwipeReturn(MotionSpec.SWIPE_CANCEL_MS);
            }
          })
          .onActionCancel(() => {
            this.animateSwipeReturn(MotionSpec.SWIPE_CANCEL_MS);
          })
      )
      .translate({ x: this.swipeOffset })
      .scale(this.swiping ? { x: 0.975, y: 0.975 } : { x: 1, y: 1 })
    }
    .width('100%')
    .backgroundColor(this.glassEffect ? Theme.surfaceGlass(Theme.isDark()) : Theme.surface(Theme.isDark()))
    .backgroundBlurStyle(this.glassEffect ? BlurStyle.COMPONENT_THICK : BlurStyle.NONE)
    .borderRadius(16)
    .clip(true)
    .margin({ left: 10, right: 10, bottom: 8 })
    .shadow({ radius: 12, color: '#22000000', offsetY: 2 })
  }
}
