import { SongItem } from '../../model/SongItem';
import { LyricLine } from '../../model/LyricLine';
import { QueueState } from '../../model/QueueState';
import { SettingsRepository } from '../../data/SettingsRepository';
import { LyricDispatcher } from '../../lyrics/LyricDispatcher';
import { LyricIndexResolver } from '../../lyrics/LyricIndexResolver';
import { LyricLineTracker } from '../../lyrics/LyricLineTracker';
import { PlayerManager } from '../../player/PlayerManager';
import { PlaybackStatus, RepeatMode } from '../../player/PlaybackConstants';
import { Theme } from '../Theme';
import { DynamicTheme } from '../theme/DynamicTheme';
import { LyricView } from '../components/LyricView';
import { WaveformSlider } from '../components/WaveformSlider';
import { LyricShareSheet } from '../components/LyricShareSheet';
import { Router } from '../Router';
import { formatDuration, platformName } from '../components/Ui';

const SPEED_STEPS: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
const SLEEP_OPTIONS: [string, number][] = [
  ['关闭', 0],
  ['10 分钟', 10],
  ['30 分钟', 30],
  ['1 小时', 60],
  ['播完当前', -1],
  ['播完列表', -2]
];

@Component
export struct NowPlayingPage {
  // Watched, not just read: the accent backdrop is derived from the cover seed
  // *and* the resolved theme, so a light/dark switch has to recompute it too.
  @StorageProp('theme.isDark') @Watch('onCoverSeedChanged') isDark: boolean = false;
  @StorageLink('player.currentSong') @Watch('onSongJsonChanged') currentSongJson: string = '';
  @StorageLink('player.status') status: number = PlaybackStatus.IDLE;
  @StorageLink('player.positionMs') positionMs: number = 0;
  @StorageLink('player.durationMs') durationMs: number = 0;
  @StorageLink('player.shuffle') shuffle: boolean = false;
  @StorageLink('player.repeatMode') repeatMode: number = RepeatMode.ALL;
  @StorageLink('player.speed') speed: number = 1.0;
  @StorageLink('player.queueJson') queueJson: string = '';
  // Published by PlayerManager rather than read locally, so toggling from the
  // media control center keeps this button in sync (M10.1).
  @StorageLink('player.favorite') favorite: boolean = false;

  @State lyrics: LyricLine[] = [];
  // Persisted, not local @State: np.show_lyrics is a user setting, and a local
  // copy reset the view back to lyrics on every entry to this page while the
  // stored preference was never read by anyone (static audit 2026-08-25).
  @StorageProp('np.show_lyrics') showLyrics: boolean = true;
  // Read for the share sheet's initial selection, which has to match the line
  // LyricView is highlighting.
  @StorageProp('np.lyric_offset_ms') lyricOffsetMs: number = 0;
  @State showQueue: boolean = false;
  @State showSleep: boolean = false;
  @State showShare: boolean = false;
  @State sleepLabel: string = '关闭';
  @StorageLink('player.sleepActive') sleepActive: boolean = false;
  @StorageLink('player.sleepRemainingMin') sleepRemainingMin: number = 0;
  @State previewMs: number = -1;
  // Cover-seed backdrop (Android NowPlayingAccentBackdrop). The raw seed is
  // mirrored into a @State accent computed via @Watch because minimal-update
  // tracking cannot see AppStorage reads inside expressions (M7.4 pitfall).
  @StorageProp('player.coverSeedHex') @Watch('onCoverSeedChanged') coverSeedHex: string = '';
  @StorageProp('np.dynamic_color') @Watch('onCoverSeedChanged') dynamicColor: boolean = true;
  @State accentHex: string = '';
  // Blurred-cover backdrop with track-switch crossfade (Android keeps the old
  // artwork blurred while the new cover fades in). Layer B sits on top; once
  // its fade finishes it collapses into layer A without animation.
  @StorageProp('np.nowplaying_blur_strength') blurStrength: number = 300;
  @State bgUnderUrl: string = '';
  @State bgOverUrl: string = '';
  @State bgOverOpacity: number = 0;
  private crossfadeToken: number = 0;

  private song(): SongItem {
    return this.currentSongJson.length > 0 ? SongItem.fromJson(this.currentSongJson) : new SongItem();
  }

  private queue(): QueueState {
    return this.queueJson.length > 0 ? QueueState.fromJson(this.queueJson) : new QueueState();
  }

  async aboutToAppear(): Promise<void> {
    this.recomputeAccent();
    this.bgUnderUrl = this.song().effectiveCoverUrl;
    this.bgOverUrl = '';
    this.bgOverOpacity = 0;
    await this.reloadSongData();
  }

