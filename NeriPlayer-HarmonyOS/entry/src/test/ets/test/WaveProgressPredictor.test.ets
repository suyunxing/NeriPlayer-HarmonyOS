// SPDX-License-Identifier: GPL-3.0

import { describe, it, expect } from '@ohos/hypium';
import {
  WaveProgressPredictor,
  resolveWaveProgress,
  shouldPredictWaveProgress,
  normalizeWaveProgress
} from '../../../main/ets/view/components/WaveProgressPredictor';

// 上游 WaveformSliderTest（#337）镜像：外推公式/输入容错/预测开关门控/
// 重锚对齐/暂停与 seek 立即贴合/循环重启重置锚点。
export default function waveProgressPredictorTest(): void {
  describe('WaveProgressPredictor', () => {
    it('shortTrackProgressAdvancesAtRenderedFrameCadence', 0, () => {
      // 锚点 0.2、时长 5s、1x：125ms 后 0.225；速率翻倍前进也翻倍。
      expect(Math.abs(resolveWaveProgress(0.2, 5000, 1, 125) - 0.225) < 0.0001).assertTrue();
      expect(Math.abs(resolveWaveProgress(0, 5000, 2, 125) - 0.05) < 0.0001).assertTrue();
    });

    it('predictionClampsValuesAndIgnoresInvalidInputs', 0, () => {
      // 锚点夹取 0..1；时长/速率非法与负流逝时间都回落锚点不前进。
      expect(Math.abs(resolveWaveProgress(1.5, 5000, 1, 0) - 1) < 0.0001).assertTrue();
      expect(Math.abs(resolveWaveProgress(-0.5, 5000, 1, 0) - 0) < 0.0001).assertTrue();
      expect(Math.abs(resolveWaveProgress(0.4, 0, 1, 1000) - 0.4) < 0.0001).assertTrue();
      expect(Math.abs(resolveWaveProgress(0.4, 5000, 0, 1000) - 0.4) < 0.0001).assertTrue();
      expect(Math.abs(resolveWaveProgress(0.4, 5000, -2, 1000) - 0.4) < 0.0001).assertTrue();
      expect(Math.abs(resolveWaveProgress(0.4, 5000, 1, -300) - 0.4) < 0.0001).assertTrue();
      expect(Math.abs(resolveWaveProgress(0.4, 5000, 1, Number.NaN) - 0.4) < 0.0001).assertTrue();
      // 外推结果封顶 1，不越过曲目末尾等待结束回调。
      expect(Math.abs(resolveWaveProgress(0.99, 5000, 1, 60_000) - 1) < 0.0001).assertTrue();
      expect(normalizeWaveProgress(Number.NEGATIVE_INFINITY)).assertEqual(0);
    });

    it('predictionStopsForWaitingAndSeekPreviews', 0, () => {
      expect(shouldPredictWaveProgress(true, false, false)).assertTrue();
      expect(shouldPredictWaveProgress(true, true, false)).assertFalse();
      expect(shouldPredictWaveProgress(true, false, true)).assertFalse();
      expect(shouldPredictWaveProgress(false, false, false)).assertFalse();
    });

    it('predictorReanchorsEachRealProgressUpdate', 0, () => {
      const predictor = new WaveProgressPredictor(0);
      predictor.updateTarget(0.2, 5000, 1, true);
      predictor.onFrame(1000);
      predictor.onFrame(1125);
      expect(Math.abs(predictor.currentValue - 0.225) < 0.0001).assertTrue();
      // 真实位置发布前进到 0.25：立即重锚，预测不带着旧锚点滞后。
      predictor.updateTarget(0.25, 5000, 1, true);
      predictor.onFrame(1250);
      expect(Math.abs(predictor.currentValue - 0.25) < 0.0001).assertTrue();
      predictor.onFrame(1375);
      expect(Math.abs(predictor.currentValue - 0.275) < 0.0001).assertTrue();
    });

    it('predictorImmediatelyAlignsAfterPauseAndSeek', 0, () => {
      const predictor = new WaveProgressPredictor(0);
      predictor.updateTarget(0.4, 5000, 1, true);
      predictor.onFrame(1000);
      predictor.onFrame(1200);
      expect(Math.abs(predictor.currentValue - 0.44) < 0.0001).assertTrue();
      // 暂停：观测值跳到 0.15（seek 后暂停），预测停用且立即贴合。
      predictor.updateTarget(0.15, 5000, 1, false);
      expect(Math.abs(predictor.currentValue - 0.15) < 0.0001).assertTrue();
      // 恢复预测：从当前观测值重新起锚，不累计暂停期间的时钟。
      predictor.updateTarget(0.15, 5000, 1, true);
      predictor.onFrame(2000);
      expect(Math.abs(predictor.currentValue - 0.15) < 0.0001).assertTrue();
      predictor.onFrame(2200);
      expect(Math.abs(predictor.currentValue - 0.19) < 0.0001).assertTrue();
    });

    it('predictorResetsFrameAnchorWhenAnimationResumes', 0, () => {
      const predictor = new WaveProgressPredictor(0);
      predictor.updateTarget(0.4, 5000, 1, true);
      predictor.onFrame(1000);
      predictor.onFrame(1200);
      expect(Math.abs(predictor.currentValue - 0.44) < 0.0001).assertTrue();
      // 渲染循环间歇后 resetFrameAnchor：以当前预测值为新锚点，跨间歇的
      // 帧时刻（10s）只用来重锚，不产生 8.8s 的巨额外推。
      predictor.resetFrameAnchor();
      predictor.onFrame(10_000);
      expect(Math.abs(predictor.currentValue - 0.44) < 0.0001).assertTrue();
      predictor.onFrame(10_200);
      expect(Math.abs(predictor.currentValue - 0.48) < 0.0001).assertTrue();
    });
  });
}
