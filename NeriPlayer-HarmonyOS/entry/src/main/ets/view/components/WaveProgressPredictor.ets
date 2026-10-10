// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer),
// commit bc4142bc "feat: implement playback progress prediction for
// WaveformSlider (#337)".

/**
 * 波形条播放进度预测（上游 WaveProgressPredictor 直译，时间基毫秒）。
 *
 * 播放位置只随引擎回调发布（本工程节流 500ms 一发），两次发布之间进度条
 * 会停在同一格再跳一格。播放中（非加载、非拖动预览）由本地时钟外推动画：
 *
 *   预测值 = 锚点 + 经过毫秒 / 时长 × 播放速率（夹取 0..1）
 *
 * 每次真实位置更新（target 变化）都重新锚定到观测值，预测永不领先下一次
 * 发布超过一个发布周期；暂停/加载/预览期间不预测，直接显示观测值。
 */

/** 归一化播放进度：非有限值取 0，其余夹取 0..1。 */
export function normalizeWaveProgress(value: number): number {
  if (!Number.isFinite(value)) {
    return 0;
  }
  return Math.max(0, Math.min(1, value));
}

/** 归一化播放速率：非正/非有限值取 0（0 表示不前进）。 */
export function normalizeWavePlaybackSpeed(value: number): number {
  if (!Number.isFinite(value) || value <= 0) {
    return 0;
  }
  return value;
}

/** 由锚点外推进度：时长/速率非法时回落锚点（不前进）。 */
export function resolveWaveProgress(anchorValue: number, durationMs: number,
  playbackSpeed: number, elapsedMs: number): number {
  const anchor = normalizeWaveProgress(anchorValue);
  if (durationMs <= 0) {
    return anchor;
  }
  const speed = normalizeWavePlaybackSpeed(playbackSpeed);
  if (speed <= 0) {
    return anchor;
  }
  const elapsed = Math.max(0, elapsedMs);
  return normalizeWaveProgress(anchor + elapsed / durationMs * speed);
}

/** 播放中且未加载停顿、未拖动/点击预览时才启用预测。 */
export function shouldPredictWaveProgress(isWaveAnimating: boolean,
  isProgressStalled: boolean, isProgressPreviewing: boolean): boolean {
  return isWaveAnimating && !isProgressStalled && !isProgressPreviewing;
}

/**
 * 预测器状态机：持有锚点值与锚定帧时刻，target 输入变化或预测开关切换时
 * 重锚（currentValue 立即贴合观测值），帧循环里用 onFrame 外推。
 */
export class WaveProgressPredictor {
  private anchorValue: number;
  private targetValue: number;
  private durationMs: number = 0;
  private playbackSpeed: number = 0;
  private anchorFrameMs: number = 0;
  private hasPendingAnchor: boolean = true;
  private wasAnimating: boolean = false;
  private current: number;

  constructor(initialValue: number) {
    const normalized = normalizeWaveProgress(initialValue);
    this.anchorValue = normalized;
    this.targetValue = normalized;
    this.current = normalized;
  }

  get currentValue(): number {
    return this.current;
  }

  /**
   * 更新观测目标：输入（值/时长/速率）变化、本次或上次未处于预测态时重锚。
   * 输入不变且持续预测时保持原锚点继续外推（不追帧补偿）。
   */
  updateTarget(targetValue: number, durationMs: number,
    playbackSpeed: number, animate: boolean): void {
    const normalizedTarget = normalizeWaveProgress(targetValue);
    const normalizedDurationMs = Math.max(0, durationMs);
    const normalizedPlaybackSpeed = normalizeWavePlaybackSpeed(playbackSpeed);
    const inputChanged = normalizedTarget !== this.targetValue
      || normalizedDurationMs !== this.durationMs
      || normalizedPlaybackSpeed !== this.playbackSpeed;
    if (inputChanged || !animate || !this.wasAnimating) {
      this.anchorValue = normalizedTarget;
      this.current = normalizedTarget;
      this.hasPendingAnchor = true;
    }
    this.targetValue = normalizedTarget;
    this.durationMs = normalizedDurationMs;
    this.playbackSpeed = normalizedPlaybackSpeed;
    this.wasAnimating = animate;
  }

  /** 帧回调：重锚帧只记录时刻，其后每帧由锚点外推；时钟回拨时重新锚定。 */
  onFrame(frameMs: number): void {
    if (frameMs <= 0) {
      return;
    }
    if (this.hasPendingAnchor || this.anchorFrameMs === 0 || frameMs < this.anchorFrameMs) {
      this.anchorFrameMs = frameMs;
      this.current = this.anchorValue;
      this.hasPendingAnchor = false;
      return;
    }
    this.current = resolveWaveProgress(this.anchorValue, this.durationMs,
      this.playbackSpeed, frameMs - this.anchorFrameMs);
  }

  /** 动画循环重启时调用：以当前预测值为新锚点，避免跨间歇累计外推。 */
  resetFrameAnchor(): void {
    this.anchorValue = this.current;
    this.anchorFrameMs = 0;
    this.hasPendingAnchor = true;
  }
}