  private onSongJsonChanged(): void {
    this.transitionCover(this.song().effectiveCoverUrl);
  }

  /**
   * Crossfades the blurred backdrop to the next cover: layer B fades in over
   * the still-visible old layer, then collapses into layer A. Same-URL and
   * empty-URL switches short-circuit without animation.
   */
  private transitionCover(nextUrl: string): void {
    if (nextUrl === this.bgUnderUrl && this.bgOverUrl.length === 0) {
      return;
    }
    this.crossfadeToken += 1;
    const token = this.crossfadeToken;
    if (nextUrl.length === 0) {
      this.bgUnderUrl = '';
      this.bgOverUrl = '';
      this.bgOverOpacity = 0;
      return;
    }
    this.bgOverUrl = nextUrl;
    this.bgOverOpacity = 0;
    animateTo({ duration: 400, curve: Curve.EaseOut }, () => {
      this.bgOverOpacity = 1;
    });
    setTimeout(() => {
      if (token === this.crossfadeToken && this.bgOverUrl === nextUrl) {
        this.bgUnderUrl = nextUrl;
        this.bgOverUrl = '';
        this.bgOverOpacity = 0;
      }
    }, 460);
  }

  private recomputeAccent(): void {
    const seed = this.dynamicColor ? this.coverSeedHex.trim() : '';
    this.accentHex = seed.length > 0 ? DynamicTheme.adjustedAccentColor(seed, this.isDark) : '';
  }

  private onCoverSeedChanged(): void {
    this.recomputeAccent();
  }

  /**
   * Line the share sheet should pre-select. Goes through the same resolver as
   * LyricView and applies np.lyric_offset_ms: the previous hand-rolled scan
   * ignored the offset, so with an offset configured the sheet opened on a
   * different line than the one on screen.
   */
  private currentLyricIndex(): number {
    return LyricIndexResolver.resolve(this.lyrics, this.positionMs + this.lyricOffsetMs, -1);
  }

  private async reloadSongData(): Promise<void> {
    const song = this.song();
    this.lyrics = [];
    LyricLineTracker.getInstance().setLines([]);
    if (song.audioId.length > 0) {
      try {
        this.lyrics = await LyricDispatcher.loadLyrics(song);
        LyricLineTracker.getInstance().setLines(this.lyrics);
      } catch (error) {
        const e = error as Error;
        this.lyrics = [];
        console.warn(`lyrics load failed: ${e.message}`);
      }
    }
  }

  private async toggleFavorite(): Promise<void> {
    // Goes through PlayerManager so the repository write, the AppStorage flag
    // and the AVSession favorite state stay in one place.
    await PlayerManager.toggleFavoriteForCurrentSong();
  }

  private cycleSpeed(): void {
    let nextIndex = SPEED_STEPS.indexOf(this.speed) + 1;
    if (nextIndex >= SPEED_STEPS.length) {
      nextIndex = 0;
    }
    const next = SPEED_STEPS[nextIndex];
    PlayerManager.setSpeed(next);
  }

  private cycleRepeat(): void {
    PlayerManager.cycleRepeatMode();
  }

  /** Announces the current repeat mode; the icon alone carries no label. */
  private repeatLabel(): string {
    if (this.repeatMode === RepeatMode.ONE) {
      return '单曲循环，点击切换';
    }
    return this.repeatMode === RepeatMode.OFF ? '不循环，点击切换' : '列表循环，点击切换';
  }

  private sleepButtonText(): string {
    if (!this.sleepActive) {
      return '定时';
    }
    if (this.sleepRemainingMin > 0) {
      return `${this.sleepRemainingMin} 分钟`;
    }
    return this.sleepLabel === '关闭' ? '定时' : this.sleepLabel;
  }

  private setSleep(option: [string, number]): void {    this.sleepLabel = option[0];
    this.showSleep = false;
    if (option[1] > 0) {
      PlayerManager.setSleepCountdown(option[1]);
    } else if (option[1] === -1) {
      PlayerManager.setSleepFinishCurrent();
    } else if (option[1] === -2) {
      PlayerManager.setSleepFinishPlaylist();
    } else {
      PlayerManager.cancelSleepTimer();
    }
  }

