// SPDX-License-Identifier: GPL-3.0

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
import { AppColorMode } from '../util/AppColorMode';
import { WindowMetrics } from '../util/WindowMetrics';
import { ListenTogetherSessionManager } from '../listentogether/ListenTogetherSessionManager';
import { CrashEventWatcher } from '../app/diagnostics/CrashEventWatcher';
import { StableKeyMigration } from '../data/StableKeyMigration';

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
    // Seed the system dark flag from the ability configuration. Hardcoding
    // false made a cold start under system dark mode paint the light palette:
    // onConfigurationUpdate only fires when the system theme actually changes,
    // so the wrong value survived the whole session.
    AppStorage.setOrCreate('systemDark',
      this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    // 冷启动即把已保存的深色模式选择交给系统，让首帧、系统弹窗与 sys.color.*
    // 资源都落在同一档配色上（'auto' 对应 COLOR_MODE_NOT_SET，即交还系统）。
    AppColorMode.apply(this.context,
      SettingsRepository.getString(SettingsRepository.KEY_DARK_MODE, 'auto'));
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
    const dark = this.isDark();
    this.applyEdgeToEdge(windowStage, dark);
    SystemBars.apply(this.context, dark);
    // 必须在 loadContent 之前：首帧就要拿到断点与真实避让区，否则大屏设备会先
    // 按窄屏画一帧底部 Tab 栏再跳成侧边栏，而跨断点重建会白丢一次页面状态。
    WindowMetrics.start(windowStage);
    // 同样在 loadContent 之前等待登录凭据恢复：每个页面的 aboutToAppear 都在
    // loadContent 之后执行，凭据先就位才能保证首屏请求带上 MUSIC_U（否则
    // 冷启动首个 weapi 请求以匿名会话发出，杀进程重启后表现为掉登录）。
    // onCreate 里的 init() 调用已让恢复在本阶段并行推进，这里通常只等余下尾延。
    // 稳定键 SHA-256 迁移必须最先完成：页面与播放器恢复一旦以新算法读写
    // 歌单/统计/下载编目，而存量键还是旧 FNV 算法，就会造成一次性孤儿数据。
    StableKeyMigration.runIfNeeded()
      .then(() => NeteaseCookieRepository.init())
      .then(() => BiliCookieRepository.init())
      .then(() => {
        windowStage.loadContent('pages/Index', (error) => {
          if (error.code) {
            hilog.error(DOMAIN, TAG, 'Failed to load content: %{public}s', JSON.stringify(error));
            return;
          }
          hilog.info(DOMAIN, TAG, 'Content loaded');
        });
      });
  }

  onWindowStageDestroy(): void {
    WindowMetrics.stop();
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

  private applyEdgeToEdge(windowStage: window.WindowStage, dark: boolean): void {
    try {
      const mainWindow = windowStage.getMainWindowSync();
      // Non-fullscreen on purpose: ArkUI then keeps every page's content inside
      // the safe area by itself. A previous immersive attempt with
      // setWindowLayoutFullScreen(true) placed page headers under the status
      // bar on API 24 phone emulators. Immersion instead comes from transparent
      // system bars plus expandSafeArea background layers (Index/MainShell), so
      // the bars show the app background rather than a separate colour block.
      mainWindow.setWindowLayoutFullScreen(false);
      mainWindow.setWindowSystemBarEnable(['status', 'navigation']);
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        // Follow the resolved theme from the very first frame. The hardcoded
        // white this replaces left status bar text near-invisible on the light
        // palette until SystemBars.apply resolved its async window handle.
        statusBarContentColor: dark ? '#FFFFFF' : '#000000',
        navigationBarColor: '#00000000',
        navigationBarContentColor: dark ? '#FFFFFF' : '#000000'
      });
    } catch (error) {
      const e = error as Error;
      hilog.warn(DOMAIN, TAG, 'applyEdgeToEdge failed: %{public}s', e.message);
    }
  }
}
