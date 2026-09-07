import { SettingsRepository } from '../../data/SettingsRepository';
import { OptionEntry, OptionRow, SliderRow, ToggleRow } from './Ui';
import { Theme } from '../Theme';

/**
 * 歌词设置行组（设置页「歌词设置」分区与播放页歌词面板共用）。
 *
 * 每行自己订阅 `np.lyric_*` AppStorage 键并直接写 SettingsRepository，宿主
 * 无需传值，两处入口展示与生效的配置天然一致。字号/偏移/字重/行距按参考
 * 应用做成滑杆（拖动实时预览数值，松手才落库）。
 */
@Component
export struct LyricSettingsRows {
  /** true 时行底色透明（用于 bindSheet 材质背景上）；默认不透明 surface。 */
  @Prop transparentBg: boolean = false;
  @StorageProp('np.lyric_font_size') lyricFontSize: number = 16;
  @StorageProp('np.lyric_offset_ms') lyricOffsetMs: number = 0;
  @StorageProp('np.lyric_center') lyricCenter: boolean = true;
  @StorageProp('np.lyric_font_weight') lyricFontWeight: number = 500;
  @StorageProp('np.lyric_line_spacing') lyricLineSpacing: number = 1.0;
  @StorageProp('np.amll_lyrics') amllLyrics: boolean = true;
  @StorageProp('np.lyric_translation') lyricTranslation: boolean = true;
  @StorageProp('np.lyric_phonetic') lyricPhonetic: boolean = false;
  @StorageProp('np.lyric_blur') lyricBlur: boolean = true;
  @StorageProp('np.floating_lyric') floatingLyric: boolean = false;
  @StorageProp('np.bt_lyric') btLyric: boolean = false;

  private offsetText(value: number): string {
    if (value === 0) {
      return '0';
    }
    return value > 0 ? `提前 ${value}` : `延后 ${-value}`;
  }

  /** 多行歌词副行的当前档位（写回时同时维护 translation/phonetic 两个键）。 */
  private secondaryLineOptions(): OptionEntry[] {
    const options: OptionEntry[] = [
      { value: 'translation', label: '中文翻译' },
      { value: 'phonetic', label: '发音音译' },
      { value: 'off', label: '不显示' }
    ];
    return options;
  }

  private secondaryLineCurrent(): string {
    if (this.lyricPhonetic) {
      return 'phonetic';
    }
    return this.lyricTranslation ? 'translation' : 'off';
  }

  private applySecondaryLine(value: string): void {
    SettingsRepository.setBoolean(SettingsRepository.KEY_LYRIC_TRANSLATION, value === 'translation');
    SettingsRepository.setBoolean(SettingsRepository.KEY_LYRIC_PHONETIC, value === 'phonetic');
  }

  build() {
    Column({ space: 1 }) {
      ToggleRow({
        title: '歌词居中显示',
        subtitle: '关闭后歌词靠左对齐',
        icon: '⇹',
        transparentBg: this.transparentBg,
        value: this.lyricCenter,
        onChange: (on: boolean) => SettingsRepository.setBoolean(SettingsRepository.KEY_LYRIC_CENTER, on)
      })
      SliderRow({
        title: '歌词字号',
        icon: '🔠',
        transparentBg: this.transparentBg,
        min: 14,
        max: 24,
        step: 1,
        value: this.lyricFontSize,
        format: (value: number) => `${Math.round(value)}`,
        onPick: (value: number) =>
          SettingsRepository.setNumber(SettingsRepository.KEY_LYRIC_FONT_SIZE, Math.round(value))
      })
      SliderRow({
        title: '字体粗细',
        icon: '𝐁',
        transparentBg: this.transparentBg,
        min: 100,
        max: 900,
        step: 100,
        value: this.lyricFontWeight,
        format: (value: number) => `${Math.round(value)}`,
        onPick: (value: number) =>
          SettingsRepository.setNumber(SettingsRepository.KEY_LYRIC_FONT_WEIGHT, Math.round(value))
      })
      SliderRow({
        title: '歌词行间距',
        icon: '↕',
        transparentBg: this.transparentBg,
        min: 0.6,
        max: 2,
        step: 0.1,
        value: this.lyricLineSpacing,
        format: (value: number) => `${value.toFixed(1)} 倍`,
        onPick: (value: number) =>
          SettingsRepository.setNumber(SettingsRepository.KEY_LYRIC_LINE_SPACING, Math.round(value * 10) / 10)
      })
      SliderRow({
        title: '歌词时间偏移',
        icon: '⏱',
        transparentBg: this.transparentBg,
        min: -1000,
        max: 1000,
        step: 50,
        value: this.lyricOffsetMs,
        format: (value: number) => this.offsetText(Math.round(value)),
        onPick: (value: number) =>
          SettingsRepository.setNumber(SettingsRepository.KEY_LYRIC_OFFSET_MS, Math.round(value))
      })
      OptionRow({
        title: '多行歌词副行',
        subtitle: '主歌词下方的第二行内容',
        icon: '🌐',
        transparentBg: this.transparentBg,
        options: this.secondaryLineOptions(),
        current: this.secondaryLineCurrent(),
        onPick: (value: string) => this.applySecondaryLine(value)
      })
      ToggleRow({
        title: 'AMLL 逐字歌词',
        subtitle: '优先逐字 TTML 词库',
        icon: '✍',
        transparentBg: this.transparentBg,
        value: this.amllLyrics,
        onChange: (on: boolean) => SettingsRepository.setBoolean(SettingsRepository.KEY_AMLL_LYRICS, on)
      })
      ToggleRow({
        title: '歌词模糊效果',
        icon: '🌫',
        transparentBg: this.transparentBg,
        value: this.lyricBlur,
        onChange: (on: boolean) => SettingsRepository.setBoolean(SettingsRepository.KEY_LYRIC_BLUR, on)
      })
      ToggleRow({
        title: '应用内悬浮歌词',
        subtitle: '页面顶部悬浮一行，系统级悬浮不受支持',
        icon: '👓',
        transparentBg: this.transparentBg,
        value: this.floatingLyric,
        onChange: (on: boolean) => SettingsRepository.setBoolean(SettingsRepository.KEY_FLOATING_LYRIC, on)
      })
      ToggleRow({
        title: '通知栏/蓝牙歌词',
        subtitle: '播放时通知栏与蓝牙设备显示当前歌词行',
        icon: '📡',
        transparentBg: this.transparentBg,
        value: this.btLyric,
        onChange: (on: boolean) => SettingsRepository.setBoolean(SettingsRepository.KEY_BT_LYRIC, on)
      })
    }
    .width('100%')
  }
}

