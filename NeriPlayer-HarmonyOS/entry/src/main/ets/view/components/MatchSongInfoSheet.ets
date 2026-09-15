// SPDX-License-Identifier: GPL-3.0

import { MatchCandidate, MatchSource, SongMatchApi, matchSourceTag } from '../../network/SongMatchApi';
import { SongItem } from '../../model/SongItem';
import { stableKeyOf } from '../../model/SongIdentity';
import { AutoSongMatcher } from '../../player/AutoSongMatcher';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { PlayerManager } from '../../player/PlayerManager';
import { Theme } from '../Theme';
import { BottomSheetPanel } from './BottomSheetPanel';
import { EmptyState, LoadingState, formatDuration } from './Ui';

/**
 *「匹配歌曲信息」面板：跨平台搜索同名歌曲，把选中结果（名称/歌手/封面经
 * custom* 覆盖、歌词与翻译写入 matched*）同步到当前歌曲，并立刻刷新播放
 * 队列与 AVSession。两个来源各自缓存上次关键字的结果，切回时不重复请求。
 */
@Component
export struct MatchSongInfoSheet {
  songJson: string = '';
  onClose: () => void = () => {};
  /** Called after a candidate was applied so the page can reload its lyrics. */
  onApplied: () => void = () => {};

  @State keyword: string = '';
  @State source: MatchSource = MatchSource.NETEASE;
  @State loading: boolean = false;
  @State errorText: string = '';
  @State neteaseResults: MatchCandidate[] = [];
  @State qqResults: MatchCandidate[] = [];
  @State neteaseKeyword: string = '';
  @State qqKeyword: string = '';
  @State selectedIndex: number = -1;
  @State applying: boolean = false;
  private searchSeq: number = 0;

  private song(): SongItem {
    return this.songJson.length > 0 ? SongItem.fromJson(this.songJson) : new SongItem();
  }

  aboutToAppear(): void {
    // The user took over matching for this song: the automatic matcher in
    // AutoSongMatcher stands down for it for the rest of the session.
    AutoSongMatcher.markManualQuery(this.song());
    this.keyword = this.song().displayName;
    if (this.keyword.length > 0) {
      void this.search();
    }
  }

  private currentResults(): MatchCandidate[] {
    return this.source === MatchSource.QQ ? this.qqResults : this.neteaseResults;
  }

  private hasSearched(): boolean {
    const cached = this.source === MatchSource.QQ ? this.qqKeyword : this.neteaseKeyword;
    return cached.length > 0;
  }

  private async search(): Promise<void> {
    const keyword = this.keyword.trim();
    if (keyword.length === 0 || this.loading || this.applying) {
      return;
    }
    this.searchSeq += 1;
    const seq = this.searchSeq;
    this.loading = true;
    this.errorText = '';
    this.selectedIndex = -1;
    const candidates = await SongMatchApi.searchCandidates(this.source, keyword);
    if (seq !== this.searchSeq) {
      return;
    }
    this.loading = false;
    if (candidates.length === 0) {
      // searchCandidates never throws; empty means error or no hit. The two
      // are indistinguishable here, so keep the neutral empty copy and log
      // happened inside SongMatchApi.
      if (this.source === MatchSource.QQ) {
        this.qqResults = [];
        this.qqKeyword = keyword;
      } else {
        this.neteaseResults = [];
        this.neteaseKeyword = keyword;
      }
      return;
    }
    if (this.source === MatchSource.QQ) {
      this.qqResults = candidates;
      this.qqKeyword = keyword;
    } else {
      this.neteaseResults = candidates;
      this.neteaseKeyword = keyword;
    }
  }

  private selectSource(source: MatchSource): void {
    if (this.source === source) {
      return;
    }
    this.source = source;
    this.selectedIndex = -1;
    // Reuse the cached tab when the keyword is unchanged (tab jitter guard).
    const cached = source === MatchSource.QQ ? this.qqKeyword : this.neteaseKeyword;
    if (cached !== this.keyword.trim() && !this.loading) {
      void this.search();
    }
  }

  private async apply(): Promise<void> {
    if (this.applying) {
      return;
    }
    const candidates = this.currentResults();
    const candidate = this.selectedIndex >= 0 && this.selectedIndex < candidates.length
      ? candidates[this.selectedIndex]
      : null;
    if (candidate === null) {
      return;
    }
    this.applying = true;
    const detail = await SongMatchApi.fetchDetail(candidate);
    if (detail === null) {
      this.getUIContext().getPromptAction().showToast({ message: '获取歌曲详情失败，请重试', duration: 2000 });
      this.applying = false;
      return;
    }
    const base = this.song();
    const updated = SongItem.fromJson(base.toJson());
    // Same convention as EditSongInfoSheet: custom* only when it actually
    // differs from the original, '' falls back to the original value.
    updated.customName = detail.name !== base.name ? detail.name : '';
    updated.customArtist = detail.artist !== base.artist ? detail.artist : '';
    updated.customCoverUrl = detail.coverUrl.length > 0 && detail.coverUrl !== base.coverUrl ? detail.coverUrl : '';
    updated.matchedSongId = `${matchSourceTag(detail.source)}:${detail.id}`;
    updated.matchedLyric = detail.lyric;
    updated.matchedTranslatedLyric = detail.translatedLyric;
    const replaced = await LocalPlaylistRepository.updateSongMetadata(updated);
    PlayerManager.applySongMetadataUpdate(updated);
    this.getUIContext().getPromptAction().showToast({
      message: replaced > 0 ? '已应用匹配结果' : '已应用（仅当前播放，歌曲不在歌单中）',
      duration: 2000
    });
    this.applying = false;
    this.onApplied();
    this.onClose();
  }

