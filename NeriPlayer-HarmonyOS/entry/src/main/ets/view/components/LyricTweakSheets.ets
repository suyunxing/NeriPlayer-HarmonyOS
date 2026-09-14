// SPDX-License-Identifier: GPL-3.0

import { SettingsRepository } from '../../data/SettingsRepository';
import { Theme } from '../Theme';
import { BottomSheetPanel } from './BottomSheetPanel';

const OFFSET_LIMIT_MS = 10000;
const FONT_MIN = 14;
const FONT_MAX = 24;
const FONT_STEP = 2;

/** 「调整歌词偏移」面板：写全局 np.lyric_offset_ms，LyricView 经 @StorageProp 即时生效。 */
@Component
export struct LyricOffsetSheet {
  onClose: () => void = () => {};
  @StorageProp(SettingsRepository.KEY_LYRIC_OFFSET_MS) offsetMs: number = 0;

  private adjust(deltaMs: number): void {
    const next = Math.max(-OFFSET_LIMIT_MS, Math.min(OFFSET_LIMIT_MS, this.offsetMs + deltaMs));
    SettingsRepository.setNumber(SettingsRepository.KEY_LYRIC_OFFSET_MS, next);
  }

  private offsetLabel(): string {
    if (this.offsetMs === 0) {
      return '无偏移';
    }
    const seconds = parseFloat((Math.abs(this.offsetMs) / 1000).toFixed(2));
    return this.offsetMs > 0 ? `提前 ${seconds}s` : `延后 ${seconds}s`;
  }

  build() {
    BottomSheetPanel({
      title: '调整歌词偏移',
      onClose: () => this.onClose()
    }) {
      Column({ space: 10 }) {
        Text(this.offsetLabel())
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.primary(Theme.isDark()))
          .width('100%')
          .textAlign(TextAlign.Center)
        Text('正值让歌词提前显示，负值让歌词延后，立即生效并全局保存。')
          .fontSize(11)
          .fontColor(Theme.textSecondary(Theme.isDark()))
          .width('100%')
          .textAlign(TextAlign.Center)
        Row({ space: 8 }) {
          Button('-0.25s')
            .adjustButtonStyle()
            .onClick(() => this.adjust(-250))
          Button('-0.05s')
            .adjustButtonStyle()
            .onClick(() => this.adjust(-50))
          Button('重置')
            .adjustButtonStyle()
            .fontColor(Theme.danger(Theme.isDark()))
            .onClick(() => SettingsRepository.setNumber(SettingsRepository.KEY_LYRIC_OFFSET_MS, 0))
          Button('+0.05s')
            .adjustButtonStyle()
            .onClick(() => this.adjust(50))
          Button('+0.25s')
            .adjustButtonStyle()
            .onClick(() => this.adjust(250))
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceEvenly)
        .padding({ top: 4 })
      }
      .width('100%')
    }
  }
}

/** 「歌词字体大小」面板：写 np.lyric_font_size（14..24，步进 2），带实时预览。 */
@Component
export struct LyricFontSizeSheet {
  onClose: () => void = () => {};
  @StorageProp(SettingsRepository.KEY_LYRIC_FONT_SIZE) fontSize: number = 16;

  private adjust(delta: number): void {
    const next = Math.max(FONT_MIN, Math.min(FONT_MAX, this.fontSize + delta));
    SettingsRepository.setNumber(SettingsRepository.KEY_LYRIC_FONT_SIZE, next);
  }

  build() {
    BottomSheetPanel({
      title: '歌词字体大小',
      onClose: () => this.onClose()
    }) {
      Column({ space: 10 }) {
        Row({ space: 16 }) {
          Button('A-')
            .fontSize(16)
            .width(52)
            .height(40)
            .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
            .fontColor(this.fontSize > FONT_MIN
              ? Theme.textPrimary(Theme.isDark())
              : Theme.textDisabled(Theme.isDark()))
            .enabled(this.fontSize > FONT_MIN)
            .accessibilityText('减小歌词字体')
            .onClick(() => this.adjust(-FONT_STEP))
          Column({ space: 4 }) {
            Text('这是歌词预览')
              .fontSize(this.fontSize)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.textPrimary(Theme.isDark()))
              .maxLines(1)
            Text(`${this.fontSize}sp`)
              .fontSize(12)
              .fontColor(Theme.textSecondary(Theme.isDark()))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          Button('A+')
            .fontSize(16)
            .width(52)
            .height(40)
            .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
            .fontColor(this.fontSize < FONT_MAX
              ? Theme.textPrimary(Theme.isDark())
              : Theme.textDisabled(Theme.isDark()))
            .enabled(this.fontSize < FONT_MAX)
            .accessibilityText('增大歌词字体')
            .onClick(() => this.adjust(FONT_STEP))
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
      }
      .width('100%')
    }
  }
}

/** 二级面板里的 40vp 触达小按钮统一外观。 */
@Extend(Button)
function adjustButtonStyle() {
  .height(40)
  .fontSize(12)
  .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
  .fontColor(Theme.textPrimary(Theme.isDark()))
}
