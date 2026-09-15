// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Runtime owner for an active Listen Together room.
 *
 * The protocol, policies and player applier are deliberately kept in smaller
 * modules. This class is the lifecycle boundary that joins them: it owns the
 * current session, serialises room-state acceptance, drives the socket timers,
 * and forwards local player commands to the worker.
 */
import { util } from '@kit.ArkTS';
import { Logger } from '../app/Logger';
import { PlayerManager, ListenTogetherPlaybackDelegate, PlayerCommandListener } from '../player/PlayerManager';
import { PlayerManagerListenTogetherSurface } from '../player/ListenTogetherPlayerBinding';
import { SongItem } from '../model/SongItem';
import { PlaybackStatus } from '../player/PlaybackConstants';
import { ListenTogetherPreferences } from '../data/listentogether/ListenTogetherPreferences';
import { resolveListenTogetherServerBaseUrl } from './settings/ListenTogetherServerPreferences';
import { normalizeListenTogetherBaseUrl } from './network/ListenTogetherBaseUrl';
import { ListenTogetherApi } from './network/ListenTogetherApi';
import { ListenTogetherWebSocketClient, ListenTogetherWebSocketListener } from './network/ListenTogetherWebSocketClient';
import { resolveListenTogetherWsUrl } from './network/ListenTogetherWsUrl';
import {
  listenTogetherReconnectDelayMs,
  isTerminalListenTogetherReconnectError,
  LISTEN_TOGETHER_MAX_RECONNECT_ATTEMPTS
} from './network/ListenTogetherReconnectPolicy';
import {
  ListenTogetherConnectionState,
  ListenTogetherSessionState,
  LISTEN_TOGETHER_ROLE_CONTROLLER
} from './protocol/ListenTogetherSessionModels';
import {
  ListenTogetherRoomState,
  ListenTogetherRoomStatuses,
  cloneListenTogetherRoomState,
  ListenTogetherRoomSettings
} from './protocol/ListenTogetherRoomModels';
import {
  ListenTogetherInitialSnapshot,
  ListenTogetherRoomResponse,
  ListenTogetherStateResponse,
  ListenTogetherControlResponse
} from './protocol/ListenTogetherHttpMessages';
import { ListenTogetherSocketEnvelope } from './protocol/ListenTogetherSocketEnvelope';
import { ListenTogetherTrack } from './protocol/ListenTogetherTrack';
import {
  ListenTogetherEvent,
  ListenTogetherCause
} from './protocol/ListenTogetherEventModels';
import { ListenTogetherEventFactory, ListenTogetherLocalPlaybackSnapshot } from './control/ListenTogetherEventFactory';
import {
  ListenTogetherPlaybackCommand,
  ListenTogetherPlaybackCommandSource
} from './control/ListenTogetherPlaybackCommand';
import { ListenTogetherPlayerStateApplier } from './playback/ListenTogetherPlayerStateApplier';
import { LISTEN_TOGETHER_LISTENER_SAFETY_RESUME_CAUSE } from './playback/ListenTogetherListenerSafetyPausePolicy';
import {
  ListenTogetherPlayerStateApplierConfig,
  ListenTogetherPlayerSurface
} from './playback/ListenTogetherPlayerSurface';
import { resolveListenTogetherSessionRole } from './session/ListenTogetherSessionRole';
import { resolveListenTogetherJoinAutoPauseCause } from './session/ListenTogetherJoinPolicy';
import { shouldDropListenTogetherControllerLocalEcho } from './session/ListenTogetherControllerEchoPolicy';
import {
  ListenTogetherRoomStateSource,
  ListenTogetherAcceptedRoomState
} from './session/ListenTogetherRoomStateAcceptance';
import {
  shouldIgnoreListenTogetherIncomingState,
  shouldDeferListenTogetherIncomingStateForLocalTrackFinish,
  shouldRepairListenTogetherListenerState,
  resolveListenTogetherHeartbeatIntervalMs
} from './session/ListenTogetherIncomingStatePolicy';
import { resolveListenTogetherRoomNotice } from './session/ListenTogetherRoomNotice';
import { ListenTogetherRecentEventTracker } from './session/ListenTogetherRecentEventTracker';
import { ListenTogetherServerClockOffset } from './session/ListenTogetherServerClockOffset';
import { ListenTogetherForwardedRequestDeduper } from './session/ListenTogetherForwardedRequestDeduper';
import {
  resolveListenTogetherControlBlockReason,
  shouldRejectForwardedListenTogetherMemberControl
} from './session/ListenTogetherControlBlockPolicy';
import {
  ListenTogetherMembershipCredential,
  listenTogetherMembershipCredentialOrNull,
  resolveReusableListenTogetherMembershipCredential
} from './session/ListenTogetherMembershipCredential';
import { resolveListenTogetherTrackFinishedFallback } from './session/ListenTogetherTrackFinishedFallbackPolicy';
import { ListenTogetherPendingTrackFinishedLegacyFallback, ListenTogetherPendingMemberControlRequest } from './session/ListenTogetherPendingEvents';
import { buildListenTogetherPendingMemberControlRequest, resolveListenTogetherPendingMemberControlRetry } from './session/ListenTogetherPendingMemberControlRetry';
import {
  shouldRecoverMissingListenTogetherMembership,
  isFatalListenTogetherMembershipError,
  canTriggerListenTogetherMembershipRecovery
} from './session/ListenTogetherMembershipRecoveryPolicy';
import {
  LISTEN_TOGETHER_TRACK_SWITCH_GRACE_PERIOD_MS,
  LISTEN_TOGETHER_HEARTBEAT_STATE_RECHECK_INTERVAL_MS,
  LISTEN_TOGETHER_SOCKET_KEEP_ALIVE_INTERVAL_MS,
  LISTEN_TOGETHER_SYNC_WATCHDOG_INTERVAL_MS,
  LISTEN_TOGETHER_LISTENER_WEB_SOCKET_SILENCE_TIMEOUT_MS,
  LISTEN_TOGETHER_LISTENER_STATE_REPAIR_MIN_INTERVAL_MS,
  LISTEN_TOGETHER_CONTROLLER_LOCAL_CONTROL_COOLDOWN_MS,
  LISTEN_TOGETHER_LINK_REQUEST_THROTTLE_MS
} from './session/ListenTogetherSessionRuntimeConstants';
import { isListenTogetherRequestControlEventType } from './control/ListenTogetherControlEventTypes';
import { nextListenTogetherEventId } from './invite/ListenTogetherIdentity';
import {
  listenTogetherTrackWithStreamUrls,
  songItemToListenTogetherTrackOrNull
} from './mapping/ListenTogetherTrackMapping';
import {
  listenTogetherCurrentStableKey,
  listenTogetherRequestedStableKey,
  listenTogetherTargetSongItem,
  sameListenTogetherTrack
} from './playback/ListenTogetherPlaybackTrack';
import { buildListenTogetherForwardedControlSyntheticState } from './control/ListenTogetherForwardedControlState';
import {
  isListenTogetherMemberControlTargetCurrent,
  shouldSuppressListenerControlWhileAwaitingStream,
  buildTrackFinishedLegacyFallbackEvent
} from './compat/ListenTogetherEventCompatibility';
import { isUnsupportedListenTogetherClockSyncPingError } from './session/ListenTogetherServerClockOffset';
import { requireValidListenTogetherRoomCreation } from './validation/ListenTogetherRoomCreationValidation';
import {
  requireValidListenTogetherJoinSecret,
  requireValidListenTogetherNickname,
  requireValidListenTogetherRoomId,
  requireValidListenTogetherUserUuid
} from './validation/ListenTogetherFieldValidation';
import {
  normalizedDirectStreamUrl,
  shouldWaitForListenTogetherAuthoritativeStreamPlayback
} from './playback/ListenTogetherStreamPolicy';
import { trustedListenTogetherStreamUrls } from './mapping/ListenTogetherStreamUrlPolicy';
import { ListenTogetherSessionOperationGate } from './session/ListenTogetherSessionOperationGate';

const TAG: string = 'ListenTogetherSession';
const SESSION_STATE_KEY: string = 'listenTogether.sessionState';
const ROOM_STATE_KEY: string = 'listenTogether.roomState';

function errorMessage(error: Object): string {
  const candidate = error as Error;
  const message = candidate.message;
  return message === undefined || message.trim().length === 0 ? 'Listen Together operation failed' : message;
}

