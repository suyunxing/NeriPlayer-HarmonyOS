// SPDX-License-Identifier: GPL-3.0

import { common } from '@kit.AbilityKit';
import { Constants } from '../../app/Constants';
import { SettingsRepository } from '../../data/SettingsRepository';
import { openExternalLink } from '../../util/LinkLauncher';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import {
  ContentBand,
  SettingHubRow,
  SettingRow,
  ToggleRow,
  FLOAT_TAB_CLEARANCE
} from '../components/Ui';
import { BAND_LIST_VP } from '../../util/Breakpoint';
import { Router } from '../Router';

/** MINI 标题栏标准高度（MainShell 同名常量）：内容顶部让位，滚动时从标题栏背后滚过。 */
const TITLEBAR_SPACE_VP: number = 56;

export const SETTING_PLAYBACK: string = 'playback';
export const SETTING_DOWNLOAD: string = 'download';
export const SETTING_LYRICS: string = 'lyrics';
export const SETTING_PLAYER: string = 'player';
export const SETTING_APPEARANCE: string = 'appearance';
export const SETTING_NAVIGATION: string = 'navigation';
export const SETTING_TRAFFIC: string = 'traffic';
export const SETTING_STORAGE: string = 'storage';
export const SETTING_ACCOUNTS: string = 'accounts';
export const SETTING_SYNC: string = 'sync';
export const SETTING_PLAYLIST_SYNC: string = 'playlist_sync';
export const SETTING_DEBUG: string = 'debug';
export const SETTING_DONATE: string = 'donate';
export const SETTING_ABOUT: string = 'about';

