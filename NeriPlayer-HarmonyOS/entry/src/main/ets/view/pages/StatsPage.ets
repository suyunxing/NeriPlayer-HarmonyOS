import { PlaybackStatsRepository } from '../../data/PlaybackStatsRepository';
import { HistoryRepository } from '../../data/HistoryRepository';
import { SongItem } from '../../model/SongItem';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { Router } from '../Router';
import { iconForLegacy } from '../../util/IconCatalog';

@Component
export struct StatsPage {
  /**
   * S5: 订阅封面配色。Theme.*() 读 AppStorage 是无跟踪调用（M7.4），换歌后
   * 坐在本页的组件不会重建；有了这个成员并在 build 里经 schemeBg() 直读，
   * scheme 一发布本页就随新配色重染。
   */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @State totalPlays: number = 0;
  @State totalListenMs: number = 0;
  @State topSongs: SongItem[] = [];
  @State loaded: boolean = false;

  async aboutToAppear(): Promise<void> {
    this.totalPlays = await PlaybackStatsRepository.getTotalPlayCount();
    this.totalListenMs = await PlaybackStatsRepository.getTotalListenMs();
    this.topSongs = (await HistoryRepository.getRecent()).slice(0, 20);
    this.loaded = true;
  }


  /** build 里直读被跟踪成员注册依赖；颜色本身仍由 Theme 统一决策。 */
  private schemeBg(dark: boolean): string {
    const hasScheme = this.coverScheme.light.background.length > 0;
    return hasScheme ? Theme.background(dark) : Theme.background(dark);
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
        Text('播放统计')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary(Theme.isDark()))
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
      } else {
        Column({ space: 12 }) {
          Row({ space: 10 }) {
            StatTile({ icon: '▶', value: `${this.totalPlays}`, label: '累计播放' })
            StatTile({
              icon: '⏱',
              value: `${Math.floor(this.totalListenMs / 3600000)} 小时`,
              label: '累计收听'
            })
            StatTile({ icon: '🎵', value: `${this.topSongs.length}`, label: '历史曲目' })
          }
          .width('100%')

          Text('最近播放')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .width('100%')

          List() {
            ForEach(this.topSongs, (song: SongItem) => {
              ListItem() {
                Row({ space: 10 }) {
                  Image($r('app.media.ic_music_note_24'))
                    .width(18)
                    .height(18)
                    .fillColor(Theme.primary(Theme.isDark()))
                  Column({ space: 2 }) {
                    Text(song.displayName)
                      .fontSize(14)
                      .fontColor(Theme.textPrimary(Theme.isDark()))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(song.displayArtist)
                      .fontSize(11)
                      .fontColor(Theme.textSecondary(Theme.isDark()))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .padding(8)
              }
            }, (song: SongItem) => `${song.platform}_${song.audioId}_${song.id}`)
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .width('100%')
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.schemeBg(Theme.isDark()))
  }
}

@Component
struct StatTile {
  icon: string = '';
  value: string = '';
  label: string = '';

  build() {
    Column({ space: 4 }) {
      Image(iconForLegacy(this.icon, $r('app.media.ic_music_note_24')))
        .width(20)
        .height(20)
        .fillColor(Theme.primary(Theme.isDark()))
      Text(this.value)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary(Theme.isDark()))
        .maxLines(1)
      Text(this.label)
        .fontSize(11)
        .fontColor(Theme.textSecondary(Theme.isDark()))
    }
    .layoutWeight(1)
    .padding({ top: 14, bottom: 14 })
    .backgroundColor(Theme.surface(Theme.isDark()))
    .borderRadius(14)
    .alignItems(HorizontalAlign.Center)
  }
}
