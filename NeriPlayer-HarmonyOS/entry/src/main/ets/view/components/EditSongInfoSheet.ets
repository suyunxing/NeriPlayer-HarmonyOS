// SPDX-License-Identifier: GPL-3.0

import { SongItem } from '../../model/SongItem';
import { MusicPlatform } from '../../model/MusicPlatform';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { PlayerManager } from '../../player/PlayerManager';
import { Theme } from '../Theme';
import { BottomSheetPanel } from './BottomSheetPanel';

/**
 * 「编辑歌曲信息」面板：写入 SongItem.custom* 字段（空串 = 沿用原始值），
 * 全 UI 已通过 display* getter 消费；持久化到所有包含该曲的歌单并刷新
 * 播放队列/AVSession，使播放页立即生效。
 */
@Component
export struct EditSongInfoSheet {
  songJson: string = '';
  onClose: () => void = () => {};
  @State name: string = '';
  @State artist: string = '';
  @State coverUrl: string = '';
  @State saving: boolean = false;

  private song(): SongItem {
    return this.songJson.length > 0 ? SongItem.fromJson(this.songJson) : new SongItem();
  }

  aboutToAppear(): void {
    const song = this.song();
    this.name = song.displayName;
    this.artist = song.displayArtist;
    this.coverUrl = song.customCoverUrl;
  }

  private resetToOriginal(): void {
    const song = this.song();
    this.name = song.name;
    this.artist = song.artist;
    this.coverUrl = '';
  }

  private async save(): Promise<void> {
    if (this.saving) {
      return;
    }
    this.saving = true;
    const base = this.song();
    const updated = SongItem.fromJson(base.toJson());
    // Empty custom* falls back to the original value; saving an unchanged
    // field therefore clears the override instead of duplicating it.
    const name = this.name.trim();
    const artist = this.artist.trim();
    const coverUrl = this.coverUrl.trim();
    updated.customName = name !== base.name ? name : '';
    updated.customArtist = artist !== base.artist ? artist : '';
    // Cover gate (upstream #368): a hand-typed cover only applies to local
    // songs. Remote songs keep whatever the match flow wrote — hand edits on
    // them would leak into sync payloads as dead local references.
    if (base.platform === MusicPlatform.LOCAL) {
      updated.customCoverUrl = coverUrl.length > 0 && coverUrl !== base.coverUrl ? coverUrl : '';
    } else {
      updated.customCoverUrl = base.customCoverUrl;
    }
    const replaced = await LocalPlaylistRepository.updateSongMetadata(updated);
    PlayerManager.applySongMetadataUpdate(updated);
    this.getUIContext().getPromptAction().showToast({
      message: replaced > 0 ? '已保存' : '已保存（仅当前播放，歌曲不在歌单中）',
      duration: 2000
    });
    this.saving = false;
    this.onClose();
  }

  /** Hand-typed covers only apply to local songs (see save). */
  private coverEditable(): boolean {
    return this.song().platform === MusicPlatform.LOCAL;
  }

  @Builder
  fieldLabel(text: string) {
    Text(text)
      .fontSize(13)
      .fontColor(Theme.textSecondary(Theme.isDark()))
      .width('100%')
      .padding({ top: 8, bottom: 4 })
  }

  build() {
    BottomSheetPanel({
      title: '编辑歌曲信息',
      onClose: () => this.onClose()
    }) {
      Column() {
        this.fieldLabel('标题')
        TextInput({ text: this.name, placeholder: this.song().name })
          .fontSize(14)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .placeholderColor(Theme.textDisabled(Theme.isDark()))
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          .borderRadius(10)
          .height(44)
          .width('100%')
          .maxLength(120)
          .onChange((value: string) => {
            this.name = value;
          })
        this.fieldLabel('歌手')
        TextInput({ text: this.artist, placeholder: this.song().artist })
          .fontSize(14)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .placeholderColor(Theme.textDisabled(Theme.isDark()))
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          .borderRadius(10)
          .height(44)
          .width('100%')
          .maxLength(120)
          .onChange((value: string) => {
            this.artist = value;
          })
        if (this.coverEditable()) {
          this.fieldLabel('封面地址（可选）')
          TextInput({ text: this.coverUrl, placeholder: 'https://…' })
            .fontSize(14)
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .placeholderColor(Theme.textDisabled(Theme.isDark()))
            .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
            .borderRadius(10)
            .height(44)
            .width('100%')
            .maxLength(500)
            .onChange((value: string) => {
              this.coverUrl = value;
            })
        } else {
          Text('在线歌曲的封面由平台提供，可通过「匹配歌曲信息」更换。')
            .fontSize(11)
            .fontColor(Theme.textSecondary(Theme.isDark()))
            .width('100%')
            .padding({ top: 8 })
        }
        Text('修改保存在本机歌单与当前播放，清空字段即恢复原始值。')
          .fontSize(11)
          .fontColor(Theme.textSecondary(Theme.isDark()))
          .width('100%')
          .padding({ top: 8, bottom: 4 })
        Row({ space: 10 }) {
          Button('恢复默认')
            .height(40)
            .layoutWeight(1)
            .fontSize(14)
            .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .onClick(() => this.resetToOriginal())
          Button(this.saving ? '保存中…' : '保存')
            .height(40)
            .layoutWeight(1)
            .fontSize(14)
            .backgroundColor(Theme.primary(Theme.isDark()))
            .fontColor(Theme.onPrimary(Theme.isDark()))
            .enabled(!this.saving)
            .onClick(() => {
              this.save();
            })
        }
        .width('100%')
        .padding({ top: 6 })
      }
      .width('100%')
    }
  }
}