class ListenTogetherSessionSocketListener implements ListenTogetherWebSocketListener {
  private readonly openHandler: () => void;
  private readonly messageHandler: (message: ListenTogetherSocketEnvelope) => void;
  private readonly closedHandler: (code: number, reason: string) => void;
  private readonly failureHandler: (error: Error) => void;
  private readonly protocolErrorHandler: (raw: string, error: Error) => void;

  constructor(
    openHandler: () => void,
    messageHandler: (message: ListenTogetherSocketEnvelope) => void,
    closedHandler: (code: number, reason: string) => void,
    failureHandler: (error: Error) => void,
    protocolErrorHandler: (raw: string, error: Error) => void
  ) {
    this.openHandler = openHandler;
    this.messageHandler = messageHandler;
    this.closedHandler = closedHandler;
    this.failureHandler = failureHandler;
    this.protocolErrorHandler = protocolErrorHandler;
  }

  onOpen(): void { this.openHandler(); }
  onMessage(message: ListenTogetherSocketEnvelope): void { this.messageHandler(message); }
  onClosed(code: number, reason: string): void { this.closedHandler(code, reason); }
  onFailure(error: Error): void { this.failureHandler(error); }
  onProtocolError(raw: string, error: Error): void { this.protocolErrorHandler(raw, error); }
}

export class ListenTogetherSessionManager implements ListenTogetherPlaybackDelegate, PlayerCommandListener {
  private static instance: ListenTogetherSessionManager | null = null;

  static getInstance(): ListenTogetherSessionManager {
    if (ListenTogetherSessionManager.instance === null) {
      ListenTogetherSessionManager.instance = new ListenTogetherSessionManager();
    }
    return ListenTogetherSessionManager.instance;
  }

  private readonly api: ListenTogetherApi;
  private readonly webSocketClient: ListenTogetherWebSocketClient;
  private readonly surface: ListenTogetherPlayerSurface;
  private readonly clientInstanceId: string = util.generateRandomUUID(false);
  private readonly recentEvents: ListenTogetherRecentEventTracker = new ListenTogetherRecentEventTracker();
  private readonly clockOffset: ListenTogetherServerClockOffset = new ListenTogetherServerClockOffset();
  private readonly forwardedRequestDeduper: ListenTogetherForwardedRequestDeduper = new ListenTogetherForwardedRequestDeduper();
  private readonly sessionState: ListenTogetherSessionState = new ListenTogetherSessionState();
  private readonly operationGate: ListenTogetherSessionOperationGate = new ListenTogetherSessionOperationGate();
  private roomState: ListenTogetherRoomState | null = null;
  private readonly eventFactory: ListenTogetherEventFactory;
  private readonly stateApplier: ListenTogetherPlayerStateApplier;
  private commandSequence: number = 0;
  private acceptedVersion: number = -1;
  private started: boolean = false;
  private reconnectEnabled: boolean = false;
  private reconnectAttempt: number = 0;
  private awaitingTrackFinishStableKey: string | null = null;
  private lastSocketMessageAtMs: number = 0;
  private lastStateRefreshAtMs: number = 0;
  private pendingRepairVersion: number = -1;
  private heartbeatTimer: number = -1;
  private keepAliveTimer: number = -1;
  private watchdogTimer: number = -1;
  private reconnectTimer: number = -1;
  private pendingTrackFinishedFallback: ListenTogetherPendingTrackFinishedLegacyFallback | null = null;
  private pendingMemberControlRequest: ListenTogetherPendingMemberControlRequest | null = null;
  private retainedCredential: ListenTogetherMembershipCredential | null = null;
  private lastOutboundSyncAtMs: number = 0;
  private lastControllerLocalControlAtMs: number = 0;
  private membershipRecoveryGeneration: number = -1;
  private lastRequestedLinkStableKey: string | null = null;
  private lastRequestedLinkAtMs: number = 0;
  private controllerLinkResolveStableKey: string | null = null;

  private constructor(
    api: ListenTogetherApi = new ListenTogetherApi(),
    webSocketClient: ListenTogetherWebSocketClient = new ListenTogetherWebSocketClient(),
    surface: ListenTogetherPlayerSurface = PlayerManagerListenTogetherSurface.getInstance()
  ) {
    this.api = api;
    this.webSocketClient = webSocketClient;
    this.surface = surface;
    this.eventFactory = new ListenTogetherEventFactory(
      () => this.roomState,
      () => this.isCurrentUserController(),
      () => this.localPlaybackSnapshot(),
      () => nextListenTogetherEventId(),
      () => this.clientInstanceId,
      () => this.nextClientSequence(),
      () => Date.now(),
      (message: string): void => Logger.warn(message)
    );
    this.stateApplier = new ListenTogetherPlayerStateApplier(
      new ListenTogetherPlayerStateApplierConfig(
        TAG, 500, 5000, 2500, 800, 600, 1500,
        LISTEN_TOGETHER_TRACK_SWITCH_GRACE_PERIOD_MS, 2000
      ),
      surface,
      () => this.roomState,
      () => this.isCurrentUserController(),
      () => this.clockOffset.estimatedOffsetMs()
    );
  }

  start(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    PlayerManager.addCommandListener(this);
    PlayerManager.setListenTogetherDelegate(this);
  }

  async destroy(): Promise<void> {
    this.operationGate.begin();
    this.reconnectEnabled = false;
    this.stopTimers();
    PlayerManager.removeCommandListener(this);
    PlayerManager.setListenTogetherDelegate(null);
    this.started = false;
    await this.webSocketClient.disconnect();
    this.forwardedRequestDeduper.clear();
    this.recentEvents.clear();
    this.pendingTrackFinishedFallback = null;
    this.pendingMemberControlRequest = null;
    this.awaitingTrackFinishStableKey = null;
    this.lastOutboundSyncAtMs = 0;
    this.lastControllerLocalControlAtMs = 0;
    this.lastRequestedLinkStableKey = null;
    this.lastRequestedLinkAtMs = 0;
    this.controllerLinkResolveStableKey = null;
    this.pendingRepairVersion = -1;
    this.lastSocketMessageAtMs = 0;
    this.lastStateRefreshAtMs = 0;
    this.membershipRecoveryGeneration = -1;
    this.retainedCredential = null;
    this.reconnectAttempt = 0;
    PlayerManager.clearListenTogetherSafetyPause();
    PlayerManager.resetListenTogetherSyncPlaybackRate();
    this.roomState = null;
    this.acceptedVersion = -1;
    this.sessionState.connectionState = ListenTogetherConnectionState.DISCONNECTED;
    this.sessionState.baseUrl = null;
    this.sessionState.roomId = null;
    this.sessionState.userUuid = null;
    this.sessionState.nickname = null;
    this.sessionState.wsUrl = null;
    this.sessionState.token = null;
    this.sessionState.memberSecret = null;
    this.sessionState.joinSecret = null;
    this.sessionState.role = null;
    this.sessionState.lastError = null;
    this.sessionState.expectedPositionMs = null;
    this.sessionState.roomNotice = null;
    this.clockOffset.reset();
    this.publishStates();
  }

  isListenTogetherActive(): boolean { return this.sessionState.roomId !== null; }
  isCurrentUserController(): boolean {
    return resolveListenTogetherSessionRole(
      this.sessionState.userUuid,
      this.sessionState.role,
      this.roomState
    ) === LISTEN_TOGETHER_ROLE_CONTROLLER;
  }
  shouldUseListenerSafetyPause(): boolean {
    return this.isListenTogetherActive() && !this.isCurrentUserController() &&
      this.roomState?.settings.allowMemberControl === false;
  }
  requestListenerSafetyResume(): void {
    const roomId = this.sessionState.roomId;
    if (roomId === null || this.isCurrentUserController()) {
      PlayerManager.retryListenTogetherSafetyPauseResume();
      return;
    }
    this.refreshRoomState().then((response: ListenTogetherStateResponse | null): void => {
      if (this.sessionState.roomId !== roomId) {
        PlayerManager.clearListenTogetherSafetyPause();
        return;
      }
      if (response === null || !response.ok || response.state === null) {
        PlayerManager.retryListenTogetherSafetyPauseResume();
        this.sessionState.lastError = response?.error ?? 'listener_safety_resume_state_unavailable';
        this.publishStates();
        return;
      }
      if (this.sessionState.roomId !== roomId || this.isCurrentUserController()) {
        PlayerManager.clearListenTogetherSafetyPause();
        return;
      }
      const latest = this.roomState !== null && this.roomState.roomId === roomId
        ? this.roomState
        : response.state;
      const expectedPositionMs = latest.version === response.state.version
        ? response.expectedPositionMs
        : null;
      if (this.stateApplier.apply(
        latest,
        LISTEN_TOGETHER_LISTENER_SAFETY_RESUME_CAUSE,
        expectedPositionMs
      )) {
        PlayerManager.completeListenTogetherSafetyPauseResume();
      } else {
        PlayerManager.retryListenTogetherSafetyPauseResume();
      }
    }).catch((error: Object): void => {
      PlayerManager.retryListenTogetherSafetyPauseResume();
      this.sessionState.lastError = errorMessage(error);
      this.publishStates();
      Logger.warn(errorMessage(error));
    });
  }
  shouldWaitForAuthoritativeStream(song: SongItem): boolean {
    const target = this.authoritativeStreamTargetFor(song);
    if (target === null) {
      return false;
    }
    return this.trustedRoomStreamUrls(target).length === 0;
  }
  resolveAuthoritativeStreamUrls(song: SongItem): string[] {
    const target = this.authoritativeStreamTargetFor(song);
    return target === null ? [] : this.trustedRoomStreamUrls(target);
  }
  resumeListenerAfterSafetyPause(): void { this.requestListenerSafetyResume(); }

