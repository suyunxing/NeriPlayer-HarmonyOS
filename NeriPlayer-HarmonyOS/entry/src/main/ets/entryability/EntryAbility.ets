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
import { WebDavConfigRepository } from '../sync/webdav/WebDavConfigRepository';
import { SystemBars } from '../util/SystemBars';
import { Theme } from '../view/Theme';
import { ListenTogetherSessionManager } from '../listentogether/ListenTogetherSessionManager';
import { CrashEventWatcher } from '../app/diagnostics/CrashEventWatcher';

const TAG: string = 'EntryAbility';
const DOMAIN: number = 0x4E50;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'Ability onCreate');
    SettingsRepository.initialize(this.context);
    // Start the diagnostics loop before Index resolves the startup phase:
    // init() pulls this app's fault history, arms the SafeMode flag when a
    // fault falls inside the window since the previous launch (the crash or
    // freeze that killed the last session), then subscribes for live fault
    // events. Index @Watch-es the flag so a late arm still switches.
    CrashEventWatcher.init(this.context);
    AppStorage.setOrCreate('abilityContext', this.context);
    // Seed the system dark flag from the launch configuration rather than a
    // hardcoded false: only onConfigurationUpdate used to write the real value,
    // so launching while the system was in dark mode rendered the whole app
    // light until the user toggled the system theme (static audit 2026-08-25).
    AppStorage.setOrCreate('systemDark',
      this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    // Publish the resolved flag the whole view layer subscribes to. At this
    // point only the settings *defaults* are in AppStorage (the persisted load
    // in doInitialize is async), so an explicit light/dark choice is still
    // pending — Index.aboutToAppear republishes once it has landed.
    Theme.refreshIsDark();
    PlayerManager.initialize(this.context);
    ListenTogetherSessionManager.getInstance().start();
    DownloadEngine.init(this.context);
    NeteaseCookieRepository.init();
    BiliCookieRepository.init();
    GitHubConfigRepository.init();
    WebDavConfigRepository.init();
  }

  onDestroy(): void {
    PlayerManager.flushPlaybackStatsAsync();
    PlayerManager.persistNow();
    AVSessionManager.release();
    ListenTogetherSessionManager.getInstance().destroy().catch((error: Object): void => {
      hilog.warn(DOMAIN, TAG, 'Listen Together destroy failed: %{public}s', (error as Error).message);
    });
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageCreate');
    this.applyEdgeToEdge(windowStage);
    SystemBars.apply(this.context, Theme.refreshIsDark());
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
    AppStorage.setOrCreate('systemDark',
      newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    // System bars follow the *resolved* theme, not the raw system colorMode:
    // with np.dark_mode pinned to light/dark, a system switch must not flip the
    // bars out of step with the app surfaces.
    SystemBars.apply(this.context, Theme.refreshIsDark());
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
