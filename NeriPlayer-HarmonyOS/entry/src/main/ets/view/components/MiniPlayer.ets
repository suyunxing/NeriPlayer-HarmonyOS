// ReplaceSymbolEffect/EffectScope 是 symbolglyph.d.ts 的全局 ambient 类
// （与 VisualEffect 同类），不从 kit 导入。
import { curves } from '@kit.ArkUI';
import { SongItem } from '../../model/SongItem';
import { PlaybackStatus } from '../../player/PlaybackConstants';
import { PlayerManager } from '../../player/PlayerManager';
import { Router } from '../Router';
import { Theme } from '../Theme';
import { platformName } from './Ui';

@Component
export struct MiniPlayer {
  /**
   * S5 修复：官方 HdsTabsMiniBar 槽位高度有限，嵌入时用紧凑形态
   * （去进度条、48vp 行、去外边距），独立悬浮形态才用完整卡片。
   */
  @Prop compact: boolean = false;
  @StorageLink('player.currentSong') currentSongJson: string = '';
  @StorageLink('player.status') @Watch('onStatusChanged') status: number = PlaybackStatus.IDLE;
  /** ReplaceSymbolEffect 触发计数：播放/暂停切换时 +1 驱动交叉淡入。 */
  @State symbolTrigger: number = 0;
  private replaceEffect: ReplaceSymbolEffect = new ReplaceSymbolEffect(EffectScope.WHOLE);
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

  private onStatusChanged(): void {
    this.symbolTrigger += 1;
  }

  build() {
    Column() {
      if (!this.compact) {
        // Progress 的 total 不给就是 100，原来喂进去的是 0..1 的比例，播到一半也只
        // 有 0.5% 的填充（tablet 上像素采样实测：播放 11% 时整条都是轨道色）。改成
        // 直接把毫秒喂给 value/total，单位自洽（同 DownloadsPage 的 value+total 写法）。
        // 紧凑形态（HdsTabsMiniBar 槽位）没有这条高度，进度看播放页波形条。
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
      }

      Row({ space: this.compact ? 8 : 12 }) {
        Stack() {
          if (this.song().effectiveCoverUrl.length > 0) {
            Image(this.song().effectiveCoverUrl)
              .width(this.compact ? 32 : 44)
              .height(this.compact ? 32 : 44)
              .borderRadius(this.compact ? 16 : 8)
              .objectFit(ImageFit.Cover)
              // S6 一镜到底：与播放页封面共享元素（打断保护靠 .id()）。
              .geometryTransition('np.cover')
              .id('np_cover_mini')
              .transition(TransitionEffect.OPACITY)
          } else {
            Image($r('app.media.ic_music_note_24'))
              .width(this.compact ? 16 : 22)
              .height(this.compact ? 16 : 22)
              .fillColor(Theme.primary(Theme.isDark()))
              .margin(this.compact
                ? { left: 8, right: 8, top: 8, bottom: 8 }
                : { left: 11, right: 11, top: 11, bottom: 11 })
              .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
              .borderRadius(this.compact ? 16 : 8)
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
          // S6: 官方符号替换动效（CROSS_FADE），播放/暂停切换不再是硬切。
          SymbolGlyph(this.status === PlaybackStatus.PLAYING
            ? $r('sys.symbol.pause_fill')
            : $r('sys.symbol.play_fill'))
            .fontSize(22)
            .fontColor(['#FFFFFF'])
            .symbolEffect(this.replaceEffect, this.symbolTrigger)
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
      .height(this.compact ? 40 : 60)
      .padding({ left: this.compact ? 6 : 12, right: this.compact ? 2 : 8 })
      .onClick(() => {
        // 一镜到底：push 放进 animateTo 闭包并关闭单次系统转场，
        // geometryTransition('np.cover') 接管封面过渡（官方共享元素范式）。
        this.getUIContext().animateTo(
          { curve: curves.interpolatingSpring(0, 1, 328, 36) },
          () => {
            Router.push(Router.NOW_PLAYING);
          });
      })
      .clickEffect({ level: ClickEffectLevel.LIGHT })
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
            this.getUIContext().animateTo({ duration: 180, curve: Curve.Friction }, () => {
              this.swipeOffset = 0;
              this.swiping = false;
            });
          })
          .onActionCancel(() => {
            this.getUIContext().animateTo({ duration: 180, curve: Curve.Friction }, () => {
              this.swipeOffset = 0;
              this.swiping = false;
            });
          })
      )
      .translate({ x: this.swipeOffset })
      .scale(this.swiping ? { x: 0.975, y: 0.975 } : { x: 1, y: 1 })
    }
    .width('100%')
    .backgroundColor(this.glassEffect ? Theme.surfaceGlass(Theme.isDark()) : Theme.surface(Theme.isDark()))
    .backgroundBlurStyle(this.glassEffect ? BlurStyle.COMPONENT_THICK : BlurStyle.NONE)
    .borderRadius(this.compact ? 24 : 16)
    .clip(true)
    .margin(this.compact ? { left: 0, right: 0, bottom: 0 } : { left: 10, right: 10, bottom: 8 })
    .shadow(this.compact ? { radius: 0, color: '#00000000' } : { radius: 12, color: '#22000000', offsetY: 2 })
  }
}