  async createRoom(
    baseUrl: string = resolveListenTogetherServerBaseUrl(),
    queue: SongItem[] = PlayerManager.getQueue(),
    currentIndex: number = PlayerManager.getCurrentQueueIndex(),
    positionMs: number = PlayerManager.getPositionMs(),
    isPlaying: boolean = PlayerManager.getStatus() === PlaybackStatus.PLAYING,
    settings: ListenTogetherRoomSettings = this.roomState?.settings ?? new ListenTogetherRoomSettings()
  ): Promise<ListenTogetherRoomResponse> {
    const operationGeneration = this.operationGate.begin();
    requireValidListenTogetherRoomCreation(queue, currentIndex, PlayerManager.getCurrentSong());
    const normalizedBaseUrl = normalizeListenTogetherBaseUrl(baseUrl);
    const userUuid = requireValidListenTogetherUserUuid(ListenTogetherPreferences.getOrCreateUserUuid());
    const nickname = requireValidListenTogetherNickname(ListenTogetherPreferences.getOrCreateNickname());
    const snapshot = new ListenTogetherInitialSnapshot();
    snapshot.queue = this.eventFactory.buildSetTrackEvent(queue, currentIndex, positionMs, isPlaying).queue ?? [];
    snapshot.currentIndex = Math.min(Math.max(currentIndex, 0), Math.max(snapshot.queue.length - 1, 0));
    snapshot.track = snapshot.queue.length > 0 ? snapshot.queue[snapshot.currentIndex] : null;
    snapshot.settings = settings;
    snapshot.isPlaying = isPlaying;
    snapshot.positionMs = Math.max(positionMs, 0);
    snapshot.repeatMode = PlayerManager.getRepeatMode();
    snapshot.shuffleEnabled = PlayerManager.isShuffleEnabled();
    const response = await this.api.createRoom(normalizedBaseUrl, userUuid, nickname, snapshot);
    if (!this.operationGate.isCurrent(operationGeneration)) {
      return response;
    }
    this.updateSession(normalizedBaseUrl, response);
    if (response.ok) {
      this.connectWebSocket();
    }
    return response;
  }

  async joinRoom(
    roomId: string,
    baseUrl: string = resolveListenTogetherServerBaseUrl(),
    joinSecret: string | null = null
  ): Promise<ListenTogetherRoomResponse> {
    return await this.joinRoomWithIdentity(
      roomId,
      baseUrl,
      joinSecret,
      ListenTogetherPreferences.getOrCreateUserUuid(),
      ListenTogetherPreferences.getOrCreateNickname(),
      this.operationGate.begin()
    );
  }

  private async joinRoomWithIdentity(
    roomId: string,
    baseUrl: string,
    joinSecret: string | null,
    requestedUserUuid: string,
    requestedNickname: string,
    operationGeneration: number
  ): Promise<ListenTogetherRoomResponse> {
    const normalizedBaseUrl = normalizeListenTogetherBaseUrl(baseUrl);
    const userUuid = requireValidListenTogetherUserUuid(requestedUserUuid);
    const nickname = requireValidListenTogetherNickname(requestedNickname);
    const normalizedRoomId = requireValidListenTogetherRoomId(roomId);
    const reusable = resolveReusableListenTogetherMembershipCredential(
      this.sessionState,
      this.retainedCredential,
      normalizedBaseUrl,
      normalizedRoomId,
      userUuid
    );
    const explicitJoinSecret = joinSecret === null || joinSecret.trim().length === 0
      ? null
      : requireValidListenTogetherJoinSecret(joinSecret);
    const resolvedJoinSecret = explicitJoinSecret ?? reusable?.joinSecret ?? null;
    const hasReusableMembership = reusable?.memberSecret !== null || reusable?.token !== null;
    const validatedJoinSecret = hasReusableMembership
      ? resolvedJoinSecret
      : requireValidListenTogetherJoinSecret(resolvedJoinSecret);
    const response = await this.api.joinRoom(
      normalizedBaseUrl,
      normalizedRoomId,
      userUuid,
      nickname,
      reusable?.memberSecret ?? null,
      validatedJoinSecret,
      reusable?.token ?? null
    );
    if (!this.operationGate.isCurrent(operationGeneration)) {
      return response;
    }
    this.updateSession(normalizedBaseUrl, response, userUuid, nickname);
    if (response.ok) {
      this.connectWebSocket();
    }
    return response;
  }

  async refreshRoomState(): Promise<ListenTogetherStateResponse | null> {
    const baseUrl = this.sessionState.baseUrl;
    const roomId = this.sessionState.roomId;
    if (baseUrl === null || roomId === null) {
      return null;
    }
    const operationGeneration = this.operationGate.begin();
    const sentAtMs = Date.now();
    try {
      const response = await this.api.getRoomState(baseUrl, roomId, this.sessionState.token);
      const receivedAtMs = Date.now();
      if (!this.operationGate.isCurrent(operationGeneration) || this.sessionState.roomId !== roomId) {
        return null;
      }
      this.lastStateRefreshAtMs = receivedAtMs;
      this.clockOffset.acceptHttpRoundTrip(
        response.serverNowMs,
        sentAtMs,
        sentAtMs,
        receivedAtMs,
        receivedAtMs
      );
      if (response.state !== null && response.ok) {
        this.acceptRoomState(response.state, response.expectedPositionMs, ListenTogetherRoomStateSource.HTTP_REFRESH, null);
        if (response.state.roomStatus === ListenTogetherRoomStatuses.CLOSED) {
          this.closeRoomLocally(response.state.closedReason ?? 'room_closed');
          return response;
        }
        if (!this.isCurrentUserController()) {
          this.applyRoomState(response.state, 'HTTP_REFRESH', response.expectedPositionMs);
          this.maybeRequestControllerLink(response.state, 'HTTP_REFRESH');
        }
      }
      if (!response.ok) {
        const message = response.error ?? 'room state rejected';
        this.sessionState.lastError = message;
        if (this.handleHttpSessionError(message, 'http_state_refresh')) {
          return response;
        }
      } else {
        this.sessionState.lastError = null;
      }
      this.publishStates();
      return response;
    } catch (error) {
      if (!this.operationGate.isCurrent(operationGeneration) || this.sessionState.roomId !== roomId) {
        return null;
      }
      const message = errorMessage(error);
      this.sessionState.lastError = message;
      this.publishStates();
      if (isTerminalListenTogetherReconnectError(message)) {
        this.closeRoomLocally(message);
      }
      throw new Error(message);
    }
  }

  async leaveRoom(): Promise<void> {
    const baseUrl = this.sessionState.baseUrl;
    const roomId = this.sessionState.roomId;
    const token = this.sessionState.token;
    this.closeRoomLocally(null);
    if (baseUrl !== null && roomId !== null && token !== null && token.trim().length > 0) {
      try { await this.api.leaveRoom(baseUrl, roomId, token); } catch (error) { Logger.warn(errorMessage(error)); }
    }
  }

