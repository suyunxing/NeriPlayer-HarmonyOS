import { SongItem } from '../../model/SongItem';
import { LyricLine } from '../../model/LyricLine';
import { QueueState } from '../../model/QueueState';
import { MusicPlatform } from '../../model/MusicPlatform';
import { LyricApi } from '../../network/LyricApi';
import { LyricPayload } from '../../network/NeteaseApi';
import { LrcParser } from '../../lyrics/LrcParser';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { SettingsRepository } from '../../data/SettingsRepository';
import { PlayerManager } from '../../player/PlayerManager';
import { PlaybackStatus, RepeatMode } from '../../player/PlaybackConstants';
import { CoverColorExtractor } from '../../util/CoverColorExtractor';
import { Theme } from '../Theme';
import { LyricView } from '../components/LyricView';
import { Router } from '../Router';
import { formatDuration, platformName } from '../components/Ui';

const SPEED_STEPS: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
const SLEEP_OPTIONS: [string, number][] = [
  ['关闭', 0],
  ['10 分钟', 10],
  ['30 分钟', 30],
  ['1 小时', 60],
  ['播完当前', -1],
  ['播完列表', -2]
];

@Component
export struct NowPlayingPage {
  @StorageLink('player.currentSong') currentSongJson: string = '';
  @StorageLink('player.status') status: number = PlaybackStatus.IDLE;
  @StorageLink('player.positionMs') positionMs: number = 0;
  @StorageLink('player.durationMs') durationMs: number = 0;
  @StorageLink('player.shuffle') shuffle: boolean = false;
  @StorageLink('player.repeatMode') repeatMode: number = RepeatMode.ALL;
  @StorageLink('player.speed') speed: number = 1.0;
  @StorageLink('player.queueJson') queueJson: string = '';

  @State lyrics: LyricLine[] = [];
  @State showLyrics: boolean = true;
  @State favorite: boolean = false;
  @State showQueue: boolean = false;
  @State showSleep: boolean = false;
  @State sleepLabel: string = '关闭';
  @State sliderPosition: number = 0;
  @State sliding: boolean = false;
  @State accentColor: string = '';

  private song(): SongItem {
    return this.currentSongJson.length > 0 ? SongItem.fromJson(this.currentSongJson) : new SongItem();
  }

  private queue(): QueueState {
    return this.queueJson.length > 0 ? QueueState.fromJson(this.queueJson) : new QueueState();
  }

  async aboutToAppear(): Promise<void> {
    await this.reloadSongData();
  }

  private async reloadSongData(): Promise<void> {
    const song = this.song();
    this.favorite = await LocalPlaylistRepository.isFavorite(song);
    this.lyrics = [];
    if (song.audioId.length > 0) {
      try {
        let payload: LyricPayload;
        if (song.platform === MusicPlatform.NETEASE) {
          payload = await LyricApi.fetchFromNetease(Number(song.audioId));
        } else {
          payload = await LyricApi.fetchFromLrcLib(song.displayName, song.displayArtist, song.durationMs);
        }
        let parsed = LrcParser.parse(payload.lyric);
        parsed = LrcParser.mergeTranslation(parsed, payload.translated);
        this.lyrics = parsed;
      } catch (error) {
        const e = error as Error;
        this.lyrics = [];
        console.warn(`lyrics load failed: ${e.message}`);
      }
    }
    this.accentColor = '';
    if (SettingsRepository.getBoolean(SettingsRepository.KEY_DYNAMIC_COLOR, true) && song.effectiveCoverUrl.length > 0) {
      this.accentColor = await CoverColorExtractor.extractAccent(song.effectiveCoverUrl);
    }
  }

  private async toggleFavorite(): Promise<void> {
    const song = this.song();
    if (this.favorite) {
      await LocalPlaylistRepository.removeFavorite(song);
      this.favorite = false;
    } else {
      await LocalPlaylistRepository.addFavorite(song);
      this.favorite = true;
    }
  }

  private cycleSpeed(): void {
    let nextIndex = SPEED_STEPS.indexOf(this.speed) + 1;
    if (nextIndex >= SPEED_STEPS.length) {
      nextIndex = 0;
    }
    const next = SPEED_STEPS[nextIndex];
    PlayerManager.setSpeed(next);
  }

  private cycleRepeat(): void {
    const next = (this.repeatMode + 1) % 3;
    PlayerManager.setRepeatMode(next as RepeatMode);
  }

