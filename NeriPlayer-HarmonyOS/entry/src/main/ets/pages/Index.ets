// SPDX-License-Identifier: GPL-3.0

import { SettingsRepository } from '../data/SettingsRepository';
import { Router } from '../view/Router';
import { Theme } from '../view/Theme';
import { AccentScheme } from '../view/theme/AccentScheme';
import { SchemeCustomTheme } from '../view/theme/SchemeCustomTheme';
import { CURRENT_DISCLAIMER_VERSION, isDisclaimerConfirmationRequired } from '../util/DisclaimerConsentPolicy';
import { LoadingPage } from '../view/pages/LoadingPage';
import { DisclaimerPage, DISCLAIMER_OPENED_DOC_KEY } from '../view/pages/DisclaimerPage';
import { OnboardingPage } from '../view/pages/OnboardingPage';
import { SafeModePage } from '../view/pages/SafeModePage';
import { MainShell } from '../view/pages/MainShell';

enum StartupPhase {
  LOADING = 0,
  DISCLAIMER = 1,
  ONBOARDING = 2,
  SAFE_MODE = 3,
  MAIN = 4
}

/**
 * Startup state machine: Loading -> Disclaimer -> Onboarding -> Main.
 * Safe Mode interrupts the flow when the previous launch crashed.
 */
@Entry
@Component
struct Index {
  @StorageProp('np.disclaimer_accepted') disclaimerAccepted: boolean = false;
  // 用户上次同意的协议文本版本；版本化之前的安装为空串。与当前版本不一致时
  // 首次启动会重新进入一次合规页。
  @StorageProp('np.disclaimer_accepted_version') disclaimerAcceptedVersion: string = '';
  @StorageProp('np.onboarding_completed') onboardingCompleted: boolean = false;
  // The crash flag is armed asynchronously by CrashEventWatcher (fault
  // history pull on startup); watch it so a late flag still switches a
  // already-rendered main UI into Safe Mode.
  @StorageProp('np.last_crash_detected') @Watch('onCrashFlagChanged') lastCrashDetected: boolean = false;
  // The immersive background layer below lives for the whole session and is
  // never rebuilt by a parent, so it has to subscribe to both dark-mode inputs
  // itself. Reading them through resolveDark() during build() is tracked (they
  // are decorated members); Theme.isDark() would not be, because it reaches
  // into AppStorage directly.
  @StorageProp('systemDark') systemDark: boolean = false;
  @StorageProp('np.dark_mode') darkMode: string = 'auto';
  // 封面配色方案：CoverArtColorCache 每次换歌发布新实例，WithTheme 用它构建
  // 官方 51 槽 CustomTheme，让系统内建控件跟随封面变色。
  @StorageProp('player.coverScheme') @Watch('onSchemeChanged') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @State appTheme: CustomTheme = SchemeCustomTheme.build(null);
  @State phase: StartupPhase = StartupPhase.LOADING;
  @State loadingDone: boolean = false;

  async aboutToAppear(): Promise<void> {
    await SettingsRepository.initialize();
    this.rebuildTheme();
    this.phase = this.resolvePhase();
    this.loadingDone = true;
  }

  private onSchemeChanged(): void {
    this.rebuildTheme();
  }

  private rebuildTheme(): void {
    this.appTheme = SchemeCustomTheme.build(this.coverScheme);
  }

  private onCrashFlagChanged(): void {
    if (this.lastCrashDetected && this.phase === StartupPhase.MAIN) {
      this.phase = StartupPhase.SAFE_MODE;
    }
  }

  private resolvePhase(): StartupPhase {
    if (this.lastCrashDetected) {
      return StartupPhase.SAFE_MODE;
    }
    if (isDisclaimerConfirmationRequired(this.disclaimerAccepted, this.disclaimerAcceptedVersion)) {
      return StartupPhase.DISCLAIMER;
    }
    if (!this.onboardingCompleted) {
      return StartupPhase.ONBOARDING;
    }
    return StartupPhase.MAIN;
  }

  private onDisclaimerAgree(): void {
    SettingsRepository.setBoolean(SettingsRepository.KEY_DISCLAIMER_ACCEPTED, true);
    SettingsRepository.setString(SettingsRepository.KEY_DISCLAIMER_ACCEPTED_VERSION, CURRENT_DISCLAIMER_VERSION);
    this.phase = this.onboardingCompleted ? StartupPhase.MAIN : StartupPhase.ONBOARDING;
  }