  connectWebSocket(): void {
    if (!this.sessionState.wsUrl || !this.sessionState.roomId) {
      return;
    }
    this.reconnectEnabled = true;
    this.clearReconnectTimer();
    this.sessionState.connectionState = ListenTogetherConnectionState.CONNECTING;
    this.publishStates();
    const operationGeneration = this.operationGate.current();
    const roomId = this.sessionState.roomId;
    this.webSocketClient.connect(this.sessionState.wsUrl, this.socketListener()).then((): void => {
      // connect() resolves when the request is accepted, not when the handshake succeeds.
    }).catch((error: Object): void => {
      if (this.operationGate.isCurrent(operationGeneration) && this.sessionState.roomId === roomId) {
        this.onSocketFailure(errorMessage(error));
      }
    });
  }

  disconnectWebSocket(): void {
    this.operationGate.begin();
    this.reconnectEnabled = false;
    this.stopTimers();
    this.webSocketClient.disconnect().catch((error: Object): void => Logger.warn(errorMessage(error)));
    this.sessionState.connectionState = ListenTogetherConnectionState.DISCONNECTED;
    this.sessionState.roomNotice = null;
    this.forwardedRequestDeduper.clear();
    this.pendingTrackFinishedFallback = null;
    this.pendingMemberControlRequest = null;
    this.awaitingTrackFinishStableKey = null;
    this.pendingRepairVersion = -1;
    this.lastOutboundSyncAtMs = 0;
    this.lastControllerLocalControlAtMs = 0;
    this.lastRequestedLinkStableKey = null;
    this.lastRequestedLinkAtMs = 0;
    this.controllerLinkResolveStableKey = null;
    this.lastSocketMessageAtMs = 0;
    this.lastStateRefreshAtMs = 0;
    this.clockOffset.reset();
    PlayerManager.resetListenTogetherSyncPlaybackRate();
    this.publishStates();
  }

  onPlaybackCommand(command: ListenTogetherPlaybackCommand): void {
    if (command.source !== ListenTogetherPlaybackCommandSource.LOCAL || !this.isListenTogetherActive() ||
      this.sessionState.connectionState !== ListenTogetherConnectionState.CONNECTED) {
      return;
    }
    const block = resolveListenTogetherControlBlockReason(this.sessionState.role, this.roomState, command.type);
    if (block !== null) {
      this.sessionState.lastError = block;
      this.publishStates();
      return;
    }
    const event = this.eventFactory.buildEventForPlaybackCommand(command);
    if (event === null) {
      return;
    }
    if (this.shouldSuppressLocalListenerControlEvent(event)) {
      return;
    }
    const now = Date.now();
    this.lastOutboundSyncAtMs = now;
    this.markOutbound(event.eventId);
    this.pendingMemberControlRequest = buildListenTogetherPendingMemberControlRequest(
      event,
      this.isCurrentUserController(),
      now
    );
    if (event.type === 'TRACK_FINISHED') {
      this.awaitingTrackFinishStableKey = event.finishedTrackStableKey;
      const fallback = buildTrackFinishedLegacyFallbackEvent(
        event,
        this.isCurrentUserController(),
        now,
        (): string => nextListenTogetherEventId()
      );
      this.pendingTrackFinishedFallback = fallback === null
        ? null
        : new ListenTogetherPendingTrackFinishedLegacyFallback(fallback, now);
    } else {
      this.awaitingTrackFinishStableKey = null;
      this.pendingTrackFinishedFallback = null;
    }
    if (this.isCurrentUserController()) {
      this.lastControllerLocalControlAtMs = now;
    }
    this.sendEvent(event).catch((error: Object): void => Logger.warn(errorMessage(error)));
  }

  private async sendEvent(event: ListenTogetherEvent): Promise<boolean> {
    if (this.sessionState.connectionState === ListenTogetherConnectionState.CONNECTED) {
      const sent = await this.webSocketClient.sendEvent(event);
      if (sent) {
        return true;
      }
    }
    const baseUrl = this.sessionState.baseUrl;
    const roomId = this.sessionState.roomId;
    const token = this.sessionState.token;
    if (baseUrl === null || roomId === null || token === null) {
      return false;
    }
    const operationGeneration = this.operationGate.current();
    let response: ListenTogetherControlResponse;
    try {
      response = await this.api.sendControlEvent(baseUrl, roomId, token, event);
    } catch (error) {
      if (!this.operationGate.isCurrent(operationGeneration) || this.sessionState.roomId !== roomId) {
        return false;
      }
      const message = errorMessage(error);
      this.sessionState.lastError = message;
      this.publishStates();
      this.handleHttpSessionError(message, 'http_control');
      throw new Error(message);
    }
    if (!this.operationGate.isCurrent(operationGeneration) || this.sessionState.roomId !== roomId) {
      return false;
    }
    if (!response.ok || response.error !== null) {
      const message = response.error ?? 'control event rejected';
      this.sessionState.lastError = message;
      this.publishStates();
      if (this.trySendTrackFinishedLegacyFallback(message)) {
        return true;
      }
      this.handleHttpSessionError(message, 'http_control_response');
      return false;
    }
    this.sessionState.lastError = null;
    const applied = response.applied;
    if (applied !== null && applied.state !== null) {
      const accepted = this.acceptRoomState(
        applied.state,
        applied.expectedPositionMs,
        ListenTogetherRoomStateSource.HTTP_CONTROL_FALLBACK,
        applied.causedBy
      );
      if (accepted !== null && !this.isCurrentUserController()) {
        this.applyRoomState(
          accepted.state,
          applied.causedBy?.type ?? event.type,
          accepted.expectedPositionMs
        );
        this.maybeRequestControllerLink(
          accepted.state,
          applied.causedBy?.type ?? event.type
        );
      }
    }
    this.publishStates();
    return response.ok;
  }

  private socketListener(): ListenTogetherWebSocketListener {
    return new ListenTogetherSessionSocketListener(
      (): void => this.onSocketOpen(),
      (message: ListenTogetherSocketEnvelope): void => this.onSocketMessage(message),
      (code: number, reason: string): void => this.onSocketClosed(code, reason),
      (error: Error): void => this.onSocketFailure(errorMessage(error)),
      (_raw: string, error: Error): void => this.onSocketFailure(errorMessage(error))
    );
  }

  private onSocketOpen(): void {
    if (!this.reconnectEnabled || this.sessionState.roomId === null) {
      Logger.info('LT socket open ignored (disabled or no room), disconnecting');
      this.disconnectWebSocket();
      return;
    }
    this.reconnectAttempt = 0;
    this.lastSocketMessageAtMs = Date.now();
    this.sessionState.connectionState = ListenTogetherConnectionState.CONNECTED;
    Logger.info(`LT socket open -> CONNECTED (room ${this.sessionState.roomId})`);
    this.sessionState.lastError = null;
    this.startTimers();
    this.refreshRoomState().catch((error: Object): void => Logger.warn(errorMessage(error)));
    if (this.roomState !== null) {
      this.maybeRequestControllerLink(this.roomState, 'SOCKET_OPEN');
    }
    this.publishStates();
  }

