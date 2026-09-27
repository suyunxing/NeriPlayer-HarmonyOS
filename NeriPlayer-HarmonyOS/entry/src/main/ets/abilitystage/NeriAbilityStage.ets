// SPDX-License-Identifier: GPL-3.0

import { AbilityStage, Configuration } from '@kit.AbilityKit';
import { ezCustomTransition } from '@hmanimations/ezcustomtransition';

/**
 * 模块级 AbilityStage（module.json5 的 module.srcEntry 指向本文件）。
 * 一镜到底三方库（@hmanimations/ezcustomtransition）要求在配置变更（深色
 * 模式/语言/窗口形态）时广播刷新：onConfigurationChanged 内部只往 AppStorage
 * 写一个时间戳键，由各 LongTakeSession 订阅后重算转场参数。UIAbility 的
 * onConfigurationUpdate（EntryAbility）已用于深色模式发布，库的标准接入点
 * 按官方要求放在 AbilityStage 层，两者互不影响。
 */
export default class NeriAbilityStage extends AbilityStage {
  onConfigurationUpdate(newConfig: Configuration): void {
    ezCustomTransition.onConfigurationChanged();
  }
}
