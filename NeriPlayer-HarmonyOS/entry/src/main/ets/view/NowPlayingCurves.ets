import { curves } from '@kit.ArkUI';

/**
 * 播放页一镜到底的原生动画曲线（curves.customCurve，任意插值函数）。
 * 几何全部走 ArkUI 属性动画（render/动画管线逐帧驱动，无 JS 定时抖动），
 * 这里只定义“先慢后快”与“回弹”两条形状。
 */

/** 面板几何：先慢后快（起步斜率 0，全程加速收官）。 */
export const PANEL_CURVE: curves.ICurve = curves.customCurve((fraction: number): number => {
  return Math.pow(fraction, 2.2);
});

/** 行入场/迷你条跟随：冲过落点后回弹落定（easeOutBack 形状）。 */
export const ROW_CURVE: curves.ICurve = curves.customCurve((fraction: number): number => {
  const c1 = 1.70158;
  const c3 = c1 + 1;
  const u = fraction - 1;
  return 1 + c3 * u * u * u + c1 * u * u;
});
