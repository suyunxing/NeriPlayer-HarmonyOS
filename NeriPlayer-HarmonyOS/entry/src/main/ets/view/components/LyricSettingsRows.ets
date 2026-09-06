import { SettingsRepository } from '../../data/SettingsRepository';
import { OptionEntry, OptionRow, ToggleRow } from './Ui';

/**
 * 歌词设置行组（设置页「歌词设置」分区与播放页歌词面板共用）。
 *
 * 每行自己订阅 `np.lyric_*` AppStorage 键并直接写 SettingsRepository，宿主
 * 无需传值，两处入口展示与生效的配置天然一致。
 */
@Component
export struct LyricSettingsRows {
  /** true 时行底色透明（用于 bindSheet 材质背景上）；默认不透明 surface。 */
  @Prop transparentBg: boolean = false;
  @StorageProp('np.lyric_font_size') lyricFontSize: number = 16;
  @StorageProp('np.lyric_offset_ms') lyricOffsetMs: number = 0;
  @StorageProp('np.amll_lyrics') amllLyrics: boolean = true;
  @StorageProp('np.lyric_translation') lyricTranslation: boolean = true;
  @StorageProp('np.lyric_phonetic') lyricPhonetic: boolean = false;
  @StorageProp('np.lyric_blur') lyricBlur: boolean = true;
  @StorageProp('np.floating_lyric') floatingLyric: boolean = false;
  @StorageProp('np.bt_lyric') btLyric: boolean = false;

  private fontSizeOptions(): OptionEntry[] {
    const options: OptionEntry[] = [];
    for (let size = 14; size <= 24; size += 2) {
      options.push({ value: `${size}`, label: `${size} sp` });
    }
    return options;
  }

  private lyricOffsetOptions(): OptionEntry[] {
    const options: OptionEntry[] = [
      { value: '0', label: '无偏移' },
      { value: '250', label: '提前 0.25s' },
      { value: '500', label: '提前 0.5s' },
      { value: '1000', label: '提前 1s' },
      { value: '-250', label: '延后 0.25s' },
      { value: '-500', label: '延后 0.5s' },
      { value: '-1000', label: '延后 1s' }
    ];
    return options;
  }

  private lyricOffsetSubtitle(): string {
    if (this.lyricOffsetMs === 0) {
      return '无偏移';
    }
    return this.lyricOffsetMs > 0 ? `提前 ${this.lyricOffsetMs} ms` : `延后 ${-this.lyricOffsetMs} ms`;
  }

  build() {
    Column({ space: 1 }) {
      OptionRow({
        title: '歌词字号',
        icon: '🔠',
        transparentBg: this.transparentBg,
        options: this.fontSizeOptions(),
        current: `${this.lyricFontSize}`,
        onPick: (value: string) =>
          SettingsRepository.setNumber(SettingsRepository.KEY_LYRIC_FONT_SIZE, Number(value))
      })
      OptionRow({
        title: '歌词偏移',
        icon: '⏱',
        subtitle: this.lyricOffsetSubtitle(),
        transparentBg: this.transparentBg,
        options: this.lyricOffsetOptions(),
        current: `${this.lyricOffsetMs}`,
        onPick: (value: string) =>
          SettingsRepository.setNumber(SettingsRepository.KEY_LYRIC_OFFSET_MS, Number(value))
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
        title: '显示翻译',
        icon: '🌐',
        transparentBg: this.transparentBg,
        value: this.lyricTranslation,
        onChange: (on: boolean) => SettingsRepository.setBoolean(SettingsRepository.KEY_LYRIC_TRANSLATION, on)
      })
      ToggleRow({
        title: '音译显示',
        icon: '🗣',
        transparentBg: this.transparentBg,
        value: this.lyricPhonetic,
        onChange: (on: boolean) => SettingsRepository.setBoolean(SettingsRepository.KEY_LYRIC_PHONETIC, on)
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
