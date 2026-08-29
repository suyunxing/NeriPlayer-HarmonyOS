import { Theme } from '../Theme';
import { Playlist } from '../../model/Playlist';
import { MusicPlatform } from '../../model/MusicPlatform';
import { iconForLegacy } from '../../util/IconCatalog';

/**
 * Shared UI building blocks used across pages (section headers, cards,
 * empty states, list rows). Mirrors the Android ui/component/* helpers.
 */

/**
 * S3b-2: 悬浮胶囊 Tab 栏（barOverlap）遮住的内容高度避让。MiniBar 展开
 * 时 HdsTabs 自行增高，此值按「Tab 栏 56 + MiniBar 56 + 边距/呼吸 24」取。
 * 各 Tab 页滚动尾部 padding.bottom 叠加 ui.bottomLiftVp。
 */
export const FLOAT_TAB_CLEARANCE: number = 136;


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
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary(Theme.isDark()))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 10, bottom: 8 })
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
    .clickEffect({ level: ClickEffectLevel.LIGHT })
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
    .clickEffect({ level: ClickEffectLevel.LIGHT })
  }
}

/**
 * 大屏栏宽约束容器。
 *
 * 上一轮设备实测（审计 §8.2）暴露的一整类问题是「内容按窗口宽度线性拉伸」：
 * tablet 1440vp 下设置行文本被拉到 1300vp 以上、法务正文一行装七八十个字，
 * 阅读时眼睛要横扫整块屏。官方大屏适配指南对这类内容的处理是限制正文栏宽并
 * 居中，而不是继续铺满。
 *
 * 用 Row + justifyContent(Center) 而不是 margin：约束只在窗口比 maxWidth 宽时
 * 生效，窄屏（sm）下 constraintSize 不裁剪，布局与改造前逐像素一致。
 *
 * 档位约定：正文类 600vp（法务 / 免责声明 / 引导），列表与设置类 840vp，
 * 卡片网格不套此容器 —— 那类内容由 GridRow 分列消化宽度。
 *
 * 适用边界：本容器高度按内容自适应，所以只能包「Scroll 里的那坨内容」。若被包
 * 住的子树里有 layoutWeight(1) 要撑满窗口剩余高度（如探索页的结果列表、法务页的
 * 正文区），必须在页面里手写 Row + constraintSize 并逐层传 height('100%')，
 * 否则那一层会塌成内容高度。
 */
@Component
export struct ContentBand {
  @Prop maxWidth: number = 600;
  @BuilderParam content: () => void;

  build() {
    Row() {
      Column() {
        this.content()
      }
      // width 先给满、再由 constraintSize 收口：Column 默认按内容自适应宽度，
      // 而子节点普遍写 width('100%')，两边互相等对方定宽会拿到不确定结果。
      .width('100%')
      .constraintSize({ maxWidth: this.maxWidth })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
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

/** Single-choice entry shown in an OptionRow's dropdown menu. */
export interface OptionEntry {
  /** Stable id compared against OptionRow.current. */
  value: string;
  /** Displayed text. */
  label: string;
}

/**
 * Binary setting row with a real switch (UX rule: every on/off option must
 * carry a Toggle). Tapping the switch — not the row — flips the value, so the
 * interaction point and the visual state stay on the same control.
 */
@Component
export struct ToggleRow {
  @Prop title: string;
  @Prop subtitle: string = '';
  @Prop icon: string = '';
  @Prop iconResource: Resource = $r('app.media.ic_info_24');
  @Prop showIcon: boolean = false;
  @Prop value: boolean = false;
  onChange: (value: boolean) => void = () => {};

  build() {
    Row({ space: 12 }) {
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
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(15)
          .fontColor(Theme.textPrimary(Theme.isDark()))
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

      Toggle({ type: ToggleType.Switch, isOn: this.value })
        .selectedColor(Theme.primary(Theme.isDark()))
        .onChange((isOn: boolean) => this.onChange(isOn))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(Theme.surface(Theme.isDark()))
  }
}

/**
 * Multi-choice setting row (UX rule: non-binary options expose a secondary
 * menu). Shows the current value as the subtitle and opens a checked
 * single-choice Menu anchored at the trailing chevron (not the row), which
 * also rotates 90° while the menu is open so the open state stays visible.
 */
@Component
export struct OptionRow {
  @Prop title: string;
  @Prop subtitle: string = '';
  @Prop icon: string = '';
  @Prop iconResource: Resource = $r('app.media.ic_info_24');
  @Prop showIcon: boolean = false;
  @Prop options: OptionEntry[] = [];
  @Prop current: string = '';
  onPick: (value: string) => void = () => {};
  @State menuShow: boolean = false;

  private currentLabel(): string {
    // Hoisted out of the loop: repeated state-var reads in loops are flagged
    // by hp-arkui-no-state-var-access-in-loop.
    const options = this.options;
    const current = this.current;
    for (const option of options) {
      if (option.value === current) {
        return option.label;
      }
    }
    return '';
  }

  @Builder
  optionMenuBuilder() {
    Menu() {
      ForEach(this.options, (option: OptionEntry) => {
        MenuItem({ content: option.label })
          .selected(option.value === this.current)
          .selectIcon(true)
          .onClick(() => this.onPick(option.value))
      }, (option: OptionEntry) => option.value)
    }
  }

  build() {
    Row({ space: 12 }) {
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
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(15)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.currentLabel().length > 0 ? this.currentLabel() : this.subtitle)
          .fontSize(12)
          .fontColor(Theme.textSecondary(Theme.isDark()))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 40vp anchor/hot zone around the chevron: the menu always opens from
      // the arrow (placement BottomRight), tapping the row body opens it too.
      // The icon stays right-aligned so its visual position is unchanged; the
      // extra 20vp of hot zone extend to the left only.
      Row() {
        Image($r('app.media.ic_chevron_right_24'))
          .width(20)
          .height(20)
          .fillColor(Theme.textDisabled(Theme.isDark()))
          .rotate({ angle: this.menuShow ? 90 : 0 })
          .animation({ duration: 180, curve: Curve.EaseInOut })
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.End)
      .accessibilityText(`${this.title}，当前${this.currentLabel()}，点击选择`)
      .bindMenu(this.menuShow!!, this.optionMenuBuilder, {
        placement: Placement.BottomRight,
        onDisappear: () => {
          this.menuShow = false;
        }
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(Theme.surface(Theme.isDark()))
    .onClick(() => {
      this.menuShow = true;
    })
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
