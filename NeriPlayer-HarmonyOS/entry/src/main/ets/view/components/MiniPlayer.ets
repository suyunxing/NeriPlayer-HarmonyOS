// SPDX-License-Identifier: GPL-3.0

// ReplaceSymbolEffect/EffectScope 是 symbolglyph.d.ts 的全局 ambient 类
// （与 VisualEffect 同类），不从 kit 导入。
import { SongItem } from '../../model/SongItem';
import { PlaybackStatus } from '../../player/PlaybackConstants';
import { PlayerManager } from '../../player/PlayerManager';
import { Router } from '../Router';
import { Theme } from '../Theme';
import { AccentScheme, SchemeMode } from '../theme/AccentScheme';
import { HdsLight } from '../theme/HdsLight';
import { MarqueeText } from './MarqueeText';

@Component
export struct MiniPlayer {
  /**
   * 官方 HdsTabsMiniBar 槽位形态（用户决策：回用官方槽位、缩小播放按钮
   * 适配尺寸）。紧凑形态：无线性进度条、40vp 行、32vp 圆封面、无外边距；
   * 播放键触控热区保持 40vp（项目触达下限），进度改由播放键外圈细环
   * 显示（可见环缩到 30vp 在槽位圆角内留出空余）。独立悬浮形态才用完整卡片。
   */
  @Prop compact: boolean = false;
  /**
   * 脱离 HdsTabs 槽位的独立承载形态（壳层 dock 态覆盖层使用）：非紧凑形态
   * 去掉自带的悬浮卡片外边距，几何完全由使用方给定。背景分两档：设备支持
   * ArkUI 沉浸材质（.systemMaterial，API 26）时挂系统玻璃质感（与悬浮 Tab
   * 栏的沉浸光感同族），不支持时回落自绘玻璃。
   */
  @Prop embedded: boolean = false;
  onMeasured: (area: Area) => void = (_area: Area): void => {};
  @StorageLink('player.currentSong') currentSongJson: string = '';
  @StorageLink('player.status') @Watch('onStatusChanged') status: number = PlaybackStatus.IDLE;
  /**
   * ReplaceSymbolEffect 触发计数：播放/暂停切换时 +1 驱动交叉淡入。初值必须
   * 为 -1（官方语义：triggerValue 变更才触发动效，「首次不希望触发动效，
   * 设置 -1」）——HdsTabs 切 Tab 时会重建 miniBar 槽位内容（CustomBuilder
   * remount），新 SymbolGlyph 以非 -1 的 trigger 挂载会被当成一次变更，误放
   * 替换动效，播放键随每次切页闪烁。
   */
  @State symbolTrigger: number = -1;
  private replaceEffect: ReplaceSymbolEffect = new ReplaceSymbolEffect(EffectScope.WHOLE);
  @StorageLink('player.positionMs') positionMs: number = 0;
  @StorageLink('player.durationMs') durationMs: number = 0;
  // 播放页同源全量配色：进度环已播放取 primary、未播放取 secondary
  // （与 NowPlayingPage.im() 同一来源）。@StorageProp 成员直读即可被最小
  // 更新跟踪，换封面 scheme 即重染，无需镜像 @State（M7.4）。
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  // Mirror the cover seed into @State and read it directly in the accent
  // expressions: AppStorage reads hidden inside Theme.* calls are invisible
  // to minimal-update tracking (M7.4 pitfall), so the raw copy is required.
  @StorageProp('player.coverSeedHex') @Watch('onCoverSeedChanged') coverSeedHex: string = '';
  @State seedHex: string = '';
  // 播放页模态显示状态：控制右侧非封面元素在展开/收起时平滑显隐。
  @StorageProp('ui.nowPlayingShown') nowPlayingShown: boolean = false;
  // 播放器设置（np.mini_next_button / np.mini_show_lyric / np.mini_expand_autoplay）。
  @StorageProp('np.mini_next_button') miniNextButton: boolean = true;
  @StorageProp('np.mini_show_lyric') miniShowLyric: boolean = true;
  @StorageProp('np.mini_expand_autoplay') miniExpandAutoplay: boolean = false;
  // 当前歌词行（PlayerManager 经 LyricLineTracker 发布，与悬浮歌词条同源）。
  @StorageProp('player.currentLyricLine') @Watch('onLyricLineChanged') lyricLineFeed: string = '';
  @State lyricLineText: string = '';
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

  private onLyricLineChanged(): void {
    this.lyricLineText = this.lyricLineFeed;
  }

