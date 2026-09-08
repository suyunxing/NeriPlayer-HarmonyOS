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
import { EmptyState, LoadingState, FLOAT_TAB_CLEARANCE } from '../components/Ui';

/** 本页在 MainShell 的 Tabs 里的下标，用于过滤刷新信号。 */
const TAB_INDEX: number = 1;

@Component
export struct ExplorePage {
  /**
   * S5: 订阅封面配色。Theme.*() 读 AppStorage 是无跟踪调用（M7.4），换歌后
   * 坐在本页的组件不会重建；有了这个成员并在 build 里经 schemeBg() 直读，
   * scheme 一发布本页就随新配色重染。
   */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @State query: string = '';
  @State platform: number = 0;
  @State results: SongItem[] = [];
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
        .fontColor(this.platform === index ? Theme.onPrimary(Theme.isDark()) : Theme.textSecondary(Theme.isDark()))
    }
    .height(40)
    .padding({ left: 14, right: 14 })
    .backgroundColor(this.platform === index ? Theme.primary(Theme.isDark()) : Theme.surface(Theme.isDark()))
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

  build() {
    // 栏宽约束手写在这里而不套 ContentBand：结果列表靠 layoutWeight(1) 撑满剩余
    // 高度，需要 height('100%') 一路传到被约束的那一层，而 ContentBand 是按内容
    // 自适应高度的。Row 只负责把这条内容带在宽屏上居中。
    Row() {
    Column({ space: 10 }) {
      Text('探索')
        .fontSize(32)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary(Theme.isDark()))
        .width('100%')
        .margin({ top: 12 })

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
        .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
        .borderRadius(22)

        Button() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(20)
            .fontColor([Theme.onPrimary(Theme.isDark())])
        }
        .width(44)
        .height(44)
        .type(ButtonType.Circle)
        .backgroundColor(Theme.primary(Theme.isDark()))
        .accessibilityText('搜索')
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => this.search())
      }
      .width('100%')

      // Wraps instead of a plain Row: at 1.45x system font the third chip
      // overflowed the right edge and became unreachable (device audit
      // 2026-08-24). Trading the X axis for the Y axis keeps it tappable.
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(10), cross: LengthMetrics.vp(8) } }) {
        this.platformButton(0, '网易云', $r('app.media.ic_netease_cloud_music'))
        this.platformButton(1, 'Bilibili', $r('app.media.ic_bilibili'))
        this.platformButton(2, 'YouTube Music', $r('app.media.ic_youtube'))
      }
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
                .backgroundColor(Theme.surface(Theme.isDark()))
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
        List() {
          ForEach(this.results, (item: SongItem, index: number) => {
            ListItem() {
              SongRow({
                songJson: item.toJson(),
                index: index,
                onPlay: () => this.play(index)
              })
            }
          }, (item: SongItem) => `${item.platform}_${item.audioId}_${item.id}`)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .width('100%')
      } else if (!this.searched) {
        Column({ space: 12 }) {
          Row({ space: 12 }) {
            Image($r('app.media.ic_music_note_24'))
              .width(26)
              .height(26)
              .fillColor(Theme.primary(Theme.isDark()))
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
          .backgroundColor(Theme.surface(Theme.isDark()))
          .borderRadius(Theme.cardRadius())

          Row({ space: 12 }) {
            Image($r('app.media.ic_queue_music_24'))
              .width(26)
              .height(26)
              .fillColor(Theme.primary(Theme.isDark()))
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
          .backgroundColor(Theme.surface(Theme.isDark()))
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
    .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.schemeBg(Theme.isDark()))
  }
}
