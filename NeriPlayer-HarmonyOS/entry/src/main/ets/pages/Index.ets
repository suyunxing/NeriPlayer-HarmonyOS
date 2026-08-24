import { SettingsRepository } from '../data/SettingsRepository';
import { Router } from '../view/Router';
import { LoadingPage } from '../view/pages/LoadingPage';
import { DisclaimerPage } from '../view/pages/DisclaimerPage';
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
  @StorageProp('np.onboarding_completed') onboardingCompleted: boolean = false;
  // The crash flag is armed asynchronously by CrashEventWatcher (fault
  // history pull on startup); watch it so a late flag still switches a
  // already-rendered main UI into Safe Mode.
  @StorageProp('np.last_crash_detected') @Watch('onCrashFlagChanged') lastCrashDetected: boolean = false;
  @State phase: StartupPhase = StartupPhase.LOADING;
  @State loadingDone: boolean = false;

  async aboutToAppear(): Promise<void> {
    AppStorage.setOrCreate('systemDark', false);
    await SettingsRepository.initialize();
    this.phase = this.resolvePhase();
    this.loadingDone = true;
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
    if (!this.disclaimerAccepted) {
      return StartupPhase.DISCLAIMER;
    }
    if (!this.onboardingCompleted) {
      return StartupPhase.ONBOARDING;
    }
    return StartupPhase.MAIN;
  }

  private onDisclaimerAgree(): void {
    SettingsRepository.setBoolean(SettingsRepository.KEY_DISCLAIMER_ACCEPTED, true);
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
   * default (leave the app) still applies.
   */
  onBackPress(): boolean {
    if (this.phase === StartupPhase.MAIN && Router.canPop()) {
      Router.pop();
      return true;
    }
    return false;
  }

  build() {
    Stack() {
      if (!this.loadingDone) {
        LoadingPage()
      } else if (this.phase === StartupPhase.DISCLAIMER) {
        DisclaimerPage({
          onAgree: () => this.onDisclaimerAgree()
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
      }
    }
    .width('100%')
    .height('100%')
  }
}
