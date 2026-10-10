// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer),
// commit 2644267f "feat(ui): customize playback control layout".
//
// 上游三档「主控位置」（中下/贴底/贴底含进度）不随本模块移植：鸿蒙播放页
// 控制区自始贴底（Swiper 吃掉全部弹性空间），不存在「中下」形态可切换。

/** 播放控件大小档位（序数持久化，np.nowplaying_control_size / np.lyric_control_size）。 */
export enum PlaybackControlSize {
  SMALL = 0,
  MEDIUM = 1,
  LARGE = 2
}

/** 越界/缺省值回落中档（上游 getOrElse 语义）。 */
export function parsePlaybackControlSize(value: number): PlaybackControlSize {
  if (value === PlaybackControlSize.SMALL || value === PlaybackControlSize.MEDIUM
    || value === PlaybackControlSize.LARGE) {
    return value;
  }
  return PlaybackControlSize.MEDIUM;
}

/** 档位对应的缩放系数：小 0.9 / 中 1.0 / 大 1.2。 */
export function playbackControlScale(size: PlaybackControlSize): number {
  if (size === PlaybackControlSize.SMALL) {
    return 0.9;
  }
  if (size === PlaybackControlSize.LARGE) {
    return 1.2;
  }
  return 1.0;
}

/** 按钮尺寸缩放：触控热区下限 40vp（上游 scaleButtonSize）。 */
export function scaleButtonSize(baseVp: number, scale: number): number {
  return Math.max(40, baseVp * scale);
}

/** 图标尺寸缩放：可读下限 18vp（上游 scaleIconSize）。 */
export function scaleIconSize(baseVp: number, scale: number): number {
  return Math.max(18, baseVp * scale);
}

/** 主控组（若干次键 + 一个主键）的最终布局尺寸。 */
export class MainControlsLayout {
  readonly secondaryButtonSize: number;
  readonly primaryButtonSize: number;
  readonly spacing: number;
  /** 相对请求尺寸的整体压缩比（≤1），图标按同比跟随。 */
  readonly buttonScale: number;

  constructor(secondaryButtonSize: number, primaryButtonSize: number,
    spacing: number, buttonScale: number) {
    this.secondaryButtonSize = secondaryButtonSize;
    this.primaryButtonSize = primaryButtonSize;
    this.spacing = spacing;
    this.buttonScale = buttonScale;
  }
}

/**
 * 把主控组塞进可用宽度（上游 resolveNowPlayingMainControlsLayout 直译，
 * 次键数参数化——上游固定 4，本工程传输行为 2）：
 *
 * 1. 先按 4vp 最小间距预留间隙得到可用按钮总宽；
 * 2. 请求宽超出时按比例压缩全部按钮（不做差异化挤压）；
 * 3. 剩余空间再在期望间距与最大可容纳间距之间取小。
 *
 * preferredSpacing 传 0 表示间距交给外层 SpaceEvenly 分配（只取压缩结果）。
 */
export function resolveMainControlsLayout(availableWidth: number, secondaryButtonSize: number,
  primaryButtonSize: number, secondaryCount: number,
  preferredSpacing: number): MainControlsLayout {
  const gapCount = Math.max(1, secondaryCount);
  const minimumSpacing = Math.min(4, availableWidth / gapCount);
  const availableButtonWidth = Math.max(0, availableWidth - minimumSpacing * gapCount);
  const requestedButtonWidth = secondaryButtonSize * secondaryCount + primaryButtonSize;
  let buttonScale = 1;
  if (requestedButtonWidth > 0 && requestedButtonWidth > availableButtonWidth) {
    buttonScale = Math.min(1, Math.max(0, availableButtonWidth / requestedButtonWidth));
  }
  const resolvedSecondary = secondaryButtonSize * buttonScale;
  const resolvedPrimary = primaryButtonSize * buttonScale;
  const maximumSpacing = Math.max(0,
    (availableWidth - resolvedSecondary * secondaryCount - resolvedPrimary) / gapCount);
  return new MainControlsLayout(resolvedSecondary, resolvedPrimary,
    Math.min(preferredSpacing, maximumSpacing), buttonScale);
}
