// SPDX-License-Identifier: GPL-3.0

import { LengthMetrics } from '@kit.ArkUI';
import { SongItem } from '../../model/SongItem';
import { NeteaseApi } from '../../network/NeteaseApi';
import { BiliApi } from '../../network/BiliApi';
import { YouTubeMusicApi } from '../../network/YouTubeMusicApi';
import { NetworkStatus } from '../../util/NetworkStatus';
import { SearchHistoryRepository } from '../../data/SearchHistoryRepository';
import { UsageRepository } from '../../data/UsageRepository';
import { PlayerManager } from '../../player/PlayerManager';
import { Router } from '../Router';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { BAND_LIST_VP, BP_LG, BP_MD } from '../../util/Breakpoint';
import { SongRow } from '../components/SongRow';
import { SongListDataSource } from '../components/SongListDataSource';
import { EmptyState, LoadingState, FLOAT_TAB_CLEARANCE } from '../components/Ui';

/** 本页在 MainShell 的 Tabs 里的下标，用于过滤刷新信号。 */
const TAB_INDEX: number = 1;

/** MINI 标题栏标准高度（MainShell 同名常量）：内容顶部让位。 */
const TITLEBAR_SPACE_VP: number = 56;

@Component
export struct ExplorePage {
  /** 滚动控制器：实例由 MainShell 下发，绑定结果列表，壳层标题栏按当前 Tab 取用。 */
  scroller: Scroller = new Scroller();
  /** 滚动增量上报（MainShell 下发）：驱动悬浮栏组滚动自适应显隐，见 MainShell.handleTabBarScroll。 */
  onBarScroll: (yDelta: number) => void = () => {};
  /**
   * S5: 订阅封面配色。Theme.*() 读 AppStorage 是无跟踪调用（M7.4），换歌后
   * 坐在本页的组件不会重建；有了这个成员并经 schemeBg()/accent*() 直读，
   * scheme 一发布本页就随新配色重染。
   */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @State query: string = '';
  @State platform: number = 0;
  @Watch('onResultsChanged') @State results: SongItem[] = [];
  @State loading: boolean = false;
  @State error: string = '';
  @State history: string[] = [];
  @State searched: boolean = false;
  /** 由 util/WindowMetrics.ets 发布，这里只用来决定空态是否竖向居中。 */
  @StorageProp('ui.breakpoint') breakpoint: string = 'sm';
  /** 常驻 Tab 页的显式刷新钩子，详见 HomePage 同名成员。 */
  @StorageProp('np.default_start_tab') activeTab: number = 0;
  @StorageProp('ui.refreshTick') @Watch('onRefreshTick') refreshTick: number = 0;

  async aboutToAppear(): Promise<void> {
    await this.reload();
  }

  /**
   * 搜索结果列表走 LazyForEach 按需建行。@State results 整体重赋值时由
   * @Watch 同步进数据源。
   */
  private resultsDs: SongListDataSource = new SongListDataSource();

  onResultsChanged(): void {
    this.resultsDs.reset(this.results);
  }

  private async reload(): Promise<void> {
    this.history = await SearchHistoryRepository.load();
  }

  private onRefreshTick(): void {
    if (this.activeTab === TAB_INDEX) {
      this.reload();
    }
  }

  private wideLayout(): boolean {
    return this.breakpoint === BP_MD || this.breakpoint === BP_LG;
  }

  private async search(): Promise<void> {
    const keyword = this.query.trim();
    if (keyword.length === 0) {
      return;
    }
    this.history = await SearchHistoryRepository.add(keyword);
    const online = await NetworkStatus.hasNetwork();
    if (!online) {
      this.error = '离线模式：请联网后再搜索';
      this.results = [];
      this.searched = true;
      return;
    }
    this.loading = true;
    this.error = '';
    this.searched = true;
    try {
      if (this.platform === 0) {
        this.results = await NeteaseApi.search(keyword, 30);
      } else if (this.platform === 1) {
        this.results = await BiliApi.search(keyword, 20);
      } else {
        this.results = await YouTubeMusicApi.search(keyword, 20);
      }
      if (this.results.length === 0) {
        this.error = '没有找到结果';
      }
    } catch (searchError) {
      const e = searchError as Error;
      this.error = `搜索失败：${e.message}`;
      this.results = [];
    }
    this.loading = false;
  }

  private async play(index: number): Promise<void> {
    const songs = this.results;
    await PlayerManager.playPlaylist(songs, index);
    Router.push(Router.NOW_PLAYING);
    const song = songs[index];
    if (song !== undefined) {
      await UsageRepository.record({
        id: song.audioId,
        name: song.displayName,
        picUrl: song.effectiveCoverUrl,
        source: 'song',
        subtype: 'song',
        trackCount: 0,
        updatedAt: Date.now()
      });
    }
  }

