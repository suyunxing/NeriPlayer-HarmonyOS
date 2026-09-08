import { curves } from '@kit.ArkUI';
import { LyricLine, LyricWord } from '../../model/LyricLine';
import { LyricLineLayout, LyricScrollMath } from '../../lyrics/LyricScrollMath';
import { Theme } from '../Theme';

const LYRIC_OFFSET_STORAGE_KEY = 'np.lyric_offset_ms';
const LYRIC_TRANSLATION_STORAGE_KEY = 'np.lyric_translation';
const LYRIC_PHONETIC_STORAGE_KEY = 'np.lyric_phonetic';
const LYRIC_FONT_SIZE_STORAGE_KEY = 'np.lyric_font_size';
const LYRIC_CENTER_STORAGE_KEY = 'np.lyric_center';
const LYRIC_FONT_WEIGHT_STORAGE_KEY = 'np.lyric_font_weight';
const LYRIC_LINE_SPACING_STORAGE_KEY = 'np.lyric_line_spacing';

// The reference lyric page uses an editorial, airy rhythm rather than a
// compact karaoke list. Keep the value in vp so it scales with the device;
// np.lyric_line_spacing scales it (1.0 = this base).
const LINE_SPACING = 22;
const ACTIVE_LINE_ANCHOR = 0.42;
/** How long a user-dragged line stays centered before re-syncing (spec: 2s). */
const USER_HOLD_REVERT_MS = 2000;
/** HarmonyOS physical spring for the auto-follow; duration is auto-derived. */
const FOLLOW_SPRING = curves.springMotion(0.42, 0.86);
/** Row height sentinel meaning "not measured yet" (a real row may be 0 high). */
const HEIGHT_UNMEASURED = -1;

/**
 * Centered, auto-scrolling lyric view.
 *
 * Follow mode: the playing line is kept centered via a spring scrollTo on
 * every line change. Scrub mode: a touch takes over (playback keeps running),
 * the line nearest the viewport center is highlighted and its time reported
 * through onScrubLine for the page's preview labels; after the finger leaves
 * and scrolling stops, the dragged position holds for USER_HOLD_REVERT_MS and
 * then springs back to the playing line. Tapping a line always seeks.
 */
@Component
export struct LyricView {
  // @Prop: the page mounts the view with [] first and fills lyrics after the
  // async fetch, so the child must re-render when the array is replaced.
  @Prop @Watch('onLyricsReplaced') lyrics: LyricLine[] = [];
  onSeek: (timeMs: number) => void = () => {};
  // Reports the centered line's playback time while scrubbing; -1 ends the preview.
  onScrubLine: (timeMs: number) => void = () => {};
  @StorageLink('player.positionMs') @Watch('onPositionChanged') positionMs: number = 0;
  // Global lyric offset (np.lyric_offset_ms, ms): applied at display time,
  // positive = lyrics advance (Android lyricOffsetMs semantics).
  @StorageProp(LYRIC_OFFSET_STORAGE_KEY) @Watch('onOffsetChanged') lyricOffsetMs: number = 0;
  @StorageProp(LYRIC_TRANSLATION_STORAGE_KEY) lyricTranslation: boolean = true;
  @StorageProp(LYRIC_PHONETIC_STORAGE_KEY) lyricPhonetic: boolean = false;
  @StorageProp(LYRIC_FONT_SIZE_STORAGE_KEY) lyricFontSize: number = 16;
  @StorageProp(LYRIC_CENTER_STORAGE_KEY) lyricCenter: boolean = true;
  @StorageProp(LYRIC_FONT_WEIGHT_STORAGE_KEY) lyricFontWeight: number = 500;
  @StorageProp(LYRIC_LINE_SPACING_STORAGE_KEY) lyricLineSpacing: number = 1.0;

  @State viewportHeight: number = 0;
  @State scrubIndex: number = -1;
  private scroller: Scroller = new Scroller();
  private rowHeights: number[] = [];
  private userHold: boolean = false;
  private userTouching: boolean = false;
  // Scroll already stopped while the finger was still down: wait for touch up
  // before arming the revert timer (another drag may still begin).
  private stoppedWhileHolding: boolean = false;
  // Distinguishes our own scrollTo from user gestures in onScroll callbacks.
  private programmaticScroll: boolean = false;
  private lastFollowedIndex: number = -1;
  private pendingInitial: boolean = false;
  private revertTimerId: number = -1;

