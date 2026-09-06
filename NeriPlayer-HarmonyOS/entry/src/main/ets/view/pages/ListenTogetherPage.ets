import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { ListenTogetherSessionManager } from '../../listentogether/ListenTogetherSessionManager';
import {
  ListenTogetherConnectionState,
  ListenTogetherSessionState,
  listenTogetherSessionStateFromJson
} from '../../listentogether/protocol/ListenTogetherSessionModels';
import {
  ListenTogetherRoomState,
  ListenTogetherRoomStatuses,
  listenTogetherRoomStateFromRecord
} from '../../listentogether/protocol/ListenTogetherRoomModels';
import { jsonRecordFromText } from '../../listentogether/protocol/ListenTogetherJson';
import { ListenTogetherPreferences } from '../../data/listentogether/ListenTogetherPreferences';
import { resolveListenTogetherServerBaseUrl } from '../../listentogether/settings/ListenTogetherServerPreferences';
import { buildListenTogetherInviteUri } from '../../listentogether/invite/ListenTogetherInviteBuilder';
import { parseListenTogetherInvite } from '../../listentogether/invite/ListenTogetherInviteParser';
import { PlayerManager } from '../../player/PlayerManager';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { Router } from '../Router';

/** Room creation needs a live local queue (upstream validates this too). */
function hasPlayableQueue(): boolean {
  return PlayerManager.getQueue().length > 0 && PlayerManager.getCurrentSong() !== null;
}

/** View-only member row: nickname plus a precomputed controller flag. */
class ListenTogetherRoomMemberView {
  userUuid: string = '';
  nickname: string = '';
  joinedAt: number = 0;
  isController: boolean = false;

  constructor(userUuid: string, nickname: string, joinedAt: number, isController: boolean) {
    this.userUuid = userUuid;
    this.nickname = nickname;
    this.joinedAt = joinedAt;
    this.isController = isController;
  }
}

/** Controller identity is decided by the room state, not the server role field. */
function memberViews(room: ListenTogetherRoomState): ListenTogetherRoomMemberView[] {
  const controllerUuid = room.controllerUserUuid ?? '';
  const views: ListenTogetherRoomMemberView[] = [];
  for (const member of room.members) {
    views.push(new ListenTogetherRoomMemberView(
      member.userUuid,
      member.nickname,
      member.joinedAt,
      member.userUuid === controllerUuid
    ));
  }
  views.sort((left: ListenTogetherRoomMemberView, right: ListenTogetherRoomMemberView): number => {
    return left.joinedAt === right.joinedAt
      ? left.userUuid.localeCompare(right.userUuid)
      : left.joinedAt - right.joinedAt;
  });
  return views;
}

function connectionLabel(state: ListenTogetherConnectionState): string {
  if (state === ListenTogetherConnectionState.CONNECTED) {
    return '已连接';
  }
  return state === ListenTogetherConnectionState.CONNECTING ? '连接中' : '未连接';
}

function roomStatusLabel(status: string): string {
  if (status === ListenTogetherRoomStatuses.CONTROLLER_OFFLINE) {
    return '主持端离线';
  }
  return status === ListenTogetherRoomStatuses.CLOSED ? '已关闭' : '进行中';
}

/**
 * Minimal M7.4 room page: create/join by nickname + invite link, live status
 * card and member list from the session manager's AppStorage publications,
 * invite copy for the controller, leave/refresh actions. Playback control
 * stays in the player UI — the session manager already intercepts it.
 */
@Component
export struct ListenTogetherPage {
  /**
   * S5: 订阅封面配色。Theme.*() 读 AppStorage 是无跟踪调用（M7.4），换歌后
   * 坐在本页的组件不会重建；有了这个成员并在 build 里经 schemeBg() 直读，
   * scheme 一发布本页就随新配色重染。
   */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  // Parsing is mirrored into @State objects via @Watch instead of parsed in
  // render expressions: a state read hidden inside a method call is NOT
  // dependency-tracked on this platform, so `this.session()` in a builder
  // argument froze at its first value on device (the connection row kept
  // showing "connecting" while the raw JSON in a probe Text said "connected").
  // The @Watch reassignment re-renders the whole component, which re-runs
  // every expression.
  @StorageLink('listenTogether.sessionState') @Watch('onSessionJsonChange') sessionStateJson: string = '';
  @StorageLink('listenTogether.roomState') @Watch('onRoomJsonChange') roomStateJson: string = '';
  @State sessionView: ListenTogetherSessionState = new ListenTogetherSessionState();
  @State roomViewData: ListenTogetherRoomState = new ListenTogetherRoomState();
  @State hasRoomState: boolean = false;
  @State nicknameInput: string = '';
  @State inviteInput: string = '';
  @State busy: boolean = false;