@Component
export struct SettingsPage {
  /** 滚动控制器：实例由 MainShell 下发，壳层标题栏 bindToScrollable 绑定当前 Tab 的它。 */
  scroller: Scroller = new Scroller();
  /** 滚动增量上报（MainShell 下发）：驱动悬浮栏组滚动自适应显隐，见 MainShell.handleTabBarScroll。 */
  onBarScroll: (yDelta: number) => void = () => {};
  /**
   * S5: 订阅封面配色。Theme.*() 读 AppStorage 是无跟踪调用（M7.4），换歌后
   * 坐在本页的组件不会重建；有了这个成员并在 build 里经 schemeBg() 直读，
   * scheme 一发布本页就随新配色重染。
   */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @StorageProp('np.youtube_enabled') youtubeEnabled: boolean = true;
  @StorageProp('np.dev_mode') devMode: boolean = false;

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(Theme.textSecondary(Theme.isDark()))
      .width('100%')
      .margin({ left: 6, top: 14, bottom: 4 })
  }

  /** build 里直读被跟踪成员注册依赖；颜色本身仍由 Theme 统一决策。 */
  private schemeBg(dark: boolean): string {
    const hasScheme = this.coverScheme.light.background.length > 0;
    return hasScheme ? Theme.background(dark) : Theme.background(dark);
  }

  /** 托管的法律文档：拉起系统浏览器打开（正文不在应用内，母本见仓库 docs/legal/）。 */
  private openLegalDoc(url: string): void {
    const context = AppStorage.get<common.UIAbilityContext>('abilityContext');
    if (context === undefined || context === null) {
      return;
    }
    openExternalLink(context, url);
  }

  build() {
    // 页内不再自绘标题栏：标题由 MainShell 的 HdsNavigation MINI 标题栏
    // （GRADIENT_BLUR 渐变模糊）承载，本页只做列表 + 顶部让位，滚动时列表
    // 从标题栏背后滚过。
    Scroll(this.scroller) {
      // 840vp 列表栏宽：tablet 1440vp 下设置行的图标贴左边缘、箭头贴右边缘，中间
      // 是一大片空白，一屏只读到七八个标题（审计 §8.2 第 2 条）。
      ContentBand({ maxWidth: BAND_LIST_VP }) {
      Column() {
        // 设置总览（参考应用的设置中心）：六大分类入口一屏直达，其余分组
        // （网络与存储、平台、隐私、其他）保留在下方。
        Column({ space: 10 }) {
          SettingHubRow({
            title: '云端',
            subtitle: 'GitHub / WebDAV 备份与一起听服务器',
            icon: '☁',
            onTap: () => Router.push(Router.SETTINGS_DETAIL, SETTING_SYNC)
          })
          SettingHubRow({
            title: '播放',
            subtitle: '音质、音量与播放行为',
            icon: '▶',
            onTap: () => Router.push(Router.SETTINGS_DETAIL, SETTING_PLAYBACK)
          })
          SettingHubRow({
            title: '歌词',
            subtitle: '歌词显示与外观样式',
            icon: '♪',
            onTap: () => Router.push(Router.SETTINGS_DETAIL, SETTING_LYRICS)
          })
          SettingHubRow({
            title: '播放器',
            subtitle: '全屏播放器与底部播放器',
            icon: '🎧',
            onTap: () => Router.push(Router.SETTINGS_DETAIL, SETTING_PLAYER)
          })
          SettingHubRow({
            title: '界面与外观',
            subtitle: '应用深浅色、主题色与背景',
            icon: '🎨',
            onTap: () => Router.push(Router.SETTINGS_DETAIL, SETTING_APPEARANCE)
          })
          SettingHubRow({
            title: '页面与导航',
            subtitle: '默认启动页与页面内容设置',
            icon: '🧭',
            onTap: () => Router.push(Router.SETTINGS_DETAIL, SETTING_NAVIGATION)
          })
          SettingHubRow({
            title: '歌单同步',
            subtitle: '网易云歌单 / B站收藏夹自动同步为镜像歌单',
            icon: '🔁',
            onTap: () => Router.push(Router.SETTINGS_DETAIL, SETTING_PLAYLIST_SYNC)
          })
        }
        .width('100%')

        this.sectionTitle('网络与存储')
        Column({ space: 10 }) {
          SettingRow({
            title: '下载设置',
            subtitle: '并发数、下载目录与流量提醒',
            icon: '⤓',
            onTap: () => Router.push(Router.SETTINGS_DETAIL, SETTING_DOWNLOAD)
          })
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

        this.sectionTitle('平台')
        Column({ space: 10 }) {
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
            title: '一起听',
            subtitle: '创建或加入房间，与好友同步播放',
            icon: '👥',
            onTap: () => Router.push(Router.LISTEN_TOGETHER)
          })
        }
        .width('100%')

        // 指南要求隐私政策与用户协议在应用内随时可达、可完整打开，不只出现在
        // 首启弹窗里。正文托管在应用外，点击经系统浏览器打开。
        this.sectionTitle('隐私与协议')
        Column({ space: 10 }) {
          SettingRow({
            title: '隐私政策',
            subtitle: '收集范围、权限用途与你的控制权',
            icon: '🔒',
            onTap: () => this.openLegalDoc(Constants.LEGAL_PRIVACY_URL)
          })
          SettingRow({
            title: '用户协议',
            subtitle: '使用限制、账号与免责声明',
            icon: '📄',
            onTap: () => this.openLegalDoc(Constants.LEGAL_AGREEMENT_URL)
          })
        }
        .width('100%')

        this.sectionTitle('其他')
        Column({ space: 10 }) {
          SettingRow({
            title: '播放历史',
            subtitle: '最近播放的歌曲与播放次数',
            icon: '⏱',
            onTap: () => Router.push(Router.RECENT)
          })
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
          SettingRow({
            title: '打赏作者',
            subtitle: '微信 / 支付宝收款码',
            icon: '❤',
            onTap: () => Router.push(Router.SETTINGS_DETAIL, SETTING_DONATE)
          })
        }
        .width('100%')
              }
        .width('100%')
      .padding({ top: TITLEBAR_SPACE_VP, left: 14, right: 14, bottom: 24 + FLOAT_TAB_CLEARANCE })
      }
      }
      .scrollBar(BarState.Off)
      // 滚动自适应悬浮栏：增量交壳层（不消费，见 MainShell.handleTabBarScroll）。
      .onScrollFrameBegin((offset: number) => {
        this.onBarScroll(offset);
        return { offsetRemain: offset };
      })
      // Scroll 的 align 默认是 Alignment.Center：内容短于视口时（大屏、或字号最小
      // 档）整份设置项会被甩到屏幕竖向正中，标题留在顶上，读起来是断开的两块。
      // 设置类页面必须自上而下读，这里显式钉到顶部。
      .align(Alignment.Top)
      .width('100%')
      .height('100%')
      // 顶部沉浸：视口向上延伸进状态栏区，列表滚过标题栏后继续钻到状态栏
      // 被渐变模糊覆盖（与首页统一）；clip(false) 放行内容画出视口上沿，
      // expandSafeArea 只扩绘制区不改布局，首屏让位不变。
      .clip(false)
      .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP])
      .backgroundColor(this.schemeBg(Theme.isDark()))
  }
}
