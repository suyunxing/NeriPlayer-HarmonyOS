import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { SongItem } from '../../model/SongItem';
import { NeteaseApi } from '../../network/NeteaseApi';
import { BiliApi } from '../../network/BiliApi';
import { YouTubeMusicApi } from '../../network/YouTubeMusicApi';
import { NetworkStatus } from '../../util/NetworkStatus';
import { SearchHistoryRepository } from '../../data/SearchHistoryRepository';
import { UsageRepository } from '../../data/UsageRepository';
import { PlayerManager } from '../../player/PlayerManager';
import { Theme } from '../Theme';
import { SongRow } from '../components/SongRow';
import { EmptyState, LoadingState } from '../components/Ui';

@Component
export struct ExplorePage {
  // Target for focusControl.requestFocus when the "搜索歌曲" card is tapped.
  private static readonly SEARCH_INPUT_ID: string = 'explore_search_input';

  @StorageProp('theme.isDark') isDark: boolean = false; // see Theme.IS_DARK_KEY
  @State query: string = '';
  @State platform: number = 0;
  @State results: SongItem[] = [];
  @State loading: boolean = false;
  @State error: string = '';
  @State history: string[] = [];
  @State searched: boolean = false;

  async aboutToAppear(): Promise<void> {
    this.history = await SearchHistoryRepository.load();
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
        .fontColor(this.platform === index ? Theme.onPrimary(this.isDark) : Theme.textSecondary(this.isDark))
    }
    .height(40)
    .padding({ left: 14, right: 14 })
    .backgroundColor(this.platform === index ? Theme.primary(this.isDark) : Theme.surface(this.isDark))
    .borderRadius(17)
    .onClick(() => {
      this.platform = index;
      this.results = [];
      this.error = '';
      this.searched = false;
    })
  }

  build() {
    Column({ space: 10 }) {
      Text('探索')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary(this.isDark))
        .width('100%')
        .margin({ top: 12 })

      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索歌曲 / 歌手 / 歌单', text: this.query })
          .id(ExplorePage.SEARCH_INPUT_ID)
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .onChange((value: string) => {
            this.query = value;
          })
          .onSubmit(() => {
            this.search();
          })
        Button('搜索')
          .height(42)
          .fontSize(14)
          .backgroundColor(Theme.primary(this.isDark))
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
              .fontColor(Theme.textSecondary(this.isDark))
              .layoutWeight(1)
            Text('清空')
              .fontSize(12)
              .fontColor(Theme.danger(this.isDark))
              .onClick(async () => {
                this.history = await SearchHistoryRepository.clear();
              })
          }
          .width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.history, (keyword: string) => {
              Text(keyword)
                .fontSize(13)
                .fontColor(Theme.textPrimary(this.isDark))
                .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                .backgroundColor(Theme.surface(this.isDark))
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
        // The bare EmptyState left a dead end on a failed/offline search.
        Column({ space: 4 }) {
          EmptyState({ icon: '!', title: this.error })
          Button('重新搜索')
            .height(40)
            .fontSize(14)
            .backgroundColor(Theme.primary(this.isDark))
            .onClick(() => this.search())
        }
        .width('100%')
      } else if (this.searched && this.results.length > 0) {
        List() {
          ForEach(this.results, (item: SongItem, index: number) => {
            ListItem() {
              SongRow({
                songJson: item.toJson(),
                index: index,
                showPlatform: true,
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
              .fillColor(Theme.primary(this.isDark))
            Column({ space: 2 }) {
              Text('搜索歌曲')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.textPrimary(this.isDark))
              Text('输入关键词搜索网易云 / Bilibili / YouTube Music')
                .fontSize(12)
                .fontColor(Theme.textSecondary(this.isDark))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('›')
              .fontSize(18)
              .fontColor(Theme.textDisabled(this.isDark))
          }
          .width('100%')
          .padding(14)
          .backgroundColor(Theme.surface(this.isDark))
          .borderRadius(Theme.cardRadius())
          // The card carried a › affordance but no handler, so it read as a
          // broken button. It now does what its label says: focus the field.
          .onClick(() => {
            focusControl.requestFocus(ExplorePage.SEARCH_INPUT_ID);
          })

          Row({ space: 12 }) {
            Image($r('app.media.ic_queue_music_24'))
              .width(26)
              .height(26)
              .fillColor(Theme.primary(this.isDark))
            Column({ space: 2 }) {
              Text('搜索歌单')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.textPrimary(this.isDark))
              Text('待移植；可在「资料库」打开已导入的歌单与收藏夹')
                .fontSize(12)
                .fontColor(Theme.textSecondary(this.isDark))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('›')
              .fontSize(18)
              .fontColor(Theme.textDisabled(this.isDark))
          }
          .width('100%')
          .padding(14)
          .backgroundColor(Theme.surface(this.isDark))
          .borderRadius(Theme.cardRadius())
          // No playlist-search API is wired up, and both playlist routes need a
          // concrete id, so there is nothing honest to navigate to yet. Say so
          // rather than stay silent (registered in RELEASE_CHECKLIST.md §6).
          .onClick(() => {
            promptAction.openToast({ message: '歌单搜索待移植，请在「资料库」打开已导入的歌单' });
          })
        }
        .width('100%')
      }
    }
    .padding({ left: 16, right: 16 })
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background(this.isDark))
  }
}