  aboutToAppear(): void {
    // Persists a generated default on first run, exactly like the manager
    // would before any create/join call.
    this.nicknameInput = ListenTogetherPreferences.getOrCreateNickname();
    this.onSessionJsonChange();
    this.onRoomJsonChange();
  }

  onSessionJsonChange(): void {
    this.sessionView = listenTogetherSessionStateFromJson(this.sessionStateJson) ??
      new ListenTogetherSessionState();
  }

  onRoomJsonChange(): void {
    if (this.roomStateJson.length === 0) {
      this.roomViewData = new ListenTogetherRoomState();
      this.hasRoomState = false;
      return;
    }
    const raw = jsonRecordFromText(this.roomStateJson);
    this.roomViewData = raw === null ? new ListenTogetherRoomState() : listenTogetherRoomStateFromRecord(raw);
    this.hasRoomState = raw !== null;
  }

  private applyNickname(): void {
    const trimmed = this.nicknameInput.trim();
    if (trimmed.length > 0 && trimmed !== ListenTogetherPreferences.getOrCreateNickname()) {
      ListenTogetherPreferences.setNickname(trimmed);
    }
  }

  private async createRoom(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      this.applyNickname();
      const response = await ListenTogetherSessionManager.getInstance().createRoom();
      if (response.ok) {
        promptAction.openToast({ message: `房间已创建：${response.roomId ?? ''}` });
      } else {
        promptAction.openToast({ message: `创建失败：${response.error ?? '未知错误'}` });
      }
    } catch (error) {
      promptAction.openToast({ message: `创建失败：${(error as Error).message}` });
    }
    this.busy = false;
  }

  private async joinByInvite(): Promise<void> {
    if (this.busy) {
      return;
    }
    const invite = parseListenTogetherInvite(this.inviteInput);
    if (invite === null) {
      promptAction.openToast({ message: '无法识别邀请链接' });
      return;
    }
    if (invite.hasInvalidBaseUrl) {
      promptAction.openToast({ message: '邀请链接中的服务器地址无效' });
      return;
    }
    this.busy = true;
    try {
      this.applyNickname();
      const response = await ListenTogetherSessionManager.getInstance().joinRoom(
        invite.roomId,
        invite.baseUrl ?? resolveListenTogetherServerBaseUrl(),
        invite.joinSecret
      );
      if (response.ok) {
        promptAction.openToast({ message: `已加入房间：${invite.roomId}` });
      } else {
        promptAction.openToast({ message: `加入失败：${response.error ?? '未知错误'}` });
      }
    } catch (error) {
      promptAction.openToast({ message: `加入失败：${(error as Error).message}` });
    }
    this.busy = false;
  }

  private async refreshState(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const response = await ListenTogetherSessionManager.getInstance().refreshRoomState();
      if (response === null || !response.ok) {
        promptAction.openToast({ message: '刷新失败，请检查网络' });
      }
    } catch (error) {
      promptAction.openToast({ message: `刷新失败：${(error as Error).message}` });
    }
    this.busy = false;
  }

  private async leaveRoom(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      await ListenTogetherSessionManager.getInstance().leaveRoom();
      promptAction.openToast({ message: '已离开房间' });
    } catch (error) {
      promptAction.openToast({ message: `离开失败：${(error as Error).message}` });
    }
    this.busy = false;
  }

  private inviteShareText(session: ListenTogetherSessionState): string | null {
    const roomId = session.roomId ?? '';
    const joinSecret = session.joinSecret;
    if (roomId.length === 0 || joinSecret === null || joinSecret.length === 0) {
      return null;
    }
    try {
      const uri = buildListenTogetherInviteUri(roomId, joinSecret, session.nickname, session.baseUrl);
      const inviter = session.nickname !== null && session.nickname.length > 0 ? session.nickname : '我';
      return `${inviter} 邀请你一起听 ${uri}`;
    } catch (error) {
      return null;
    }
  }

  private copyInvite(): void {
    const shareText = this.inviteShareText(this.sessionView);
    if (shareText === null) {
      promptAction.openToast({ message: '邀请信息不可用' });
      return;
    }
    const board = pasteboard.getSystemPasteboard();
    board.setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, shareText))
      .then((): void => {
        promptAction.openToast({ message: '邀请已复制，发送给朋友即可' });
      })
      .catch((): void => {
        promptAction.openToast({ message: '复制失败' });
      });
  }

  @Builder
  joinForm() {
    Column({ space: 12 }) {
      Column({ space: 8 }) {
        Text('昵称')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textPrimary(Theme.isDark()))
        TextInput({ text: this.nicknameInput, placeholder: '留空自动生成' })
          .height(42)
          .fontSize(14)
          .maxLength(24)
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          .onChange((value: string) => {
            // Plain assignment only; no derived state is reset here, so the
            // TextInput programmatic-echo pitfall does not apply.
            this.nicknameInput = value;
          })
      }
      .width('100%')

      Button(this.busy ? '创建中…' : '创建房间（使用当前播放列表）')
        .width('100%')
        .height(42)
        .fontSize(14)
        .fontColor(Theme.onPrimary(Theme.isDark()))
        .backgroundColor(Theme.primary(Theme.isDark()))
        .enabled(!this.busy && hasPlayableQueue())
        .onClick(() => {
          this.createRoom();
        })
      if (!hasPlayableQueue()) {
        Text('播放列表为空：先播放一首歌，再创建房间')
          .fontSize(12)
          .fontColor(Theme.textSecondary(Theme.isDark()))
      }

      Divider().margin({ top: 6, bottom: 6 })

      Column({ space: 8 }) {
        Text('邀请链接')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textPrimary(Theme.isDark()))
        TextInput({ text: this.inviteInput, placeholder: '粘贴 neriplayer://listen-together/join?… 链接' })
          .height(42)
          .fontSize(13)
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          .onChange((value: string) => {
            this.inviteInput = value;
          })
        Button(this.busy ? '加入中…' : '加入房间')
          .width('100%')
          .height(42)
          .fontSize(14)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          .enabled(!this.busy && this.inviteInput.trim().length > 0)
          .onClick(() => {
            this.joinByInvite();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(Theme.surface(Theme.isDark()))
  }

  // Flat on purpose: rows read the @State mirrors directly. Nested @Builder
  // arguments and method-wrapped state reads are not dependency-tracked on
  // this platform and froze at their first evaluated value on device.
  @Builder
  roomView() {
    Column({ space: 12 }) {
      Column({ space: 8 }) {
        Row() {
          Text('房间').fontSize(13).fontColor(Theme.textSecondary(Theme.isDark())).width(76)
          Text(this.sessionView.roomId ?? '—')
            .fontSize(13).fontColor(Theme.textPrimary(Theme.isDark()))
            .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.width('100%')
        Row() {
          Text('本端角色').fontSize(13).fontColor(Theme.textSecondary(Theme.isDark())).width(76)
          Text(ListenTogetherSessionManager.getInstance().isCurrentUserController() ? '控制端' : '监听端')
            .fontSize(13).fontColor(Theme.textPrimary(Theme.isDark()))
            .layoutWeight(1).maxLines(1)
        }.width('100%')
        Row() {
          Text('连接').fontSize(13).fontColor(Theme.textSecondary(Theme.isDark())).width(76)
          Text(connectionLabel(this.sessionView.connectionState))
            .fontSize(13).fontColor(Theme.textPrimary(Theme.isDark()))
            .layoutWeight(1).maxLines(1)
        }.width('100%')
        if (this.hasRoomState) {
          Row() {
            Text('房间状态').fontSize(13).fontColor(Theme.textSecondary(Theme.isDark())).width(76)
            Text(roomStatusLabel(this.roomViewData.roomStatus))
              .fontSize(13).fontColor(Theme.textPrimary(Theme.isDark()))
              .layoutWeight(1).maxLines(1)
          }.width('100%')
          Row() {
            Text('成员').fontSize(13).fontColor(Theme.textSecondary(Theme.isDark())).width(76)
            Text(`${this.roomViewData.members.length} 人`)
              .fontSize(13).fontColor(Theme.textPrimary(Theme.isDark()))
              .layoutWeight(1).maxLines(1)
          }.width('100%')
          Row() {
            Text('当前曲目').fontSize(13).fontColor(Theme.textSecondary(Theme.isDark())).width(76)
            Text(this.roomViewData.track !== null
              ? `${this.roomViewData.track?.name} · ${this.roomViewData.track?.artist}` : '—')
              .fontSize(13).fontColor(Theme.textPrimary(Theme.isDark()))
              .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.width('100%')
          Row() {
            Text('播放').fontSize(13).fontColor(Theme.textSecondary(Theme.isDark())).width(76)
            Text(this.roomViewData.playback.state === 'playing' ? '播放中' : '已暂停')
              .fontSize(13).fontColor(Theme.textPrimary(Theme.isDark()))
              .layoutWeight(1).maxLines(1)
          }.width('100%')
        }
      }
      .width('100%')

      if ((this.sessionView.roomNotice ?? '').length > 0) {
        Text(this.sessionView.roomNotice ?? '')
          .fontSize(12)
          .fontColor(Theme.textSecondary(Theme.isDark()))
          .width('100%')
      }
      if ((this.sessionView.lastError ?? '').length > 0) {
        Text(this.sessionView.lastError ?? '')
          .fontSize(12)
          .fontColor('#E5484D')
          .width('100%')
      }

      if (ListenTogetherSessionManager.getInstance().isCurrentUserController()) {
        Column({ space: 8 }) {
          Text('邀请')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.textPrimary(Theme.isDark()))
          Text(this.inviteShareText(this.sessionView) ?? '邀请信息不可用')
            .fontSize(12)
            .fontColor(Theme.textSecondary(Theme.isDark()))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Button('复制邀请')
            .height(40)
            .fontSize(13)
            .fontColor(Theme.onPrimary(Theme.isDark()))
            .backgroundColor(Theme.primary(Theme.isDark()))
            .onClick(() => this.copyInvite())
        }
        .width('100%')
        .padding(12)
        .borderRadius(12)
        .backgroundColor(Theme.surface(Theme.isDark()))
        .alignItems(HorizontalAlign.Start)
      }

      if (this.hasRoomState && this.roomViewData.members.length > 0) {
        Column({ space: 4 }) {
          ForEach(memberViews(this.roomViewData), (member: ListenTogetherRoomMemberView) => {
            Row() {
              Text(member.nickname)
                .fontSize(14)
                .fontColor(Theme.textPrimary(Theme.isDark()))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(member.isController ? '控制端' : '监听端')
                .fontSize(11)
                .fontColor(member.isController ? Theme.primary(Theme.isDark()) : Theme.textSecondary(Theme.isDark()))
            }
            .width('100%')
            .padding({ top: 6, bottom: 6 })
          }, (member: ListenTogetherRoomMemberView) => `${member.userUuid}_${member.joinedAt}`)
        }
        .width('100%')
        .padding(12)
        .borderRadius(12)
        .backgroundColor(Theme.surface(Theme.isDark()))
      }

      Row({ space: 10 }) {
        Button('刷新状态')
          .height(40)
          .fontSize(13)
          .layoutWeight(1)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          .enabled(!this.busy)
          .onClick(() => {
            this.refreshState();
          })
        Button('离开房间')
          .height(40)
          .fontSize(13)
          .layoutWeight(1)
          .fontColor('#E5484D')
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          .enabled(!this.busy)
          .onClick(() => {
            this.leaveRoom();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(Theme.surface(Theme.isDark()))
  }


  /** build 里直读被跟踪成员注册依赖；颜色本身仍由 Theme 统一决策。 */
  private schemeBg(dark: boolean): string {
    const hasScheme = this.coverScheme.light.background.length > 0;
    return hasScheme ? Theme.background(dark) : Theme.background(dark);
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button('‹')
          .width(40)
          .height(40)
          // '‹' is punctuation to a screen reader; name the action.
          .accessibilityText('返回')
          .type(ButtonType.Circle)
          .backgroundColor(Color.Transparent)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .fontSize(20)
          .onClick(() => Router.pop())
        Text('一起听')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 8, right: 12, top: 8, bottom: 8 })

      Scroll() {
        Column() {
          if (this.sessionView.roomId !== null) {
            this.roomView()
          } else {
            this.joinForm()
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.schemeBg(Theme.isDark()))
  }
}
