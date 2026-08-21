import { describe, it, expect } from '@ohos/hypium';
import { ListenTogetherSessionManager } from '../../../main/ets/listentogether/ListenTogetherSessionManager';
import {
  ListenTogetherConnectionState,
  listenTogetherSessionStateFromJson
} from '../../../main/ets/listentogether/protocol/ListenTogetherSessionModels';

function sessionJson(): string {
  const raw = AppStorage.get<string>('listenTogether.sessionState');
  return raw ?? '';
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => setTimeout(resolve, ms));
}

/**
 * Runs while the MAIN ability holds a live room session: entry_test shares
 * the process, so this singleton is the session the UI is looking at. Forcing
 * connectWebSocket() replaces the established socket — the reconnect path a
 * network flap exercises — and the session must return to CONNECTED on the
 * SAME room without re-authentication. Skips itself when no room is active so
 * it can stay registered permanently.
 */
export default function listenTogetherReconnectProbeTest(): void {
  describe('ActsListenTogetherReconnectProbe', () => {
    it('replacesSocketAndReturnsToConnected', 0, async () => {
      const manager = ListenTogetherSessionManager.getInstance();
      if (!manager.isListenTogetherActive()) {
        console.info('reconnect probe skipped: no active room');
        return;
      }
      const before = listenTogetherSessionStateFromJson(sessionJson());
      expect(before?.roomId !== null && before?.roomId !== undefined).assertTrue();
      const roomId = before?.roomId ?? '';

      manager.connectWebSocket();

      let connected = false;
      for (let i = 0; i < 15; i++) {
        await sleep(1000);
        const state = listenTogetherSessionStateFromJson(sessionJson());
        if (state?.connectionState === ListenTogetherConnectionState.CONNECTED) {
          connected = true;
          break;
        }
      }
      expect(connected).assertTrue();
      const after = listenTogetherSessionStateFromJson(sessionJson());
      expect(after?.roomId).assertEqual(roomId);
    });
  });
}
