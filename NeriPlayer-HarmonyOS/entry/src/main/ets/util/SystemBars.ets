// SPDX-License-Identifier: GPL-3.0

import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Logger } from '../app/Logger';

/**
 * Applies status/navigation bar colors matching the current theme, so the
 * transparent bars never hide white-on-white (or black-on-black) content.
 */
export class SystemBars {
  static apply(context: common.UIAbilityContext, dark: boolean): void {
    window.getLastWindow(context).then((win: window.Window) => {
      win.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: dark ? '#FFFFFF' : '#000000',
        navigationBarColor: '#00000000',
        navigationBarContentColor: dark ? '#FFFFFF' : '#000000'
      }).catch((error: Error) => {
        Logger.warn(`SystemBars.apply failed: ${error.message}`);
      });
    }).catch((error: Error) => {
      Logger.warn(`SystemBars.getLastWindow failed: ${error.message}`);
    });
  }
}