  build() {
    Stack() {
      // Seed-accent backdrop under the blurred cover: prevents black flashes
      // while a cover loads and tints artwork-less songs (Android keeps the
      // same accent layer under its blurred artwork).
      if (this.accentHex.length > 0) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.accentHex)
      }
      // Blurred cover backdrop; np.nowplaying_blur_strength is Android's
      // 0..500 scale mapped onto blur vp (0 disables blur entirely).
      if (this.bgUnderUrl.length > 0) {
        Image(this.bgUnderUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(this.blurStrength * 80 / 500)
          .scale({ x: 1.4, y: 1.4 })
      }
      if (this.bgOverUrl.length > 0) {
        Image(this.bgOverUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(this.blurStrength * 80 / 500)
          .scale({ x: 1.4, y: 1.4 })
          .opacity(this.bgOverOpacity)
      }
      if (this.bgUnderUrl.length === 0 && this.bgOverUrl.length === 0) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Theme.surfaceVariant(this.isDark))
      }
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.scrim(this.isDark))

      Column() {
        Row() {
          Button() {
            Image($r('app.media.ic_arrow_back_24'))
              .width(22)
              .height(22)
              .fillColor('#FFFFFF')
          }
          .width(40)
          .height(40)
          .type(ButtonType.Circle)
          .backgroundColor(Theme.onSurfaceOverlay(this.isDark))
          .accessibilityText('返回')
          .onClick(() => Router.pop())
          Text('正在播放')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Button() {
            Image($r('app.media.ic_group_24'))
              .width(20)
              .height(20)
              .fillColor('#FFFFFF')
          }
          .width(40)
          .height(40)
          .type(ButtonType.Circle)
          .backgroundColor(Theme.onSurfaceOverlay(this.isDark))
          .accessibilityText('一起听')
          .onClick(() => Router.push(Router.LISTEN_TOGETHER))
          Button('⋯')
            .width(40)
            .height(40)
            .type(ButtonType.Circle)
            .backgroundColor(Theme.onSurfaceOverlay(this.isDark))
            .fontColor('#FFFFFF')
            .fontSize(18)
            // '⋯' on its own is read out as punctuation, or skipped entirely.
            .accessibilityText('播放列表')
            .onClick(() => this.showQueue = true)
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 8 })

        // The lyric view has its own empty state ("暂无歌词"); entering it
        // must not depend on lyrics being available (Bilibili/LOCAL songs
        // often have no remote lyric source, Android shows an empty state).
        if (this.showLyrics) {
          LyricView({
            lyrics: this.lyrics,
            onSeek: (timeMs: number) => PlayerManager.seekTo(timeMs)
          })
        } else {
          Column() {
            Stack() {
              if (this.song().effectiveCoverUrl.length > 0) {
                Image(this.song().effectiveCoverUrl)
                  .width('78%')
                  .aspectRatio(1)
                  .borderRadius(22)
                  .objectFit(ImageFit.Cover)
                  .shadow({ radius: 24, color: '#66000000', offsetY: 8 })
              } else {
                Image($r('app.media.ic_music_note_24'))
                  .width('78%')
                  .aspectRatio(1)
                  .objectFit(ImageFit.Contain)
                  .padding({ left: 32, right: 32, top: 32, bottom: 32 })
                  .fillColor(Theme.primary(this.isDark))
                  .backgroundColor(Theme.onSurfaceOverlay(this.isDark))
                  .borderRadius(22)
              }
            }
            .width('100%')
            .layoutWeight(1)

            Column({ space: 8 }) {
              Row({ space: 8 }) {
                Text(this.song().displayName)
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FFFFFF')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Image(this.favorite
                  ? $r('app.media.ic_baseline_favorite_24')
                  : $r('app.media.ic_outline_favorite_24'))
                  .width(24)
                  .height(24)
                  .fillColor(this.favorite ? Theme.danger(false) : '#CCFFFFFF')
                  .padding(6)
                  .onClick(() => this.toggleFavorite())
              }
              .width('100%')

              Row({ space: 8 }) {
                Text(this.song().displayArtist)
                  .fontSize(14)
                  .fontColor('#B8FFFFFF')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(platformName(this.song().platform))
                  .fontSize(10)
                  .fontColor('#FFFFFF')
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .backgroundColor('#33FFFFFF')
                  .borderRadius(8)
              }
              .width('100%')
            }
            .width('100%')
            .padding({ left: 24, right: 24 })
          }
          .layoutWeight(1)
          .width('100%')
        }

        Column() {
          WaveformSlider({
            positionMs: this.positionMs,
            durationMs: this.durationMs,
            playing: this.status === PlaybackStatus.PLAYING,
            loading: this.status === PlaybackStatus.LOADING,
            onSeek: (ms: number) => PlayerManager.seekTo(ms),
            onPreview: (fraction: number) => {
              this.previewMs = fraction >= 0 ? Math.round(fraction * Math.max(1, this.durationMs)) : -1;
            }
          })

          Row() {
            Text(formatDuration(this.previewMs >= 0 ? this.previewMs : this.positionMs))
              .fontSize(12)
              .fontColor('#B8FFFFFF')
            Blank()
            Text(formatDuration(this.durationMs))
              .fontSize(12)
              .fontColor('#B8FFFFFF')
          }
          .width('100%')

          Row() {
            PlayerControlButton({
              icon: $r('app.media.ic_shuffle_24'),
              active: this.shuffle,
              label: this.shuffle ? '关闭随机播放' : '随机播放',
              onTap: () => PlayerManager.setShuffle(!this.shuffle)
            })
            PlayerControlButton({
              icon: $r('app.media.round_skip_previous_24'),
              label: '上一首',
              onTap: () => PlayerManager.previous()
            })
            PlayerControlButton({
              icon: this.status === PlaybackStatus.PLAYING
                ? $r('app.media.round_pause_24')
                : $r('app.media.round_play_arrow_24'),
              active: true,
              buttonSize: 64,
              label: this.status === PlaybackStatus.PLAYING ? '暂停' : '播放',
              onTap: () => PlayerManager.togglePlayPause()
            })
            PlayerControlButton({
              icon: $r('app.media.round_skip_next_24'),
              label: '下一首',
              onTap: () => PlayerManager.next(false)
            })
            PlayerControlButton({
              icon: this.repeatMode === RepeatMode.ONE
                ? $r('app.media.ic_repeat_one_24')
                : $r('app.media.ic_repeat_24'),
              active: this.repeatMode !== RepeatMode.OFF,
              label: this.repeatLabel(),
              onTap: () => this.cycleRepeat()
            })
          }
          .width('100%')
          .padding({ top: 6 })
          .justifyContent(FlexAlign.SpaceEvenly)

          Row({ space: 8 }) {
            Button(`${this.speed}x`)
              .height(40)
              .fontSize(12)
              .fontColor('#FFFFFF')
              .backgroundColor('#33FFFFFF')
              .borderRadius(16)
              .accessibilityText(`播放速度 ${this.speed} 倍，点击切换`)
              .onClick(() => this.cycleSpeed())
            Button() {
              Row({ space: 6 }) {
                Image($r('app.media.ic_bedtime_24'))
                  .width(14)
                  .height(14)
                  .fillColor('#FFFFFF')
                Text(this.sleepButtonText())
                  .fontSize(12)
                  .fontColor('#FFFFFF')
              }
            }
            .height(40)
            .padding({ left: 12, right: 12 })
            .backgroundColor('#33FFFFFF')
            .borderRadius(16)
            .onClick(() => {
              this.showSleep = true;
            })
            Button('歌词')
              .height(40)
              .fontSize(12)
              .fontColor(this.showLyrics ? '#1A1A1A' : '#FFFFFF')
              .backgroundColor(this.showLyrics ? '#FFFFFF' : '#33FFFFFF')
              .borderRadius(16)
              .accessibilityText(this.showLyrics ? '切换到封面' : '切换到歌词')
              .onClick(() => {
                // Through the repository so the choice reaches AppPreferences;
                // @StorageProp is read-only, the write has to go via the setter.
                SettingsRepository.setBoolean(SettingsRepository.KEY_SHOW_LYRICS, !this.showLyrics);
              })
            Button('分享')
              .height(40)
              .fontSize(12)
              .fontColor('#FFFFFF')
              .backgroundColor('#33FFFFFF')
              .borderRadius(16)
              .onClick(() => {
                this.showShare = true;
              })
            Button() {
              Image($r('app.media.ic_queue_music_24'))
                .width(18)
                .height(18)
                .fillColor('#FFFFFF')
            }
            // Was 36x32; every chip in this row is now at the 40vp floor.
            .width(40)
            .height(40)
            .backgroundColor('#33FFFFFF')
            .borderRadius(16)
            .accessibilityText('播放列表')
            .onClick(() => {
              this.showQueue = true;
            })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 12, bottom: 18 })
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
        .backgroundColor(Theme.scrim(this.isDark))
      }
      .width('100%')
      .height('100%')

      if (this.showQueue) {
        QueueSheet({
          queueJson: this.queueJson,
          currentOrderIndex: PlayerManager.getCurrentQueueIndex(),
          onClose: () => {
            this.showQueue = false;
          },
          onPlay: (orderIndex: number) => {
            PlayerManager.playAt(orderIndex);
          }
        })
      }

      if (this.showShare) {
        LyricShareSheet({
          lyrics: this.lyrics,
          songName: this.song().displayName,
          artistName: this.song().displayArtist,
          coverSeedHex: this.coverSeedHex,
          initialSelection: this.currentLyricIndex(),
          onClose: () => {
            this.showShare = false;
          }
        })
      }

      if (this.showSleep) {
        Column() {
          Column({ space: 4 }) {
            Text('睡眠定时')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.textPrimary(this.isDark))
              .margin({ bottom: 8 })
            ForEach(SLEEP_OPTIONS, (option: [string, number]) => {
              Text(option[0])
                .fontSize(15)
                .fontColor(this.sleepLabel === option[0] ? Theme.primary(this.isDark) : Theme.textPrimary(this.isDark))
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding(10)
                .onClick(() => this.setSleep(option))
            }, (option: [string, number]) => `${option[0]}_${option[1]}`)
          }
          .width('80%')
          .padding(16)
          .backgroundColor(Theme.surface(this.isDark))
          .borderRadius(18)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Theme.scrim(this.isDark))
        .onClick(() => {
          this.showSleep = false;
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background(this.isDark))
  }
}

