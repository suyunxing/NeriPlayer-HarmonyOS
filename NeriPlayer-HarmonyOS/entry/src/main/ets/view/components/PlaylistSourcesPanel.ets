// SPDX-License-Identifier: GPL-3.0

import { Playlist } from '../../model/Playlist';
import { MusicPlatform } from '../../model/MusicPlatform';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { PlaylistSyncSource, sourceKeyOf, SOURCE_SYNC_MODE_APPEND } from '../../sourcesync/SourceSyncModels';
import { SourceSyncCoordinator } from '../../sourcesync/SourceSyncCoordinator';
import { Theme } from '../Theme';

/** Shared source management: view state only, every operation is source-key scoped. */
@Component
export struct PlaylistSourcesPanel {
  @Prop @Watch('onPlaylistJsonChanged') playlistJson: string = '';
  @Prop globalBusy: boolean = false;
  @State sourceRows: PlaylistSyncSource[] = [];
  @State playlistName: string = '';
  @State busySourceKey: string = '';
  private internalPlaylistId: string = '';
  onChanged: () => void = (): void => {};

  aboutToAppear(): void {
    this.onPlaylistJsonChanged();
  }

  onPlaylistJsonChanged(): void {
    if (this.playlistJson.length === 0) {
      this.sourceRows = [];
      return;
    }
    const playlist = Playlist.fromJson(this.playlistJson);
    this.internalPlaylistId = playlist.id;
    this.playlistName = playlist.name;
    this.sourceRows = playlist.getSyncSources();
  }

  private sourceSubtitle(source: PlaylistSyncSource): string {
    const platform = source.platform === MusicPlatform.BILIBILI ? 'B站收藏夹' : '网易云歌单';
    const mode = source.mode === SOURCE_SYNC_MODE_APPEND ? '仅追加' : '跟随远端';
    const timestamp = source.lastSyncAt > 0 ? source.lastSyncAt : source.lastCheckedAt;
    let state = '尚未同步';
    if (timestamp > 0) {
      const date = new Date(timestamp);
      const pad = (part: number): string => part < 10 ? '0' + part : String(part);
      state = (source.lastSyncAt > 0 ? '最近同步 ' : '上次检查 ') + (date.getMonth() + 1) + '-' +
        date.getDate() + ' ' + pad(date.getHours()) + ':' + pad(date.getMinutes());
    }
    return platform + ' · ' + mode + ' · ' + state;
  }

  private async refreshSources(): Promise<void> {
    const playlists = await LocalPlaylistRepository.loadAll();
    const playlist = playlists.find((item: Playlist): boolean => item.id === this.internalPlaylistId);
    this.sourceRows = playlist?.getSyncSources() ?? [];
    this.onChanged();
  }

  private async runSourceAction(source: PlaylistSyncSource, action: string, nextEnabled: boolean = false): Promise<void> {
    if (this.busySourceKey.length > 0 || this.globalBusy) {
      return;
    }
    if (action === 'sync' && SourceSyncCoordinator.isRunning()) {
      this.getUIContext().getPromptAction().openToast({ message: $r('app.string.playlist_source_sync_busy') });
      return;
    }
    const sourceKey = sourceKeyOf(source);
    this.busySourceKey = sourceKey;
    try {
      let changed = true;
      if (action === 'sync') {
        await SourceSyncCoordinator.runNow(this.internalPlaylistId, sourceKey);
      } else if (action === 'enabled') {
        changed = await LocalPlaylistRepository.setMirrorEnabled(this.internalPlaylistId, nextEnabled, sourceKey);
      } else if (action === 'reset') {
        changed = await LocalPlaylistRepository.resetMirrorSkips(this.internalPlaylistId, sourceKey);
      } else if (action === 'unbind') {
        changed = await LocalPlaylistRepository.unbindMirrorSource(this.internalPlaylistId, sourceKey);
      }
      if (!changed) {
        throw new Error('歌单或来源已变更，请刷新后重试');
      }
      await this.refreshSources();
      this.getUIContext().getPromptAction().openToast({
        message: action === 'sync' ? $r('app.string.playlist_source_sync_done') :
          $r('app.string.playlist_source_updated')
      });
    } catch (error) {
      this.getUIContext().getPromptAction().openToast({
        message: $r('app.string.playlist_source_failed', (error as Error).message)
      });
      try {
        await this.refreshSources();
      } catch (refreshError) {
        this.getUIContext().getPromptAction().openToast({
          message: $r('app.string.playlist_source_failed', (refreshError as Error).message)
        });
      }
    } finally {
      this.busySourceKey = '';
    }
  }

