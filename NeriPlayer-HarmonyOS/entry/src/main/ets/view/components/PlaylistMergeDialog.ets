// SPDX-License-Identifier: GPL-3.0

import { Playlist } from '../../model/Playlist';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { Theme } from '../Theme';
import { PlaylistDialogFrame } from './PlaylistImportDialog';

/** Multi-selects existing internal playlists; repository owns dedupe and merging. */
@Component
export struct PlaylistMergeDialog {
  @Prop targetId: string = '';
  @Prop targetName: string = '';
  @State candidates: Playlist[] = [];
  @State selectedIds: string[] = [];
  @State candidateLoading: boolean = true;
  @State candidateError: string = '';
  @State merging: boolean = false;
  onCancel: () => void = (): void => {};
  onMerged: () => void = (): void => {};

  aboutToAppear(): void {
    void this.reloadCandidates();
  }

  private async reloadCandidates(): Promise<void> {
    this.candidateLoading = true;
    this.candidateError = '';
    try {
      const playlists = await LocalPlaylistRepository.loadAll();
      this.candidates = playlists.filter((playlist: Playlist): boolean =>
        playlist.id !== this.targetId && playlist.id !== LocalPlaylistRepository.FAVORITES_ID &&
        playlist.id !== LocalPlaylistRepository.LOCAL_MUSIC_ID);
      this.selectedIds = [];
    } catch (error) {
      this.candidateError = (error as Error).message;
    } finally {
      this.candidateLoading = false;
    }
  }

  private selectCandidate(playlistId: string, selected: boolean): void {
    if (this.merging) {
      return;
    }
    const next = this.selectedIds.filter((id: string): boolean => id !== playlistId);
    if (selected) {
      next.push(playlistId);
    }
    this.selectedIds = next;
  }

  private async confirmMerge(): Promise<void> {
    if (this.merging || this.selectedIds.length === 0) {
      return;
    }
    this.merging = true;
    try {
      const selected = this.selectedIds.slice();
      const playlists = await LocalPlaylistRepository.loadAll();
      if (!playlists.some((playlist: Playlist): boolean => playlist.id === this.targetId) ||
        selected.some((id: string): boolean => !playlists.some((playlist: Playlist): boolean => playlist.id === id))) {
        throw new Error('所选歌单已变更，请关闭并重新选择');
      }
      const count = await LocalPlaylistRepository.mergePlaylists(this.targetId, selected);
      const latest = await LocalPlaylistRepository.loadAll();
      if (!latest.some((playlist: Playlist): boolean => playlist.id === this.targetId)) {
        throw new Error('目标歌单已移除，请刷新后重新选择');
      }
      this.getUIContext().getPromptAction().openToast({
        message: $r('app.string.playlist_merge_done', count)
      });
      this.onMerged();
    } catch (error) {
      this.getUIContext().getPromptAction().openToast({
        message: $r('app.string.playlist_merge_failed', (error as Error).message)
      });
    } finally {
      this.merging = false;
    }
  }

  @Builder
  mergeContent() {
    Text($r('app.string.playlist_merge_title'))
      .fontSize(17)
      .fontWeight(FontWeight.Bold)
      .fontColor(Theme.textPrimary(Theme.isDark()))
    Text($r('app.string.playlist_merge_description', this.targetName))
      .fontSize(12)
      .fontColor(Theme.textSecondary(Theme.isDark()))
      .width('100%')
    if (this.candidateLoading) {
      Text($r('app.string.playlist_targets_loading'))
        .fontSize(13)
        .fontColor(Theme.textSecondary(Theme.isDark()))
    } else if (this.candidateError.length > 0) {
      Text(this.candidateError)
        .fontSize(13)
        .fontColor(Theme.danger(Theme.isDark()))
      Button($r('app.string.playlist_retry'))
        .constraintSize({ minHeight: 40 })
        .onClick((): void => { void this.reloadCandidates(); })
    } else if (this.candidates.length === 0) {
      Text($r('app.string.playlist_merge_empty'))
        .fontSize(13)
        .fontColor(Theme.textSecondary(Theme.isDark()))
        .width('100%')
    } else {
      List({ space: 4 }) {
        ForEach(this.candidates, (candidate: Playlist) => {
          ListItem() {
            Row({ space: 10 }) {
              Checkbox({ name: candidate.id, group: 'playlistMerge' })
                .select(this.selectedIds.includes(candidate.id))
                .selectedColor(Theme.primary(Theme.isDark()))
                .enabled(!this.merging)
                .accessibilityText(candidate.name)
                .onChange((selected: boolean): void => { this.selectCandidate(candidate.id, selected); })
              Column({ space: 3 }) {
                Text(candidate.name)
                  .fontSize(15)
                  .fontColor(Theme.textPrimary(Theme.isDark()))
                  .width('100%')
                Text($r('app.string.playlist_merge_candidate', candidate.songKeys.length,
                  candidate.getSyncSources().length))
                  .fontSize(12)
                  .fontColor(Theme.textSecondary(Theme.isDark()))
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .constraintSize({ minHeight: 56 })
            .padding(8)
          }
        }, (candidate: Playlist): string => candidate.id)
      }
      .width('100%')
      .height(220)
      .scrollBar(BarState.Auto)
    }
    Row({ space: 12 }) {
      Button($r('app.string.playlist_cancel'))
        .layoutWeight(1)
        .constraintSize({ minHeight: 48 })
        .enabled(!this.merging)
        .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
        .fontColor(Theme.textPrimary(Theme.isDark()))
        .onClick((): void => { this.onCancel(); })
      Button(this.merging ? $r('app.string.playlist_merge_busy') :
        $r('app.string.playlist_merge_confirm', this.selectedIds.length))
        .layoutWeight(1)
        .constraintSize({ minHeight: 48 })
        .enabled(!this.merging && this.selectedIds.length > 0 && !this.candidateLoading)
        .backgroundColor(Theme.primary(Theme.isDark()))
        .fontColor(Theme.onPrimary(Theme.isDark()))
        .onClick((): void => { void this.confirmMerge(); })
    }
    .width('100%')
  }

  build() {
    PlaylistDialogFrame({
      operationBusy: this.merging,
      onCancel: (): void => { this.onCancel(); }
    }) {
      this.mergeContent()
    }
  }
}
