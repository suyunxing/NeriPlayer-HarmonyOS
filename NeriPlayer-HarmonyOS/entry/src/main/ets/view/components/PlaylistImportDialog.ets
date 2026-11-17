// SPDX-License-Identifier: GPL-3.0

import { Playlist } from '../../model/Playlist';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { Theme } from '../Theme';
import { OptionEntry, OptionRow } from './Ui';

/** Shared in-page modal shell; only the separate scrim dismisses the dialog. */
@Component
export struct PlaylistDialogFrame {
  @Prop operationBusy: boolean = false;
  @BuilderParam content: () => void;
  onCancel: () => void = (): void => {};

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.scrim(Theme.isDark()))
        .onClick((): void => {
          if (!this.operationBusy) {
            this.onCancel();
          }
        })
      Scroll() {
        Column({ space: 12 }) {
          this.content()
        }
        .width('100%')
        .padding(20)
        .alignItems(HorizontalAlign.Start)
      }
      .width('90%')
      .constraintSize({ maxWidth: 560, maxHeight: '80%' })
      .scrollBar(BarState.Auto)
      .backgroundColor(Theme.surface(Theme.isDark()))
      .borderRadius(18)
    }
    .width('100%')
    .height('100%')
  }
}

/** Shared target picker for one-shot imports and optional append-only binding. */
@Component
export struct PlaylistImportDialog {
  @Prop suggestedName: string = '';
  @Prop itemCount: number = 0;
  @Prop importing: boolean = false;
  @State draftName: string = '';
  @State selectedTargetId: string = '';
  @State bindContinuous: boolean = false;
  @State targetOptions: OptionEntry[] = [];
  @State targetLoading: boolean = true;
  @State targetError: string = '';
  onCancel: () => void = (): void => {};
  onConfirm: (targetId: string, name: string, bind: boolean) => void =
    (_targetId: string, _name: string, _bind: boolean): void => {};

  aboutToAppear(): void {
    this.draftName = this.suggestedName;
    void this.reloadTargets();
  }

  private async reloadTargets(): Promise<void> {
    this.targetLoading = true;
    this.targetError = '';
    try {
      const playlists = await LocalPlaylistRepository.loadAll();
      const options: OptionEntry[] = [{ value: '', label: '新建本地歌单' }];
      for (const playlist of playlists) {
        if (playlist.id === LocalPlaylistRepository.FAVORITES_ID ||
          playlist.id === LocalPlaylistRepository.LOCAL_MUSIC_ID) {
          continue;
        }
        options.push({ value: playlist.id, label: playlist.name });
      }
      this.targetOptions = options;
      if (!options.some((option: OptionEntry): boolean => option.value === this.selectedTargetId)) {
        this.selectedTargetId = '';
      }
    } catch (error) {
      this.targetError = (error as Error).message;
    } finally {
      this.targetLoading = false;
    }
  }

  @Builder
  importContent() {
    Text($r('app.string.playlist_import_title'))
      .fontSize(17)
      .fontWeight(FontWeight.Bold)
      .fontColor(Theme.textPrimary(Theme.isDark()))
    Text($r('app.string.playlist_import_description', this.itemCount))
      .fontSize(12)
      .fontColor(Theme.textSecondary(Theme.isDark()))
      .width('100%')
    if (this.targetLoading) {
      Text($r('app.string.playlist_targets_loading'))
        .fontSize(13)
        .fontColor(Theme.textSecondary(Theme.isDark()))
    } else if (this.targetError.length > 0) {
      Text(this.targetError)
        .fontSize(13)
        .fontColor(Theme.danger(Theme.isDark()))
      Button($r('app.string.playlist_retry'))
        .constraintSize({ minHeight: 40 })
        .enabled(!this.importing)
        .onClick((): void => { void this.reloadTargets(); })
    } else {
      OptionRow({
        title: '导入目标',
        subtitle: '已绑定来源的歌单也可继续选择',
        options: this.targetOptions,
        current: this.selectedTargetId,
        onPick: (targetId: string): void => { this.selectedTargetId = targetId; }
      })
      .enabled(!this.importing)
    }
    if (this.selectedTargetId.length === 0) {
      TextInput({ placeholder: $r('app.string.playlist_name_placeholder'), text: this.draftName })
        .enabled(!this.importing)
        .onChange((name: string): void => {
          if (name === this.draftName) {
            return;
          }
          this.draftName = name;
        })
    }
    Row({ space: 10 }) {
      Text($r('app.string.playlist_import_bind'))
        .fontSize(14)
        .fontColor(Theme.textPrimary(Theme.isDark()))
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.bindContinuous })
        .selectedColor(Theme.primary(Theme.isDark()))
        .enabled(!this.importing)
        .accessibilityText($r('app.string.playlist_import_bind'))
        .onChange((isOn: boolean): void => { this.bindContinuous = isOn; })
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
    Text($r('app.string.playlist_import_bind_hint'))
      .fontSize(12)
      .fontColor(Theme.textSecondary(Theme.isDark()))
      .width('100%')
    Row({ space: 12 }) {
      Button($r('app.string.playlist_cancel'))
        .layoutWeight(1)
        .constraintSize({ minHeight: 48 })
        .enabled(!this.importing)
        .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
        .fontColor(Theme.textPrimary(Theme.isDark()))
        .onClick((): void => { this.onCancel(); })
      Button(this.importing ? $r('app.string.playlist_import_busy') : $r('app.string.playlist_import_action'))
        .layoutWeight(1)
        .constraintSize({ minHeight: 48 })
        .enabled(!this.importing && !this.targetLoading && this.targetError.length === 0)
        .backgroundColor(Theme.primary(Theme.isDark()))
        .fontColor(Theme.onPrimary(Theme.isDark()))
        .onClick((): void => {
          this.onConfirm(this.selectedTargetId, this.draftName, this.bindContinuous);
        })
    }
    .width('100%')
  }

  build() {
    PlaylistDialogFrame({
      operationBusy: this.importing,
      onCancel: (): void => { this.onCancel(); }
    }) {
      this.importContent()
    }
  }
}
