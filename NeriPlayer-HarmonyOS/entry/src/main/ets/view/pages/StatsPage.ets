// SPDX-License-Identifier: GPL-3.0

import { PlaybackStatsRepository } from '../../data/PlaybackStatsRepository';
import {
  AggregatedArtistStat,
  AggregatedTrackStat,
  STATS_RANGE_LABELS,
  StatsTimeRange,
  aggregateArtistStats,
  aggregateTrackStats,
  attachTrackSongMeta,
  compareTracksByCountDesc,
  compareTracksByListenMsDesc
} from '../../data/PlaybackStatsAggregator';
import { HistoryRepository } from '../../data/HistoryRepository';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { DownloadStorage } from '../../download/DownloadStorage';
import { SongItem } from '../../model/SongItem';
import { stableKeyOf } from '../../model/SongIdentity';
import { PlayerManager } from '../../player/PlayerManager';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { Router } from '../Router';
import { iconForLegacy } from '../../util/IconCatalog';

/**
 * 播放统计（backlog §5.1，对齐 Android PlaybackStatsScreen）：日/周/月/年/全部
 * 时间窗、按次数/时长排序、艺人聚合、条目点击起播。聚合逻辑在
 * PlaybackStatsAggregator（纯函数单测），本页只负责装载与渲染。
 */
@Component
export struct StatsPage {
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @State range: StatsTimeRange = StatsTimeRange.ALL;
  @State sortByDuration: boolean = false;
  @State tracks: AggregatedTrackStat[] = [];
  @State artists: AggregatedArtistStat[] = [];
  @State songsByKey: Map<string, SongItem> = new Map();
  @State loaded: boolean = false;

  async aboutToAppear(): Promise<void> {
    this.songsByKey = await StatsPage.buildSongIndex();
    this.loaded = true;
    await this.reload();
  }

  private static async buildSongIndex(): Promise<Map<string, SongItem>> {
    const index = new Map<string, SongItem>();
    for (const playlist of await LocalPlaylistRepository.loadAll()) {
      for (const song of playlist.songs) {
        index.set(stableKeyOf(song), song);
      }
    }
    for (const song of await HistoryRepository.getRecent()) {
      index.set(stableKeyOf(song), song);
    }
    for (const entry of await DownloadStorage.getCatalog()) {
      if (entry.songJson.length > 0) {
        try {
          const song = SongItem.fromJson(entry.songJson);
          index.set(stableKeyOf(song), song);
        } catch (_error) {
          // Corrupt snapshot rows simply miss their display metadata.
        }
      }
    }
    return index;
  }

  private async reload(): Promise<void> {
    const root = await PlaybackStatsRepository.snapshot();
    let tracks = aggregateTrackStats(root, this.range, Date.now());
    attachTrackSongMeta(tracks, this.songsByKey);
    tracks.sort(this.sortByDuration ? compareTracksByListenMsDesc : compareTracksByCountDesc);
    this.tracks = tracks.slice(0, 100);
    this.artists = aggregateArtistStats(tracks,
      this.sortByDuration ? compareTracksByListenMsDesc : compareTracksByCountDesc).slice(0, 10);
  }

  private totalPlays(): number {
    let total = 0;
    for (const track of this.tracks) {
      total += track.playCount;
    }
    return total;
  }

  private totalListenMs(): number {
    let total = 0;
    for (const track of this.tracks) {
      total += track.listenMs;
    }
    return total;
  }

  private static formatDuration(listenMs: number): string {
    if (listenMs >= 3600000) {
      const hours = Math.floor(listenMs / 3600000);
      const minutes = Math.floor((listenMs % 3600000) / 60000);
      return minutes > 0 ? `${hours} 小时 ${minutes} 分` : `${hours} 小时`;
    }
    return `${Math.floor(listenMs / 60000)} 分钟`;
  }

  private playTrack(track: AggregatedTrackStat): void {
    if (track.song !== null) {
      PlayerManager.playPlaylist([track.song], 0);
    }
  }