  aboutToAppear(): void {
    // @Watch 在初始化时不回调：槽位被切 Tab 重建时，下面的镜像 @State 若从
    // 空值起步，歌词副行会回退成歌手行、封面取色回退默认主色，直到下一次
    // 数据变更才恢复。挂载时先从 AppStorage 源补齐，重建与首挂同观感。
    this.seedHex = this.coverSeedHex;
    this.lyricLineText = this.lyricLineFeed;
  }

  /** np.mini_show_lyric：有当前歌词行且正在播放时，副行换成歌词。 */
  private showLyricLine(): boolean {
    return this.miniShowLyric && this.lyricLineText.length > 0
      && this.status === PlaybackStatus.PLAYING;
  }

  private playBackground(): string {
    return this.seedHex.length > 0
      ? Theme.primaryFor(this.seedHex, Theme.isDark())
      : Theme.primary(Theme.isDark());
  }

  /** 当前深浅色模式的 scheme ramp（与播放页 im() 同一规则）。 */
  private scheme(): SchemeMode {
    return Theme.isDark() ? this.coverScheme.dark : this.coverScheme.light;
  }

  /**
   * 进度环未播放段：主色低透明度。scheme.secondary 与 primary 明度几乎相同
   * （播放页 4-6px 粗波形条靠色相才可辨），2vp 细环上不可分，改用主色
   * ~27% alpha 拉开明暗（浅色下≈L83、深色下≈L28，对 primary 均 ≥40 L 差）。
   */
  private ringTrackColor(): string {
    return '#45' + this.scheme().primary.substring(1);
  }

  /**
   * 官方槽位形态且设备支持系统材质：不自绘背景，透出悬浮 Tab 栏的沉浸
   * 光感材质（MainShell 的 barFloatingStyle.systemMaterialEffect 作用于
   * 整条栏，enableMiniBarBackground 让槽位背景跟随栏身，lightColor 随
   * 封面取色）。自绘玻璃会盖在系统材质上把光感挡掉，仅在不支持材质的
   * 设备（模拟器 getSystemMaterialTypes 为空）时回落。
   */
  private followsBarMaterial(): boolean {
    return !this.embedded
      && this.compact
      && (HdsLight.immersiveSupported() || HdsLight.adaptiveSupported());
  }

  /**
   * 独立承载（embedded）且设备支持 ArkUI 沉浸材质（API 26）时挂系统玻璃
   * 背景。材质启用后系统接管背景色/边框/阴影（官方告诫不要与常规属性叠加
   * 设置），所以三处分支都按本档位让位：背景透明、模糊关闭、卡片阴影关闭
   * （材质默认 applyShadow 自带投影）。
   */
  private usesSystemMaterial(): boolean {
    return this.embedded && HdsLight.systemMaterialSupported();
  }

  private barBackground(): ResourceColor {
    if (this.usesSystemMaterial() || this.followsBarMaterial()) {
      return Color.Transparent;
    }
    return Theme.surfaceGlass(Theme.isDark());
  }

