import { LyricLine, LyricWord } from '../../model/LyricLine';
import { LyricIndexResolver } from '../../lyrics/LyricIndexResolver';
import { Theme } from '../Theme';

const LYRIC_OFFSET_STORAGE_KEY = 'np.lyric_offset_ms';
const LYRIC_TRANSLATION_STORAGE_KEY = 'np.lyric_translation';
const LYRIC_PHONETIC_STORAGE_KEY = 'np.lyric_phonetic';
const LYRIC_FONT_SIZE_STORAGE_KEY = 'np.lyric_font_size';
const LYRIC_BLUR_STORAGE_KEY = 'np.lyric_blur';

/**
 * Where the active line is parked in the viewport, as a fraction of its
 * height. Mirrors Android's playedLyricViewportFraction = 0.30f
 * (ui/component/lyrics/SyncedLyricsView.kt).
 */
const ACTIVE_LINE_VIEWPORT_FRACTION: number = 0.30;
/** Auto-scroll steps aside for this long after the user last touched the list. */
const USER_SCROLL_GRACE_MS: number = 2500;
/** Ceiling for the distance-based blur of inactive lines, in vp. */
const MAX_INACTIVE_BLUR_VP: number = 4;
const SCROLL_ANIMATION_MS: number = 420;
/** lineTops entry meaning "not measured yet". */
const UNMEASURED: number = -1;

@Component
export struct LyricView {
  @StorageProp('theme.isDark') isDark: boolean = false; // see Theme.IS_DARK_KEY
  // @Prop: the page mounts the view with [] first and fills lyrics after the
  // async fetch, so the child must re-render when the array is replaced.
  @Prop @Watch('onLyricsChanged') lyrics: LyricLine[] = [];
  onSeek: (timeMs: number) => void = () => {};
  @StorageLink('player.positionMs') @Watch('onPositionChanged') positionMs: number = 0;
  // Global lyric offset (np.lyric_offset_ms, ms): applied at display time,
  // positive = lyrics advance (Android lyricOffsetMs semantics).
  @StorageProp(LYRIC_OFFSET_STORAGE_KEY) @Watch('onPositionChanged') lyricOffsetMs: number = 0;
  @StorageProp(LYRIC_TRANSLATION_STORAGE_KEY) lyricTranslation: boolean = true;
  @StorageProp(LYRIC_PHONETIC_STORAGE_KEY) lyricPhonetic: boolean = false;
  @StorageProp(LYRIC_FONT_SIZE_STORAGE_KEY) lyricFontSize: number = 16;
  // np.lyric_blur had a switch and a subtitle but no consumer anywhere in
  // main/ets until now. Inactive lines blur by distance from the active one,
  // matching AdvancedLyricsView.lyricBlurEnabled. (The M11 review proposed
  // blurring the *active* line, which would blur the line being read.)
  @StorageProp(LYRIC_BLUR_STORAGE_KEY) lyricBlur: boolean = true;

  // Resolved once per position tick and then read by every line. The previous
  // currentIndex() was called four times per rendered line inside ForEach —
  // an O(lines x rebuilds) scan on the most frequent path in the app.
  @State activeIndex: number = -1;
  // Drives the leading/trailing padding that lets the first and last lines
  // still reach the 30% band, so it has to be observable.
  @State viewportHeight: number = 0;

  private scroller: Scroller = new Scroller();
  // Y offset of each line inside the scrolling Column, captured from layout.
  // A plain field rather than @State: it is read only by the scroll maths, and
  // writing @State from a layout callback would re-enter layout every frame.
  private lineTops: number[] = [];
  private lastScrolledIndex: number = UNMEASURED;
  private userScrollUntilMs: number = 0;
  private lyricsSignature: string = '';

  aboutToAppear(): void {
    this.onLyricsChanged();
  }

  private displayTimeMs(): number {
    return this.positionMs + this.lyricOffsetMs;
  }

  /**
   * Active line for the current playhead. Resumes from `hint` and walks
   * forward, which is O(1) on the common path (the playhead crosses one line
   * at a time); a backward seek falls back to a scan from the top.
   */
  private resolveActiveIndex(hint: number): number {
    return LyricIndexResolver.resolve(this.lyrics, this.displayTimeMs(), hint);
  }

  private onPositionChanged(): void {
    const next = this.resolveActiveIndex(this.activeIndex);
    if (next === this.activeIndex) {
      return;
    }
    this.activeIndex = next;
    this.scrollToActive(next);
  }

  private onLyricsChanged(): void {
    const lines = this.lyrics;
    const signature = lines.length === 0
      ? 'empty'
      : `${lines.length}_${lines[0].timeMs}_${lines[lines.length - 1].timeMs}`;
    // @Prop re-copies the array whenever the parent rebuilds, and
    // NowPlayingPage rebuilds on every position tick, so guard on content
    // instead of resetting the scroll state dozens of times a second.
    if (signature === this.lyricsSignature) {
      return;
    }
    this.lyricsSignature = signature;
    const tops: number[] = [];
    for (let i = 0; i < lines.length; i++) {
      tops.push(UNMEASURED);
    }
    this.lineTops = tops;
    this.lastScrolledIndex = UNMEASURED;
    this.userScrollUntilMs = 0;
    this.activeIndex = this.resolveActiveIndex(-1);
  }

  private scrollToActive(index: number): void {
    if (index < 0 || index === this.lastScrolledIndex || this.viewportHeight <= 0) {
      return;
    }
    // Leave a manual scroll alone briefly, or auto-scroll fights the finger.
    if (Date.now() < this.userScrollUntilMs) {
      return;
    }
    const top = index < this.lineTops.length ? this.lineTops[index] : UNMEASURED;
    if (top === UNMEASURED) {
      // Geometry is not known yet; recordLineTop retries once it is.
      return;
    }
    this.lastScrolledIndex = index;
    this.scroller.scrollTo({
      xOffset: 0,
      yOffset: Math.max(0, top - this.viewportHeight * ACTIVE_LINE_VIEWPORT_FRACTION),
      animation: { duration: SCROLL_ANIMATION_MS, curve: Curve.EaseOut }
    });
  }