  private schemeBg(dark: boolean): string {
    return Theme.background(dark);
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button('‹')
          .width(40)
          .height(40)
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
          // 时间范围选择（Android 日/周/月/年/全部）。
          Row({ space: 6 }) {
            ForEach(STATS_RANGE_LABELS, (label: string, index: number) => {
              Text(label)
                .fontSize(12)
                .fontColor(this.range === index
                  ? Theme.onPrimary(Theme.isDark())
                  : Theme.textSecondary(Theme.isDark()))
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .backgroundColor(this.range === index
                  ? Theme.primary(Theme.isDark())
                  : Theme.surface(Theme.isDark()))
                .borderRadius(12)
                .onClick(() => {
                  this.range = index as StatsTimeRange;
                  this.reload();
                })
            }, (label: string) => label)
          }
          .width('100%')

          Row({ space: 10 }) {
            StatTile({ icon: '▶', value: `${this.totalPlays()}`, label: '播放次数' })
            StatTile({
              icon: '⏱',
              value: StatsPage.formatDuration(this.totalListenMs()),
              label: '收听时长'
            })
            StatTile({ icon: '🎵', value: `${this.tracks.length}`, label: '上榜曲目' })
          }
          .width('100%')

          if (this.artists.length > 0) {
            Column({ space: 6 }) {
              Text('歌手榜')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.textPrimary(Theme.isDark()))
                .width('100%')
              Scroll() {
                Row({ space: 8 }) {
                  ForEach(this.artists, (artist: AggregatedArtistStat) => {
                    Column({ space: 4 }) {
                      Text(artist.artist.length > 0 ? artist.artist.substring(0, 8) : '未知')
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(Theme.textPrimary(Theme.isDark()))
                        .maxLines(1)
                      Text(`${artist.playCount} 次 · ${artist.trackCount} 首`)
                        .fontSize(10)
                        .fontColor(Theme.textSecondary(Theme.isDark()))
                        .maxLines(1)
                    }
                    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                    .backgroundColor(Theme.surface(Theme.isDark()))
                    .borderRadius(12)
                    .alignItems(HorizontalAlign.Center)
                  }, (artist: AggregatedArtistStat) => `${artist.artist}_${artist.playCount}`)
                }
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
            }
            .width('100%')
          }

          Row() {
            Text(this.sortByDuration ? '曲目榜 · 按时长' : '曲目榜 · 按次数')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.textPrimary(Theme.isDark()))
              .layoutWeight(1)
            Text('切换排序')
              .fontSize(12)
              .fontColor(Theme.primary(Theme.isDark()))
              .padding(4)
              .onClick(() => {
                this.sortByDuration = !this.sortByDuration;
                this.reload();
              })
          }
          .width('100%')

          if (this.tracks.length === 0) {
            Column() {
              Text('该时间范围内还没有播放记录')
                .fontSize(13)
                .fontColor(Theme.textSecondary(Theme.isDark()))
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .width('100%')
          } else {
            List() {
              ForEach(this.tracks, (track: AggregatedTrackStat, index: number) => {
                ListItem() {
                  Row({ space: 10 }) {
                    Text(`${index + 1}`)
                      .fontSize(13)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Theme.textSecondary(Theme.isDark()))
                      .width(20)
                    Image(track.coverUrl.length > 0 ? track.coverUrl : $r('app.media.ic_music_note_24'))
                      .width(38)
                      .height(38)
                      .borderRadius(8)
                      .fillColor(track.coverUrl.length > 0 ? Color.Transparent : Theme.primary(Theme.isDark()))
                      .alt($r('app.media.ic_music_note_24'))
                    Column({ space: 2 }) {
                      Text(track.name.length > 0 ? track.name : '未知歌曲')
                        .fontSize(14)
                        .fontColor(Theme.textPrimary(Theme.isDark()))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(track.artist.length > 0 ? track.artist : ' ')
                        .fontSize(11)
                        .fontColor(Theme.textSecondary(Theme.isDark()))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    Column({ space: 2 }) {
                      Text(`${track.playCount} 次`)
                        .fontSize(12)
                        .fontColor(Theme.textPrimary(Theme.isDark()))
                      Text(StatsPage.formatDuration(track.listenMs))
                        .fontSize(10)
                        .fontColor(Theme.textSecondary(Theme.isDark()))
                    }
                    .alignItems(HorizontalAlign.End)
                  }
                  .width('100%')
                  .padding(8)
                  .onClick(() => this.playTrack(track))
                }
              }, (track: AggregatedTrackStat) => `${track.key}_${track.playCount}_${track.listenMs}`)
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .width('100%')
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10 })
        .layoutWeight(1)
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
