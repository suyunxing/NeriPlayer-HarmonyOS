import { LyricLine } from '../../model/LyricLine';
import { Theme } from '../Theme';

@Component
export struct LyricView {
  lyrics: LyricLine[] = [];
  onSeek: (timeMs: number) => void = () => {};
  @StorageLink('player.positionMs') positionMs: number = 0;

  private currentIndex(): number {
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
            .onClick(() => this.onSeek(line.timeMs))
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
