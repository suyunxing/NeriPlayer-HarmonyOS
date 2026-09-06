import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { SettingsRepository } from '../../data/SettingsRepository';
import { AppColorMode } from '../../util/AppColorMode';
import { SystemBars } from '../../util/SystemBars';
import { Router } from '../Router';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { ContentBand, OptionEntry, OptionRow, SettingRow, ToggleRow , FLOAT_TAB_CLEARANCE } from '../components/Ui';
import { BAND_LIST_VP } from '../../util/Breakpoint';
import { LEGAL_AGREEMENT, LEGAL_PRIVACY } from './LegalDocPage';

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
  /**
   * S5: 订阅封面配色。Theme.*() 读 AppStorage 是无跟踪调用（M7.4），换歌后
   * 坐在本页的组件不会重建；有了这个成员并在 build 里经 schemeBg() 直读，
   * scheme 一发布本页就随新配色重染。
   */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @StorageProp('np.dark_mode') darkMode: string = 'auto';
  @StorageProp('np.youtube_enabled') youtubeEnabled: boolean = true;
  @StorageProp('np.dev_mode') devMode: boolean = false;
  @StorageProp('np.dynamic_color') dynamicColor: boolean = true;

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(Theme.textSecondary(Theme.isDark()))
      .width('100%')
      .margin({ left: 6, top: 14, bottom: 4 })
  }

  private darkModeOptions(): OptionEntry[] {
    const options: OptionEntry[] = [
      { value: 'auto', label: '跟随系统' },
      { value: 'light', label: '浅色' },
      { value: 'dark', label: '深色' }
    ];
    return options;
  }

  private applyDarkMode(mode: string): void {
    if (mode === this.darkMode) {
      return;
    }
    SettingsRepository.setString(SettingsRepository.KEY_DARK_MODE, mode);
    const context = AppStorage.get<common.UIAbilityContext>('abilityContext');
    if (context !== undefined) {
      // setColorMode 触发配置变更、重建整棵组件树，否则本页与 MainShell 的
      // 颜色表达式不引用可观察状态，切换后不会重绘（见 AppColorMode 注释）。
      AppColorMode.apply(context, mode);
      // 系统栏内容色仍显式跟一次：setColorMode 抛错时这里是兜底。
      SystemBars.apply(context, Theme.isDark());
    }
  }


  /** build 里直读被跟踪成员注册依赖；颜色本身仍由 Theme 统一决策。 */
  private schemeBg(dark: boolean): string {
    const hasScheme = this.coverScheme.light.background.length > 0;
    return hasScheme ? Theme.background(dark) : Theme.background(dark);
  }

  build() {
    Scroll() {
      // 840vp 列表栏宽：tablet 1440vp 下设置行的图标贴左边缘、箭头贴右边缘，中间
      // 是一大片空白，一屏只读到七八个标题（审计 §8.2 第 2 条）。
      ContentBand({ maxWidth: BAND_LIST_VP }) {
      Column() {
        Text('设置')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary(Theme.isDark()))
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
        .backgroundColor(Theme.surface(Theme.isDark()))
        .borderRadius(Theme.cardRadius())
        .clip(true)

        this.sectionTitle('外观')
        Column({ space: 1 }) {
          OptionRow({
            title: '深色模式',
            icon: '◐',
            options: this.darkModeOptions(),
            current: this.darkMode,
            onPick: (mode: string) => this.applyDarkMode(mode)
          })
          ToggleRow({
            title: '动态取色',
            subtitle: '主题色跟随当前歌曲封面',
            icon: '🎨',
            value: this.dynamicColor,
            onChange: (on: boolean) => {
              SettingsRepository.setBoolean(SettingsRepository.KEY_DYNAMIC_COLOR, on);
              promptAction.openToast({
                message: on
                  ? '已开启：主题色跟随当前歌曲封面'
                  : '已关闭：主题与播放页使用默认配色'
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
        .backgroundColor(Theme.surface(Theme.isDark()))
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
        .backgroundColor(Theme.surface(Theme.isDark()))
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
          ToggleRow({
            title: '启用 YouTube',
            icon: '▶',
            value: this.youtubeEnabled,
            onChange: (on: boolean) =>
              SettingsRepository.setBoolean(SettingsRepository.KEY_YOUTUBE_ENABLED, on)
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
        .backgroundColor(Theme.surface(Theme.isDark()))
        .borderRadius(Theme.cardRadius())
        .clip(true)

        // 指南要求隐私政策与用户协议在应用内随时可达、可完整打开，不只出现在
        // 首启弹窗里。
        this.sectionTitle('隐私与协议')
        Column({ space: 1 }) {
          SettingRow({
            title: '隐私政策',
            subtitle: '收集范围、权限用途与你的控制权',
            icon: '🔒',
            onTap: () => Router.push(Router.LEGAL_DOC, LEGAL_PRIVACY)
          })
          SettingRow({
            title: '用户协议',
            subtitle: '使用限制、账号与免责声明',
            icon: '📄',
            onTap: () => Router.push(Router.LEGAL_DOC, LEGAL_AGREEMENT)
          })
        }
        .width('100%')
        .backgroundColor(Theme.surface(Theme.isDark()))
        .borderRadius(Theme.cardRadius())
        .clip(true)

        this.sectionTitle('其他')
        Column({ space: 1 }) {
          ToggleRow({
            title: '开发者模式',
            icon: '⚙',
            value: this.devMode,
            onChange: (on: boolean) =>
              SettingsRepository.setBoolean(SettingsRepository.KEY_DEV_MODE, on)
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
        .backgroundColor(Theme.surface(Theme.isDark()))
        .borderRadius(Theme.cardRadius())
        .clip(true)
      }
      .width('100%')
      .padding({ left: 14, right: 14, bottom: 24 + FLOAT_TAB_CLEARANCE })
      }
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    // Scroll 的 align 默认是 Alignment.Center：内容短于视口时（大屏、或字号最小
    // 档）整份设置项会被甩到屏幕竖向正中，标题留在顶上，读起来是断开的两块。
    // 设置类页面必须自上而下读，这里显式钉到顶部。
    .align(Alignment.Top)
    .width('100%')
    .height('100%')
    .backgroundColor(this.schemeBg(Theme.isDark()))
  }
}
