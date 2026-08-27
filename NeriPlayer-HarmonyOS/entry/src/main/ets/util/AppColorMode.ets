import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { Logger } from '../app/Logger';

/**
 * 应用级深色模式覆写。
 *
 * 指南要求深色模式切换后整个界面立即生效，而 Theme.isDark() 读的是
 * preferences，不是可观察状态：ArkUI 的最小化更新会跳过所有不引用
 * @State/@StorageProp 的颜色表达式（Theme.ets 注释里记的 M7.4 renderer
 * pitfall）。实测后果是切换后当前页保持原配色，且 MainShell 底部导航栏的
 * 背景永久停在浅色 —— 切页也修不回来，因为它不依赖任何被跟踪的状态。
 *
 * setColorMode 把选择交给系统：它触发一次配置变更，整棵组件树重建，全项目
 * 482 处 Theme.isDark() 一次性重新求值；系统弹窗与 sys.color.* 资源也随之
 * 跟随同一档配色，不需要逐个调用点改签名。
 */
export class AppColorMode {
  /** mode 取 SettingsRepository.KEY_DARK_MODE 的三个值：auto | light | dark。 */
  static apply(context: common.UIAbilityContext, mode: string): void {
    let colorMode: ConfigurationConstant.ColorMode =
      ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (mode === 'dark') {
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } else if (mode === 'light') {
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    try {
      // COLOR_MODE_NOT_SET 即交还给系统主题，对应应用内的「跟随系统」。
      context.getApplicationContext().setColorMode(colorMode);
    } catch (error) {
      const e = error as Error;
      Logger.warn(`AppColorMode.apply failed: ${e.message}`);
    }
  }
}