@Component
struct PlayerControlButton {
  // @Prop so icon/active/buttonSize refresh when the parent's bound state
  // changes (the play/pause icon switches on player.status; plain members
  // never re-render the child).
  @Prop icon: Resource = $r('app.media.round_play_arrow_24');
  @Prop active: boolean = false;
  @Prop buttonSize: number = 48;
  // Transport buttons carry no text, so the label has to be supplied here or a
  // screen reader announces an anonymous button (device audit 2026-08-24).
  @Prop label: string = '';
  onTap: () => void = () => {};

  build() {
    Button() {
      Image(this.icon)
        .width(this.buttonSize >= 60 ? 34 : 24)
        .height(this.buttonSize >= 60 ? 34 : 24)
        .fillColor(this.active ? '#FFFFFF' : '#B8FFFFFF')
    }
    .width(this.buttonSize)
    .height(this.buttonSize)
    .type(ButtonType.Circle)
    .backgroundColor(this.buttonSize >= 60 ? Theme.primary(false) : Color.Transparent)
    .accessibilityText(this.label)
    .onClick(() => this.onTap())
  }
}

@Component
struct QueueSheet {
  @StorageProp('theme.isDark') isDark: boolean = false; // see Theme.IS_DARK_KEY
  queueJson: string = '';
  currentOrderIndex: number = 0;
  onClose: () => void = () => {};
  onPlay: (orderIndex: number) => void = () => {};
  @StorageProp('np.glass_effect') glassEffect: boolean = true;

