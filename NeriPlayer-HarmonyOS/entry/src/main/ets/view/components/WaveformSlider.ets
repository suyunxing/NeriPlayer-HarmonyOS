/**
 * Waveform-style playback progress slider, the HarmonyOS counterpart of
 * Android ui/component/playback/WaveformSlider.kt. The wave is procedural,
 * not real audio data: a fixed sine (amplitude 6, frequency 0.08 per px)
 * sampled every 6 px into 48..180 points whose phase loops every 2s while
 * playing (a lightweight timer instead of withFrameNanos). Drag gestures
 * mirror the Material Slider contract of the previous inline Slider: local
 * preview while dragging, seek fires on release/tap.
 */
const SAMPLE_INTERVAL_PX = 6;
const MIN_POINTS = 48;
const MAX_POINTS = 180;
const WAVE_AMPLITUDE = 6;
const WAVE_FREQUENCY = 0.08;
const PHASE_LOOP_MS = 2000;
const REPAINT_INTERVAL_MS = 50;
const DRAG_THRESHOLD_VP = 8;

@Component
export struct WaveformSlider {
  @Prop positionMs: number = 0;
  @Prop durationMs: number = 0;
  @Prop playing: boolean = false;
  @Prop loading: boolean = false;
  onSeek: (ms: number) => void = () => {};
  /** Drag preview as a 0..1 fraction; -1 restores the live position. */
  onPreview: (fraction: number) => void = () => {};

  private canvasWidth: number = 0;
  private canvasHeight: number = 0;
  private pointCount: number = MIN_POINTS;
  private phase: number = 0;
  private repaintTimer: number = -1;
  private frameTime: number = 0;
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
      const now = Date.now();
      const delta = now - this.frameTime;
      this.frameTime = now;
      if (this.playing) {
        this.phase = (this.phase + (Math.PI * 2) * delta / PHASE_LOOP_MS) % (Math.PI * 2);
      }
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

  private waveY(x: number): number {
    const center = this.canvasHeight / 2;
    let amplitude = WAVE_AMPLITUDE;
    if (this.loading) {
      // Waiting pulse: the wave breathes between half-height 2 and 7 over a
      // 1.4s cycle while playback is buffering (Android waiting animation).
      amplitude = 4.5 + 2.5 * Math.sin((Date.now() % 1400) / 1400 * Math.PI * 2);
    }
    return center + Math.sin(x * WAVE_FREQUENCY + this.phase) * amplitude;
  }

  private draw(): void {
    const ctx = this.renderContext;
    if (this.canvasWidth <= 0 || this.canvasHeight <= 0) {
      return;
    }
    ctx.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
    const progressX = this.fraction() * this.canvasWidth;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    this.drawWaveSegment(this.canvasWidth, 4, 'rgba(255,255,255,0.45)');
    if (progressX > 1) {
      this.drawWaveSegment(progressX, 6, '#FFFFFF');
    }
    ctx.beginPath();
    ctx.arc(progressX, this.waveY(progressX), 7, 0, Math.PI * 2);
    ctx.fillStyle = '#FFFFFF';
    ctx.fill();
  }

  /** Continuous sine polyline from x=0 to `widthPx`. */
  private drawWaveSegment(widthPx: number, stroke: number, color: string): void {
    const ctx = this.renderContext;
    const step = widthPx / this.pointCount;
    ctx.strokeStyle = color;
    ctx.lineWidth = stroke;
    ctx.beginPath();
    ctx.moveTo(0, this.waveY(0));
    for (let x = step; x < widthPx; x += step) {
      ctx.lineTo(x, this.waveY(x));
    }
    ctx.stroke();
  }

  private commitPreview(): void {
    if (this.previewFraction >= 0) {
      this.onSeek(Math.round(this.previewFraction * Math.max(1, this.durationMs)));
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
        this.pointCount = Math.max(MIN_POINTS, Math.min(MAX_POINTS,
          Math.floor(this.canvasWidth / SAMPLE_INTERVAL_PX)));
        this.draw();
      })
      .onAttach(() => {
        this.startTimer();
      })
      .onDetach(() => {
        this.stopTimer();
      })
      .gesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: DRAG_THRESHOLD_VP })
          .onActionStart(() => {
            this.previewFraction = this.fraction();
          })
          .onActionUpdate((event: GestureEvent) => {
            if (this.canvasWidth <= 0) {
              return;
            }
            const raw = (this.previewFraction * this.canvasWidth + event.offsetX) / this.canvasWidth;
            this.previewFraction = Math.max(0, Math.min(1, raw));
            this.onPreview(this.previewFraction);
            this.draw();
          })
          .onActionEnd(() => {
            this.commitPreview();
          })
          .onActionCancel(() => {
            this.previewFraction = -1;
            this.onPreview(-1);
            this.draw();
          })
      )
      .onClick((event: ClickEvent) => {
        if (this.canvasWidth <= 0) {
          return;
        }
        this.previewFraction = Math.max(0, Math.min(1, event.x / this.canvasWidth));
        this.commitPreview();
      })
  }
}
