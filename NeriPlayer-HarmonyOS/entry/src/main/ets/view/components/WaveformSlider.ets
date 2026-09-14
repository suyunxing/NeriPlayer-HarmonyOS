// SPDX-License-Identifier: GPL-3.0

/**
 * Linear playback progress bar (the successor of the waveform slider): a thin
 * round-capped track spanning the full width with the played part drawn on
 * top in the accent color, slightly thicker. The accent segment's round cap
 * protrudes over the unplayed track and forms the connecting arc between the
 * two segments; both ends are clipped flush against the canvas edges. Colors
 * come from the cover scheme via the parent (unplayed = secondary, played =
 * accent), so the bar re-tints together with the rest of the page.
 *
 * Scrubbing is absolute (Material Slider contract): the preview jumps to the
 * touch point and follows the finger, and the seek fires on release/tap. The
 * 50ms repaint timer keeps the bar in sync while positionMs advances and
 * drives the buffering pulse while loading.
 *
 * Units: canvasWidth comes from renderContext.width and GestureEvent.localX /
 * ClickEvent.x are component-local values in vp, so all fraction math stays
 * in vp — never convert either side to px.
 */
import { Logger } from '../../app/Logger';

const REPAINT_INTERVAL_MS = 50;
const TRACK_HEIGHT_PX = 4;
const PLAYED_HEIGHT_PX = 6;
const PULSE_LOOP_MS = 1400;

@Component
export struct WaveformSlider {
  @Prop positionMs: number = 0;
  @Prop durationMs: number = 0;
  @Prop playing: boolean = false;
  @Prop loading: boolean = false;
  /** Unplayed track color: the cover scheme's secondary tone. */
  @Prop unplayedColor: string = '#80FFFFFF';
  /** Played segment color: the scheme accent (same source as the home FAB). */
  @Prop playedColor: string = '#FFFFFF';
  onSeek: (ms: number) => void = () => {};
  /** Drag preview as a 0..1 fraction; -1 restores the live position. */
  onPreview: (fraction: number) => void = () => {};

  private canvasWidth: number = 0;
  private canvasHeight: number = 0;
  private repaintTimer: number = -1;
  private frameTime: number = 0;
  /** Fraction under the finger at touch-down; anchors the absolute pan. */
  private panBaseFraction: number = -1;
  @State previewFraction: number = -1;

  private renderContext: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));

  aboutToDisappear(): void {
    this.stopTimer();
  }

  private startTimer(): void {
    if (this.repaintTimer >= 0) {
      return;
    }
    this.frameTime = Date.now();
    this.repaintTimer = setInterval(() => {
      this.draw();
    }, REPAINT_INTERVAL_MS);
  }

  private stopTimer(): void {
    if (this.repaintTimer >= 0) {
      clearInterval(this.repaintTimer);
      this.repaintTimer = -1;
    }
  }

  private fraction(): number {
    const duration = Math.max(1, this.durationMs);
    const raw = this.previewFraction >= 0 ? this.previewFraction : this.positionMs / duration;
    return Math.max(0, Math.min(1, raw));
  }

  /** Maps a component-local touch x to the 0..1 bar fraction (both in vp). */
  private fractionAt(localX: number): number {
    if (this.canvasWidth <= 0) {
      return 0;
    }
    return Math.max(0, Math.min(1, localX / this.canvasWidth));
  }

  private draw(): void {
    const ctx = this.renderContext;
    if (this.canvasWidth <= 0 || this.canvasHeight <= 0) {
      return;
    }
    ctx.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
    const cy = this.canvasHeight / 2;
    const progressX = this.fraction() * this.canvasWidth;
    // 'round' must be the string literal — the enum form is not accepted here.
    ctx.lineCap = 'round';
    // Unplayed track: full width; both round caps get clipped flush at the
    // canvas edges, leaving only the joint arc visible mid-bar.
    ctx.strokeStyle = this.unplayedColor;
    ctx.lineWidth = TRACK_HEIGHT_PX;
    ctx.beginPath();
    ctx.moveTo(0, cy);
    ctx.lineTo(this.canvasWidth, cy);
    ctx.stroke();
    if (progressX > 0) {
      if (this.loading) {
        // Buffering pulse: the accent breathes between 0.45 and 1 alpha.
        ctx.globalAlpha = 0.45 + 0.55 *
          (0.5 + 0.5 * Math.sin((Date.now() % PULSE_LOOP_MS) / PULSE_LOOP_MS * Math.PI * 2));
      }
      ctx.strokeStyle = this.playedColor;
      ctx.lineWidth = PLAYED_HEIGHT_PX;
      ctx.beginPath();
      ctx.moveTo(0, cy);
      ctx.lineTo(progressX, cy);
      ctx.stroke();
      ctx.globalAlpha = 1;
    }
  }

  private commitPreview(): void {
    if (this.previewFraction >= 0) {
      const targetMs = Math.round(this.previewFraction * Math.max(1, this.durationMs));
      Logger.debug(`WaveformSlider commit: fraction=${this.previewFraction.toFixed(3)} targetMs=${targetMs}`);
      this.onSeek(targetMs);
    }
    this.previewFraction = -1;
    this.onPreview(-1);
    this.draw();
  }

  build() {
    Canvas(this.renderContext)
      .width('100%')
      .height(44)
      .onReady(() => {
        this.canvasWidth = this.renderContext.width;
        this.canvasHeight = this.renderContext.height;
        this.draw();
      })
      .onAttach(() => {
        this.startTimer();
      })
      .onDetach(() => {
        this.stopTimer();
      })
      .onTouch((event: TouchEvent) => {
        // GestureEvent carries no component-local position on this API level,
        // so the touch-down point is captured here: TouchInfo.x, offsetX and
        // canvasWidth are all component-local vp, keeping the math unit-safe.
        if (event.type === TouchType.Down && event.touches.length > 0) {
          this.panBaseFraction = this.fractionAt(event.touches[0].x);
        }
      })
      .gesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal })
          .onActionStart(() => {
            this.previewFraction = this.panBaseFraction >= 0 ? this.panBaseFraction : this.fraction();
            this.onPreview(this.previewFraction);
            this.draw();
          })
          .onActionUpdate((event: GestureEvent) => {
            if (this.panBaseFraction < 0) {
              return;
            }
            const raw = this.panBaseFraction + event.offsetX / this.canvasWidth;
            this.previewFraction = Math.max(0, Math.min(1, raw));
            this.onPreview(this.previewFraction);
            this.draw();
          })
          .onActionEnd(() => {
            this.commitPreview();
            this.panBaseFraction = -1;
          })
          .onActionCancel(() => {
            this.previewFraction = -1;
            this.panBaseFraction = -1;
            this.onPreview(-1);
            this.draw();
          })
      )
      .onClick((event: ClickEvent) => {
        this.previewFraction = this.fractionAt(event.x);
        this.commitPreview();
      })
  }
}