  private onSocketMessage(message: ListenTogetherSocketEnvelope): void {
    if (this.sessionState.roomId === null) {
      return;
    }
    if (message.roomId !== null && message.roomId !== this.sessionState.roomId) {
      return;
    }
    this.lastSocketMessageAtMs = Date.now();
    if (message.type === 'pong' || message.type === 'np_pong') {
      if (message.type === 'np_pong') {
        this.clockOffset.markClockSyncPingSupported();
      }
      this.clockOffset.acceptPong(message.nowMs, message.t, Date.now(), Date.now());
      this.sessionState.lastError = null;
      this.publishStates();
      return;
    }
    const serverNowMs = message.nowMs ?? message.result?.applied?.nowMs ?? null;
    if (serverNowMs !== null) {
      this.clockOffset.acceptServerMessage(serverNowMs, Date.now());
    }
    if (message.type === 'welcome' || message.type === 'room_state_updated' ||
      message.type === 'room_suspended' || message.type === 'room_resumed') {
      if (message.state !== null) {
        if (!this.shouldIgnoreState(message.causedBy) &&
          !shouldDeferListenTogetherIncomingStateForLocalTrackFinish(message.state, message.causedBy, this.awaitingTrackFinishStableKey)) {
          const accepted = this.acceptRoomState(
            message.state,
            message.expectedPositionMs,
            message.type === 'room_suspended' || message.type === 'room_resumed'
              ? ListenTogetherRoomStateSource.WEB_SOCKET_ROOM_STATUS
              : ListenTogetherRoomStateSource.WEB_SOCKET_STATE,
            message.causedBy
          );
          if (accepted !== null) {
            if (message.message !== null) {
              this.sessionState.roomNotice = resolveListenTogetherRoomNotice(accepted.state, message.message);
              this.publishStates();
            }
            if (message.causedBy?.type === 'TRACK_FINISHED') {
              this.awaitingTrackFinishStableKey = null;
              this.pendingTrackFinishedFallback = null;
            }
            const localEcho = this.isCurrentUserController() &&
              shouldDropListenTogetherControllerLocalEcho(
                accepted.state,
                message.causedBy,
                this.acceptedVersion - 1,
                this.sessionState.userUuid,
                this.lastControllerLocalControlAtMs,
                Date.now(),
                LISTEN_TOGETHER_CONTROLLER_LOCAL_CONTROL_COOLDOWN_MS
              );
            if (!localEcho) {
              this.applyRoomState(accepted.state, message.causedBy?.type ?? message.type, accepted.expectedPositionMs);
              this.maybeRequestControllerLink(accepted.state, message.causedBy?.type ?? message.type);
            }
          }
        }
      }
      return;
    }
    if (message.type === 'link_requested') {
      this.handleLinkRequested(message);
      return;
    }
    if (message.type === 'member_control_requested') {
      this.handleMemberControlRequested(message);
      return;
    }
    if (message.type === 'room_closed') {
      if (message.state !== null) {
        this.acceptRoomState(message.state, message.expectedPositionMs, ListenTogetherRoomStateSource.WEB_SOCKET_ROOM_CLOSED, message.causedBy);
      }
      this.closeRoomLocally(message.message ?? 'room_closed');
      return;
    }
    if (message.type === 'control_result' || message.type === 'ack') {
      const resultError = message.result?.error ?? (message.ok === false ? message.message : null);
      const applied = message.result?.applied;
      if (applied !== null && applied !== undefined && applied.state !== null) {
        const accepted = this.acceptRoomState(
          applied.state,
          applied.expectedPositionMs,
          ListenTogetherRoomStateSource.WEB_SOCKET_CONTROL_RESULT,
          applied.causedBy
        );
        if (accepted !== null && (!this.isCurrentUserController() || applied.causedBy?.userUuid === this.sessionState.userUuid)) {
          this.applyRoomState(accepted.state, applied.causedBy?.type ?? message.type, accepted.expectedPositionMs);
          if (!this.isCurrentUserController()) {
            this.maybeRequestControllerLink(accepted.state, applied.causedBy?.type ?? message.type);
          }
        }
        if (applied.causedBy?.type === 'TRACK_FINISHED' && resultError === null) {
          this.awaitingTrackFinishStableKey = null;
          this.pendingTrackFinishedFallback = null;
        }
        if (applied.causedBy !== null && isListenTogetherRequestControlEventType(applied.causedBy.type ?? '') &&
          applied.causedBy.userUuid === this.sessionState.userUuid) {
          this.pendingMemberControlRequest = null;
        }
      }
      if (resultError !== null && resultError.trim().length > 0) {
        if (this.handleUnsupportedClockSyncPingError(resultError)) {
          return;
        }
        if (this.trySendTrackFinishedLegacyFallback(resultError)) {
          return;
        }
        this.sessionState.lastError = resultError;
        this.publishStates();
        this.handleHttpSessionError(resultError, 'socket_control_result');
      }
      return;
    }
    if (message.type === 'error') {
      const error = message.message ?? 'socket error';
      if (this.handleUnsupportedClockSyncPingError(error)) {
        return;
      }
      this.sessionState.lastError = error;
      this.publishStates();
      this.handleHttpSessionError(error, 'socket_error');
    }
  }

  private onSocketClosed(code: number, reason: string): void {
    this.stopTimers();
    Logger.info(`LT socket closed: code=${code} reason=${reason}`);
    if (!this.reconnectEnabled) {
      return;
    }
    this.sessionState.connectionState = ListenTogetherConnectionState.DISCONNECTED;
    this.sessionState.lastError = reason.length > 0 ? reason : `socket_closed:${code}`;
    if (isTerminalListenTogetherReconnectError(this.sessionState.lastError)) {
      this.closeRoomLocally(this.sessionState.lastError);
      return;
    }
    this.scheduleReconnect(this.sessionState.lastError);
  }

  private onSocketFailure(message: string): void {
    this.stopTimers();
    this.sessionState.connectionState = ListenTogetherConnectionState.DISCONNECTED;
    this.sessionState.lastError = message;
    Logger.warn(`LT socket failure: ${message}`);
    this.publishStates();
    if (isTerminalListenTogetherReconnectError(message)) {
      this.closeRoomLocally(message);
      return;
    }
    if (!this.reconnectEnabled) {
      return;
    }
    this.scheduleReconnect(message);
  }

  private scheduleReconnect(reason: string): void {
    if (!this.reconnectEnabled || this.sessionState.wsUrl === null) {
      return;
    }
    if (this.reconnectAttempt >= LISTEN_TOGETHER_MAX_RECONNECT_ATTEMPTS) {
      const roomId = this.sessionState.roomId;
      this.refreshRoomState().then((response: ListenTogetherStateResponse | null): void => {
        if (!this.reconnectEnabled || roomId === null || this.sessionState.roomId !== roomId) {
          return;
        }
        if (response !== null && response.ok && this.reconnectEnabled) {
          this.reconnectAttempt = 0;
          this.connectWebSocket();
          return;
        }
        if (response !== null && !response.ok) {
          const message = response.error ?? 'room state rejected';
          if (this.handleHttpSessionError(message, 'reconnect_exhausted_state')) {
            return;
          }
          this.closeRoomLocally(message);
        }
      }).catch((error: Object): void => {
        if (!this.reconnectEnabled || roomId === null || this.sessionState.roomId !== roomId) {
          return;
        }
        const message = errorMessage(error);
        if (!isTerminalListenTogetherReconnectError(message) && this.triggerListenerMembershipRecovery('reconnect_exhausted')) {
          return;
        }
        this.closeRoomLocally(message);
      });
      return;
    }
    this.clearReconnectTimer();
    this.reconnectAttempt++;
    const delay = listenTogetherReconnectDelayMs(this.reconnectAttempt);
    this.reconnectTimer = setTimeout((): void => {
      this.reconnectTimer = -1;
      this.connectWebSocket();
    }, delay);
    this.publishStates();
  }

  private acceptRoomState(
    state: ListenTogetherRoomState,
    expectedPositionMs: number | null,
    _source: ListenTogetherRoomStateSource,
    cause: ListenTogetherCause | null
  ): ListenTogetherAcceptedRoomState | null {
    if (this.sessionState.roomId === null || state.roomId !== this.sessionState.roomId || state.version < this.acceptedVersion) {
      return null;
    }
    if (this.isCurrentUserController() && shouldDropListenTogetherControllerLocalEcho(
      state,
      cause,
      this.acceptedVersion,
      this.sessionState.userUuid,
      this.lastControllerLocalControlAtMs,
      Date.now(),
      LISTEN_TOGETHER_CONTROLLER_LOCAL_CONTROL_COOLDOWN_MS
    )) {
      return null;
    }
    if (this.acceptedVersion >= 0 && state.version > this.acceptedVersion + 1) {
      this.pendingRepairVersion = state.version;
    }
    if (cause !== null && cause.userUuid === this.sessionState.userUuid && cause.type !== 'TRACK_FINISHED') {
      this.markInbound(cause.eventId);
    }
    if (state.version === this.acceptedVersion && this.roomState !== null) {
      this.sessionState.expectedPositionMs = expectedPositionMs;
      this.sessionState.roomNotice = resolveListenTogetherRoomNotice(state, null);
      this.publishStates();
      return new ListenTogetherAcceptedRoomState(this.roomState, expectedPositionMs);
    }
    this.acceptedVersion = state.version;
    if (this.pendingRepairVersion >= 0 && state.version >= this.pendingRepairVersion) {
      this.pendingRepairVersion = -1;
    }
    this.roomState = cloneListenTogetherRoomState(state);
    this.sessionState.role = resolveListenTogetherSessionRole(this.sessionState.userUuid, this.sessionState.role, state);
    this.sessionState.expectedPositionMs = expectedPositionMs;
    this.sessionState.roomNotice = resolveListenTogetherRoomNotice(state, null);
    if (this.awaitingTrackFinishStableKey !== null && listenTogetherCurrentStableKey(state) !== this.awaitingTrackFinishStableKey) {
      this.awaitingTrackFinishStableKey = null;
    }
    if (state.roomStatus === ListenTogetherRoomStatuses.CLOSED) {
      this.reconnectEnabled = false;
    }
    if (shouldRecoverMissingListenTogetherMembership(
      state,
      this.sessionState.userUuid,
      this.isCurrentUserController()
    )) {
      this.triggerListenerMembershipRecovery('state_missing_member');
    }
    this.publishStates();
    return new ListenTogetherAcceptedRoomState(this.roomState, expectedPositionMs);
  }

