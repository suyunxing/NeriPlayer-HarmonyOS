// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer),
// commit 01c57a11 (multi-step onboarding). The upstream 9 steps are tailored
// to the HarmonyOS surface: no language step (zh only) and no runtime
// permission step (AVSession-managed notifications, picker-based file access);
// playback sources and playback controls stay as separate steps.

import { common } from '@kit.AbilityKit';
import { SettingsRepository } from '../../data/SettingsRepository';
import { Theme } from '../Theme';
import { OptionEntry, OptionRow, SliderRow, ToggleRow } from '../components/Ui';
import { AccentScheme } from '../theme/AccentScheme';
import { AppColorMode } from '../../util/AppColorMode';
import { SystemBars } from '../../util/SystemBars';
import { BAND_BUTTON_VP, BAND_TEXT_VP, BP_LG, BP_MD } from '../../util/Breakpoint';
import {
  STARTUP_ONBOARDING_STEP_COUNT,
  calculateStartupOnboardingProgress,
  shouldWarnStartupNoPlatformConnected
} from '../onboarding/StartupOnboardingPolicy';

/** 引导里可选的音质档（与设置页 QUALITIES 一致，去掉最重的两档作默认推荐面）。 */
const ONBOARDING_QUALITIES: string[] = ['standard', 'high', 'exhigh', 'lossless', 'hires'];

function onboardingQualityLabel(quality: string): string {
  if (quality === 'standard') {
    return '标准';
  }
  if (quality === 'high') {
    return '较高';
  }
  if (quality === 'exhigh') {
    return '极高';
  }
  if (quality === 'lossless') {
    return '无损';
  }
  return 'Hi-Res';
}

/**
 * 多步初始设置向导（上游 StartupOnboardingScreen 的鸿蒙 7 步形态）：
 * 欢迎 → 外观 → 播放源 → 歌词 → 播放器 → 账号与备份 → 开始使用。
 * 全部开关直写既有设置键（与设置页同一存储，立即生效）；启动门阶段无
 * Navigation，账号/备份只做说明引导，入口留在设置页。
 */
@Component
export struct OnboardingPage {
  onDone: () => void = () => {};
  @State step: number = 0;
  /** 由 util/WindowMetrics.ets 发布，决定引导内容是否竖向居中。 */
  @StorageProp('ui.breakpoint') breakpoint: string = 'sm';
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @StorageProp('np.dark_mode') darkMode: string = 'auto';
  @StorageProp('np.dynamic_color') dynamicColor: boolean = true;
  @StorageProp('np.youtube_enabled') youtubeEnabled: boolean = true;
  @StorageProp('np.audio_quality_wifi') qualityWifi: string = '';
  @StorageProp('np.audio_quality_cellular') qualityCellular: string = '';
  /** 旧版总档位：新 Wi-Fi/蜂窝键为空串时的回退（与设置页同规则）。 */
  @StorageProp('np.audio_quality') qualityLegacy: string = 'standard';
  @StorageProp('np.lyric_font_size') lyricFontSize: number = 16;
  @StorageProp('np.lyric_translation') lyricTranslation: boolean = true;
  @StorageProp('np.lyric_phonetic') lyricPhonetic: boolean = false;
  @StorageProp('np.nowplaying_control_size') nowPlayingControlSize: number = 1;
  @StorageProp('np.lyric_control_size') lyricControlSize: number = 1;
  @StorageProp('np.netease_logged') neteaseLogged: boolean = false;
  @StorageProp('np.bilibili_logged') biliLogged: boolean = false;

  private wideLayout(): boolean {
    return this.breakpoint === BP_MD || this.breakpoint === BP_LG;
  }

  private isLastStep(): boolean {
    return this.step >= STARTUP_ONBOARDING_STEP_COUNT - 1;
  }

  private stepTitles(): string[] {
    return ['欢迎', '外观', '播放源', '歌词', '播放器', '账号与备份', '开始使用'];
  }

  private applyDarkMode(mode: string): void {
    SettingsRepository.setString(SettingsRepository.KEY_DARK_MODE, mode);
    const context = AppStorage.get<common.UIAbilityContext>('abilityContext');
    if (context !== undefined) {
      // setColorMode 触发配置变更重建组件树，否则引导页颜色表达式不重绘
      //（与设置页 applyDarkMode 同一机制）。
      AppColorMode.apply(context, mode);
      SystemBars.apply(context, Theme.isDark());
    }
  }

  private qualityOptions(): OptionEntry[] {
    const options: OptionEntry[] = [];
    for (const quality of ONBOARDING_QUALITIES) {
      options.push({ value: quality, label: onboardingQualityLabel(quality) });
    }
    return options;
  }

  private controlSizeOptions(): OptionEntry[] {
    return [
      { value: '0', label: '小' },
      { value: '1', label: '中' },
      { value: '2', label: '大' }
    ];
  }

  private darkModeOptions(): OptionEntry[] {
    return [
      { value: 'auto', label: '跟随系统' },
      { value: 'light', label: '浅色' },
      { value: 'dark', label: '深色' }
    ];
  }

