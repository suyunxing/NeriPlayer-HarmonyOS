import { Theme } from '../Theme';
import { Playlist } from '../../model/Playlist';
import { MusicPlatform } from '../../model/MusicPlatform';
import { iconForLegacy } from '../../util/IconCatalog';

/**
 * Shared UI building blocks used across pages (section headers, cards,
 * empty states, list rows). Mirrors the Android ui/component/* helpers.
 */

@Component
export struct SectionHeader {
  @Prop title: string;
  @Prop icon: string = '';
  @Prop iconResource: Resource = $r('app.media.ic_music_note_24');
  @Prop showIcon: boolean = false;

  build() {
    Row({ space: 8 }) {
      if (this.showIcon) {
        Image(this.iconResource)
          .width(20)
          .height(20)
          .fillColor(Theme.primary(Theme.isDark()))
      } else if (this.icon.length > 0) {
        Image(iconForLegacy(this.icon, this.iconResource))
          .width(20)
          .height(20)
          .fillColor(Theme.primary(Theme.isDark()))
      }
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary(Theme.isDark()))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }
}

@Component
export struct EmptyState {
  @Prop icon: string = '';
  @Prop iconResource: Resource = $r('app.media.ic_music_note_24');
  @Prop showIcon: boolean = false;
  @Prop title: string;
  @Prop subtitle: string = '';

  build() {
    Column({ space: 6 }) {
      if (this.showIcon) {
        Image(this.iconResource)
          .width(38)
          .height(38)
          .fillColor(Theme.textDisabled(Theme.isDark()))
      } else if (this.icon.length > 0) {
        Image(iconForLegacy(this.icon, this.iconResource))
          .width(38)
          .height(38)
          .fillColor(Theme.textDisabled(Theme.isDark()))
      }
      Text(this.title)
        .fontSize(15)
        .fontColor(Theme.textSecondary(Theme.isDark()))
        .textAlign(TextAlign.Center)
      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(12)
          .fontColor(Theme.textDisabled(Theme.isDark()))
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .padding({ top: 48, bottom: 48, left: 24, right: 24 })
    .justifyContent(FlexAlign.Center)
  }
}

@Component
export struct LoadingState {
  build() {
    Column() {
      LoadingProgress()
        .width(36)
        .height(36)
        .color(Theme.primary(Theme.isDark()))
    }
    .width('100%')
    .height(120)
    .justifyContent(FlexAlign.Center)
  }
}

@Component
export struct PlaylistCard {
  @Prop name: string;
  @Prop subtitle: string = '';
  @Prop coverUrl: string = '';
  @Prop trackCount: number = 0;
  @Prop isFavorite: boolean = false;
  onOpen: () => void = () => {};

  build() {
    Column({ space: 6 }) {
      Stack() {
        if (this.coverUrl.length > 0) {
          Image(this.coverUrl)
            .width('100%')
            .aspectRatio(1)
            .borderRadius(12)
            .objectFit(ImageFit.Cover)
            .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
        } else {
          Column() {
            Image($r('app.media.ic_music_note_24'))
              .width(36)
              .height(36)
              .fillColor(Theme.primary(Theme.isDark()))
          }
          .width('100%')
          .aspectRatio(1)
          .borderRadius(12)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
        }
        if (this.isFavorite) {
          Image($r('app.media.ic_baseline_favorite_24'))
            .width(16)
            .height(16)
            .fillColor(Theme.warning(Theme.isDark()))
            .padding(5)
            .backgroundColor(Theme.scrim(Theme.isDark()))
            .borderRadius(8)
            .position({ x: '82%', y: '3%' })
        }
      }
      .width('100%')

      Text(this.name)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.textPrimary(Theme.isDark()))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      if (this.subtitle.length > 0 || this.trackCount > 0) {
        Text(this.subtitle.length > 0 ? this.subtitle : `${this.trackCount} 首`)
          .fontSize(12)
          .fontColor(Theme.textSecondary(Theme.isDark()))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .onClick(() => this.onOpen())
  }
}

@Component
export struct SettingRow {
  @Prop title: string;
  @Prop subtitle: string = '';
  @Prop icon: string = '';
  @Prop iconResource: Resource = $r('app.media.ic_info_24');
  @Prop showIcon: boolean = false;
  @Prop showArrow: boolean = true;
  @Prop danger: boolean = false;
  @Prop tintIcon: boolean = true;
  onTap: () => void = () => {};

  build() {
    Row({ space: 12 }) {
      if (this.showIcon) {
        if (this.tintIcon) {
          Image(this.iconResource)
            .width(20)
            .height(20)
            .fillColor(this.danger ? Theme.danger(Theme.isDark()) : Theme.primary(Theme.isDark()))
        } else {
          Image(this.iconResource)
            .width(22)
            .height(22)
        }
      } else if (this.icon.length > 0) {
        if (this.tintIcon) {
          Image(iconForLegacy(this.icon, this.iconResource))
            .width(20)
            .height(20)
            .fillColor(this.danger ? Theme.danger(Theme.isDark()) : Theme.primary(Theme.isDark()))
        } else {
          Image(iconForLegacy(this.icon, this.iconResource))
            .width(22)
            .height(22)
        }
      }
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(15)
          .fontColor(this.danger ? Theme.danger(Theme.isDark()) : Theme.textPrimary(Theme.isDark()))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(12)
            .fontColor(Theme.textSecondary(Theme.isDark()))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.showArrow) {
        Image($r('app.media.ic_chevron_right_24'))
          .width(20)
          .height(20)
          .fillColor(Theme.textDisabled(Theme.isDark()))
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(Theme.surface(Theme.isDark()))
    .onClick(() => this.onTap())
  }
}

@Component
export struct SongCountChip {
  @Prop count: number;

  build() {
    Text(`${this.count} 首`)
      .fontSize(12)
      .fontColor(Theme.textSecondary(Theme.isDark()))
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
      .borderRadius(10)
  }
}

export function platformName(platform: MusicPlatform): string {
  if (platform === MusicPlatform.BILIBILI) {
    return 'Bilibili';
  }
  if (platform === MusicPlatform.YOUTUBE_MUSIC) {
    return 'YouTube Music';
  }
  if (platform === MusicPlatform.LOCAL) {
    return '本地';
  }
  return '网易云';
}

export function formatDuration(ms: number): string {
  const totalSeconds = Math.max(0, Math.floor(ms / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${seconds.toString().padStart(2, '0')}`;
}