  private applyRoomState(state: ListenTogetherRoomState, causeType: string, expectedPositionMs: number | null): void {
    if (this.isCurrentUserController() && causeType !== 'TRACK_FINISHED') {
      return;
    }
    this.stateApplier.apply(state, causeType, expectedPositionMs);
  }

  private shouldIgnoreState(cause: ListenTogetherCause | null): boolean {
    return shouldIgnoreListenTogetherIncomingState(
      cause,
      this.sessionState.userUuid,
      (eventId: string): boolean => this.recentEvents.hasOutbound(eventId),
      (eventId: string): boolean => this.recentEvents.hasInbound(eventId)
    );
  }

  private shouldSuppressLocalListenerControlEvent(event: ListenTogetherEvent): boolean {
    if (this.isCurrentUserController() || !isListenTogetherRequestControlEventType(event.type)) {
      return false;
    }
    const currentStableKey = this.roomState === null ? null : listenTogetherCurrentStableKey(this.roomState);
    const requestedStableKey = listenTogetherRequestedStableKey(event);
    if (!isListenTogetherMemberControlTargetCurrent(event.type, requestedStableKey, currentStableKey)) {
      Logger.warn(`ListenTogether listener control target is stale: ${event.type}`);
      return true;
    }
    if (this.roomState === null) {
      return false;
    }
    const target = listenTogetherTargetSongItem(this.roomState);
    const currentSong = PlayerManager.getCurrentSong();
    const awaitingStream = target !== null && shouldWaitForListenTogetherAuthoritativeStreamPlayback(
      this.shouldWaitForAuthoritativeStream(target),
      currentSong !== null && sameListenTogetherTrack(currentSong, target),
      currentSong === null ? null : currentSong.streamUrl,
      PlayerManager.getCurrentMediaUrl()
    );
    const localDirectStream = normalizedDirectStreamUrl(currentSong === null ? null : currentSong.streamUrl) !== null ||
      normalizedDirectStreamUrl(PlayerManager.getCurrentMediaUrl()) !== null;
    if (shouldSuppressListenerControlWhileAwaitingStream(event.type, awaitingStream, localDirectStream)) {
      this.maybeRequestControllerLink(this.roomState, `SUPPRESS_LOCAL_CONTROL:${event.type}`, true);
      return true;
    }
    return false;
  }

  private handleMemberControlRequested(message: ListenTogetherSocketEnvelope): void {
    if (!this.isCurrentUserController() || this.roomState === null) {
      return;
    }
    const requester = message.causedBy === null ? null : message.causedBy.userUuid;
    const sequence = message.requestSequence;
    const eventId = message.causedBy === null ? null : message.causedBy.eventId;
    if (!this.forwardedRequestDeduper.shouldProcess(requester, sequence, eventId)) {
      return;
    }
    const committed = this.eventFactory.buildControllerCommitEventFromForwardedRequest(message);
    if (committed === null) {
      return;
    }
    const allow = this.roomState.settings.allowMemberControl;
    if (shouldRejectForwardedListenTogetherMemberControl(
      requester,
      this.roomState.controllerUserUuid ?? this.roomState.controllerUserId,
      allow
    )) {
      return;
    }
    const requestType = message.causedBy === null ? null : message.causedBy.type;
    if (requestType !== null && !isListenTogetherMemberControlTargetCurrent(
      requestType,
      listenTogetherRequestedStableKey(committed),
      listenTogetherCurrentStableKey(this.roomState)
    )) {
      return;
    }
    if (Date.now() - this.lastControllerLocalControlAtMs < LISTEN_TOGETHER_CONTROLLER_LOCAL_CONTROL_COOLDOWN_MS) {
      return;
    }
    const synthetic = buildListenTogetherForwardedControlSyntheticState(
      this.roomState,
      message,
      committed,
      Date.now()
    );
    this.roomState = synthetic;
    this.sessionState.expectedPositionMs = committed.positionMs ?? message.expectedPositionMs;
    this.publishStates();
    this.stateApplier.apply(synthetic, requestType ?? committed.type, this.sessionState.expectedPositionMs);
    this.lastOutboundSyncAtMs = Date.now();
    this.markOutbound(committed.eventId);
    this.sendEvent(committed).catch((error: Object): void => Logger.warn(errorMessage(error)));
  }

  private handleLinkRequested(message: ListenTogetherSocketEnvelope): void {
    if (!this.isCurrentUserController()) {
      return;
    }
    const stableKey = message.requestTrackStableKey ?? message.track?.stableKey;
    if (stableKey === null || stableKey === undefined || stableKey.trim().length === 0) {
      Logger.warn('ListenTogether link request missing stable key');
      return;
    }
    const reason = `request:${message.causedBy?.userUuid ?? 'unknown'}`;
    const current = this.roomState === null ? null : listenTogetherCurrentStableKey(this.roomState);
    if (current !== stableKey) {
      return;
    }
    if (!this.publishControllerLinkReadyIfPossible(stableKey, reason)) {
      this.resolveAndPublishControllerLink(stableKey, reason);
    }
  }

  private maybeRequestControllerLink(
    state: ListenTogetherRoomState,
    causeType: string,
    force: boolean = false
  ): void {
    if (this.isCurrentUserController() || this.sessionState.connectionState !== ListenTogetherConnectionState.CONNECTED ||
      !state.settings.shareAudioLinks || state.roomStatus !== ListenTogetherRoomStatuses.ACTIVE) {
      return;
    }
    let target = state.track;
    if (target === null && state.currentIndex >= 0 && state.currentIndex < state.queue.length) {
      target = state.queue[state.currentIndex];
    }
    if (target === null || target.stableKey.trim().length === 0) {
      return;
    }
    if (!force && this.trustedRoomStreamUrls(target).length > 0) {
      return;
    }
    const currentSong = PlayerManager.getCurrentSong();
    if (!force && currentSong !== null && songItemToListenTogetherTrackOrNull(currentSong)?.stableKey === target.stableKey &&
      PlayerManager.getShareableListenTogetherStreamUrls().length > 0) {
      return;
    }
    const now = Date.now();
    if (this.lastRequestedLinkStableKey === target.stableKey &&
      now - this.lastRequestedLinkAtMs < LISTEN_TOGETHER_LINK_REQUEST_THROTTLE_MS) {
      return;
    }
    const cleanTrack = listenTogetherTrackWithStreamUrls(target, []);
    const event = this.eventFactory.buildRequestLinkEvent(
      target.stableKey,
      state.currentIndex,
      cleanTrack,
      force
    );
    this.lastRequestedLinkStableKey = target.stableKey;
    this.lastRequestedLinkAtMs = now;
    this.markOutbound(event.eventId);
    this.sendEvent(event).catch((error: Object): void => Logger.warn(errorMessage(error)));
    Logger.debug(`ListenTogether REQUEST_LINK sent, cause=${causeType}, stableKey=${target.stableKey}`);
  }

  private currentRoomTargetTrack(): ListenTogetherTrack | null {
    if (this.roomState === null) {
      return null;
    }
    if (this.roomState.track !== null) {
      return this.roomState.track;
    }
    const index = this.roomState.currentIndex;
    return index >= 0 && index < this.roomState.queue.length ? this.roomState.queue[index] : null;
  }

  private authoritativeStreamTargetFor(song: SongItem): ListenTogetherTrack | null {
    if (!this.isListenTogetherActive() || this.isCurrentUserController() || this.roomState === null ||
      !this.roomState.settings.shareAudioLinks || this.roomState.roomStatus !== ListenTogetherRoomStatuses.ACTIVE) {
      return null;
    }
    const target = this.currentRoomTargetTrack();
    if (target === null || songItemToListenTogetherTrackOrNull(song)?.stableKey !== target.stableKey) {
      return null;
    }
    return target;
  }

