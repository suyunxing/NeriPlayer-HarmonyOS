import { SongItem } from '../../model/SongItem';
import { HistoryRepository } from '../../data/HistoryRepository';
import { UsageRepository, UsageEntry } from '../../data/UsageRepository';
import { PlayerManager } from '../../player/PlayerManager';
import { Theme } from '../Theme';
import { EmptyState } from '../components/Ui';
import { SongRow } from '../components/SongRow';
import { Router } from '../Router';

@Component
export struct RecentPage {
  @State songs: SongItem[] = [];
  @State usage: UsageEntry[] = [];
  @State loaded: boolean = false;

  async aboutToAppear(): Promise<void> {
    this.songs = await HistoryRepository.getRecent();
    this.usage = await UsageRepository.load();
    this.loaded = true;
  }

  private play(index: number): void {
    PlayerManager.playPlaylist(this.songs, index);
    Router.push(Router.NOW_PLAYING);
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button('‹')
          .width(40)
          .height(40)
          // '‹' is punctuation to a screen reader; name the action.
          .accessibilityText('返回')
          .type(ButtonType.Circle)
          .backgroundColor(Color.Transparent)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .fontSize(20)
          .onClick(() => Router.pop())
        Text('播放历史')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .layoutWeight(1)
        Button('清空')
          .height(40)
          .fontSize(13)
          .backgroundColor(Theme.surface(Theme.isDark()))
          .fontColor(Theme.danger(Theme.isDark()))
          .onClick(async () => {
            await HistoryRepository.clear();
            this.songs = [];
          })
      }
      .width('100%')
      .padding({ left: 8, right: 14, top: 8, bottom: 8 })

      if (!this.loaded) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(Theme.primary(Theme.isDark()))
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.songs.length === 0) {
        EmptyState({
          icon: '⏱',
          title: '暂无播放历史',
          subtitle: '去「探索」找点歌吧'
        })
      } else {
        List() {
          ForEach(this.songs, (song: SongItem, index: number) => {
            ListItem() {
              SongRow({
                songJson: song.toJson(),
                index: index,
                showPlatform: true,
                onPlay: () => this.play(index)
              })
            }
          }, (song: SongItem) => `${song.platform}_${song.audioId}_${song.id}_${song.addedAt}`)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background(Theme.isDark()))
  }
}
