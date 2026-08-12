import { SettingsRepository } from '../data/SettingsRepository';
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
  @StorageProp('np.last_crash_detected') lastCrashDetected: boolean = false;
  @State phase: StartupPhase = StartupPhase.LOADING;
  @State loadingDone: boolean = false;

  async aboutToAppear(): Promise<void> {
    AppStorage.setOrCreate('systemDark', false);
    await SettingsRepository.initialize();
    this.phase = this.resolvePhase();
    this.loadingDone = true;
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
