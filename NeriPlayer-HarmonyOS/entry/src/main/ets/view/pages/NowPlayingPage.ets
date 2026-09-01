import { curves, SymbolGlyphModifier, LengthMetrics } from '@kit.ArkUI';
import { SongItem } from '../../model/SongItem';
import { LyricLine } from '../../model/LyricLine';
import { QueueState } from '../../model/QueueState';
import { LyricDispatcher } from '../../lyrics/LyricDispatcher';
import { LyricLineTracker } from '../../lyrics/LyricLineTracker';
import { PlayerManager } from '../../player/PlayerManager';
import { PlaybackStatus, RepeatMode } from '../../player/PlaybackConstants';
import { Theme } from '../Theme';
import { DynamicTheme } from '../theme/DynamicTheme';
import { AccentScheme, SchemeMode } from '../theme/AccentScheme';
import { LyricView } from '../components/LyricView';
import { WaveformSlider } from '../components/WaveformSlider';
import { LyricShareSheet } from '../components/LyricShareSheet';
import { MatchSongInfoSheet } from '../components/MatchSongInfoSheet';
import { EditSongInfoSheet } from '../components/EditSongInfoSheet';
import { LyricOffsetSheet, LyricFontSizeSheet } from '../components/LyricTweakSheets';
import { SongShareSheet } from '../components/SongShareSheet';
import { DownloadEngine } from '../../download/DownloadEngine';
import { DownloadStorage } from '../../download/DownloadStorage';
import { AlbumSongs } from '../../util/AlbumSongs';
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

/** 背景层的沉浸延伸参数，见 build() 顶部的说明。 */
const IMMERSIVE_TYPES: SafeAreaType[] = [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT];
const IMMERSIVE_EDGES: SafeAreaEdge[] = [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM];