  private async useHistory(keyword: string): Promise<void> {
    this.query = keyword;
    await this.search();
  }

  @Builder
  platformButton(index: number, label: string, icon: Resource) {
    Row({ space: 6 }) {
      Image(icon)
        .width(18)
        .height(18)
      Text(label)
        .fontSize(13)
        .fontColor(this.platform === index ? this.accentOnPrimary(Theme.isDark()) : Theme.textSecondary(Theme.isDark()))
    }
    .height(40)
    .padding({ left: 14, right: 14 })
    .backgroundColor(this.platform === index ? this.accentPrimary(Theme.isDark()) : this.accentSurface(Theme.isDark()))
    .borderRadius(17)
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .onClick(() => {
      this.platform = index;
      this.results = [];
      this.error = '';
      this.searched = false;
    })
  }


  /** build 里直读被跟踪成员注册依赖；颜色本身仍由 Theme 统一决策。 */
  private schemeBg(dark: boolean): string {
    const hasScheme = this.coverScheme.light.background.length > 0;
    return hasScheme ? Theme.background(dark) : Theme.background(dark);
  }

  /**
   * M7.4 的另一半：强调色与卡片底色节点直接写 Theme.*() 仍是无跟踪调用，
   * 换歌后不动。读法与 schemeBg 相同——先摸被跟踪的 coverScheme 注册依赖，
   * 取值依旧交给 Theme 统一决策（动态取色关闭、legacy seed 等回退路径不变）。
   */
  private accentPrimary(dark: boolean): string {
    const hasScheme = this.coverScheme.light.primary.length > 0;
    return hasScheme ? Theme.primary(dark) : Theme.primary(dark);
  }

  private accentOnPrimary(dark: boolean): string {
    const hasScheme = this.coverScheme.light.primary.length > 0;
    return hasScheme ? Theme.onPrimary(dark) : Theme.onPrimary(dark);
  }

  private accentSurfaceVariant(dark: boolean): string {
    const hasScheme = this.coverScheme.light.primary.length > 0;
    return hasScheme ? Theme.surfaceVariant(dark) : Theme.surfaceVariant(dark);
  }

  private accentSurface(dark: boolean): string {
    const hasScheme = this.coverScheme.light.primary.length > 0;
    return hasScheme ? Theme.surface(dark) : Theme.surface(dark);
  }