  private barBlurStyle(): BlurStyle {
    return this.usesSystemMaterial() || this.followsBarMaterial()
      ? BlurStyle.NONE
      : BlurStyle.COMPONENT_THICK;
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height(this.compact ? 40 : 62)
        .backgroundColor(this.barBackground())
        .backgroundBlurStyle(this.barBlurStyle())
        // ArkUI 通用沉浸材质（embedded 独立承载档；设备不支持传 undefined
        // 即无材质，走上面的自绘玻璃分支）。
        .systemMaterial(this.usesSystemMaterial() ? HdsLight.barSystemMaterial() : undefined)
        .borderRadius(this.compact ? 20 : 16)
        .hitTestBehavior(HitTestMode.None)
      this.playerContent()
    }
    .width('100%')
    .margin(this.compact || this.embedded
      ? { left: 0, right: 0, bottom: 0 }
      : { left: 10, right: 10, bottom: 8 })
    // 显隐由使用方控制（壳层在转场期间对真实迷你条做淡入/隐藏），组件自身
    // 不再持有 mounted/presentation 状态——展示副本已删除，收缩时直接淡入
    // 真实迷你条，杜绝副本与真实布局不一致导致的切换闪烁。
    .onAreaChange((_oldArea: Area, area: Area) => {
      this.onMeasured(area);
    })
    // 沉浸材质档的投影由材质自带（applyShadow），卡片阴影只在自绘玻璃档启用，
    // 避免与系统材质的阴影层叠加。
    .shadow(this.compact || this.usesSystemMaterial()
      ? { radius: 0, color: '#00000000' }
      : { radius: 12, color: '#22000000', offsetY: 2 })
    // 滑动切歌的位移/缩放挂在 Stack 根上：玻璃背景是 playerContent 的兄弟
    // 节点，变换若只挂内容行，滑动时文字按钮滑走而药丸壳纹丝不动。
    .translate({ x: this.swipeOffset })
    .scale(this.swiping ? { x: 0.975, y: 0.975 } : { x: 1, y: 1 })
  }

  @Builder
  playerContent() {
    Column() {
      if (!this.compact) {
        // Progress 的 total 不给就是 100，原来喂进去的是 0..1 的比例，播到一半也只
        // 有 0.5% 的填充（tablet 上像素采样实测：播放 11% 时整条都是轨道色）。改成
        // 直接把毫秒喂给 value/total，单位自洽（同 DownloadsPage 的 value+total 写法）。
        // 紧凑形态没有这条高度，进度由播放键外圈细环显示。
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

      Row({ space: 12 }) {
        Stack() {
          if (this.song().effectiveCoverUrl.length > 0) {
            Image(this.song().effectiveCoverUrl)
              .width(this.compact ? 32 : 44)
              .height(this.compact ? 32 : 44)
              .borderRadius(this.compact ? 16 : 8)
              .objectFit(ImageFit.Cover)
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

        Row() {
          Column({ space: 2 }) {
            // 标题超宽时跑马灯滚动，引擎级 fadeout 两端渐隐在毛玻璃背景上
            // 成立——替代旧版手写离屏 DST_IN 渐隐蒙版（那套方案只做静态
            // 截断淡出，长标题永远看不全）；未超宽时静止显示，不受影响。
            MarqueeText({
              text: this.song().displayName,
              fontSize: 14,
              fontWeight: FontWeight.Medium,
              fontColor: Theme.textPrimary(Theme.isDark())
            })

            // np.mini_show_lyric 开启且正在播放时，这一行优先显示当前歌词行。
            // embedded（壳层 dock 态的两个副本）一律不放作者名：用户决策
            // 2026-09-21，二级页播放控件及其进出场飞行全程只留歌名——紧凑副本
            // 若保留作者行，会在返程交叠淡入时重新显形。槽位真实迷你条（主页
            // 药丸）不受影响。
            if (this.showLyricLine()) {
              Text(this.lyricLineText)
                .fontSize(11)
                .fontColor(Theme.primary(Theme.isDark()))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            } else if (!this.embedded) {
              Text(this.song().displayArtist)
                .fontSize(11)
                .fontColor(Theme.textSecondary(Theme.isDark()))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Stack() {
            if (this.compact) {
              Progress({
                value: this.positionMs,
                total: this.durationMs > 0 ? this.durationMs : 1,
                type: ProgressType.Ring
              })
                .width(30)
                .height(30)
                .style({ strokeWidth: 2 })
                .color(this.scheme().primary)
                .backgroundColor(this.ringTrackColor())
                .hitTestBehavior(HitTestMode.None)
            }
          Button() {
            Stack({ alignContent: Alignment.Center }) {
              // S6: 官方符号替换动效（CROSS_FADE），播放/暂停切换不再是硬切。
              SymbolGlyph(this.status === PlaybackStatus.PLAYING
                ? $r('sys.symbol.pause_fill')
                : $r('sys.symbol.play_fill'))
                .fontSize(this.compact ? 15 : 22)
                .fontColor([this.compact ? this.scheme().primary : '#FFFFFF'])
                .symbolEffect(this.replaceEffect, this.symbolTrigger)
            }
          }
          .width(40)
          .height(40)
          .type(ButtonType.Circle)
          .backgroundColor(this.compact ? Color.Transparent : this.playBackground())
          // Icon-only control: without an explicit label a screen reader reads
          // nothing at all (device audit 2026-08-24 found 9 such buttons).
          .accessibilityText(this.status === PlaybackStatus.PLAYING ? '暂停' : '播放')
          .onClick(() => {
            PlayerManager.togglePlayPause();
          })
          }
          .width(40)
          .height(40)

          if (this.miniNextButton) {
            Button() {
              Image($r('app.media.round_skip_next_24'))
                .width(this.compact ? 20 : 22)
                .height(this.compact ? 20 : 22)
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
        }
        .layoutWeight(1)
      }
      .width('100%')
      .height(this.compact ? 40 : 60)
      .padding({ left: this.compact ? 8 : 12, right: this.compact ? 4 : 8 })
      .onClick(() => {
        // 播放页是壳层全屏模态：打开/收起的动画状态由 MainShell 的
        // motionProgress 统一驱动，这里只翻转开关即可。
        if (this.miniExpandAutoplay && this.status !== PlaybackStatus.PLAYING) {
          // np.mini_expand_autoplay：从底部播放器展开到全屏播放页时自动续播。
          PlayerManager.play().catch(() => {
          });
        }
        Router.push(Router.NOW_PLAYING);
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
    }
    .width('100%')
  }
}