/**
 * 歌词排版「效果预览」卡片（设置页歌词分区专用，不进播放页半模态面板）：
 * 用当前字号/字重/行距/居中/副行配置渲染两行示例，所见即所得。
 */
@Component
export struct LyricStylePreview {
  @StorageProp('np.lyric_font_size') lyricFontSize: number = 16;
  @StorageProp('np.lyric_font_weight') lyricFontWeight: number = 500;
  @StorageProp('np.lyric_line_spacing') lyricLineSpacing: number = 1.0;
  @StorageProp('np.lyric_center') lyricCenter: boolean = true;
  @StorageProp('np.lyric_translation') lyricTranslation: boolean = true;
  @StorageProp('np.lyric_phonetic') lyricPhonetic: boolean = false;

  build() {
    Column() {
      Text('效果预览')
        .fontSize(13)
        .fontColor(Theme.textSecondary(Theme.isDark()))
        .width('100%')
        .margin({ left: 6, top: 14, bottom: 6 })

      Column({ space: 10 * this.lyricLineSpacing }) {
        Column({ space: 3 }) {
          Text('这是一句歌词')
            .fontSize(Math.max(18, this.lyricFontSize + 2))
            .fontColor(Theme.textSecondary(Theme.isDark()))
            .fontWeight(FontWeight.Normal)
            .textAlign(this.lyricCenter ? TextAlign.Center : TextAlign.Start)
            .width('100%')
          if (this.lyricTranslation) {
            Text('这是中文翻译')
              .fontSize(12)
              .fontColor(Theme.textDisabled(Theme.isDark()))
              .textAlign(this.lyricCenter ? TextAlign.Center : TextAlign.Start)
              .width('100%')
          }
          if (this.lyricPhonetic) {
            Text('zhè shì fā yīn')
              .fontSize(12)
              .fontColor(Theme.textDisabled(Theme.isDark()))
              .textAlign(this.lyricCenter ? TextAlign.Center : TextAlign.Start)
              .width('100%')
          }
        }
        .alignItems(this.lyricCenter ? HorizontalAlign.Center : HorizontalAlign.Start)
        .width('100%')

        Column({ space: 3 }) {
          Text('这是当前歌词高亮效果')
            .fontSize(this.lyricFontSize + 6)
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .fontWeight(this.lyricFontWeight)
            .textAlign(this.lyricCenter ? TextAlign.Center : TextAlign.Start)
            .width('100%')
          if (this.lyricTranslation) {
            Text('这是高亮行的中文翻译')
              .fontSize(12)
              .fontColor(Theme.textSecondary(Theme.isDark()))
              .textAlign(this.lyricCenter ? TextAlign.Center : TextAlign.Start)
              .width('100%')
          }
          if (this.lyricPhonetic) {
            Text('zhè shì gāo liàng xíng')
              .fontSize(12)
              .fontColor(Theme.textSecondary(Theme.isDark()))
              .textAlign(this.lyricCenter ? TextAlign.Center : TextAlign.Start)
              .width('100%')
          }
        }
        .alignItems(this.lyricCenter ? HorizontalAlign.Center : HorizontalAlign.Start)
        .width('100%')
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 16 })
      .backgroundColor(Theme.surface(Theme.isDark()))
      .borderRadius(Theme.cardRadius())
    }
    .width('100%')
  }
}