  private confirmReset(source: PlaylistSyncSource): void {
    if (this.busySourceKey.length > 0 || this.globalBusy) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.playlist_source_reset'),
      message: $r('app.string.playlist_source_reset_hint', source.remoteName || source.remoteId),
      primaryButton: { value: $r('app.string.playlist_cancel'), action: (): void => {} },
      secondaryButton: {
        value: $r('app.string.playlist_source_reset'),
        action: (): void => { void this.runSourceAction(source, 'reset'); }
      }
    });
  }

  private confirmUnbind(source: PlaylistSyncSource): void {
    if (this.busySourceKey.length > 0 || this.globalBusy) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.playlist_source_unbind'),
      message: $r('app.string.playlist_source_unbind_hint', source.remoteName || source.remoteId),
      primaryButton: { value: $r('app.string.playlist_cancel'), action: (): void => {} },
      secondaryButton: {
        value: $r('app.string.playlist_source_unbind'),
        action: (): void => { void this.runSourceAction(source, 'unbind'); }
      }
    });
  }

  build() {
    Column({ space: 10 }) {
      Text(this.playlistName)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.textPrimary(Theme.isDark()))
        .width('100%')
      ForEach(this.sourceRows, (source: PlaylistSyncSource) => {
        Column({ space: 8 }) {
          Text(source.remoteName.length > 0 ? source.remoteName : source.remoteId)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .width('100%')
          Text(this.sourceSubtitle(source))
            .fontSize(12)
            .fontColor(Theme.textSecondary(Theme.isDark()))
            .width('100%')
          Text($r('app.string.playlist_source_skip_count', source.skipKeys.length))
            .fontSize(12)
            .fontColor(Theme.textSecondary(Theme.isDark()))
          Row({ space: 10 }) {
            Text(source.enabled ? $r('app.string.playlist_source_enabled') : $r('app.string.playlist_source_paused'))
              .fontSize(13)
              .fontColor(Theme.textSecondary(Theme.isDark()))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: source.enabled })
              .selectedColor(Theme.primary(Theme.isDark()))
              .enabled(this.busySourceKey.length === 0 && !this.globalBusy)
              .accessibilityText(source.remoteName)
              .onChange((isOn: boolean): void => {
                if (isOn === source.enabled) {
                  return;
                }
                void this.runSourceAction(source, 'enabled', isOn);
              })
          }
          .width('100%')
          .constraintSize({ minHeight: 48 })
          Flex({ wrap: FlexWrap.Wrap }) {
            Button(this.busySourceKey === sourceKeyOf(source) ?
              $r('app.string.playlist_source_working') : $r('app.string.playlist_source_sync'))
              .constraintSize({ minHeight: 40 })
              .fontSize(12)
              .margin({ right: 8, bottom: 6 })
              .enabled(this.busySourceKey.length === 0 && !this.globalBusy)
              .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
              .fontColor(Theme.textPrimary(Theme.isDark()))
              .onClick((): void => { void this.runSourceAction(source, 'sync'); })
            Button($r('app.string.playlist_source_reset'))
              .constraintSize({ minHeight: 40 })
              .fontSize(12)
              .margin({ right: 8, bottom: 6 })
              .enabled(this.busySourceKey.length === 0 && !this.globalBusy)
              .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
              .fontColor(Theme.textPrimary(Theme.isDark()))
              .onClick((): void => { this.confirmReset(source); })
            Button($r('app.string.playlist_source_unbind'))
              .constraintSize({ minHeight: 40 })
              .fontSize(12)
              .margin({ bottom: 6 })
              .enabled(this.busySourceKey.length === 0 && !this.globalBusy)
              .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
              .fontColor(Theme.danger(Theme.isDark()))
              .onClick((): void => { this.confirmUnbind(source); })
          }
          .width('100%')
        }
        .width('100%')
        .padding(12)
        .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
        .borderRadius(12)
      }, (source: PlaylistSyncSource): string =>
        sourceKeyOf(source) + '_' + source.enabled + '_' + source.lastSyncAt + '_' + source.lastCheckedAt + '_' + source.skipKeys.length)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Theme.surface(Theme.isDark()))
    .borderRadius(Theme.cardRadius())
  }
}
