import { LyricLine } from '../../model/LyricLine';
import { Theme } from '../Theme';

const LYRIC_OFFSET_STORAGE_KEY = 'np.lyric_offset_ms';

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
              Text(line.text)
                .fontSize(index === this.currentIndex() ? 18 : 14)
                .fontColor(index === this.currentIndex()
                  ? Theme.primary(Theme.isDark())
                  : Theme.textSecondary(Theme.isDark()))
                .fontWeight(index === this.currentIndex() ? FontWeight.Bold : FontWeight.Normal)
                .textAlign(TextAlign.Center)
                .width('100%')
              if (line.translated.length > 0) {
                Text(line.translated)
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