  build() {
    // 栏宽约束手写在这里而不套 ContentBand：结果列表靠 layoutWeight(1) 撑满剩余
    // 高度，需要 height('100%') 一路传到被约束的那一层，而 ContentBand 是按内容
    // 自适应高度的。Row 只负责把这条内容带在宽屏上居中。
    Row() {
    // 页内大标题「探索」由 MainShell 的 HdsNavigation MINI 标题栏承载，不再重复；
    // 内容顶部让位见下方 Column 的 padding({ top })。
    Column({ space: 10 }) {
      // S5: 参考图搜索条——胶囊输入框 + 重点色圆形搜索键（触达 44vp）。
      Row({ space: 10 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(18)
            .fontColor([Theme.textSecondary(Theme.isDark())])
          TextInput({ placeholder: '搜索歌曲 / 歌手 / 歌单', text: this.query })
            .layoutWeight(1)
            .height(44)
            .fontSize(14)
            .backgroundColor(Color.Transparent)
            .padding({ left: 0, right: 0 })
            .onChange((value: string) => {
              this.query = value;
            })
            .onSubmit(() => {
              this.search();
            })
        }
        .layoutWeight(1)
        .height(44)
        .padding({ left: 14, right: 8 })
        .backgroundColor(this.accentSurfaceVariant(Theme.isDark()))
        .borderRadius(22)

        Button() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(20)
            .fontColor([this.accentOnPrimary(Theme.isDark())])
        }
        .width(44)
        .height(44)
        .type(ButtonType.Circle)
        .backgroundColor(this.accentPrimary(Theme.isDark()))
        .accessibilityText('搜索')
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => this.search())
      }
      // 结果列表向上穿透时从这排固定控件背后滚过：列表声明在后、默认会盖住
      // 先声明的兄弟，这里提升搜索条的绘制次序保持其可见可点。
      .zIndex(1)
      .width('100%')

      // Wraps instead of a plain Row: at 1.45x system font the third chip
      // overflowed the right edge and became unreachable (device audit
      // 2026-08-24). Trading the X axis for the Y axis keeps it tappable.
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(10), cross: LengthMetrics.vp(8) } }) {
        this.platformButton(0, '网易云', $r('app.media.ic_netease_cloud_music'))
        this.platformButton(1, 'Bilibili', $r('app.media.ic_bilibili'))
        this.platformButton(2, 'YouTube Music', $r('app.media.ic_youtube'))
      }
      // 同搜索条：平台切换 chips 固定，需压在穿透列表之上。
      .zIndex(1)
      .width('100%')

      if (!this.searched && this.history.length > 0) {
        Column({ space: 8 }) {
          Row() {
            Text('搜索历史')
              .fontSize(13)
              .fontColor(Theme.textSecondary(Theme.isDark()))
              .layoutWeight(1)
            Text('清空')
              .fontSize(12)
              .fontColor(Theme.danger(Theme.isDark()))
              .onClick(async () => {
                this.history = await SearchHistoryRepository.clear();
              })
          }
          .width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.history, (keyword: string) => {
              Text(keyword)
                .fontSize(13)
                .fontColor(Theme.textPrimary(Theme.isDark()))
                .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                .backgroundColor(this.accentSurface(Theme.isDark()))
                .borderRadius(16)
                .margin({ right: 8, bottom: 8 })
                .onClick(() => this.useHistory(keyword))
            }, (keyword: string) => keyword)
          }
          .width('100%')
        }
        .width('100%')
      }

      if (this.loading) {
        LoadingState()
      } else if (this.error.length > 0) {
        EmptyState({ icon: '!', title: this.error })
      } else if (this.searched && this.results.length > 0) {
        List({ scroller: this.scroller }) {
          LazyForEach(this.resultsDs, (item: SongItem, index: number) => {
            ListItem() {
              SongRow({
                songJson: item.toJson(),
                index: index,
                onPlay: () => this.play(index)
              })
            }
          // key 含 index：新搜索后行内缓存的 index（onPlay 定位）会过期，
          // 靠 key 变化强制重建受影响行。
          }, (item: SongItem, index: number) => `${index}_${item.platform}_${item.audioId}_${item.id}`)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        // LazyForEach 视口外预建行数（与其他歌曲列表页一致）。
        .cachedCount(3, true)
        // 滚动自适应悬浮栏：增量交壳层（不消费）；触底报 -1 兜底唤回。
        .onScrollFrameBegin((offset: number) => {
          this.onBarScroll(offset);
          return { offsetRemain: offset };
        })
        .onReachEnd(() => {
          this.onBarScroll(-1);
        })
        // 顶部沉浸：结果列表向上穿透，滚过固定搜索区、标题栏后钻到状态栏
        // 被渐变模糊覆盖（与首页统一）；clip(false) 放行内容画出视口上沿。
        .clip(false)
        .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP])
        .width('100%')
      } else if (!this.searched) {
        Column({ space: 12 }) {
          Row({ space: 12 }) {
            Image($r('app.media.ic_music_note_24'))
              .width(26)
              .height(26)
              .fillColor(this.accentPrimary(Theme.isDark()))
            Column({ space: 2 }) {
              Text('搜索歌曲')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.textPrimary(Theme.isDark()))
              Text('输入关键词搜索网易云 / Bilibili / YouTube Music')
                .fontSize(12)
                .fontColor(Theme.textSecondary(Theme.isDark()))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('›')
              .fontSize(18)
              .fontColor(Theme.textDisabled(Theme.isDark()))
          }
          .width('100%')
          .padding(14)
          .backgroundColor(this.accentSurface(Theme.isDark()))
          .borderRadius(Theme.cardRadius())

          Row({ space: 12 }) {
            Image($r('app.media.ic_queue_music_24'))
              .width(26)
              .height(26)
              .fillColor(this.accentPrimary(Theme.isDark()))
            Column({ space: 2 }) {
              Text('搜索歌单')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.textPrimary(Theme.isDark()))
              Text('查找网易云歌单与 Bilibili 收藏夹')
                .fontSize(12)
                .fontColor(Theme.textSecondary(Theme.isDark()))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('›')
              .fontSize(18)
              .fontColor(Theme.textDisabled(Theme.isDark()))
          }
          .width('100%')
          .padding(14)
          .backgroundColor(this.accentSurface(Theme.isDark()))
          .borderRadius(Theme.cardRadius())
        }
        .width('100%')
        // md/lg 下这两张引导卡只占顶部一小条，下面整块都是空白。撑满剩余高度
        // 并竖向居中；窄屏保持原来的顶部对齐，视觉不变。
        .layoutWeight(1)
        .justifyContent(this.wideLayout() ? FlexAlign.Center : FlexAlign.Start)
      }
    }
    .width('100%')
    .height('100%')
    .constraintSize({ maxWidth: BAND_LIST_VP })
    .padding({ top: TITLEBAR_SPACE_VP, left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.schemeBg(Theme.isDark()))
  }
}
