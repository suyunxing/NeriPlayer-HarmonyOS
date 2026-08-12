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
        .fontColor(this.platform === index ? Theme.onPrimary(Theme.isDark()) : Theme.textSecondary(Theme.isDark()))
    }
    .height(34)
    .padding({ left: 14, right: 14 })
    .backgroundColor(this.platform === index ? Theme.primary(Theme.isDark()) : Theme.surface(Theme.isDark()))
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
        .fontColor(Theme.textPrimary(Theme.isDark()))
        .width('100%')
        .margin({ top: 12 })

      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索歌曲 / 歌手 / 歌单', text: this.query })
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
          .backgroundColor(Theme.primary(Theme.isDark()))
          .onClick(() => this.search())
      }
      .width('100%')

      Row({ space: 10 }) {
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
            Text('🎵')
              .fontSize(28)
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
            Text('📋')
              .fontSize(28)
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
      }
    }
    .padding({ left: 16, right: 16 })
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background(Theme.isDark()))
  }
}
