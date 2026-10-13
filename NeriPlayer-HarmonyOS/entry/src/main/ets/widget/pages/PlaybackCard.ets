// SPDX-License-Identifier: GPL-3.0
// HarmonyOS Form Kit playback card UI (upstream reference: Android playback
// widgets #472 — feature parity only). Runs in the system card render
// service: no AppStorage/Theme access, fixed dark styling; data arrives via
// updateForm pushes and control buttons go through postCardAction call
// events (launches EntryAbility to background, no UI brought to front).

let storage = new LocalStorage();

@Entry(storage)
@Component
struct PlaybackCard {
  @LocalStorageProp('title') title: string = '未在播放';
  @LocalStorageProp('artist') artist: string = '';
  @LocalStorageProp('playing') playing: string = 'false';
  @LocalStorageProp('hasSong') hasSong: string = 'false';
  @LocalStorageProp('coverKey') coverKey: string = '';
  @LocalStorageProp('hasCover') hasCover: string = 'false';
  @LocalStorageProp('formId') formId: string = '';

  private control(action: string): void {
    // call 事件的 method 必须放在 params 内（官方 js-apis-postCardAction 约定，
    // 顶层仅 action/bundleName/moduleName/abilityName/uri/params 合法）：放顶层
    // 会被系统静默丢弃，卡片按钮完全无响应（2026-10-13 真机反馈实证）。
    postCardAction(this, {
      action: 'call',
      abilityName: 'EntryAbility',
      params: {
        method: 'playbackCardControl',
        formId: this.formId,
        action: action
      }
    });
  }

  private openApp(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: { fromPlaybackCard: 'true' }
    });
  }

  build() {
    Column() {
      // 上半：封面 + 歌名/艺人（点击主体打开应用）。
      Row({ space: 10 }) {
        if (this.hasCover === 'true') {
          Image(`memory://${this.coverKey}`)
            .width(52)
            .height(52)
            .borderRadius(10)
            .objectFit(ImageFit.Cover)
            .backgroundColor('#33FFFFFF')
        } else {
          Column() {
            Image($r('app.media.ic_neriplayer'))
              .width(30)
              .height(30)
              .fillColor('#CCFFFFFF')
          }
          .width(52)
          .height(52)
          .borderRadius(10)
          .backgroundColor('#33FFFFFF')
          .justifyContent(FlexAlign.Center)
        }
        Column({ space: 3 }) {
          Text(this.title)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.artist.length > 0 ? this.artist : 'NeriPlayer')
            .fontSize(11)
            .fontColor('#99FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12 })
      .onClick(() => this.openApp())

      // 下半：三控制钮（call 事件后台控制，不拉起界面）。
      Row({ space: 12 }) {
        Image($r('app.media.round_skip_previous_24'))
          .width(34)
          .height(34)
          .fillColor('#E6FFFFFF')
          .onClick(() => this.control('prev'))
        Image(this.playing === 'true'
          ? $r('app.media.round_pause_24') : $r('app.media.round_play_arrow_24'))
          .width(40)
          .height(40)
          .fillColor('#FFFFFF')
          .onClick(() => this.control('toggle'))
        Image($r('app.media.round_skip_next_24'))
          .width(34)
          .height(34)
          .fillColor('#E6FFFFFF')
          .onClick(() => this.control('next'))
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#141414')
    .borderRadius(16)
    .clip(true)
  }
}
