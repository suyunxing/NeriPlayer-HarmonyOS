import { describe, it, expect } from '@ohos/hypium';
import { ListenTogetherApi } from '../../../main/ets/listentogether/network/ListenTogetherApi';
import {
  ListenTogetherRoomResponse,
  ListenTogetherInitialSnapshot
} from '../../../main/ets/listentogether/protocol/ListenTogetherHttpMessages';
import {
  ListenTogetherWebSocketClient,
  ListenTogetherWebSocketListener
} from '../../../main/ets/listentogether/network/ListenTogetherWebSocketClient';
import { ListenTogetherSocketEnvelope } from '../../../main/ets/listentogether/protocol/ListenTogetherSocketEnvelope';
import { resolveListenTogetherBaseUrl } from '../../../main/ets/listentogether/invite/ListenTogetherBaseUrlResolver';
import { resolveListenTogetherWsUrl } from '../../../main/ets/listentogether/network/ListenTogetherWsUrl';
import { createListenTogetherTrack } from '../../../main/ets/listentogether/protocol/ListenTogetherTrack';
import { buildListenTogetherUserUuid } from '../../../main/ets/listentogether/invite/ListenTogetherIdentity';
import { LISTEN_TOGETHER_ROLE_CONTROLLER } from '../../../main/ets/listentogether/protocol/ListenTogetherSessionModels';

class RoomListener implements ListenTogetherWebSocketListener {
  events: string[] = [];

  onOpen(): void {
    this.events.push('open');
  }

  onMessage(message: ListenTogetherSocketEnvelope): void {
    this.events.push(`message:${message.type}`);
  }

  onClosed(code: number, reason: string): void {
    this.events.push(`closed:${code}:${reason}`);
  }

  onFailure(error: Error): void {
    this.events.push(`failure:${error.message}`);
  }

  onProtocolError(rawText: string, error: Error): void {
    this.events.push(`protocol:${error.message}`);
  }

  messageCount(): number {
    let total = 0;
    for (const event of this.events) {
      if (event.startsWith('message:')) {
        total += 1;
      }
    }
    return total;
  }

  hasFailure(): boolean {
    for (const event of this.events) {
      if (event.startsWith('failure:') || event.startsWith('protocol:')) {
        return true;
      }
    }
    return false;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => setTimeout(resolve, ms));
}

/**
 * One real room lifecycle against the built-in default worker: create (with a
 * one-track initial snapshot), read state back over HTTP, hold a websocket
 * session that must reach onOpen and receive the authoritative room state,
 * then leave. This is the single-device part of the M7.3 acceptance that
 * ActsListenTogetherNetworkTest deliberately skipped: it needs a live worker
 * that actually hands out room tokens.
 *
 * Leaving happens in a finally block — a failed assertion must not leak the
 * room on the shared default server.
 */
export default function listenTogetherRoomSmokeDeviceTest(): void {
  describe('ActsListenTogetherRoomSmokeTest', () => {
    it('realRoomLifecycleAgainstDefaultWorker', 0, async () => {
      const api = new ListenTogetherApi();
      const baseUrl = resolveListenTogetherBaseUrl(null);
      const client = new ListenTogetherWebSocketClient();
      const listener = new RoomListener();
      let roomId = '';
      let token = '';

      try {
        const snapshot = new ListenTogetherInitialSnapshot();
        const track = createListenTogetherTrack(
          'smoke|netease|1999',
          'netease',
          '1999',
          'Smoke Track',
          'ZCode'
        );
        track.durationMs = 200000;
        snapshot.queue = [track];
        snapshot.track = track;
        snapshot.currentIndex = 0;
        snapshot.settings.allowMemberControl = true;

        const created: ListenTogetherRoomResponse = await api.createRoom(
          baseUrl,
          buildListenTogetherUserUuid(),
          'ZCodeSmoke',
          snapshot
        );
        expect(created.ok).assertTrue();
        expect(created.roomId !== null && created.roomId.length > 0).assertTrue();
        expect(created.token !== null && created.token.length > 0).assertTrue();
        expect(created.role).assertEqual(LISTEN_TOGETHER_ROLE_CONTROLLER);
        roomId = created.roomId ?? '';
        token = created.token ?? '';

        const state = await api.getRoomState(baseUrl, roomId, token);
        expect(state.ok).assertTrue();
        expect(state.state !== null).assertTrue();
        expect(state.state?.queue.length).assertEqual(1);

        const wsUrl = resolveListenTogetherWsUrl(baseUrl, roomId, token, created.wsUrl);
        expect(wsUrl !== null).assertTrue();
        await client.connect(wsUrl as string, listener);
        // Room-state fan-out on the worker is triggered by the join; the
        // welcome/state pair follows the handshake within a few seconds.
        await sleep(6000);
        expect(listener.events.includes('open')).assertTrue();
        expect(listener.messageCount() > 0).assertTrue();
        // The authoritative room state must arrive before anything else the
        // session manager cares about; 'pong' alone would not bootstrap it.
        const firstMessage = listener.events.find((event: string): boolean => event.startsWith('message:'));
        expect(firstMessage === 'message:welcome' || firstMessage === 'message:room_state_updated').assertTrue();
        expect(listener.hasFailure()).assertFalse();
        // With the socket open, a legacy ping must be accepted for delivery.
        expect(await client.sendLegacyPing()).assertTrue();

        const left = await api.leaveRoom(baseUrl, roomId, token);
        expect(left.ok).assertTrue();
        roomId = '';
        token = '';
      } finally {
        await client.disconnect();
        if (roomId.length > 0 && token.length > 0) {
          try {
            await api.leaveRoom(baseUrl, roomId, token);
          } catch (error) {
            // Best-effort cleanup; the assertion path already reported.
          }
        }
      }
    });
  });
}