  private trustedRoomStreamUrls(track: ListenTogetherTrack): string[] {
    return trustedListenTogetherStreamUrls(
      track.channelId,
      track.streamUrls,
      track.streamUrl
    );
  }

  private publishControllerLinkReadyIfPossible(
    stableKey: string,
    reason: string,
    streamUrlsOverride: string[] = []
  ): boolean {
    const snapshot = this.sessionState;
    if (snapshot.connectionState !== ListenTogetherConnectionState.CONNECTED ||
      !this.isCurrentUserController() || this.roomState === null ||
      !this.roomState.settings.shareAudioLinks || this.roomState.roomStatus !== ListenTogetherRoomStatuses.ACTIVE) {
      return false;
    }
    if (listenTogetherCurrentStableKey(this.roomState) !== stableKey) {
      return false;
    }
    const song = PlayerManager.getCurrentSong();
    const track = song === null ? null : songItemToListenTogetherTrackOrNull(song);
    if (track === null || track.stableKey !== stableKey) {
      return false;
    }
    const event = this.eventFactory.buildLinkReadyEvent(
      stableKey,
      PlayerManager.getPositionMs(),
      null,
      streamUrlsOverride.length > 0
        ? streamUrlsOverride
        : PlayerManager.getShareableListenTogetherStreamUrls()
    );
    if (event === null) {
      return false;
    }
    this.markOutbound(event.eventId);
    this.lastOutboundSyncAtMs = Date.now();
    this.sendEvent(event).catch((error: Object): void => Logger.warn(errorMessage(error)));
    Logger.debug(`ListenTogether LINK_READY sent, reason=${reason}, stableKey=${stableKey}, user=${snapshot.userUuid}`);
    return true;
  }

  private resolveAndPublishControllerLink(stableKey: string, reason: string): void {
    if (this.controllerLinkResolveStableKey === stableKey) {
      return;
    }
    const song = PlayerManager.getCurrentSong();
    if (this.sessionState.connectionState !== ListenTogetherConnectionState.CONNECTED ||
      !this.isCurrentUserController() || this.roomState === null ||
      !this.roomState.settings.shareAudioLinks || this.roomState.roomStatus !== ListenTogetherRoomStatuses.ACTIVE ||
      listenTogetherCurrentStableKey(this.roomState) !== stableKey ||
      song === null || songItemToListenTogetherTrackOrNull(song)?.stableKey !== stableKey) {
      return;
    }
    const operationGeneration = this.operationGate.current();
    const roomId = this.sessionState.roomId;
    this.controllerLinkResolveStableKey = stableKey;
    PlayerManager.resolveShareableListenTogetherStreamUrls(song).then((urls: string[]): void => {
      if (urls.length === 0 || this.controllerLinkResolveStableKey !== stableKey ||
        !this.operationGate.isCurrent(operationGeneration) || this.sessionState.roomId !== roomId) {
        return;
      }
      if (this.publishControllerLinkReadyIfPossible(stableKey, `resolved:${reason}`, urls)) {
        Logger.debug(`ListenTogether LINK_READY resolved, reason=${reason}, stableKey=${stableKey}`);
      }
    }).catch((error: Object): void => Logger.warn(errorMessage(error))).finally((): void => {
      if (this.controllerLinkResolveStableKey === stableKey) {
        this.controllerLinkResolveStableKey = null;
      }
    });
  }

  private handleHttpSessionError(message: string, reason: string): boolean {
    if (isTerminalListenTogetherReconnectError(message)) {
      this.closeRoomLocally(message);
      return true;
    }
    if (isFatalListenTogetherMembershipError(message)) {
      return this.triggerListenerMembershipRecovery(reason);
    }
    return false;
  }

  private handleUnsupportedClockSyncPingError(message: string): boolean {
    if (!isUnsupportedListenTogetherClockSyncPingError(message)) {
      return false;
    }
    this.clockOffset.markClockSyncPingUnsupported();
    this.webSocketClient.sendLegacyPing().catch((error: Object): void => Logger.warn(errorMessage(error)));
    return true;
  }

  private trySendTrackFinishedLegacyFallback(errorMessageText: string): boolean {
    const decision = resolveListenTogetherTrackFinishedFallback(
      errorMessageText,
      this.pendingTrackFinishedFallback,
      Date.now()
    );
    this.pendingTrackFinishedFallback = decision.next;
    if (!decision.shouldSend() || decision.next === null) {
      return false;
    }
    this.awaitingTrackFinishStableKey = null;
    this.lastOutboundSyncAtMs = Date.now();
    this.markOutbound(decision.next.event.eventId);
    this.sendEvent(decision.next.event).catch((error: Object): void => Logger.warn(errorMessage(error)));
    return true;
  }

  private triggerListenerMembershipRecovery(reason: string): boolean {
    if (this.membershipRecoveryGeneration >= 0) {
      return true;
    }
    if (!canTriggerListenTogetherMembershipRecovery(
      this.sessionState.baseUrl,
      this.sessionState.roomId,
      this.sessionState.userUuid,
      this.sessionState.nickname,
      this.isCurrentUserController()
    )) {
      return false;
    }
    const baseUrl = this.sessionState.baseUrl as string;
    const roomId = this.sessionState.roomId as string;
    const userUuid = this.sessionState.userUuid as string;
    const nickname = this.sessionState.nickname as string;
    const operationGeneration = this.operationGate.begin();
    this.membershipRecoveryGeneration = operationGeneration;
    this.reconnectEnabled = true;
    this.clearReconnectTimer();
    this.stopTimers();
    this.webSocketClient.disconnect().catch((error: Object): void => Logger.warn(errorMessage(error)));
    this.sessionState.connectionState = ListenTogetherConnectionState.CONNECTING;
    this.sessionState.lastError = `rejoining:${reason}`;
    this.publishStates();
    this.joinRoomWithIdentity(
      roomId,
      baseUrl,
      null,
      userUuid,
      nickname,
      operationGeneration
    ).then((response: ListenTogetherRoomResponse): void => {
      if (!this.operationGate.isCurrent(operationGeneration) || this.sessionState.roomId !== roomId) {
        return;
      }
      if (!response.ok) {
        this.sessionState.connectionState = ListenTogetherConnectionState.DISCONNECTED;
        this.sessionState.lastError = response.error ?? 'membership recovery failed';
        this.publishStates();
        if (isTerminalListenTogetherReconnectError(this.sessionState.lastError)) {
          this.closeRoomLocally(this.sessionState.lastError);
        } else {
          this.scheduleReconnect(`membership_recovery_failed:${reason}`);
        }
      }
    }).catch((error: Object): void => {
      if (!this.operationGate.isCurrent(operationGeneration) || this.sessionState.roomId !== roomId) {
        return;
      }
      this.sessionState.connectionState = ListenTogetherConnectionState.DISCONNECTED;
      this.sessionState.lastError = errorMessage(error);
      this.publishStates();
      if (isTerminalListenTogetherReconnectError(this.sessionState.lastError)) {
        this.closeRoomLocally(this.sessionState.lastError);
      } else {
        this.scheduleReconnect(`membership_recovery_failed:${reason}`);
      }
    }).finally((): void => {
      if (this.membershipRecoveryGeneration === operationGeneration) {
        this.membershipRecoveryGeneration = -1;
      }
    });
    return true;
  }

  private startTimers(): void {
    this.stopTimers();
    this.keepAliveTimer = setInterval((): void => this.sendKeepAlive(), LISTEN_TOGETHER_SOCKET_KEEP_ALIVE_INTERVAL_MS);
    this.heartbeatTimer = setInterval((): void => this.sendHeartbeat(), LISTEN_TOGETHER_HEARTBEAT_STATE_RECHECK_INTERVAL_MS);
    this.watchdogTimer = setInterval((): void => this.runWatchdog(), LISTEN_TOGETHER_SYNC_WATCHDOG_INTERVAL_MS);
  }

  private stopTimers(): void {
    if (this.heartbeatTimer >= 0) { clearInterval(this.heartbeatTimer); this.heartbeatTimer = -1; }
    if (this.keepAliveTimer >= 0) { clearInterval(this.keepAliveTimer); this.keepAliveTimer = -1; }
    if (this.watchdogTimer >= 0) { clearInterval(this.watchdogTimer); this.watchdogTimer = -1; }
    this.clearReconnectTimer();
  }

