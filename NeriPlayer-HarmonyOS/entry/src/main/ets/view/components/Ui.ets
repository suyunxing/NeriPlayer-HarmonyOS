// SPDX-License-Identifier: GPL-3.0

import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { LengthMetrics } from '@kit.ArkUI';

import { Playlist } from '../../model/Playlist';
import { iconForLegacy } from '../../util/IconCatalog';

/**
 * Shared UI building blocks used across pages (section headers, cards,
 * empty states, list rows). Mirrors the Android ui/component/* helpers.
 *
 * 视觉规范（对齐参考截图）：非透明模式的设置行都是**独立圆角卡片**，行与
 * 行的间距由宿主容器的 space 提供（10~12vp）；透明模式（bindSheet 材质底上）
 * 保持平铺无底色。
 */

/** 菜单浮层光感样式的三个属性值（参考截图的深色磨砂浮层）。Menu 不支持
 * shadow/outline，主题色边缘光晕无法在 Menu 上实现（平台限制），以玻璃底 +
 * 细分隔线 + 选中项主色近似。 */
export function menuRadius(): number {
  return 24;
}

export function menuDivider(dark: boolean): DividerStyleOptions {
  return {
    strokeWidth: LengthMetrics.vp(0.5),
    color: Theme.withAlpha(Theme.textSecondary(dark), 0x22),
    startMargin: LengthMetrics.vp(14),
    endMargin: LengthMetrics.vp(14)
  };
}

/**
 * S3b-2: 悬浮胶囊 Tab 栏（barOverlap）遮住的内容高度避让。MiniBar 展开
 * 时 HdsTabs 自行增高，此值按「Tab 栏 56 + MiniBar 56 + 边距/呼吸 24」取。
 * 各 Tab 页滚动尾部 padding.bottom 叠加 ui.bottomLiftVp。
 */
export const FLOAT_TAB_CLEARANCE: number = 136;


@Component
export struct SectionHeader {
  /**
   * S5: 订阅封面配色（M7.4：build 里读成员才追得上换歌重染色）。
   */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();

  @Prop title: string;
  @Prop icon: string = '';
  @Prop iconResource: Resource = $r('app.media.ic_music_note_24');
  @Prop showIcon: boolean = false;

  /** build 里直读被跟踪成员注册依赖；颜色仍由 Theme 统一决策。 */
  private schemePrimary(): string {
    const hasScheme = this.coverScheme.light.background.length > 0;
    return hasScheme ? Theme.primary(Theme.isDark()) : Theme.primary(Theme.isDark());
  }