  aboutToAppear(): void {
    this.onLyricsReplaced();
  }

  aboutToDisappear(): void {
    this.cancelRevert();
  }

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

  /** The line carrying the highlight: the scrub target while dragging, else the playing line. */
  private activeIndex(): number {
    return this.userHold && this.scrubIndex >= 0 ? this.scrubIndex : this.currentIndex();
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

  /** Active lyrics are dark and large; surrounding rows fade into the glass. */
  private lineOpacity(index: number): number {
    const active = this.activeIndex();
    if (active < 0) {
      return 0.7;
    }
    const distance = Math.abs(index - active);
    return Math.max(0.18, Math.pow(0.5, distance));
  }

  private lineFontSize(index: number): number {
    return index === this.activeIndex()
      ? this.lyricFontSize + 6
      : Math.max(18, this.lyricFontSize + 2);
  }

  /** np.lyric_line_spacing multiplier applied to the base 22vp rhythm. */
  private effectiveLineSpacing(): number {
    const clamped = Math.min(2.4, Math.max(0.4, this.lyricLineSpacing));
    return LINE_SPACING * clamped;
  }

  /** Text + column alignment derived from np.lyric_center. */
  private lineTextAlign(): TextAlign {
    return this.lyricCenter ? TextAlign.Center : TextAlign.Start;
  }

  private lineColumnAlign(): HorizontalAlign {
    return this.lyricCenter ? HorizontalAlign.Center : HorizontalAlign.Start;
  }

  // ---- Layout plumbing ----------------------------------------------------

  private topEdgePadding(): number {
    return this.viewportHeight > 0 ? Math.max(0, this.viewportHeight * ACTIVE_LINE_ANCHOR - 16) : 100;
  }

  private bottomEdgePadding(): number {
    return this.viewportHeight > 0 ? Math.max(0, this.viewportHeight * (1 - ACTIVE_LINE_ANCHOR) - 16) : 140;
  }

  /** LyricScrollMath centers within this virtual height, yielding the 42% anchor. */
  private anchorViewportHeight(): number {
    return this.viewportHeight * ACTIVE_LINE_ANCHOR * 2;
  }

  private layout(): LyricLineLayout {
    return LyricScrollMath.buildLayout(
      this.rowHeights,
      this.effectiveLineSpacing(),
      this.topEdgePadding(),
      this.bottomEdgePadding()
    );
  }

  private heightsMeasured(): boolean {
    if (this.lyrics.length === 0 || this.rowHeights.length !== this.lyrics.length) {
      return false;
    }
    for (let i = 0; i < this.rowHeights.length; i++) {
      if (this.rowHeights[i] === HEIGHT_UNMEASURED) {
        return false;
      }
    }
    return true;
  }

  private onLyricsReplaced(): void {
    this.cancelRevert();
    this.userHold = false;
    this.userTouching = false;
    this.stoppedWhileHolding = false;
    this.scrubIndex = -1;
    this.onScrubLine(-1);
    this.lastFollowedIndex = -1;
    this.pendingInitial = this.lyrics.length > 0;
    if (this.rowHeights.length !== this.lyrics.length) {
      this.rowHeights = new Array<number>(this.lyrics.length).fill(HEIGHT_UNMEASURED);
    }
    // Same-length replacement: keep the old measurements as an initial guess;
    // rows whose size changed re-measure through onAreaChange.
  }

  private onRowMeasured(index: number, height: number): void {
    if (index < 0 || index >= this.rowHeights.length || this.rowHeights[index] === height) {
      return;
    }
    this.rowHeights[index] = height;
    if (this.pendingInitial && this.heightsMeasured()) {
      this.initialFollow();
    } else if (!this.userHold && !this.pendingInitial && this.heightsMeasured()) {
      this.recenterIfDrifted();
    }
  }

  private onViewportMeasured(height: number): void {
    if (this.viewportHeight === height) {
      return;
    }
    this.viewportHeight = height;
    if (!this.userHold && this.heightsMeasured() && !this.pendingInitial) {
      this.recenterIfDrifted();
    }
  }

  /** Jump (no animation) to the playing line once heights are known. */
  private initialFollow(): void {
    this.pendingInitial = false;
    this.followCurrent(false);
    this.lastFollowedIndex = this.currentIndex();
  }

  /** Re-center after a re-layout (font size / translation toggle / viewport change). */
  private recenterIfDrifted(): void {
    const current = this.scroller.currentOffset().yOffset;
    const target = LyricScrollMath.targetScroll(
      Math.max(0, this.currentIndex()),
      this.layout(),
      this.anchorViewportHeight()
    );
    if (Math.abs(current - target) > 2) {
      this.followCurrent(true);
    }
  }

  // ---- Follow mode --------------------------------------------------------

  private onPositionChanged(): void {
    if (this.userHold) {
      return;
    }
    if (this.currentIndex() !== this.lastFollowedIndex) {
      this.followCurrent(true);
    }
  }

  private onOffsetChanged(): void {
    this.lastFollowedIndex = -1;
    if (!this.userHold) {
      this.followCurrent(true);
    }
  }

  private followCurrent(animated: boolean): void {
    if (this.lyrics.length === 0 || !this.heightsMeasured() || this.viewportHeight <= 0) {
      // Heights are not ready yet; the measurement callbacks will retry.
      this.pendingInitial = true;
      return;
    }
    const index = Math.max(0, this.currentIndex());
    this.lastFollowedIndex = this.currentIndex();
    const target = LyricScrollMath.targetScroll(index, this.layout(), this.anchorViewportHeight());
    // Zero-displacement scrolls never raise onDidScroll/onScrollStop, so the
    // programmatic flag must not be armed (it would wedge scrub mode).
    if (this.scroller.currentOffset().yOffset === target) {
      return;
    }
    // Both branches arm the flag: our own scrolls (animated or not) must be
    // indistinguishable from user drags in onDidScroll, or followCurrent's
    // jump would itself arm scrub mode. handleTouch(Down) disarms it.
    this.programmaticScroll = true;
    if (!animated) {
      this.scroller.scrollTo({ xOffset: 0, yOffset: target });
      return;
    }
    this.scroller.scrollTo({ xOffset: 0, yOffset: target, animation: { curve: FOLLOW_SPRING } });
  }

  // ---- Scrub mode ---------------------------------------------------------

  private handleTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.cancelRevert();
      this.userTouching = true;
      this.stoppedWhileHolding = false;
      // A touch during our own spring interrupts it and takes over.
      this.programmaticScroll = false;
      // userHold is NOT set here: a Down also arrives for horizontal swipes
      // that the pager (Swiper) will claim, which must not pause the auto
      // follow. Scrub mode is armed on the first real (non-programmatic)
      // scroll in handleScroll instead.
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.userTouching = false;
      if (this.stoppedWhileHolding) {
        this.stoppedWhileHolding = false;
        this.scheduleRevert();
      }
    }
  }

  private handleScroll(): void {
    if (this.programmaticScroll) {
      return;
    }
    if (!this.userHold) {
      this.userHold = true;
    }
    this.updateScrubFromOffset();
  }

  private handleScrollStop(): void {
    if (this.programmaticScroll) {
      this.programmaticScroll = false;
      return;
    }
    if (this.userHold) {
      if (this.userTouching) {
        this.stoppedWhileHolding = true;
      } else {
        this.scheduleRevert();
      }
    }
  }

  private updateScrubFromOffset(): void {
    if (!this.heightsMeasured() || this.viewportHeight <= 0) {
      return;
    }
    const scroll = this.scroller.currentOffset().yOffset;
    const index = LyricScrollMath.centeredIndex(scroll, this.layout(), this.anchorViewportHeight());
    if (index !== this.scrubIndex) {
      this.scrubIndex = index;
      if (index >= 0 && index < this.lyrics.length) {
        // Playback-domain time of this line, same conversion as the click-to-seek.
        this.onScrubLine(this.lyrics[index].timeMs - this.lyricOffsetMs);
      }
    }
  }

  private scheduleRevert(): void {
    this.cancelRevert();
    this.revertTimerId = setTimeout(() => {
      this.revertTimerId = -1;
      this.revertToPlaying();
    }, USER_HOLD_REVERT_MS);
  }

  private cancelRevert(): void {
    if (this.revertTimerId >= 0) {
      clearTimeout(this.revertTimerId);
      this.revertTimerId = -1;
    }
  }

  private revertToPlaying(): void {
    this.userHold = false;
    this.scrubIndex = -1;
    this.onScrubLine(-1);
    this.lastFollowedIndex = -1;
    this.followCurrent(true);
  }

  /** A tap seeks playback to the line; lyrics re-follow from the new position. */
  private handleLineTap(line: LyricLine): void {
    this.cancelRevert();
    this.userHold = false;
    this.scrubIndex = -1;
    this.onScrubLine(-1);
    this.lastFollowedIndex = -1;
    this.onSeek(line.timeMs - this.lyricOffsetMs);
  }

  @Builder
  activeWordLine(line: LyricLine) {
    Text() {
      ForEach(line.words, (word: LyricWord) => {
        Span(word.text)
          .fontColor(this.wordState(word) > 0 ? Theme.textPrimary(Theme.isDark()) : Theme.textSecondary(Theme.isDark()))
          .fontWeight(this.wordState(word) === 1 ? FontWeight.Medium : FontWeight.Normal)
      }, (word: LyricWord, index: number) => `${index}_${word.startMs}_${word.text}`)
    }
    .fontSize(this.lyricFontSize + 6)
    .fontWeight(this.lyricFontWeight)
    .textAlign(this.lineTextAlign())
    .width('100%')
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: this.effectiveLineSpacing() }) {
        if (this.lyrics.length === 0) {
          Text('暂无歌词')
            .fontSize(14)
            .fontColor(Theme.textSecondary(Theme.isDark()))
            .margin({ top: 40 })
        } else {
          ForEach(this.lyrics, (line: LyricLine, index: number) => {
            Column({ space: 6 }) {
              if (index === this.currentIndex() && index === this.activeIndex() && line.words.length > 0) {
                // Karaoke line: per-word highlight driven by positionMs. While
                // scrubbing the highlight belongs to the centered line instead.
                this.activeWordLine(line)
              } else {
                Text(line.text)
                  .fontSize(this.lineFontSize(index))
                  .fontColor(Theme.textPrimary(Theme.isDark()))
                  .fontWeight(index === this.activeIndex() ? this.lyricFontWeight : FontWeight.Normal)
                  .animation({ duration: 250, curve: Curve.EaseOut })
                  .textAlign(this.lineTextAlign())
                  .width('100%')
              }
              if (this.lyricTranslation && line.translated.length > 0) {
                Text(line.translated)
                  .fontSize(12)
                  .fontColor(Theme.textSecondary(Theme.isDark()))
                  .textAlign(this.lineTextAlign())
                  .width('100%')
              }
              if (this.lyricPhonetic && line.phonetic.length > 0) {
                Text(line.phonetic)
                  .fontSize(12)
                  .fontColor(Theme.textSecondary(Theme.isDark()))
                  .textAlign(this.lineTextAlign())
                  .width('100%')
              }
            }
            .alignItems(this.lineColumnAlign())
            .opacity(this.lineOpacity(index))
            .animation({ duration: 250, curve: Curve.EaseOut })
            .onClick(() => this.handleLineTap(line))
            .onAreaChange((_oldArea: Area, newArea: Area) => this.onRowMeasured(index, Number(newArea.height)))
          }, (line: LyricLine) => `${line.timeMs}_${line.text}`)
        }
      }
      .width('100%')
      .padding({ top: this.topEdgePadding(), bottom: this.bottomEdgePadding() })
    }
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .layoutWeight(1)
    .onAreaChange((_oldArea: Area, newArea: Area) => this.onViewportMeasured(Number(newArea.height)))
    .onTouch((event: TouchEvent) => this.handleTouch(event))
    .onDidScroll((_xOffset: number, _yOffset: number, _scrollState: ScrollState) => this.handleScroll())
    .onScrollStop(() => this.handleScrollStop())
  }
}
