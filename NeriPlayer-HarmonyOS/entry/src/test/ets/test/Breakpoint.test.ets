import { describe, it, expect } from '@ohos/hypium';
import {
  BP_LG,
  BP_LG_VP,
  BP_MD,
  BP_MD_VP,
  BP_SM,
  GUIDELINE_BOTTOM_LIFT_VP,
  bottomLiftFor,
  breakpointFor,
  isWide
} from '../../../main/ets/util/Breakpoint';

/**
 * 窗口度量的派生规则。util/Breakpoint.ets 刻意不引 ArkUI、不读 AppStorage，
 * 就是为了让这两条规则能像 RouteStack 一样直接单测；读写 AppStorage 的那一半
 * 在 util/WindowMetrics.ets，需要真实窗口，只能靠设备实测覆盖。
 *
 * 用例里的数字全部来自上一轮三形态设备实测（审计 §8.2 / §11.2），不是随手编的
 * 边界值。
 */
export default function breakpointTest(): void {
  describe('Breakpoint', (): void => {
    it('maps the measured device widths to the intended tier', 0, (): void => {
      // phone 模拟器 391.1vp、折叠外屏 346vp —— 最窄形态都归 sm，底部导航栏。
      expect(breakpointFor(391.1)).assertEqual(BP_SM);
      expect(breakpointFor(346)).assertEqual(BP_SM);
      // 2in1 自由窗口 1100vp、最大化 1642vp、tablet 1440vp —— 都该切侧边导航栏。
      expect(breakpointFor(1100)).assertEqual(BP_LG);
      expect(breakpointFor(1642)).assertEqual(BP_LG);
      expect(breakpointFor(1440)).assertEqual(BP_LG);
    });

    it('uses the same thresholds as the GridRow defaults', 0, (): void => {
      // 阈值必须与 GridRow 默认断点 ['320vp','600vp','840vp'] 同源，否则会出现
      // 「Tab 已切成侧边栏但卡片网格还是两列」这种自相矛盾的布局。
      expect(breakpointFor(BP_MD_VP - 0.1)).assertEqual(BP_SM);
      expect(breakpointFor(BP_MD_VP)).assertEqual(BP_MD);
      expect(breakpointFor(BP_LG_VP - 0.1)).assertEqual(BP_MD);
      expect(breakpointFor(BP_LG_VP)).assertEqual(BP_LG);
    });

    it('never mistakes a missing width for a large screen', 0, (): void => {
      // 冷启动第一帧、或 densityPixels 为 0 导致的除零，都必须退到最窄一档：
      // 误判成大屏会在 phone 上把顶层导航甩到侧边。
      expect(breakpointFor(0)).assertEqual(BP_SM);
      expect(breakpointFor(-1)).assertEqual(BP_SM);
      expect(breakpointFor(Number.NaN)).assertEqual(BP_SM);
      expect(breakpointFor(Number.POSITIVE_INFINITY)).assertEqual(BP_SM);
    });

    it('treats only lg as the wide-layout form factor', 0, (): void => {
      expect(isWide(BP_LG)).assertTrue();
      expect(isWide(BP_MD)).assertFalse();
      expect(isWide(BP_SM)).assertFalse();
    });

    it('lifts bottom controls only where a navigation indicator exists', 0, (): void => {
      // tablet 实测 SCBGestureNavBar 高 56px / 2.0 = 28vp，与指南常量吻合。
      expect(bottomLiftFor(56)).assertEqual(GUIDELINE_BOTTOM_LIFT_VP);
      expect(bottomLiftFor(1)).assertEqual(GUIDELINE_BOTTOM_LIFT_VP);
      // 2in1 自由窗口 TYPE_NAVIGATION_INDICATOR 避让区为 0：原来的硬编码 28vp
      // 在那里是纯死区，必须归零。
      expect(bottomLiftFor(0)).assertEqual(0);
      // 取不到避让区时同样不留死区。
      expect(bottomLiftFor(-1)).assertEqual(0);
      expect(bottomLiftFor(Number.NaN)).assertEqual(0);
    });
  });
}
