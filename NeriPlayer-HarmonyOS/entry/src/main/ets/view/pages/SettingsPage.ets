import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { SettingsRepository } from '../../data/SettingsRepository';
import { SystemBars } from '../../util/SystemBars';
import { Router } from '../Router';
import { Theme } from '../Theme';
import { SettingRow } from '../components/Ui';

export const SETTING_PLAYBACK: string = 'playback';
export const SETTING_DOWNLOAD: string = 'download';
export const SETTING_LYRICS: string = 'lyrics';
export const SETTING_APPEARANCE: string = 'appearance';
export const SETTING_TRAFFIC: string = 'traffic';
export const SETTING_STORAGE: string = 'storage';
export const SETTING_ACCOUNTS: string = 'accounts';
export const SETTING_SYNC: string = 'sync';
export const SETTING_DEBUG: string = 'debug';
export const SETTING_ABOUT: string = 'about';

@Component
export struct SettingsPage {
  @StorageProp('np.dark_mode') darkMode: string = 'auto';
  @StorageProp('theme.isDark') isDark: boolean = false; // see Theme.IS_DARK_KEY
  @StorageProp('np.youtube_enabled') youtubeEnabled: boolean = true;
  @StorageProp('np.dev_mode') devMode: boolean = false;
  @StorageProp('np.dynamic_color') dynamicColor: boolean = true;

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(Theme.textSecondary(this.isDark))
      .width('100%')
      .margin({ left: 6, top: 14, bottom: 4 })
  }

  private cycleDarkMode(): void {
    const next = this.darkMode === 'auto' ? 'light' : (this.darkMode === 'light' ? 'dark' : 'auto');
    SettingsRepository.setString(SettingsRepository.KEY_DARK_MODE, next);
    // Republish the resolved flag so every subscribing component repaints.
    // Use the return value, not the local mirror — @StorageProp has not
    // necessarily propagated yet inside this same synchronous call. The
    // animated variant wraps the publish in a 420ms animateTo (M11.6a).
    const dark = Theme.refreshIsDarkAnimated();
    const context = AppStorage.get<common.UIAbilityContext>('abilityContext');
    if (context !== undefined) {
      SystemBars.apply(context, dark);
    }
  }

  build() {
    Scroll() {
      Column() {
        Text('设置')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary(this.isDark))
          .width('100%')
          .margin({ top: 12, bottom: 4 })

        this.sectionTitle('播放')
        Column({ space: 1 }) {
          SettingRow({
            title: '播放设置',
            subtitle: '速度、随机/循环、音质与断点恢复',
            icon: '▶',
            onTap: () => Router.push(Router.SETTINGS_DETAIL, SETTING_PLAYBACK)
          })
          SettingRow({
            title: '下载设置',
            subtitle: '并发数、下载目录与流量提醒',
            icon: '⤓',
            onTap: () => Router.push(Router.SETTINGS_DETAIL, SETTING_DOWNLOAD)
          })
          SettingRow({
            title: '歌词设置',
            subtitle: '字号、偏移、翻译与模糊效果',
            icon: '♪',
            onTap: () => Router.push(Router.SETTINGS_DETAIL, SETTING_LYRICS)
          })
        }
        .width('100%')
        .backgroundColor(Theme.surface(this.isDark))
        .borderRadius(Theme.cardRadius())
        .clip(true)

        this.sectionTitle('外观')
        Column({ space: 1 }) {
          SettingRow({
            title: '深色模式',
            subtitle: this.darkMode === 'auto' ? '跟随系统' : (this.darkMode === 'dark' ? '深色' : '浅色'),
            icon: '◐',
            onTap: () => this.cycleDarkMode()
          })
          SettingRow({
            title: '动态取色',
            subtitle: this.dynamicColor ? '已开启（跟随封面取色）' : '已关闭',
            icon: '🎨',
            onTap: () => {
              SettingsRepository.setBoolean(SettingsRepository.KEY_DYNAMIC_COLOR, !this.dynamicColor);
              promptAction.openToast({
                message: this.dynamicColor
                  ? '已关闭：主题与播放页使用默认配色'
                  : '已开启：主题色跟随当前歌曲封面'
              });
            }
          })
          SettingRow({
            title: '外观与动效',
            subtitle: '毛玻璃、过渡动画与桌面布局',
            icon: '✨',
            onTap: () => Router.push(Router.SETTINGS_DETAIL, SETTING_APPEARANCE)
          })
        }
        .width('100%')
        .backgroundColor(Theme.surface(this.isDark))
        .borderRadius(Theme.cardRadius())
        .clip(true)

        this.sectionTitle('网络与存储')
        Column({ space: 1 }) {
          SettingRow({
            title: '流量与封面',
            subtitle: '省流量模式、封面加载策略',
            icon: '📶',
            onTap: () => Router.push(Router.SETTINGS_DETAIL, SETTING_TRAFFIC)
          })
          SettingRow({
            title: '存储与缓存',
            subtitle: '缓存占用、清理与下载目录',
            icon: '🗄',
            onTap: () => Router.push(Router.SETTINGS_DETAIL, SETTING_STORAGE)
          })
        }
        .width('100%')
        .backgroundColor(Theme.surface(this.isDark))
        .borderRadius(Theme.cardRadius())
        .clip(true)

        this.sectionTitle('平台')
        Column({ space: 1 }) {
          SettingRow({
            title: '账号与登录',
            subtitle: '网易云 / Bilibili / YouTube',
            icon: '👤',
            onTap: () => Router.push(Router.SETTINGS_DETAIL, SETTING_ACCOUNTS)
          })
          SettingRow({
            title: '启用 YouTube',
            subtitle: this.youtubeEnabled ? '已启用' : '已停用',
            icon: '▶',
            onTap: () => SettingsRepository.setBoolean(SettingsRepository.KEY_YOUTUBE_ENABLED, !this.youtubeEnabled)
          })
          SettingRow({
            title: '同步',
            subtitle: 'GitHub / WebDAV 元数据同步',
            icon: '⇄',
            onTap: () => Router.push(Router.SETTINGS_DETAIL, SETTING_SYNC)
          })
          SettingRow({
            title: '一起听',
            subtitle: '创建或加入房间，与好友同步播放',
            icon: '👥',
            onTap: () => Router.push(Router.LISTEN_TOGETHER)
          })
        }
        .width('100%')
        .backgroundColor(Theme.surface(this.isDark))
        .borderRadius(Theme.cardRadius())
        .clip(true)

        this.sectionTitle('其他')
        Column({ space: 1 }) {
          SettingRow({
            title: '开发者模式',
            subtitle: this.devMode ? '已开启' : '已关闭',
            icon: '⚙',
            onTap: () => SettingsRepository.setBoolean(SettingsRepository.KEY_DEV_MODE, !this.devMode)
          })
          if (this.devMode) {
            SettingRow({
              title: '调试工具',
              subtitle: 'API 探测、日志与崩溃模拟',
              icon: '🔧',
              onTap: () => Router.push(Router.DEBUG)
            })
          }
          SettingRow({
            title: '关于',
            subtitle: '版本、许可与开源说明',
            icon: 'ℹ',
            onTap: () => Router.push(Router.SETTINGS_DETAIL, SETTING_ABOUT)
          })
        }
        .width('100%')
        .backgroundColor(Theme.surface(this.isDark))
        .borderRadius(Theme.cardRadius())
        .clip(true)
      }
      .width('100%')
      .padding({ left: 14, right: 14, bottom: 24 })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background(this.isDark))
  }
}
