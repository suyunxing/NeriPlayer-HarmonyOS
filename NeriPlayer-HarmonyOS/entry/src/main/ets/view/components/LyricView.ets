import { LyricLine, LyricWord } from '../../model/LyricLine';
import { Theme } from '../Theme';

const LYRIC_OFFSET_STORAGE_KEY = 'np.lyric_offset_ms';
const LYRIC_TRANSLATION_STORAGE_KEY = 'np.lyric_translation';
const LYRIC_PHONETIC_STORAGE_KEY = 'np.lyric_phonetic';
const LYRIC_FONT_SIZE_STORAGE_KEY = 'np.lyric_font_size';

@Component
export struct LyricView {
  // @Prop: the page mounts the view with [] first and fills lyrics after the
  // async fetch, so the child must re-render when the array is replaced.
  @Prop lyrics: LyricLine[] = [];
  onSeek: (timeMs: number) => void = () => {};
  @StorageLink('player.positionMs') positionMs: number = 0;
  // Global lyric offset (np.lyric_offset_ms, ms): applied at display time,
  // positive = lyrics advance (Android lyricOffsetMs semantics).
  @StorageProp(LYRIC_OFFSET_STORAGE_KEY) lyricOffsetMs: number = 0;
  @StorageProp(LYRIC_TRANSLATION_STORAGE_KEY) lyricTranslation: boolean = true;
  @StorageProp(LYRIC_PHONETIC_STORAGE_KEY) lyricPhonetic: boolean = false;
  @StorageProp(LYRIC_FONT_SIZE_STORAGE_KEY) lyricFontSize: number = 16;

  private currentIndex(): number {
    const selectionTimeMs = this.positionMs + this.lyricOffsetMs;
    let index = -1;
    for (let i = 0; i < this.lyrics.length; i++) {
      if (this.lyrics[i].timeMs <= selectionTimeMs) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  /** Word state for karaoke highlighting: 0 = upcoming, 1 = active, 2 = sung. */
  private wordState(word: LyricWord): number {
    const selectionTimeMs = this.positionMs + this.lyricOffsetMs;
    if (selectionTimeMs >= word.endMs) {
      return 2;
    }
    if (selectionTimeMs >= word.startMs) {
      return 1;
    }
    return 0;
  }

  @Builder
  activeWordLine(line: LyricLine) {
    Text() {
      ForEach(line.words, (word: LyricWord) => {
        Span(word.text)
          .fontColor(this.wordState(word) > 0 ? Theme.primary(Theme.isDark()) : Theme.textSecondary(Theme.isDark()))
          .fontWeight(this.wordState(word) === 1 ? FontWeight.Bold : FontWeight.Normal)
      }, (word: LyricWord, index: number) => `${index}_${word.startMs}_${word.text}`)
    }
    .fontSize(this.lyricFontSize + 2)
    .textAlign(TextAlign.Center)
    .width('100%')
  }

  build() {
    Scroll() {
      Column({ space: 10 }) {
        if (this.lyrics.length === 0) {
          Text('暂无歌词')
            .fontSize(14)
            .fontColor(Theme.textSecondary(Theme.isDark()))
            .margin({ top: 40 })
        } else {
          ForEach(this.lyrics, (line: LyricLine, index: number) => {
            Column({ space: 4 }) {
              if (index === this.currentIndex() && line.words.length > 0) {
                // Karaoke line: per-word highlight driven by positionMs.
                this.activeWordLine(line)
              } else {
                Text(line.text)
                  .fontSize(index === this.currentIndex() ? this.lyricFontSize + 2 : this.lyricFontSize - 2)
                  .fontColor(index === this.currentIndex()
                    ? Theme.primary(Theme.isDark())
                    : Theme.textSecondary(Theme.isDark()))
                  .fontWeight(index === this.currentIndex() ? FontWeight.Bold : FontWeight.Normal)
                  .textAlign(TextAlign.Center)
                  .width('100%')
              }
              if (this.lyricTranslation && line.translated.length > 0) {
                Text(line.translated)
                  .fontSize(12)
                  .fontColor(Theme.textSecondary(Theme.isDark()))
                  .textAlign(TextAlign.Center)
                  .width('100%')
              }
              if (this.lyricPhonetic && line.phonetic.length > 0) {
                Text(line.phonetic)
                  .fontSize(12)
                  .fontColor(Theme.textSecondary(Theme.isDark()))
                  .textAlign(TextAlign.Center)
                  .width('100%')
              }
            }
            .onClick(() => this.onSeek(line.timeMs - this.lyricOffsetMs))
          }, (line: LyricLine) => `${line.timeMs}_${line.text}`)
        }
      }
      .width('100%')
      .padding({ top: 24, bottom: 24 })
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .layoutWeight(1)
  }
}