  @Builder
  stepBadge() {
    Text(`初始设置 · ${this.step + 1}/${STARTUP_ONBOARDING_STEP_COUNT}`)
      .fontSize(12)
      .fontColor(Theme.primary(Theme.isDark()))
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
      .borderRadius(14)
  }

  @Builder
  stepTitle(index: number) {
    Text(this.stepTitles()[index])
      .fontSize(24)
      .fontWeight(FontWeight.Bold)
      .fontColor(Theme.textPrimary(Theme.isDark()))
  }

  @Builder
  stepBody(text: string) {
    Text(text)
      .fontSize(14)
      .fontColor(Theme.textSecondary(Theme.isDark()))
      .lineHeight(21)
  }

  @Builder
  welcomeStep() {
    Column({ space: 18 }) {
      Image($r('app.media.ic_neriplayer'))
        .width(84)
        .height(84)
        .borderRadius(20)
      this.stepTitle(0)
      this.stepBody('多源在线播放与本地音乐播放器。以下几步完成初始设置，全部可以稍后在设置中修改。')
      Column({ space: 10 }) {
        Text('🎵  网易云 / Bilibili / YouTube Music 多源搜索与播放')
          .fontSize(13)
          .fontColor(Theme.textSecondary(Theme.isDark()))
        Text('📱  本地优先：歌单、历史与设置默认保存在设备本地')
          .fontSize(13)
          .fontColor(Theme.textSecondary(Theme.isDark()))
        Text('☁️  可选的 GitHub / WebDAV 云端备份与跨端同步')
          .fontSize(13)
          .fontColor(Theme.textSecondary(Theme.isDark()))
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 6 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  appearanceStep() {
    Column({ space: 12 }) {
      this.stepTitle(1)
      this.stepBody('选择应用的明暗风格；「跟随系统」随系统深色模式自动切换。')
      OptionRow({
        title: '深色模式',
        icon: '🌙',
        options: this.darkModeOptions(),
        current: this.darkMode,
        onPick: (mode: string): void => this.applyDarkMode(mode)
      })
      ToggleRow({
        title: '动态取色',
        subtitle: '播放时按封面提取主题色',
        icon: '🎨',
        value: this.dynamicColor,
        onChange: (value: boolean): void => {
          SettingsRepository.setBoolean(SettingsRepository.KEY_DYNAMIC_COLOR, value);
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  sourcesStep() {
    Column({ space: 12 }) {
      this.stepTitle(2)
      this.stepBody('选择在线音源与音质档位；本地音乐不受影响，随时可在设置中修改。')
      ToggleRow({
        title: '启用 YouTube Music',
        subtitle: '关闭后隐藏 YouTube Music 搜索与播放入口',
        icon: '▶',
        value: this.youtubeEnabled,
        onChange: (value: boolean): void => {
          SettingsRepository.setBoolean(SettingsRepository.KEY_YOUTUBE_ENABLED, value);
        }
      })
      OptionRow({
        title: 'Wi-Fi 网络音质',
        icon: '📶',
        options: this.qualityOptions(),
        current: this.qualityWifi.length > 0 ? this.qualityWifi : this.qualityLegacy,
        onPick: (value: string): void => {
          SettingsRepository.setString(SettingsRepository.KEY_AUDIO_QUALITY_WIFI, value);
        }
      })
      OptionRow({
        title: '非 Wi-Fi 网络音质',
        subtitle: '蜂窝网络下请求的音质档位',
        icon: '📡',
        options: this.qualityOptions(),
        current: this.qualityCellular.length > 0 ? this.qualityCellular : this.qualityLegacy,
        onPick: (value: string): void => {
          SettingsRepository.setString(SettingsRepository.KEY_AUDIO_QUALITY_CELLULAR, value);
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  lyricsStep() {
    Column({ space: 12 }) {
      this.stepTitle(3)
      this.stepBody('调整歌词字号与译文显示；支持逐字歌词与翻译、音译双行。')
      SliderRow({
        title: '歌词字号',
        icon: '🔤',
        min: 12,
        max: 28,
        step: 1,
        value: this.lyricFontSize,
        format: (value: number): string => `${value}`,
        onPick: (value: number): void => {
          SettingsRepository.setNumber(SettingsRepository.KEY_LYRIC_FONT_SIZE, value);
        }
      })
      ToggleRow({
        title: '显示翻译',
        subtitle: '有翻译数据时在歌词下方显示译文行',
        icon: '🌐',
        value: this.lyricTranslation,
        onChange: (value: boolean): void => {
          SettingsRepository.setBoolean(SettingsRepository.KEY_LYRIC_TRANSLATION, value);
        }
      })
      ToggleRow({
        title: '显示音译',
        subtitle: '日语歌等场景显示罗马音注音行',
        icon: '🈁',
        value: this.lyricPhonetic,
        onChange: (value: boolean): void => {
          SettingsRepository.setBoolean(SettingsRepository.KEY_LYRIC_PHONETIC, value);
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  controlsStep() {
    Column({ space: 12 }) {
      this.stepTitle(4)
      this.stepBody('播放页与歌词页的控件大小档位，影响按钮与控制条尺寸。')
      OptionRow({
        title: '播放页控件大小',
        subtitle: '顶栏、传输行与底部工具行',
        icon: '🎚',
        options: this.controlSizeOptions(),
        current: `${this.nowPlayingControlSize}`,
        onPick: (value: string): void => {
          SettingsRepository.setNumber(SettingsRepository.KEY_NOW_PLAYING_CONTROL_SIZE, Number(value));
        }
      })
      OptionRow({
        title: '歌词页控件大小',
        subtitle: '歌词页底部控制胶囊',
        icon: '🎚',
        options: this.controlSizeOptions(),
        current: `${this.lyricControlSize}`,
        onPick: (value: string): void => {
          SettingsRepository.setNumber(SettingsRepository.KEY_LYRIC_CONTROL_SIZE, Number(value));
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  accountsStep() {
    Column({ space: 12 }) {
      this.stepTitle(5)
      this.stepBody('登录音乐平台解锁收藏夹、歌单与更高音质；数据可备份到云端。这些都可以稍后配置。')
      Column({ space: 8 }) {
        Text('账号与登录：设置 → 账号与登录（网易云扫码/网页登录，Bilibili 扫码/网页登录）')
          .fontSize(13)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .lineHeight(19)
        Text('云端备份：设置 → 云端（本机导出 / GitHub / WebDAV）')
          .fontSize(13)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .lineHeight(19)
      }
      .alignItems(HorizontalAlign.Start)
      .padding(14)
      .borderRadius(Theme.cardRadius())
      .backgroundColor(Theme.surface(Theme.isDark()))
      if (shouldWarnStartupNoPlatformConnected(this.neteaseLogged, this.biliLogged)) {
        Text('当前未登录任何平台：可以先离线体验本地音乐，需要在线内容时再回到设置连接账号。')
          .fontSize(12)
          .fontColor(Theme.textSecondary(Theme.isDark()))
          .lineHeight(18)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          .borderRadius(12)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  finishStep() {
    Column({ space: 18 }) {
      Image($r('app.media.ic_neriplayer'))
        .width(72)
        .height(72)
        .borderRadius(16)
      this.stepTitle(6)
      this.stepBody('一切就绪。去「探索」搜索歌曲，或到「资料库」导入本地音乐开始播放吧。')
      Text('所有设置均可随时在设置中调整；祝使用愉快。')
        .fontSize(13)
        .fontColor(Theme.textSecondary(Theme.isDark()))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    // 结构沿用旧版：600vp 正文栏宽 + 居中。步进制向导（按钮主导，不做
    // Swiper——设置项交互与横滑手势易冲突）；进度条在上，内容居中，
    // 底部「上一步/下一步」。
    Row() {
      Column() {
        Row({ space: 10 }) {
          this.stepBadge()
          Text(this.stepTitles()[this.step])
            .fontSize(13)
            .fontColor(Theme.textSecondary(Theme.isDark()))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding({ top: 18, bottom: 10 })

        Progress({ value: calculateStartupOnboardingProgress(this.step,
          STARTUP_ONBOARDING_STEP_COUNT) * 100, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(4)
          .color(Theme.primary(Theme.isDark()))
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          .margin({ bottom: 8 })

        Scroll() {
          Column() {
            if (this.step === 0) {
              this.welcomeStep()
            } else if (this.step === 1) {
              this.appearanceStep()
            } else if (this.step === 2) {
              this.sourcesStep()
            } else if (this.step === 3) {
              this.lyricsStep()
            } else if (this.step === 4) {
              this.controlsStep()
            } else if (this.step === 5) {
              this.accountsStep()
            } else {
              this.finishStep()
            }
          }
          .width('100%')
          .padding({ top: 14, bottom: 14 })
          .justifyContent(this.wideLayout() ? FlexAlign.Center : FlexAlign.Start)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .width('100%')

        Row({ space: 12 }) {
          if (this.step > 0) {
            Button('上一步')
              .height(44)
              .fontSize(15)
              .fontColor(Theme.textPrimary(Theme.isDark()))
              .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
              .layoutWeight(1)
              .constraintSize({ maxWidth: BAND_BUTTON_VP })
              .onClick(() => {
                this.step = Math.max(0, this.step - 1);
              })
          }
          Button(this.isLastStep() ? '进入应用' : '下一步')
            .height(44)
            .fontSize(15)
            .fontColor(Theme.onPrimary(Theme.isDark()))
            .backgroundColor(Theme.primary(Theme.isDark()))
            .layoutWeight(this.step > 0 ? 2 : 1)
            .constraintSize({ maxWidth: BAND_BUTTON_VP })
            .onClick(() => {
              if (this.isLastStep()) {
                this.onDone();
              } else {
                this.step = Math.min(STARTUP_ONBOARDING_STEP_COUNT - 1, this.step + 1);
              }
            })
        }
        .width('100%')
        .margin({ bottom: 30 })
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: BAND_TEXT_VP })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Theme.background(Theme.isDark()))
  }
}