  private queue(): QueueState {
    return this.queueJson.length > 0 ? QueueState.fromJson(this.queueJson) : new QueueState();
  }

  build() {
    Column() {
      Column() {
        Row() {
          Text('播放列表')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textPrimary(this.isDark))
            .layoutWeight(1)
          Text('关闭')
            .fontSize(14)
            .fontColor(Theme.primary(this.isDark))
            .onClick(() => this.onClose())
        }
        .width('100%')
        .padding({ bottom: 10 })

        List() {
          ForEach(this.queue().songs, (song: SongItem, index: number) => {
            ListItem() {
              Row({ space: 10 }) {
                Text(`${index + 1}`)
                  .fontSize(13)
                  .fontColor(index === this.currentOrderIndex ? Theme.primary(this.isDark) : Theme.textDisabled(this.isDark))
                  .width(24)
                Column({ space: 2 }) {
                  Text(song.displayName)
                    .fontSize(14)
                    .fontColor(index === this.currentOrderIndex ? Theme.primary(this.isDark) : Theme.textPrimary(this.isDark))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(song.displayArtist)
                    .fontSize(11)
                    .fontColor(Theme.textSecondary(this.isDark))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Text(formatDuration(song.durationMs))
                  .fontSize(11)
                  .fontColor(Theme.textDisabled(this.isDark))
              }
              .width('100%')
              .padding(8)
              .onClick(() => this.onPlay(index))
            }
          }, (song: SongItem) => `${song.platform}_${song.audioId}_${song.id}`)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .width('100%')
      }
      .width('100%')
      .height('62%')
      .padding(16)
      .backgroundColor(this.glassEffect ? Theme.surfaceGlass(this.isDark) : Theme.surface(this.isDark))
      .backgroundBlurStyle(this.glassEffect ? BlurStyle.COMPONENT_THICK : BlurStyle.NONE)
      .borderRadius({ topLeft: 22, topRight: 22 })
      .position({ x: 0, y: '38%' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.scrim(this.isDark))
    .onClick(() => this.onClose())
  }
}