  private onOnboardingDone(): void {
    SettingsRepository.setBoolean(SettingsRepository.KEY_ONBOARDING_COMPLETED, true);
    this.phase = StartupPhase.MAIN;
  }

  private onRestoreNormal(): void {
    SettingsRepository.setBoolean(SettingsRepository.KEY_LAST_CRASH_DETECTED, false);
    this.phase = this.resolvePhase();
  }

  /**
   * System back key and back-swipe gesture. ArkUI delivers them only to the
   * @Entry component, and nothing consumed them before: back on any
   * full-screen route (设置详情/播放页/调试页…) put the whole ability in the
   * background instead of returning to the previous page — device-observed
   * 2026-08-24 (播放设置 → back → 桌面, process still alive).
   *
   * Consume it while the route stack has something to pop; at the root, and in
   * the startup gates (免责声明/引导/安全模式), fall through so the system
   * default (leave the app) still applies. Exception: on the disclaimer page
   * with the legal-doc overlay open, consume back to close the overlay first —
   * the overlay state lives in DisclaimerPage and is shared via AppStorage.
   */
  onBackPress(): boolean {
    if (this.phase === StartupPhase.DISCLAIMER) {
      const openedDoc = AppStorage.get<string>(DISCLAIMER_OPENED_DOC_KEY);
      if (openedDoc !== undefined && openedDoc.length > 0) {
        AppStorage.setOrCreate(DISCLAIMER_OPENED_DOC_KEY, '');
        return true;
      }
    }
    if (this.phase === StartupPhase.MAIN && Router.canPop()) {
      Router.pop();
      return true;
    }
    return false;
  }

  /** Same rule as Theme.isDark(), but read from tracked members so build() reacts. */
  private resolveDark(): boolean {
    if (this.darkMode === 'dark') {
      return true;
    }
    if (this.darkMode === 'light') {
      return false;
    }
    return this.systemDark;
  }

  /**
   * Colour painted behind the transparent system bars. Until the first frame
   * resolves it is the splash backplate — the same resource startWindowBackground
   * uses — so the launch page hands over without a colour flash; afterwards it
   * follows the theme so the bars stay merged with the page background.
   */
  private immersiveBackground(): ResourceColor {
    if (!this.loadingDone) {
      return $r('app.color.start_window_background');
    }
    return Theme.background(this.resolveDark());
  }

  build() {
    WithTheme({ theme: this.appTheme, colorMode: this.themeColorMode() }) {
      Stack() {
        // 沉浸背景层：应用底色铺进状态栏、导航条与挖孔区，系统栏因此显示应用
        // 背景而不是独立色块。内容层不做延伸，仍由 ArkUI 的安全区自动避让保护，
        // 文字与控件不会落到系统栏或挖孔下面。
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.immersiveBackground())
          .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
            [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        if (!this.loadingDone) {
          LoadingPage()
        } else if (this.phase === StartupPhase.DISCLAIMER) {
          DisclaimerPage({
            onAgree: () => this.onDisclaimerAgree(),
            // 布尔已真但版本不符时走到这里，说明是协议更新后的重新确认。
            reconfirmAfterUpdate: this.disclaimerAccepted
          })
        } else if (this.phase === StartupPhase.ONBOARDING) {
          OnboardingPage({
            onDone: () => this.onOnboardingDone()
          })
        } else if (this.phase === StartupPhase.SAFE_MODE) {
          SafeModePage({
            onRestoreNormal: () => this.onRestoreNormal()
          })
        } else {
          MainShell()
            .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.BOTTOM])
        }
      }
      .width('100%')
      .height('100%')
    }
  }

  /** np.dark_mode → WithTheme colorMode（系统跟随由 AppColorMode 负责）。 */
  private themeColorMode(): ThemeColorMode {
    if (this.darkMode === 'dark') {
      return ThemeColorMode.DARK;
    }
    if (this.darkMode === 'light') {
      return ThemeColorMode.LIGHT;
    }
    return ThemeColorMode.SYSTEM;
  }
}