  private setSleep(option: [string, number]): void {
    this.sleepLabel = option[0];
    this.showSleep = false;
    if (option[1] > 0) {
      setTimeout(() => {
        if (this.status === PlaybackStatus.PLAYING) {
          PlayerManager.pause();
          this.sleepLabel = '关闭';
        }
      }, option[1] * 60000);
    }
  }

  build() {
    Stack() {
      // Blurred cover backdrop
      if (this.song().effectiveCoverUrl.length > 0) {
        Image(this.song().effectiveCoverUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(60)
          .scale({ x: 1.4, y: 1.4 })
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
      }
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.scrim(Theme.isDark()))

      Column() {
        Row() {
          Button() {
            Image($r('app.media.ic_arrow_back_24'))
              .width(22)
              .height(22)
              .fillColor('#FFFFFF')
          }
          .width(40)
          .height(40)
          .type(ButtonType.Circle)
          .backgroundColor(Theme.onSurfaceOverlay(Theme.isDark()))
          .onClick(() => Router.pop())
          Text('正在播放')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Button('⋯')
            .width(40)
            .height(40)
            .type(ButtonType.Circle)
            .backgroundColor(Theme.onSurfaceOverlay(Theme.isDark()))
            .fontColor('#FFFFFF')
            .fontSize(18)
            .onClick(() => this.showQueue = true)
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 8 })

        if (this.showLyrics && this.lyrics.length > 0) {
          LyricView({
            lyrics: this.lyrics,
              accentColor: this.accentColor,
            onSeek: (timeMs: number) => PlayerManager.seekTo(timeMs)
          })
        } else {
          Column() {
            Stack() {
              if (this.song().effectiveCoverUrl.length > 0) {
                Image(this.song().effectiveCoverUrl)
                  .width('78%')
                  .aspectRatio(1)
                  .borderRadius(22)
                  .objectFit(ImageFit.Cover)
                  .shadow({ radius: 24, color: '#66000000', offsetY: 8 })
              } else {
                  /*
                Text('♫')
                  .fontSize(96)
                  .fontColor(Theme.primary(Theme.isDark()))
                  .width('78%')
                  .aspectRatio(1)
                  .textAlign(TextAlign.Center)
                  */
                  Image($r('app.media.ic_music_note_24'))
                    .width('78%')
                    .aspectRatio(1)
                    .objectFit(ImageFit.Contain)
                    .padding({ left: 32, right: 32, top: 32, bottom: 32 })
                    .fillColor(Theme.primary(Theme.isDark()))
                  .backgroundColor(Theme.onSurfaceOverlay(Theme.isDark()))
                  .borderRadius(22)
              }
            }
            .width('100%')
            .layoutWeight(1)

            Column({ space: 8 }) {
              Row({ space: 8 }) {
                Text(this.song().displayName)
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FFFFFF')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Image(this.favorite
                  ? $r('app.media.ic_baseline_favorite_24')
                  : $r('app.media.ic_outline_favorite_24'))
                  .width(24)
                  .height(24)
                  .fillColor(this.favorite ? Theme.danger(false) : '#CCFFFFFF')
                  .padding(6)
                  .onClick(() => this.toggleFavorite())
              }
              .width('100%')

              Row({ space: 8 }) {
                Text(this.song().displayArtist)
                  .fontSize(14)
                  .fontColor('#B8FFFFFF')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(platformName(this.song().platform))
                  .fontSize(10)
                  .fontColor('#FFFFFF')
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .backgroundColor('#33FFFFFF')
                  .borderRadius(8)
              }
              .width('100%')
            }
            .width('100%')
            .padding({ left: 24, right: 24 })
          }
          .layoutWeight(1)
          .width('100%')
        }

        Column() {
          Slider({
            value: this.sliding ? this.sliderPosition : this.positionMs,
            min: 0,
            max: Math.max(1, this.durationMs),
            step: 1000,
            style: SliderStyle.OutSet
          })
            .showTips(false)
              /*
            .blockColor('#FFFFFF')
            .selectedColor('#FFFFFF')
              */
              .blockColor(this.accentColor.length > 0 ? this.accentColor : '#FFFFFF')
              .selectedColor(this.accentColor.length > 0 ? this.accentColor : '#FFFFFF')
            .trackColor('#33FFFFFF')
            .onChange((value: number, mode: SliderChangeMode) => {
              this.sliderPosition = value;
              this.sliding = mode !== SliderChangeMode.End;
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                PlayerManager.seekTo(value);
              }
            })

          Row() {
            Text(formatDuration(this.sliding ? this.sliderPosition : this.positionMs))
              .fontSize(12)
              .fontColor('#B8FFFFFF')
            Blank()
            Text(formatDuration(this.durationMs))
              .fontSize(12)
              .fontColor('#B8FFFFFF')
          }
          .width('100%')

          Row() {
            PlayerControlButton({
              icon: $r('app.media.ic_shuffle_24'),
              active: this.shuffle,
              onTap: () => PlayerManager.setShuffle(!this.shuffle)
            })
            PlayerControlButton({
              icon: $r('app.media.round_skip_previous_24'),
              onTap: () => PlayerManager.previous()
            })
            PlayerControlButton({
              icon: this.status === PlaybackStatus.PLAYING
                ? $r('app.media.round_pause_24')
                : $r('app.media.round_play_arrow_24'),
              active: true,
              buttonSize: 64,
              onTap: () => PlayerManager.togglePlayPause()
            })
            PlayerControlButton({
              icon: $r('app.media.round_skip_next_24'),
              onTap: () => PlayerManager.next(false)
            })
            PlayerControlButton({
              icon: this.repeatMode === RepeatMode.ONE
                ? $r('app.media.ic_repeat_one_24')
                : $r('app.media.ic_repeat_24'),
              active: this.repeatMode !== RepeatMode.OFF,
              onTap: () => this.cycleRepeat()
            })
          }
          .width('100%')
          .padding({ top: 6 })
          .justifyContent(FlexAlign.SpaceEvenly)

          Row({ space: 8 }) {
            Button(`${this.speed}x`)
              .height(32)
              .fontSize(12)
              .fontColor('#FFFFFF')
              .backgroundColor('#33FFFFFF')
              .borderRadius(16)
              .onClick(() => this.cycleSpeed())
              /*
            Button('🌙 ' + (this.sleepLabel === '关闭' ? '定时' : this.sleepLabel))
              .height(32)
              .fontSize(12)
              .fontColor('#FFFFFF')
              .backgroundColor('#33FFFFFF')
              .borderRadius(16)
              .onClick(() => {
                this.showSleep = true;
              })
              */
              Button() {
                Row({ space: 6 }) {
                  Image($r('app.media.ic_bedtime_24'))
                    .width(14)
                    .height(14)
                    .fillColor('#FFFFFF')
                  Text(this.sleepLabel === '关闭' ? '定时' : this.sleepLabel)
                    .fontSize(12)
                    .fontColor('#FFFFFF')
                }
              }
              .height(32)
              .padding({ left: 12, right: 12 })
              .backgroundColor('#33FFFFFF')
              .borderRadius(16)
              .onClick(() => {
                this.showSleep = true;
              })
            Button('歌词')
              .height(32)
              .fontSize(12)
              .fontColor(this.showLyrics ? '#1A1A1A' : '#FFFFFF')
              .backgroundColor(this.showLyrics ? '#FFFFFF' : '#33FFFFFF')
              .borderRadius(16)
              .onClick(() => {
                this.showLyrics = !this.showLyrics;
              })
              /*
            Button('📃')
              .height(32)
              .fontSize(12)
              .fontColor('#FFFFFF')
              .backgroundColor('#33FFFFFF')
              .borderRadius(16)
              .onClick(() => {
                this.showQueue = true;
              })
              */
              Button() {
                Image($r('app.media.ic_queue_music_24'))
                  .width(18)
                  .height(18)
                  .fillColor('#FFFFFF')
              }
              .width(36)
              .height(32)
              .backgroundColor('#33FFFFFF')
              .borderRadius(16)
              .onClick(() => {
                this.showQueue = true;
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 12, bottom: 18 })
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
        .backgroundColor(Theme.scrim(Theme.isDark()))
      }
      .width('100%')
      .height('100%')

      if (this.showQueue) {
        QueueSheet({
          queueJson: this.queueJson,
            /*
          currentOrderIndex: PlayerManager.getOrderIndex(),
            */
            currentQueueIndex: PlayerManager.getCurrentQueueIndex(),
          onClose: () => {
            this.showQueue = false;
          },
            /*
          onPlay: (orderIndex: number) => {
            PlayerManager.playAt(orderIndex);
          }
            */
            onPlay: (queueIndex: number) => {
              PlayerManager.playQueueAt(queueIndex);
            }
        })
      }

      if (this.showSleep) {
        Column() {
          Column({ space: 4 }) {
            Text('睡眠定时')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.textPrimary(Theme.isDark()))
              .margin({ bottom: 8 })
            ForEach(SLEEP_OPTIONS, (option: [string, number]) => {
              Text(option[0])
                .fontSize(15)
                .fontColor(this.sleepLabel === option[0] ? Theme.primary(Theme.isDark()) : Theme.textPrimary(Theme.isDark()))
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding(10)
                .onClick(() => this.setSleep(option))
            }, (option: [string, number]) => `${option[0]}_${option[1]}`)
          }
          .width('80%')
          .padding(16)
          .backgroundColor(Theme.surface(Theme.isDark()))
          .borderRadius(18)
              /*
            .onClick((event: ClickEvent) => {
              event.stopPropagation();
            })
              */
              .onClick(() => {
              })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Theme.scrim(Theme.isDark()))
        .onClick(() => {
          this.showSleep = false;
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background(Theme.isDark()))
  }
}

@Component
struct PlayerControlButton {
  icon: Resource = $r('app.media.round_play_arrow_24');
  active: boolean = false;
  onTap: () => void = () => {};
  buttonSize: number = 48;

