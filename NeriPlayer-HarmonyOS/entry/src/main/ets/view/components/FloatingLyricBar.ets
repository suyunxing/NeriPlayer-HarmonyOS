import { PlaybackStatus } from '../../player/PlaybackConstants';
import { Theme } from '../Theme';

/**
 * In-app floating lyric bar — the D4 fallback for Android's
 * FloatingLyricsOverlayManager: ordinary HarmonyOS apps cannot draw over
 * other apps (no SYSTEM_ALERT_WINDOW equivalent), so the "floating" line is
 * an overlay inside this app, pinned above the tab content on every page
 * except the full-screen NowPlaying page (which already shows full lyrics).
 * The line text itself is computed by PlayerManager via LyricLineTracker and
 * published as 'player.currentLyricLine'; the raw string is mirrored into
 * @State through @Watch (M7.4 minimal-update pitfall).
 */
@Component
export struct FloatingLyricBar {
  @StorageProp('theme.isDark') isDark: boolean = false; // see Theme.IS_DARK_KEY
  @StorageProp('np.floating_lyric') floatingEnabled: boolean = false;
  @StorageProp('player.currentLyricLine') @Watch('onLineChanged') lineFeed: string = '';
  @StorageLink('player.status') status: number = PlaybackStatus.IDLE;
  @State lineText: string = '';

  private onLineChanged(): void {
    this.lineText = this.lineFeed;
  }

  build() {
    if (this.floatingEnabled && this.lineText.length > 0 && this.status === PlaybackStatus.PLAYING) {
      Row() {
        Text(this.lineText)
          .fontSize(13)
          .fontColor(Theme.textPrimary(this.isDark))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('88%')
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .backgroundColor(Theme.withAlpha(Theme.surface(this.isDark), 0xE6))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .borderRadius(18)
      .shadow({ radius: 8, color: '#33000000', offsetY: 2 })
      .alignSelf(ItemAlign.Center)
    }
  }
}