  private sendKeepAlive(): void {
    if (this.sessionState.connectionState !== ListenTogetherConnectionState.CONNECTED) return;
    this.clockOffset.markPingSent(Date.now(), Date.now());
    if (this.clockOffset.shouldSendLegacyPing()) {
      this.webSocketClient.sendLegacyPing().catch((error: Object): void => Logger.warn(errorMessage(error)));
    } else {
      this.webSocketClient.sendPing(Date.now()).catch((error: Object): void => Logger.warn(errorMessage(error)));
    }
  }

  private sendHeartbeat(): void {
    if (this.sessionState.connectionState !== ListenTogetherConnectionState.CONNECTED ||
      this.roomState === null || !this.isCurrentUserController()) return;
    const now = Date.now();
    const heartbeatInterval = resolveListenTogetherHeartbeatIntervalMs(this.surface.isPlaying());
    if (this.lastOutboundSyncAtMs > 0 && now - this.lastOutboundSyncAtMs < heartbeatInterval) {
      return;
    }
    const event = this.eventFactory.buildHeartbeatEvent(
      this.surface.isPlaying() ? 'playing' : 'paused',
      this.surface.currentPositionMs(),
      false
    );
    this.lastOutboundSyncAtMs = now;
    this.markOutbound(event.eventId);
    this.sendEvent(event).catch((error: Object): void => Logger.warn(errorMessage(error)));
  }

  private runWatchdog(): void {
    if (this.sessionState.connectionState !== ListenTogetherConnectionState.CONNECTED) return;
    const now = Date.now();
    if (!this.isCurrentUserController() && shouldRepairListenTogetherListenerState(
      now, this.lastSocketMessageAtMs, this.lastStateRefreshAtMs, this.pendingRepairVersion,
      LISTEN_TOGETHER_LISTENER_WEB_SOCKET_SILENCE_TIMEOUT_MS,
      LISTEN_TOGETHER_LISTENER_STATE_REPAIR_MIN_INTERVAL_MS
    )) {
      this.refreshRoomState().catch((error: Object): void => Logger.warn(errorMessage(error)));
      this.pendingRepairVersion = -1;
    }
    const pending = resolveListenTogetherPendingMemberControlRetry(this.pendingMemberControlRequest, this.roomState, now);
    this.pendingMemberControlRequest = pending.next;
    if (pending.shouldResend() && pending.next !== null) {
      this.sendEvent(pending.next.event).catch((error: Object): void => Logger.warn(errorMessage(error)));
    }
  }

  private updateSession(
    baseUrl: string,
    response: ListenTogetherRoomResponse,
    fallbackUserUuid: string = ListenTogetherPreferences.getOrCreateUserUuid(),
    fallbackNickname: string = ListenTogetherPreferences.getOrCreateNickname()
  ): void {
    if (!response.ok || response.roomId === null) {
      this.sessionState.lastError = response.error ?? 'Listen Together server rejected the request';
      this.publishStates();
      return;
    }
    const previousRoomId = this.sessionState.roomId;
    const previousUserUuid = this.sessionState.userUuid;
    if (previousRoomId !== response.roomId) {
      this.roomState = null;
    }
    this.sessionState.baseUrl = baseUrl;
    this.sessionState.roomId = response.roomId;
    this.sessionState.userUuid = response.userUuid ?? response.userId ?? fallbackUserUuid;
    this.sessionState.nickname = response.nickname ?? fallbackNickname;
    this.sessionState.role = resolveListenTogetherSessionRole(
      this.sessionState.userUuid,
      response.role,
      response.state
    );
    this.sessionState.token = response.token;
    this.sessionState.memberSecret = response.memberSecret ??
      (previousRoomId === response.roomId && previousUserUuid === this.sessionState.userUuid
        ? this.sessionState.memberSecret : null);
    this.sessionState.joinSecret = response.joinSecret ??
      (previousRoomId === response.roomId ? this.sessionState.joinSecret : null);
    this.sessionState.wsUrl = resolveListenTogetherWsUrl(
      baseUrl,
      response.roomId,
      response.token,
      response.wsUrl
    );
    this.sessionState.lastError = null;
    this.sessionState.roomNotice = null;
    this.acceptedVersion = -1;
    this.pendingRepairVersion = -1;
    this.lastSocketMessageAtMs = 0;
    this.lastStateRefreshAtMs = 0;
    this.reconnectAttempt = 0;
    this.retainedCredential = listenTogetherMembershipCredentialOrNull(this.sessionState);
    this.reconnectEnabled = true;
    if (response.state !== null) {
      const accepted = this.acceptRoomState(
        response.state,
        null,
        ListenTogetherRoomStateSource.HTTP_SESSION_UPDATE,
        null
      );
      if (accepted !== null) {
        const cause = resolveListenTogetherJoinAutoPauseCause(
          response.autoPauseOnJoin,
          this.sessionState.role,
          accepted.state
        ) ?? 'HTTP_SESSION_UPDATE';
        this.applyRoomState(accepted.state, cause, accepted.expectedPositionMs);
        if (!this.isCurrentUserController()) {
          this.maybeRequestControllerLink(accepted.state, cause);
        }
      }
    }
    this.publishStates();
  }

  private closeRoomLocally(reason: string | null): void {
    this.operationGate.begin();
    this.reconnectEnabled = false;
    this.stopTimers();
    this.webSocketClient.disconnect().catch((error: Object): void => Logger.warn(errorMessage(error)));
    this.sessionState.connectionState = ListenTogetherConnectionState.DISCONNECTED;
    this.sessionState.lastError = reason;
    this.sessionState.roomNotice = reason;
    this.sessionState.roomId = null;
    this.sessionState.wsUrl = null;
    this.sessionState.token = null;
    this.sessionState.memberSecret = null;
    this.sessionState.joinSecret = null;
    this.sessionState.role = null;
    this.sessionState.expectedPositionMs = null;
    this.roomState = null;
    this.acceptedVersion = -1;
    this.reconnectAttempt = 0;
    this.retainedCredential = null;
    this.membershipRecoveryGeneration = -1;
    this.forwardedRequestDeduper.clear();
    this.recentEvents.clear();
    this.pendingTrackFinishedFallback = null;
    this.pendingMemberControlRequest = null;
    this.awaitingTrackFinishStableKey = null;
    this.pendingRepairVersion = -1;
    this.lastOutboundSyncAtMs = 0;
    this.lastControllerLocalControlAtMs = 0;
    this.lastRequestedLinkStableKey = null;
    this.lastRequestedLinkAtMs = 0;
    this.controllerLinkResolveStableKey = null;
    this.lastSocketMessageAtMs = 0;
    this.lastStateRefreshAtMs = 0;
    this.clockOffset.reset();
    PlayerManager.clearListenTogetherSafetyPause();
    PlayerManager.resetListenTogetherSyncPlaybackRate();
    this.publishStates();
  }

  private publishStates(): void {
    AppStorage.setOrCreate(SESSION_STATE_KEY, JSON.stringify(this.sessionState));
    AppStorage.setOrCreate(ROOM_STATE_KEY, this.roomState === null ? '' : JSON.stringify(this.roomState));
  }

  private localPlaybackSnapshot(): ListenTogetherLocalPlaybackSnapshot {
    const snapshot = new ListenTogetherLocalPlaybackSnapshot();
    snapshot.queue = PlayerManager.getQueue();
    snapshot.currentSong = PlayerManager.getCurrentSong();
    snapshot.positionMs = PlayerManager.getPositionMs();
    snapshot.isPlaying = PlayerManager.getStatus() === PlaybackStatus.PLAYING;
    snapshot.repeatMode = PlayerManager.getRepeatMode();
    snapshot.shuffleEnabled = PlayerManager.isShuffleEnabled();
    snapshot.transportActive = PlayerManager.isTransportActive();
    snapshot.playbackStateName = snapshot.isPlaying ? 'playing' : 'paused';
    snapshot.shareableStreamUrls = PlayerManager.getShareableListenTogetherStreamUrls();
    return snapshot;
  }

  private nextClientSequence(): number { this.commandSequence++; return this.commandSequence; }
  private markOutbound(eventId: string | null): void { this.recentEvents.markOutbound(eventId); }
  private markInbound(eventId: string | null): void { this.recentEvents.markInbound(eventId); }
  private clearReconnectTimer(): void { if (this.reconnectTimer >= 0) { clearTimeout(this.reconnectTimer); this.reconnectTimer = -1; } }
}