@Component
export struct NowPlayingPage {
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
  // 播放页↔歌词页横向分页：0 = 封面页，1 = 歌词页。默认停在封面页（设计稿
  // 行为，取代旧的 showLyrics=true 一进页面就是歌词）。
  @State pageIndex: number = 0;
  // 控制区形变开关（歌词页折叠成半透明胶囊），由 switchPane 驱动动画。
  @State lyricsMode: boolean = false;
  private paneSwiper: SwiperController = new SwiperController();
  @State showQueue: boolean = false;
  @State showSleep: boolean = false;
  @State showShare: boolean = false;
  // ⋯ menu action sheets (the queue keeps its dedicated bottom-right button).
  @State showMatchInfo: boolean = false;
  @State showEditInfo: boolean = false;
  @State showLyricOffset: boolean = false;
  @State showLyricFontSize: boolean = false;
  @State showSongShare: boolean = false;
  @State sleepLabel: string = '关闭';
  @StorageLink('player.sleepActive') sleepActive: boolean = false;
  @StorageLink('player.sleepRemainingMin') sleepRemainingMin: number = 0;
  /** 底部控件行的上抬量，由 util/WindowMetrics.ets 按真实避让区发布。 */
  @StorageProp('ui.bottomLiftVp') bottomLift: number = Theme.bottomBarLift();
  @State previewMs: number = -1;
  // Cover-seed backdrop (Android NowPlayingAccentBackdrop). The raw seed is
  // mirrored into a @State accent computed via @Watch because minimal-update
  // tracking cannot see AppStorage reads inside expressions (M7.4 pitfall).
  @StorageProp('player.coverSeedHex') @Watch('onCoverSeedChanged') coverSeedHex: string = '';
  @StorageProp('np.dynamic_color') @Watch('onCoverSeedChanged') dynamicColor: boolean = true;
  @State accentHex: string = '';
  // 封面全量配色（S1 引擎发布）：背景毛玻璃取色与文字令牌的唯一来源。
  // 组件自己订阅（M7.4：表达式里直读被跟踪成员），换歌即整页重绘。
  @StorageProp('player.coverScheme') @Watch('onCoverSchemeChanged') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  // Blurred-cover backdrop with track-switch crossfade (Android keeps the old
  // artwork blurred while the new cover fades in). Layer B sits on top; once
  // its fade finishes it collapses into layer A without animation. 两层都是
  // 整屏主背景，blur 强度跟随设置项且整体增强（毛玻璃突出控件与歌词）。
  @StorageProp('np.nowplaying_blur_strength') blurStrength: number = 300;
  @StorageProp('np.glass_effect') glassEffect: boolean = true;
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
    this.accentHex = seed.length > 0 ? DynamicTheme.adjustedAccentColor(seed, Theme.isDark()) : '';
  }

  private onCoverSeedChanged(): void {
    this.recomputeAccent();
  }

  private onCoverSchemeChanged(): void {
  }

  /** 当前模式的沉浸令牌（深色模式取 dark ramp）。页面级，M7.4 直读成员。 */
  private im(): SchemeMode {
    return Theme.isDark() ? this.coverScheme.dark : this.coverScheme.light;
  }

  private currentLyricIndex(): number {
    let index = -1;
    for (let i = 0; i < this.lyrics.length; i++) {
      if (this.lyrics[i].timeMs <= this.positionMs) {
        index = i;
      } else {
        break;
      }
    }
    return index;
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

  private cycleRepeat(): void {
    PlayerManager.cycleRepeatMode();
  }

  /** 倍速是六档单选：锚定菜单替代原来的循环点击（UX 规范）。 */
  @Builder
  speedMenuBuilder() {
    Menu() {
      ForEach(SPEED_STEPS, (speedValue: number) => {
        MenuItem({ content: speedValue === 1.0 ? '1.0x' : `${speedValue}x` })
          .selected(this.speed === speedValue)
          .selectIcon(true)
          .onClick(() => PlayerManager.setSpeed(speedValue))
      }, (speedValue: number) => `${speedValue}`)
    }
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

  /** Swiper index change: records the page and morphs the control area. */
  private switchPane(index: number): void {
    this.pageIndex = index;
    this.getUIContext().animateTo({ duration: 280, curve: Curve.Friction }, () => {
      this.lyricsMode = index === 1;
    });
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

  private async downloadCurrentSong(): Promise<void> {
    const song = this.song();
    const entry = await DownloadStorage.findCatalogEntry(song);
    if (entry !== null) {
      this.getUIContext().getPromptAction().showToast({ message: '已下载到本地', duration: 2000 });
      return;
    }
    DownloadEngine.enqueue([song]);
    this.getUIContext().getPromptAction().showToast({ message: '已加入下载队列', duration: 2000 });
  }

  private openAlbum(): void {
    const song = this.song();
    if (song.albumId > 0 || AlbumSongs.hasAlbumData(song)) {
      Router.push(Router.ALBUM, JSON.stringify({ album: song.album, albumId: song.albumId }));
      return;
    }
    this.getUIContext().getPromptAction().showToast({ message: '暂无专辑信息', duration: 2000 });
  }

  @Builder
  songMenuBuilder() {
    Menu() {
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.magnifyingglass')).fontSize(22),
        content: '匹配歌曲信息'
      }).onClick(() => {
        this.showMatchInfo = true;
      })
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')).fontSize(22),
        content: '编辑歌曲信息'
      }).onClick(() => {
        this.showEditInfo = true;
      })
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.download')).fontSize(22),
        content: '下载到本地'
      }).onClick(() => {
        this.downloadCurrentSong();
      })
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.timer')).fontSize(22),
        content: '调整歌词偏移'
      }).onClick(() => {
        this.showLyricOffset = true;
      })
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.textformat_size_square')).fontSize(22),
        content: '歌词字体大小'
      }).onClick(() => {
        this.showLyricFontSize = true;
      })
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.opticaldisc')).fontSize(22),
        content: '查看专辑'
      }).onClick(() => {
        this.openAlbum();
      })
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.share')).fontSize(22),
        content: '分享'
      }).onClick(() => {
        this.showSongShare = true;
      })
    }
  }

  build() {
    Stack() {
      // 背景层全部用 expandSafeArea 铺进状态栏、导航条与挖孔区：这些是纯展示
      // 元素，延伸后系统栏显示的就是封面与遮罩本身，不会在页面底部和导航条之间
      // 留下色块切割（浅色模式下尤其明显：页面是深色遮罩，导航条却是浅色底）。
      // 下面的内容层不延伸，仍由 ArkUI 的安全区自动避让保护。
      //
      // 背景先铺封面取色，再以半透明模糊封面补充明暗纹理。浅色模式使用白色
      // wash 保持通透，深色模式再适度压暗；双层封面的交叉淡化仍由
      // transitionCover 维护。
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.accentHex.length > 0 ? this.accentHex : this.im().background)
        .expandSafeArea(IMMERSIVE_TYPES, IMMERSIVE_EDGES)
      Stack() {
        if (this.bgUnderUrl.length > 0) {
          Image(this.bgUnderUrl)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .blur(this.blurStrength * 120 / 500)
            .scale({ x: 1.35, y: 1.35 })
            .expandSafeArea(IMMERSIVE_TYPES, IMMERSIVE_EDGES)
        }
        if (this.bgOverUrl.length > 0) {
          Image(this.bgOverUrl)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .blur(this.blurStrength * 120 / 500)
            .scale({ x: 1.35, y: 1.35 })
            .opacity(this.bgOverOpacity)
            .expandSafeArea(IMMERSIVE_TYPES, IMMERSIVE_EDGES)
        }
      }
      .width('100%')
      .height('100%')
      .opacity(Theme.isDark() ? 0.82 : 0.44)
      .expandSafeArea(IMMERSIVE_TYPES, IMMERSIVE_EDGES)
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.isDark() ? '#52000000' : '#28FFFFFF')
        .expandSafeArea(IMMERSIVE_TYPES, IMMERSIVE_EDGES)

      Column() {
        Row() {
          Button() {
            if (this.lyricsMode) {
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(22)
                .fontColor([this.im().textPrimary])
            } else {
              Image($r('app.media.ic_arrow_back_24'))
                .width(22)
                .height(22)
                .fillColor(this.im().textPrimary)
            }
          }
          .width(40)
          .height(40)
          .type(ButtonType.Circle)
          .backgroundColor(Theme.tagBg(Theme.isDark()))
          .accessibilityText(this.lyricsMode ? '收起歌词' : '返回')
          .onClick(() => {
            // 歌词页的返回先滑回封面页；系统返回键/侧滑才 pop 路由。
            if (this.lyricsMode) {
              this.paneSwiper.showPrevious();
            } else {
              Router.pop();
            }
          })
          if (this.lyricsMode) {
            Blank().layoutWeight(1)
          } else {
            Text('正在播放')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.im().textPrimary)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
            Button() {
              Image($r('app.media.ic_group_24'))
                .width(20)
                .height(20)
                .fillColor(this.im().textPrimary)
            }
            .width(40)
            .height(40)
            .type(ButtonType.Circle)
            .backgroundColor(Theme.tagBg(Theme.isDark()))
            .accessibilityText('一起听')
            .onClick(() => Router.push(Router.LISTEN_TOGETHER))
          }
          Button('⋯')
            .width(40)
            .height(40)
            .type(ButtonType.Circle)
            .backgroundColor(Theme.tagBg(Theme.isDark()))
            .fontColor(this.im().textPrimary)
            .fontSize(18)
            // '⋯' on its own is read out as punctuation, or skipped entirely.
            .accessibilityText('更多操作')
            .bindMenu(this.songMenuBuilder)
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 8 })

        // 播放页↔歌词页横向分页。LyricView 的根节点是 layoutWeight(1) 的
        // Scroll，在 Swiper item 里必须包一层定高 Column，否则高度塌 0。
        Swiper(this.paneSwiper) {
          Column() {
            Stack() {
              if (this.song().effectiveCoverUrl.length > 0) {
                Image(this.song().effectiveCoverUrl)
                  .width('78%')
                  .aspectRatio(1)
                  .borderRadius(22)
                  .objectFit(ImageFit.Cover)
                  .shadow({ radius: 24, color: '#66000000', offsetY: 8 })
                  // S6 一镜到底：与迷你条封面共享元素；.id() 防打断重影。
                  .geometryTransition('np.cover')
                  .id('np_cover_full')
                  .transition(TransitionEffect.OPACITY)
              } else {
                Image($r('app.media.ic_music_note_24'))
                  .width('78%')
                  .aspectRatio(1)
                  .objectFit(ImageFit.Contain)
                  .padding({ left: 32, right: 32, top: 32, bottom: 32 })
                  .fillColor(Theme.primary(Theme.isDark()))
                  .backgroundColor(Theme.tagBg(Theme.isDark()))
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
                  .fontColor(this.im().textPrimary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Image(this.favorite
                  ? $r('app.media.ic_baseline_favorite_24')
                  : $r('app.media.ic_outline_favorite_24'))
                  .width(24)
                  .height(24)
                  .fillColor(this.favorite ? Theme.danger(false) : this.im().textSecondary)
                  .padding(6)
                  .onClick(() => this.toggleFavorite())
              }
              .width('100%')

              Row({ space: 8 }) {
                Text(this.song().displayArtist)
                  .fontSize(14)
                  .fontColor(this.im().textSecondary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(platformName(this.song().platform))
                  .fontSize(10)
                  .fontColor(this.im().textPrimary)
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .backgroundColor(this.im().tagBg)
                  .borderRadius(8)
              }
              .width('100%')
            }
            .width('100%')
            .padding({ left: 24, right: 24 })
          }
          .width('100%')
          .height('100%')

          Column() {
            // The lyric view has its own empty state ("暂无歌词"); entering it
            // must not depend on lyrics being available (Bilibili/LOCAL songs
            // often have no remote lyric source, Android shows an empty state).
            LyricView({
              lyrics: this.lyrics,
              onSeek: (timeMs: number) => PlayerManager.seekTo(timeMs),
              // Lyric scrubbing previews the centered line's time in the shared
              // label channel (same previewMs the waveform drag uses); playback
              // itself is untouched until a line is tapped.
              onScrubLine: (timeMs: number) => {
                this.previewMs = timeMs;
              }
            })
          }
          .width('100%')
          .height('100%')
        }
        .index(this.pageIndex)
        .loop(false)
        .indicator(false)
        .duration(320)
        // 与 LyricView 自动跟随的 springMotion 同族手感。
        .curve(curves.interpolatingSpring(0, 1, 328, 34))
        .layoutWeight(1)
        .width('100%')
        .onChange((index: number) => this.switchPane(index))

        // 控制区只有一个（在 Swiper 外），歌词页通过 lyricsMode 收拢成
        // 无底控件行：传输键不重复实现，单一数据源。控件直接叠在毛玻璃
        // 背景上，不再有底部色带。
        Column() {
          if (!this.lyricsMode) {
            Column() {
              WaveformSlider({
                positionMs: this.positionMs,
                durationMs: this.durationMs,
                playing: this.status === PlaybackStatus.PLAYING,
                loading: this.status === PlaybackStatus.LOADING,
                // 未播放段用取色 scheme 的主色系（secondary），已播放段用
                // 强调色（primary，与主页 FAB 同源）——M7.4：在页面表达式里
                // 直读被跟踪的 coverScheme，取色变化即时重染。
                unplayedColor: this.im().secondary,
                playedColor: this.im().primary,
                onSeek: (ms: number) => PlayerManager.seekTo(ms),
                onPreview: (fraction: number) => {
                  this.previewMs = fraction >= 0 ? Math.round(fraction * Math.max(1, this.durationMs)) : -1;
                }
              })

              Row() {
                Text(formatDuration(this.previewMs >= 0 ? this.previewMs : this.positionMs))
                  .fontSize(12)
                  .fontColor(this.im().textSecondary)
                Blank()
                Text(formatDuration(this.durationMs))
                  .fontSize(12)
                  .fontColor(this.im().textSecondary)
              }
              .width('100%')

              Row() {
                PlayerControlButton({
                  icon: $r('app.media.ic_shuffle_24'),
                  tintOn: this.im().textPrimary,
                  tintOff: this.im().textSecondary,
                  active: this.shuffle,
                  label: this.shuffle ? '关闭随机播放' : '随机播放',
                  onTap: () => PlayerManager.setShuffle(!this.shuffle)
                })
                PlayerControlButton({
                  icon: $r('app.media.round_skip_previous_24'),
                  tintOn: this.im().textPrimary,
                  tintOff: this.im().textSecondary,
                  label: '上一首',
                  onTap: () => PlayerManager.previous()
                })
                PlayerControlButton({
                  icon: this.status === PlaybackStatus.PLAYING
                    ? $r('app.media.round_pause_24')
                    : $r('app.media.round_play_arrow_24'),
                  tintOn: this.im().onPrimary,
                  active: true,
                  buttonSize: 64,
                  label: this.status === PlaybackStatus.PLAYING ? '暂停' : '播放',
                  onTap: () => PlayerManager.togglePlayPause()
                })
                PlayerControlButton({
                  icon: $r('app.media.round_skip_next_24'),
                  tintOn: this.im().textPrimary,
                  tintOff: this.im().textSecondary,
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

              // 无背景裸图标行（鸿蒙标准符号）；去背景后状态靠颜色区分，
              // 文字信息（1.0x、剩余分钟）由无障碍文案补偿。
              Row() {
                Column() {
                  SymbolGlyph($r('sys.symbol.speed_multiple'))
                    .fontSize(24)
                    .fontColor([this.speed !== 1.0 ? this.im().textPrimary : this.im().textSecondary])
                }
                .width(44)
                .height(44)
                .justifyContent(FlexAlign.Center)
                .accessibilityText(`播放速度 ${this.speed} 倍，点击选择`)
                .bindMenu(this.speedMenuBuilder)

                Column() {
                  SymbolGlyph($r('sys.symbol.timer'))
                    .fontSize(24)
                    .fontColor([this.sleepActive ? this.im().textPrimary : this.im().textSecondary])
                }
                .width(44)
                .height(44)
                .justifyContent(FlexAlign.Center)
                .accessibilityText(this.sleepButtonText())
                .onClick(() => {
                  this.showSleep = true;
                })

                Column() {
                  SymbolGlyph($r('sys.symbol.share'))
                    .fontSize(24)
                    .fontColor([this.im().textPrimary])
                }
                .width(44)
                .height(44)
                .justifyContent(FlexAlign.Center)
                .accessibilityText('分享歌词')
                .onClick(() => {
                  this.showShare = true;
                })

                Column() {
                  SymbolGlyph($r('sys.symbol.music_note_list'))
                    .fontSize(24)
                    .fontColor([this.im().textPrimary])
                }
                .width(44)
                .height(44)
                .justifyContent(FlexAlign.Center)
                .accessibilityText('播放列表')
                .onClick(() => {
                  this.showQueue = true;
                })
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceEvenly)
              // 页面最底部的固定控件行：相对系统导航指示器上抬，抬升量取自真实
              // 避让区（见 util/WindowMetrics.ets），无指示器的形态为 0。
              .padding({ top: 12, bottom: this.bottomLift })
            }
            .width('100%')
            .transition(TransitionEffect.OPACITY.animation({ duration: 280, curve: Curve.Friction }))
          } else {
            // 歌词页控件行：歌词 / 上一首 / 播放暂停 / 下一首 / 收藏。
            // The reference uses one outlined, translucent capsule instead of
            // five unrelated floating buttons.
            Row() {
              Button() {
                Image($r('app.media.ic_lyricon'))
                  .width(25)
                  .height(25)
                  .fillColor(this.im().textSecondary)
              }
              .width(44)
              .height(44)
              .type(ButtonType.Circle)
              .backgroundColor(Color.Transparent)
              .accessibilityText('切换到封面')
              .onClick(() => this.paneSwiper.showPrevious())

              PlayerControlButton({
                icon: $r('app.media.round_skip_previous_24'),
                tintOn: this.im().textPrimary,
                tintOff: this.im().textSecondary,
                label: '上一首',
                onTap: () => PlayerManager.previous()
              })
              Button() {
                Image(this.status === PlaybackStatus.PLAYING
                  ? $r('app.media.round_pause_24')
                  : $r('app.media.round_play_arrow_24'))
                  .width(32)
                  .height(32)
                  .fillColor(this.im().textSecondary)
              }
              .width(44)
              .height(44)
              .type(ButtonType.Circle)
              .backgroundColor(Color.Transparent)
              .accessibilityText(this.status === PlaybackStatus.PLAYING ? '暂停' : '播放')
              .onClick(() => PlayerManager.togglePlayPause())
              PlayerControlButton({
                icon: $r('app.media.round_skip_next_24'),
                tintOn: this.im().textPrimary,
                tintOff: this.im().textSecondary,
                label: '下一首',
                onTap: () => PlayerManager.next(false)
              })

              Button() {
                Image(this.favorite
                  ? $r('app.media.ic_baseline_favorite_24')
                  : $r('app.media.ic_outline_favorite_24'))
                  .width(22)
                  .height(22)
                  .fillColor(this.favorite ? Theme.danger(false) : this.im().textSecondary)
              }
              .width(44)
              .height(44)
              .type(ButtonType.Circle)
              .backgroundColor(Color.Transparent)
              .accessibilityText(this.favorite ? '取消收藏' : '收藏')
              .onClick(() => this.toggleFavorite())
            }
            .width('82%')
            .height(60)
            .padding({ left: 14, right: 14 })
            .justifyContent(FlexAlign.SpaceEvenly)
            .alignSelf(ItemAlign.Center)
            .backgroundColor('#14FFFFFF')
            .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
            .border({ width: 1, color: '#52FFFFFF', radius: 32 })
            .borderRadius(32)
            .margin({ bottom: 8 })
            .transition(TransitionEffect.OPACITY.animation({ duration: 280, curve: Curve.Friction }))
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 0 })
      }
      .width('100%')
      .height('100%')


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

      if (this.showMatchInfo) {
        MatchSongInfoSheet({
          songJson: this.currentSongJson,
          onApplied: () => {
            // 匹配写入的是 matched*/custom* 字段；currentSongJson 的 @Watch
            // 只做封面淡入，歌词要在这里主动重载。
            void this.reloadSongData();
          },
          onClose: () => {
            this.showMatchInfo = false;
          }
        })
      }

      if (this.showEditInfo) {
        EditSongInfoSheet({
          songJson: this.currentSongJson,
          onClose: () => {
            this.showEditInfo = false;
          }
        })
      }

      if (this.showLyricOffset) {
        LyricOffsetSheet({
          onClose: () => {
            this.showLyricOffset = false;
          }
        })
      }

      if (this.showLyricFontSize) {
        LyricFontSizeSheet({
          onClose: () => {
            this.showLyricFontSize = false;
          }
        })
      }

      if (this.showSongShare) {
        SongShareSheet({
          songJson: this.currentSongJson,
          onClose: () => {
            this.showSongShare = false;
          },
          onOpenLyricCard: () => {
            this.showShare = true;
          }
        })
      }

      if (this.showSleep) {
        Column() {
          Column({ space: 4 }) {
            Text('睡眠定时')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.textPrimary(Theme.isDark()))
              .margin({ bottom: 8 })
            ForEach(SLEEP_OPTIONS, (option: [string, number]) => {
              Text(option[0])
                .fontSize(15)
                .fontColor(this.sleepLabel === option[0] ? Theme.primary(Theme.isDark()) : Theme.textPrimary(Theme.isDark()))
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding(10)
                .onClick(() => this.setSleep(option))
            }, (option: [string, number]) => `${option[0]}_${option[1]}`)
          }
          .width('80%')
          .padding(16)
          .backgroundColor(Theme.surface(Theme.isDark()))
          .borderRadius(18)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Theme.scrim(Theme.isDark()))
        .onClick(() => {
          this.showSleep = false;
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background(Theme.isDark()))
    // S4: 播放列表走原生半模态（官方手势关闭与档位吸附），替代手工覆盖层。
    .bindSheet($$this.showQueue, this.queueSheetBuilder(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      dragBar: true,
      onDisappear: () => {
        this.showQueue = false;
      }
    })
  }

  @Builder
  queueSheetBuilder() {
    QueueSheetContent({
      queueJson: this.queueJson,
      currentOrderIndex: PlayerManager.getCurrentQueueIndex(),
      onPlay: (orderIndex: number) => {
        PlayerManager.playAt(orderIndex);
      }
    })
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
  // Solid primary disc independent of size: the lyrics-page capsule shrinks
  // the play button below the 60vp threshold but keeps it filled.
  @Prop filled: boolean = false;
  // Transport buttons carry no text, so the label has to be supplied here or a
  // screen reader announces an anonymous button (device audit 2026-08-24).
  @Prop label: string = '';
  // S2: icon tint comes from the immersive scheme (parent passes im() tokens).
  @Prop tintOn: string = '#FFFFFF';
  @Prop tintOff: string = '#B3FFFFFF';
  onTap: () => void = () => {};

  build() {
    Button() {
      Image(this.icon)
        .width(this.buttonSize >= 60 ? 34 : 24)
        .height(this.buttonSize >= 60 ? 34 : 24)
        .fillColor(this.active ? this.tintOn : this.tintOff)
    }
    .width(this.buttonSize)
    .height(this.buttonSize)
    .type(ButtonType.Circle)
    .backgroundColor(this.filled || this.buttonSize >= 60 ? Theme.primary(false) : Color.Transparent)
    .accessibilityText(this.label)
    .onClick(() => this.onTap())
  }
}

/**
 * S4: 播放列表内容（宿主用原生 bindSheet 承载：detents 双档位 + dragBar +
 * 下滑关闭，替代旧的手工 scrim+position('38%') 覆盖层——百分比 .position
 * 是布局守则明令禁止的写法，且旧实现没有进出场动画与手势关闭）。
 */
@Component
struct QueueSheetContent {
  @Prop queueJson: string = '';
  currentOrderIndex: number = 0;
  onPlay: (orderIndex: number) => void = () => {};

  private queue(): QueueState {
    return this.queueJson.length > 0 ? QueueState.fromJson(this.queueJson) : new QueueState();
  }

  build() {
    Column() {
      Row() {
        Text('播放列表')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .layoutWeight(1)
        Text(`${this.queue().songs.length} 首`)
          .fontSize(13)
          .fontColor(Theme.textSecondary(Theme.isDark()))
      }
      .width('100%')
      .padding({ bottom: 10 })

      // bindSheet 的滚动内容要显式声明嵌套滚动方向，才能先滚内容再拉档位。
      List() {
        ForEach(this.queue().songs, (song: SongItem, index: number) => {
          ListItem() {
            Row({ space: 10 }) {
              Text(`${index + 1}`)
                .fontSize(13)
                .fontColor(index === this.currentOrderIndex ? Theme.primary(Theme.isDark()) : Theme.textDisabled(Theme.isDark()))
                .width(24)
              Column({ space: 2 }) {
                Text(song.displayName)
                  .fontSize(14)
                  .fontColor(index === this.currentOrderIndex ? Theme.primary(Theme.isDark()) : Theme.textPrimary(Theme.isDark()))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(song.displayArtist)
                  .fontSize(11)
                  .fontColor(Theme.textSecondary(Theme.isDark()))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Text(formatDuration(song.durationMs))
                .fontSize(11)
                .fontColor(Theme.textDisabled(Theme.isDark()))
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
      .nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: this.safeBottom() })
  }

  private safeBottom(): number {
    return 16;
  }
}