  /** Area/Position carry Length; layout callbacks deliver plain vp numbers. */
  private recordLineTop(index: number, area: Area): void {
    const y = area.position.y;
    if (typeof y !== 'number' || index >= this.lineTops.length) {
      return;
    }
    this.lineTops[index] = y;
    // First measurement of the active line: run the scroll that scrollToActive
    // had to skip while the geometry was still unknown.
    if (index === this.activeIndex && this.lastScrolledIndex !== index) {
      this.scrollToActive(index);
    }
  }

  private recordViewportHeight(area: Area): void {
    const height = area.height;
    // The 1vp deadband stops a padding -> relayout -> onAreaChange loop.
    if (typeof height !== 'number' || Math.abs(height - this.viewportHeight) < 1) {
      return;
    }
    this.viewportHeight = height;
    this.scrollToActive(this.activeIndex);
  }

  private onLineTap(line: LyricLine): void {
    // A tap is a seek, so re-arm auto-scroll immediately rather than honouring
    // the manual-scroll grace period this very touch just started.
    this.userScrollUntilMs = 0;
    this.lastScrolledIndex = UNMEASURED;
    this.onSeek(line.timeMs - this.lyricOffsetMs);
  }

  // Karaoke line: positionMs and lyricOffsetMs are read straight out of the
  // expressions instead of through a wordState() helper. ArkUI cannot track
  // state read inside a method call (M7.4), so the helper left the per-word
  // highlight repainting only by accident, when an unrelated parent rebuild
  // happened to recreate the whole view.
  @Builder
  activeWordLine(line: LyricLine) {
    Text() {
      ForEach(line.words, (word: LyricWord) => {
        Span(word.text)
          .fontColor(this.positionMs + this.lyricOffsetMs >= word.startMs
            ? Theme.primary(this.isDark)
            : Theme.textSecondary(this.isDark))
          .fontWeight(this.positionMs + this.lyricOffsetMs >= word.startMs
            && this.positionMs + this.lyricOffsetMs < word.endMs
            ? FontWeight.Bold
            : FontWeight.Normal)
      }, (word: LyricWord, index: number) => `${index}_${word.startMs}_${word.text}`)
    }
    .fontSize(this.lyricFontSize + 2)
    .textAlign(TextAlign.Center)
    .width('100%')
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: 10 }) {
        if (this.lyrics.length === 0) {
          Text('暂无歌词')
            .fontSize(14)
            .fontColor(Theme.textSecondary(this.isDark))
            .margin({ top: 40 })
        } else {
          ForEach(this.lyrics, (line: LyricLine, index: number) => {
            Column({ space: 4 }) {
              if (index === this.activeIndex && line.words.length > 0) {
                this.activeWordLine(line)
              } else {
                Text(line.text)
                  .fontSize(index === this.activeIndex ? this.lyricFontSize + 2 : this.lyricFontSize - 2)
                  .fontColor(index === this.activeIndex
                    ? Theme.primary(this.isDark)
                    : Theme.textSecondary(this.isDark))
                  .fontWeight(index === this.activeIndex ? FontWeight.Bold : FontWeight.Normal)
                  .textAlign(TextAlign.Center)
                  .width('100%')
              }
              if (this.lyricTranslation && line.translated.length > 0) {
                Text(line.translated)
                  .fontSize(12)
                  .fontColor(Theme.textSecondary(this.isDark))
                  .textAlign(TextAlign.Center)
                  .width('100%')
              }
              if (this.lyricPhonetic && line.phonetic.length > 0) {
                Text(line.phonetic)
                  .fontSize(12)
                  .fontColor(Theme.textSecondary(this.isDark))
                  .textAlign(TextAlign.Center)
                  .width('100%')
              }
            }
            .width('100%')
            // lyricBlur/activeIndex are read here rather than in a blurFor()
            // helper: a helper would be invisible to minimal-update tracking
            // and the blur would never re-evaluate as the active line moves.
            .blur(this.lyricBlur && this.activeIndex >= 0 && index !== this.activeIndex
              ? Math.min(MAX_INACTIVE_BLUR_VP, Math.abs(index - this.activeIndex))
              : 0)
            .onAreaChange((_oldArea: Area, newArea: Area) => {
              this.recordLineTop(index, newArea);
            })
            .onClick(() => this.onLineTap(line))
          }, (line: LyricLine) => `${line.timeMs}_${line.text}`)
        }
      }
      .width('100%')
      // Leading/trailing room so the first and last lines can still reach the
      // 30% band instead of being pinned against the viewport edges.
      .padding({
        top: this.lyrics.length === 0
          ? 24
          : Math.max(24, this.viewportHeight * ACTIVE_LINE_VIEWPORT_FRACTION),
        bottom: this.lyrics.length === 0
          ? 24
          : Math.max(24, this.viewportHeight * (1 - ACTIVE_LINE_VIEWPORT_FRACTION))
      })
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .layoutWeight(1)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.recordViewportHeight(newArea);
    })
    .onTouch((event: TouchEvent) => {
      // Any finger contact defers auto-scroll; onLineTap clears the deferral
      // again when the touch turns out to have been a seek.
      if (event.type === TouchType.Down || event.type === TouchType.Move) {
        this.userScrollUntilMs = Date.now() + USER_SCROLL_GRACE_MS;
      }
    })
  }
}