  @Builder
  segmentButton(label: string, source: MatchSource) {
    Button(label)
      .height(34)
      .layoutWeight(1)
      .fontSize(13)
      .backgroundColor(this.source === source
        ? Theme.primary(Theme.isDark())
        : Theme.surfaceVariant(Theme.isDark()))
      .fontColor(this.source === source
        ? Theme.onPrimary(Theme.isDark())
        : Theme.textSecondary(Theme.isDark()))
      .onClick(() => this.selectSource(source))
  }

  @Builder
  resultRow(candidate: MatchCandidate, index: number) {
    Row({ space: 10 }) {
      if (candidate.coverUrl.length > 0) {
        Image(candidate.coverUrl)
          .width(48)
          .height(48)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
          .border({
            width: index === this.selectedIndex ? 2 : 0,
            color: Theme.primary(Theme.isDark())
          })
          .alt($r('app.media.ic_music_note_24'))
      } else {
        Column() {
          Image($r('app.media.ic_music_note_24'))
            .width(24)
            .height(24)
            .fillColor(Theme.textDisabled(Theme.isDark()))
        }
        .width(48)
        .height(48)
        .borderRadius(8)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
        .border({
          width: index === this.selectedIndex ? 2 : 0,
          color: Theme.primary(Theme.isDark())
        })
      }
      Column({ space: 2 }) {
        Text(candidate.name)
          .fontSize(14)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(candidate.durationMs > 0
          ? `${candidate.artist} · ${formatDuration(candidate.durationMs)}`
          : candidate.artist)
          .fontSize(11)
          .fontColor(Theme.textSecondary(Theme.isDark()))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (index === this.selectedIndex) {
        Text('✓')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.primary(Theme.isDark()))
      }
    }
    .width('100%')
    .padding(8)
    .borderRadius(10)
    .backgroundColor(index === this.selectedIndex
      ? Theme.surfaceVariant(Theme.isDark())
      : Color.Transparent)
    .onClick(() => {
      this.selectedIndex = index;
    })
  }

  build() {
    BottomSheetPanel({
      title: '匹配歌曲信息',
      onClose: () => this.onClose()
    }) {
      Column() {
        Row({ space: 8 }) {
          TextInput({ text: this.keyword, placeholder: '歌名 / 歌手' })
            .fontSize(14)
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .placeholderColor(Theme.textDisabled(Theme.isDark()))
            .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
            .borderRadius(10)
            .height(40)
            .layoutWeight(1)
            .maxLength(120)
            .onChange((value: string) => {
              this.keyword = value;
            })
            .onSubmit((_enterKey: EnterKeyType) => {
              void this.search();
            })
          Button() {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(20)
              .fontColor([Theme.onPrimary(Theme.isDark())])
          }
          .width(40)
          .height(40)
          .borderRadius(10)
          .backgroundColor(Theme.primary(Theme.isDark()))
          .accessibilityText('搜索')
          .enabled(!this.loading)
          .onClick(() => {
            void this.search();
          })
        }
        .width('100%')

        Row({ space: 8 }) {
          this.segmentButton('网易云', MatchSource.NETEASE)
          this.segmentButton('QQ音乐', MatchSource.QQ)
        }
        .width('100%')
        .padding({ top: 10 })

        Column() {
          if (this.loading) {
            LoadingState()
          } else if (this.errorText.length > 0) {
            EmptyState({ title: '搜索失败', subtitle: this.errorText })
          } else if (!this.hasSearched()) {
            EmptyState({ title: '输入关键字开始搜索' })
          } else if (this.currentResults().length === 0) {
            EmptyState({ title: '没有找到匹配结果' })
          } else {
            List() {
              ForEach(this.currentResults(), (candidate: MatchCandidate, index: number) => {
                ListItem() {
                  this.resultRow(candidate, index)
                }
              }, (candidate: MatchCandidate) => `${candidate.source}_${candidate.id}_${candidate.name}`)
            }
            .width('100%')
            .height(360)
            .scrollBar(BarState.Off)
          }
        }
        .width('100%')
        .margin({ top: 10 })

        Button(this.applying ? '应用中…' : '完成')
          .height(40)
          .width('100%')
          .fontSize(14)
          .backgroundColor(Theme.primary(Theme.isDark()))
          .fontColor(Theme.onPrimary(Theme.isDark()))
          .enabled(this.selectedIndex >= 0 && !this.applying)
          .margin({ top: 10 })
          .onClick(() => {
            this.apply();
          })
      }
      .width('100%')
    }
  }
}