  build() {
    Row({ space: 8 }) {
      if (this.showIcon) {
        Image(this.iconResource)
          .width(20)
          .height(20)
          .fillColor(this.schemePrimary())
      } else if (this.icon.length > 0) {
        Image(iconForLegacy(this.icon, this.iconResource))
          .width(20)
          .height(20)
          .fillColor(this.schemePrimary())
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
  /**
   * S5: 订阅封面配色（M7.4：build 里读成员才追得上换歌重染色）。
   */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();

  @Prop title: string;
  @Prop subtitle: string = '';
  @Prop icon: string = '';
  @Prop iconResource: Resource = $r('app.media.ic_info_24');
  @Prop showIcon: boolean = false;
  @Prop showArrow: boolean = true;
  @Prop danger: boolean = false;
  @Prop tintIcon: boolean = true;
  onTap: () => void = () => {};

  /** build 里直读被跟踪成员注册依赖；颜色仍由 Theme 统一决策。 */
  private schemePrimary(): string {
    const hasScheme = this.coverScheme.light.primary.length > 0;
    return hasScheme ? Theme.primary(Theme.isDark()) : Theme.primary(Theme.isDark());
  }

  private schemeSurface(): string {
    const hasScheme = this.coverScheme.light.background.length > 0;
    return hasScheme ? Theme.surface(Theme.isDark()) : Theme.surface(Theme.isDark());
  }

  build() {
    Row({ space: 12 }) {
      if (this.showIcon) {
        if (this.tintIcon) {
          Image(this.iconResource)
            .width(20)
            .height(20)
            .fillColor(this.danger ? Theme.danger(Theme.isDark()) : this.schemePrimary())
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
            .fillColor(this.danger ? Theme.danger(Theme.isDark()) : this.schemePrimary())
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
    .backgroundColor(this.schemeSurface())
    .borderRadius(Theme.cardRadius())
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
  /**
   * S5: 订阅封面配色（M7.4：build 里读成员才追得上换歌重染色）。
   */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @Prop title: string;
  @Prop subtitle: string = '';
  @Prop icon: string = '';
  @Prop iconResource: Resource = $r('app.media.ic_info_24');
  @Prop showIcon: boolean = false;
  /** true 时底色透明（叠在 bindSheet 等材质背景上），默认不透明 surface。 */
  @Prop transparentBg: boolean = false;
  @Prop value: boolean = false;
  onChange: (value: boolean) => void = () => {};

  /** build 里直读被跟踪成员注册依赖；颜色仍由 Theme 统一决策。 */
  private schemePrimary(): string {
    const hasScheme = this.coverScheme.light.primary.length > 0;
    return hasScheme ? Theme.primary(Theme.isDark()) : Theme.primary(Theme.isDark());
  }

  private schemeSurface(): string {
    const hasScheme = this.coverScheme.light.background.length > 0;
    return hasScheme ? Theme.surface(Theme.isDark()) : Theme.surface(Theme.isDark());
  }

  build() {
    Row({ space: 12 }) {
      if (this.showIcon) {
        Image(this.iconResource)
          .width(20)
          .height(20)
          .fillColor(this.schemePrimary())
      } else if (this.icon.length > 0) {
        Image(iconForLegacy(this.icon, this.iconResource))
          .width(20)
          .height(20)
          .fillColor(this.schemePrimary())
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
        .selectedColor(this.schemePrimary())
        .onChange((isOn: boolean) => this.onChange(isOn))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.transparentBg ? Color.Transparent : this.schemeSurface())
    .borderRadius(this.transparentBg ? 0 : Theme.cardRadius())
  }
}

/**
 * Multi-choice setting row (UX rule: non-binary options expose a secondary
 * menu). The current value renders inside a bordered trailing pill together
 * with a chevron that flips 180° while the menu is open (参考截图的下拉胶囊
 * 样式), and the menu anchors at that pill.
 */
@Component
export struct OptionRow {
  /**
   * S5: 订阅封面配色（M7.4：build 里读成员才追得上换歌重染色）。
   */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @Prop title: string;
  @Prop subtitle: string = '';
  @Prop icon: string = '';
  @Prop iconResource: Resource = $r('app.media.ic_info_24');
  @Prop showIcon: boolean = false;
  /** true 时底色透明（叠在 bindSheet 等材质背景上），默认不透明 surface。 */
  @Prop transparentBg: boolean = false;
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

  /** build 里直读被跟踪成员注册依赖；颜色仍由 Theme 统一决策。 */
  private schemePrimary(): string {
    const hasScheme = this.coverScheme.light.primary.length > 0;
    return hasScheme ? Theme.primary(Theme.isDark()) : Theme.primary(Theme.isDark());
  }

  private schemeSurface(): string {
    const hasScheme = this.coverScheme.light.background.length > 0;
    return hasScheme ? Theme.surface(Theme.isDark()) : Theme.surface(Theme.isDark());
  }

  @Builder
  optionMenuBuilder() {
    // 参考截图的浮层：深色磨砂玻璃底 + 24vp 大圆角 + 细分隔线；菜单项选中态
    // 沿用勾选标记 + 主色（Menu 不支持 shadow/outline，光晕描边为平台限制）。
    Menu() {
      ForEach(this.options, (option: OptionEntry) => {
        MenuItem({ content: option.label })
          .selected(option.value === this.current)
          .selectIcon(true)
          .onClick(() => {
            // onPick 改父级状态会触发本行重渲染；此刻 menuShow 仍为 true 的话，
            // bindMenu 会在收起动画中途被再次拉起（首次选择后“多弹一次”）。
            this.menuShow = false;
            this.onPick(option.value);
          })
      }, (option: OptionEntry) => option.value)
    }
      .radius(menuRadius())
      .backgroundColor(Theme.surfaceGlass(Theme.isDark()))
      .menuItemDivider(menuDivider(Theme.isDark()))
  }

  build() {
    Row({ space: 12 }) {
      if (this.showIcon) {
        Image(this.iconResource)
          .width(20)
          .height(20)
          .fillColor(this.schemePrimary())
      } else if (this.icon.length > 0) {
        Image(iconForLegacy(this.icon, this.iconResource))
          .width(20)
          .height(20)
          .fillColor(this.schemePrimary())
      }
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(15)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.currentLabel().length === 0 && this.subtitle.length > 0) {
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

      // 参考截图的下拉样式：描边胶囊内直接显示当前值 + ▼，菜单开合时三角
      // 旋转 180°。热区 40vp 保证触达下限，菜单锚定在胶囊自身（BottomRight）。
      Row({ space: 6 }) {
        Text(this.currentLabel().length > 0 ? this.currentLabel() : '选择')
          .fontSize(14)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(12)
          .fontColor([Theme.textSecondary(Theme.isDark())])
          .rotate({ angle: this.menuShow ? 180 : 0 })
          .animation({ duration: 180, curve: Curve.EaseInOut })
      }
      .constraintSize({ minWidth: 96 })
      .height(40)
      .padding({ left: 14, right: 12 })
      .justifyContent(FlexAlign.Center)
      .border({
        width: 1,
        color: Theme.withAlpha(Theme.textSecondary(Theme.isDark()), 0x40),
        radius: 20
      })
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
    .backgroundColor(this.transparentBg ? Color.Transparent : this.schemeSurface())
    .borderRadius(this.transparentBg ? 0 : Theme.cardRadius())
    .onClick(() => {
      this.menuShow = true;
    })
  }
}

/**
 * Numeric setting row with a live slider (UX adaptation of the reference
 * app's slider rows: 字号/字重/行距/音量/偏移). `format` renders the current
 * value next to the title so the row stays readable while dragging. The
 * switch stays off here — every change is committed through onPick.
 */
@Component
export struct SliderRow {
  /**
   * S5: 订阅封面配色（M7.4：build 里读成员才追得上换歌重染色）。
   */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @Prop title: string;
  @Prop subtitle: string = '';
  @Prop icon: string = '';
  @Prop iconResource: Resource = $r('app.media.ic_info_24');
  @Prop showIcon: boolean = false;
  /** true 时底色透明（叠在 bindSheet 等材质背景上），默认不透明 surface。 */
  @Prop transparentBg: boolean = false;
  @Prop min: number = 0;
  @Prop max: number = 1;
  @Prop step: number = 0.1;
  @Prop value: number = 0;
  /** Live value label builder (e.g. `20` / `500` / `1.0x`). */
  format: (value: number) => string = (value: number) => `${value}`;
  onPick: (value: number) => void = () => {};
  /** Value currently under the finger; -1 when not dragging. */
  @State liveValue: number = -1;

  /** build 里直读被跟踪成员注册依赖；颜色仍由 Theme 统一决策。 */
  private schemePrimary(): string {
    const hasScheme = this.coverScheme.light.primary.length > 0;
    return hasScheme ? Theme.primary(Theme.isDark()) : Theme.primary(Theme.isDark());
  }

  private schemeSurface(): string {
    const hasScheme = this.coverScheme.light.background.length > 0;
    return hasScheme ? Theme.surface(Theme.isDark()) : Theme.surface(Theme.isDark());
  }

  private schemeSurfaceVariant(): string {
    const hasScheme = this.coverScheme.light.surfaceVariant.length > 0;
    return hasScheme ? Theme.surfaceVariant(Theme.isDark()) : Theme.surfaceVariant(Theme.isDark());
  }

  build() {
    Row({ space: 12 }) {
      if (this.showIcon) {
        Image(this.iconResource)
          .width(20)
          .height(20)
          .fillColor(this.schemePrimary())
      } else if (this.icon.length > 0) {
        Image(iconForLegacy(this.icon, this.iconResource))
          .width(20)
          .height(20)
          .fillColor(this.schemePrimary())
      }
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(this.title)
            .fontSize(15)
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.format(this.liveValue >= 0 ? this.liveValue : this.value))
            .fontSize(13)
            .fontColor(Theme.primary(Theme.isDark()))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Slider({
          value: this.value,
          min: this.min,
          max: this.max,
          step: this.step,
          style: SliderStyle.OutSet
        })
          .selectedColor(this.schemePrimary())
          // 参考截图：主色轨道 + 白色圆形滑钮（两种模式下都是白钮）。
          .blockColor('#FFFFFF')
          .trackColor(this.schemeSurfaceVariant())
          .width('100%')
          .height(36)
          .onChange((value: number, eventMode: SliderChangeMode) => {
            if (eventMode === SliderChangeMode.End || eventMode === SliderChangeMode.Click) {
              this.liveValue = -1;
              this.onPick(value);
            } else {
              this.liveValue = value;
            }
          })

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
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 8 })
    .backgroundColor(this.transparentBg ? Color.Transparent : this.schemeSurface())
    .borderRadius(this.transparentBg ? 0 : Theme.cardRadius())
  }
}

/**
 * Settings hub entry card (参考应用的设置总览卡片)：裸图标 + 双行文字 +
 * 跳转箭头，图标样式与其他设置行一致；取动态主色（M7.4 被跟踪读法）
 * 随封面取色重染。
 */
@Component
export struct SettingHubRow {
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @Prop title: string;
  @Prop subtitle: string = '';
  @Prop icon: string = '';
  @Prop iconResource: Resource = $r('app.media.ic_music_note_24');
  @Prop showIcon: boolean = false;
  onTap: () => void = () => {};

  /** build 里直读被跟踪成员注册依赖；颜色仍由 Theme 统一决策。 */
  private schemePrimary(): string {
    const hasScheme = this.coverScheme.light.primary.length > 0;
    return hasScheme ? Theme.primary(Theme.isDark()) : Theme.primary(Theme.isDark());
  }

  private schemeSurface(): string {
    const hasScheme = this.coverScheme.light.background.length > 0;
    return hasScheme ? Theme.surface(Theme.isDark()) : Theme.surface(Theme.isDark());
  }

  build() {
    Row({ space: 12 }) {
      if (this.showIcon) {
        Image(this.iconResource)
          .width(20)
          .height(20)
          .fillColor(this.schemePrimary())
      } else {
        Image(iconForLegacy(this.icon, this.iconResource))
          .width(20)
          .height(20)
          .fillColor(this.schemePrimary())
      }

      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(12)
            .fontColor(Theme.textSecondary(Theme.isDark()))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Image($r('app.media.ic_chevron_right_24'))
        .width(20)
        .height(20)
        .fillColor(Theme.textDisabled(Theme.isDark()))
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(this.schemeSurface())
    .borderRadius(Theme.cardRadius())
    .onClick(() => this.onTap())
    .clickEffect({ level: ClickEffectLevel.LIGHT })
  }
}

export function formatDuration(ms: number): string {
  const totalSeconds = Math.max(0, Math.floor(ms / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${seconds.toString().padStart(2, '0')}`;
}