  build() {
    Button() {
      Image(this.icon)
        .width(this.buttonSize >= 60 ? 34 : 24)
        .height(this.buttonSize >= 60 ? 34 : 24)
        .fillColor(this.active ? '#FFFFFF' : '#B8FFFFFF')
    }
    .width(this.buttonSize)
    .height(this.buttonSize)
    .type(ButtonType.Circle)
      /*
    .backgroundColor(this.buttonSize >= 60 ? Theme.primary(false) : Color.Transparent)
      */
        /*
      .backgroundColor(this.buttonSize >= 60 ? Theme.primary(Theme.isDark()) : Color.Transparent)
        */
        .backgroundColor(this.buttonSize >= 60 ? Theme.primary(false) : Color.Transparent)
    .onClick(() => this.onTap())
  }
}

@Component
struct QueueSheet {
  queueJson: string = '';
  currentQueueIndex: number = -1;
  onClose: () => void = () => {};
  onPlay: (queueIndex: number) => void = () => {};

  private queue(): QueueState {
    return this.queueJson.length > 0 ? QueueState.fromJson(this.queueJson) : new QueueState();
  }

  build() {
    Column() {
      Column() {
        Row() {
          Text('播放列表')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .layoutWeight(1)
          Text('关闭')
            .fontSize(14)
            .fontColor(Theme.primary(Theme.isDark()))
            .onClick(() => this.onClose())
        }
        .width('100%')
        .padding({ bottom: 10 })

        List() {
          ForEach(this.queue().songs, (song: SongItem, index: number) => {
            ListItem() {
              Row({ space: 10 }) {
                Text(`${index + 1}`)
                  .fontSize(13)
                    /*
                  .fontColor(index === this.currentOrderIndex ? Theme.primary(Theme.isDark()) : Theme.textDisabled(Theme.isDark()))
                    */
                    .fontColor(index === this.currentQueueIndex ? Theme.primary(Theme.isDark()) : Theme.textDisabled(Theme.isDark()))
                  .width(24)
                Column({ space: 2 }) {
                  Text(song.displayName)
                    .fontSize(14)
                      /*
                    .fontColor(index === this.currentOrderIndex ? Theme.primary(Theme.isDark()) : Theme.textPrimary(Theme.isDark()))
                      */
                      .fontColor(index === this.currentQueueIndex ? Theme.primary(Theme.isDark()) : Theme.textPrimary(Theme.isDark()))
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
                Text(formatDuration(song.durationMs))
                  .fontSize(11)
                  .fontColor(Theme.textDisabled(Theme.isDark()))
              }
              .width('100%')
              .padding(8)
                /*
              .onClick(() => this.onPlay(index))
                */
                  /*
                .onClick((event: ClickEvent) => {
                  event.stopPropagation();
                  this.onPlay(index);
                })
                  */
                  .onClick(() => this.onPlay(index))
            }
          }, (song: SongItem) => `${song.platform}_${song.audioId}_${song.id}`)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .width('100%')
      }
      .width('100%')
      .height('62%')
      .padding(16)
      .backgroundColor(Theme.surface(Theme.isDark()))
      .borderRadius({ topLeft: 22, topRight: 22 })
          /*
        .onClick((event: ClickEvent) => {
          event.stopPropagation();
        })
          */
          .onClick(() => {
          })
      .position({ x: 0, y: '38%' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.scrim(Theme.isDark()))
    .onClick(() => this.onClose())
  }
}
