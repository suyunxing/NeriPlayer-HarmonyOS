import { AbilityConstant, UIAbility, Want, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SettingsRepository } from '../data/SettingsRepository';
import { PlayerManager } from '../player/PlayerManager';
import { AVSessionManager } from '../player/AVSessionManager';
import { DownloadEngine } from '../download/DownloadEngine';
import { NeteaseCookieRepository } from '../data/auth/NeteaseCookieRepository';
import { BiliCookieRepository } from '../data/auth/BiliCookieRepository';
import { GitHubConfigRepository } from '../sync/github/GitHubConfigRepository';
import { SystemBars } from '../util/SystemBars';

const TAG: string = 'EntryAbility';
const DOMAIN: number = 0x4E50;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'Ability onCreate');
    SettingsRepository.initialize(this.context);
    AppStorage.setOrCreate('abilityContext', this.context);
    AppStorage.setOrCreate('systemDark', false);
    PlayerManager.initialize(this.context);
    DownloadEngine.init(this.context);
    NeteaseCookieRepository.init();
    BiliCookieRepository.init();
    GitHubConfigRepository.init();
  }

  onDestroy(): void {
    PlayerManager.flushPlaybackStatsAsync();
    PlayerManager.persistNow();
    AVSessionManager.release();
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageCreate');
    this.applyEdgeToEdge(windowStage);
    SystemBars.apply(this.context, this.isDark());
    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content: %{public}s', JSON.stringify(error));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Content loaded');
    });
  }

  onWindowStageDestroy(): void {
    PlayerManager.flushPlaybackStatsAsync();
  }

  onBackground(): void {
    PlayerManager.flushPlaybackStatsAsync();
    PlayerManager.persistNow();
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    const dark = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    AppStorage.setOrCreate('systemDark', dark);
    SystemBars.apply(this.context, dark);
  }

  private isDark(): boolean {
    const mode = SettingsRepository.getString(SettingsRepository.KEY_DARK_MODE, 'auto');
    if (mode === 'dark') {
      return true;
    }
    if (mode === 'light') {
      return false;
    }
    const systemDark = AppStorage.get<boolean>('systemDark');
    return systemDark === true;
  }

  private applyEdgeToEdge(windowStage: window.WindowStage): void {
    try {
      const mainWindow = windowStage.getMainWindowSync();
      // Keep the app inside the system safe area. The previous immersive layout
      // placed page headers under the status bar on API 24 phone emulators.
      mainWindow.setWindowLayoutFullScreen(false);
      mainWindow.setWindowSystemBarEnable(['status', 'navigation']);
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: '#FFFFFF',
        navigationBarColor: '#00000000',
        navigationBarContentColor: '#FFFFFF'
      });
    } catch (error) {
      const e = error as Error;
      hilog.warn(DOMAIN, TAG, 'applyEdgeToEdge failed: %{public}s', e.message);
    }
  }
}
