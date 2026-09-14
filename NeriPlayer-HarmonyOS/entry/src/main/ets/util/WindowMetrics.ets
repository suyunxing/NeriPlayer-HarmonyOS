// SPDX-License-Identifier: GPL-3.0

import { display, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  KEY_BOTTOM_LIFT_VP,
  KEY_BREAKPOINT,
  KEY_TOP_INSET_VP,
  KEY_WIDTH_VP,
  bottomLiftFor,
  breakpointFor,
  topInsetFor
} from './Breakpoint';

const TAG: string = 'WindowMetrics';
const DOMAIN: number = 0x4E50;

/**
 * 窗口度量的唯一订阅源：一次订阅同时产出「窗口有多宽」和「底部要抬多少」。
 *
 * 为什么需要它：底部抬升量原先是硬编码的 28vp。tablet 上它恰好等于导航指示器
 * 避让区实高（56px / 2.0），而 2in1 自由窗口根本没有指示器（避让区为 0），那
 * 28vp 就是纯死区 —— 常量属于碰巧对。断点同理，此前全项目没有任何断点判断，
 * 手搓的 Tab 栏单格宽度随窗口线性膨胀到 410vp。
 *
 * 派生规则本身在 util/Breakpoint.ets（纯函数，可单测）；这里只负责取窗口属性、
 * 订阅变化、把结果写进 AppStorage 供页面以 @StorageProp 消费。用 @StorageProp
 * 而不是让页面直接调函数，是因为 ArkUI 最小化更新会跳过不引用可观察状态的属性
 * 表达式（M7.4 渲染器坑，深色模式缺陷就是这么来的）。
 */
export class WindowMetrics {
  private static win: window.Window | null = null;

  /**
   * 两个事件共用一个回调实例：off() 需要传入与 on() 相同的引用才能精确退订。
   * windowSizeChange 与 avoidAreaChange 都只是「有变化」的信号，变化后一律重新
   * 整体采样，不去分别解析各自的回调载荷。
   */
  private static readonly resample: () => void = (): void => {
    WindowMetrics.sample();
  };

  /**
   * 在 onWindowStageCreate 里、loadContent 之前调用。
   *
   * 取窗口用同步的 getMainWindowSync() 而不是异步的 getLastWindow()：首帧渲染
   * 前 AppStorage 里就必须有正确的断点，否则大屏设备会先按 sm 画一帧底部 Tab
   * 栏、再跳成侧边栏，而跨断点重建会把四个 Tab 页的 @State 白丢一次。
   */
  static start(windowStage: window.WindowStage): void {
    if (WindowMetrics.win !== null) {
      return;
    }
    try {
      const win = windowStage.getMainWindowSync();
      WindowMetrics.win = win;
      WindowMetrics.sample();
      win.on('windowSizeChange', WindowMetrics.resample);
      win.on('avoidAreaChange', WindowMetrics.resample);
    } catch (error) {
      const e = error as Error;
      hilog.warn(DOMAIN, TAG, 'start failed: %{public}s', e.message);
    }
  }

  static stop(): void {
    const win = WindowMetrics.win;
    if (win === null) {
      return;
    }
    WindowMetrics.win = null;
    try {
      win.off('windowSizeChange', WindowMetrics.resample);
      win.off('avoidAreaChange', WindowMetrics.resample);
    } catch (error) {
      const e = error as Error;
      hilog.warn(DOMAIN, TAG, 'stop failed: %{public}s', e.message);
    }
  }

  private static sample(): void {
    const win = WindowMetrics.win;
    if (win === null) {
      return;
    }
    try {
      const rect = win.getWindowProperties().windowRect;
      const density = display.getDefaultDisplaySync().densityPixels;
      const widthVp = density > 0 ? rect.width / density : rect.width;
      const indicator = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const lift = bottomLiftFor(indicator.bottomRect.height);
      // TYPE_SYSTEM.topRect 即状态栏（官方 FAQ faqs-arkui-202/824）；换算成 vp
      // 供 enableSafeArea:false 的全屏播放页模态做头部避让。
      const systemArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const topInset = topInsetFor(systemArea.topRect.height, density);
      AppStorage.setOrCreate('ui.windowWidthVp', widthVp);
      AppStorage.setOrCreate('ui.windowHeightVp', density > 0 ? rect.height / density : rect.height);
      AppStorage.setOrCreate(KEY_WIDTH_VP, Math.round(widthVp));
      AppStorage.setOrCreate(KEY_BREAKPOINT, breakpointFor(widthVp));
      AppStorage.setOrCreate(KEY_BOTTOM_LIFT_VP, lift);
      AppStorage.setOrCreate(KEY_TOP_INSET_VP, topInset);
      // 布局度量，无隐私内容；这些数字是大屏适配与上下避让的取证依据。
      hilog.info(DOMAIN, TAG, 'width=%{public}dvp bp=%{public}s lift=%{public}dvp topInset=%{public}dvp',
        Math.round(widthVp), breakpointFor(widthVp), lift, topInset);
    } catch (error) {
      const e = error as Error;
      hilog.warn(DOMAIN, TAG, 'sample failed: %{public}s', e.message);
    }
  }
}
