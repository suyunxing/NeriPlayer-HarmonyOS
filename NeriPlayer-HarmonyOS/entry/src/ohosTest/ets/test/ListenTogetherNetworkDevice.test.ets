import { describe, it, expect } from '@ohos/hypium';
import {
  ListenTogetherWebSocketClient,
  ListenTogetherWebSocketListener
} from '../../../main/ets/listentogether/network/ListenTogetherWebSocketClient';
import { ListenTogetherSocketEnvelope } from '../../../main/ets/listentogether/protocol/ListenTogetherSocketEnvelope';
import { ListenTogetherApi } from '../../../main/ets/listentogether/network/ListenTogetherApi';
import {
  LISTEN_TOGETHER_TEST_INVALID_BASE_URL,
  LISTEN_TOGETHER_TEST_REACHABLE
} from '../../../main/ets/listentogether/network/ListenTogetherApiRequests';
import { resolveListenTogetherBaseUrl } from '../../../main/ets/listentogether/invite/ListenTogetherBaseUrlResolver';

/** Records every callback, in order, with the delay until the first one. */
class RecordingListener implements ListenTogetherWebSocketListener {
  calls: string[] = [];
  /** ms from construction to the first callback; 0 when nothing ever fired. */
  firstCallAfterMs: number = 0;
  private readonly createdAtMs: number = Date.now();

  onOpen(): void {
    this.record('open');
  }

  onMessage(message: ListenTogetherSocketEnvelope): void {
    this.record(`message:${message.type}`);
  }

  onClosed(code: number, reason: string): void {
    this.record(`closed:${code}:${reason}`);
  }

  onFailure(error: Error): void {
    this.record(`failure:${error.message}`);
  }

  onProtocolError(rawText: string, error: Error): void {
    this.record(`protocol:${error.message}`);
  }

  /** Number of recorded callbacks whose kind matches the given prefix. */
  countStartingWith(prefix: string): number {
    let total = 0;
    for (const call of this.calls) {
      if (call.startsWith(prefix)) {
        total += 1;
      }
    }
    return total;
  }

  private record(call: string): void {
    if (this.calls.length === 0) {
      this.firstCallAfterMs = Date.now() - this.createdAtMs;
    }
    this.calls.push(call);
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => setTimeout(resolve, ms));
}

/**
 * Device-side checks for the M7.2 network layer. The pure framing, backoff and
 * URL rules are covered by the local unit suite; what can only be checked on a
 * real device is that `@ohos.net.webSocket` behaves as the client assumes.
 *
 * The assumption these cases pin down was originally written the wrong way round
 * and only the emulator caught it: `connect()` resolves as soon as the netstack
 * accepts the request, so the handshake outcome arrives on the listener — one
 * `onFailure`, 41 ms later — exactly like upstream okhttp, not as a `connect()`
 * rejection. See divergences 3 and 4 in ListenTogetherWebSocketClient.
 *
 * Port 1 on loopback is used as the unreachable endpoint: nothing listens there,
 * so the refusal is immediate and needs no external network.
 *
 * NOT covered here: a successful room session (needs a live worker plus a room
 * token), the `(http=<code>)` handshake status (the platform never surfaced a
 * `headerReceive` for a failed handshake — divergence 5), and the `connect()`
 * rejection path, which needs the platform to refuse the call outright.
 */
export default function listenTogetherNetworkDeviceTest(): void {
  describe('ActsListenTogetherNetworkTest', () => {
    it('sendWithoutSocketReturnsFalse', 0, async () => {
      const client = new ListenTogetherWebSocketClient();
      expect(await client.sendPing(1234)).assertFalse();
      expect(await client.sendLegacyPing()).assertFalse();
    });

    it('disconnectWithoutSocketIsNoOp', 0, async () => {
      // The reconnect loop calls disconnect() unconditionally before every
      // attempt, so a no-socket disconnect must not throw.
      const client = new ListenTogetherWebSocketClient();
      await client.disconnect();
      await client.disconnect(1009, 'message_too_large');
      expect(await client.sendLegacyPing()).assertFalse();
    });

    it('refusedHandshakeReportsFailureOnceAndReleasesTheHandle', 0, async () => {
      const client = new ListenTogetherWebSocketClient();
      const listener = new RecordingListener();
      let rejection = '';
      try {
        await client.connect('ws://127.0.0.1:1/api/rooms/ABC234/ws', listener);
      } catch (error) {
        rejection = (error as Error).message;
      }
      // Divergence 3: the platform accepts the request, so connect() resolves;
      // the refusal is not known yet at this point.
      expect(rejection).assertEqual('');
      // 4x the measured 41 ms, so a slow emulator does not make this flaky.
      await sleep(2000);
      // Exactly one failure signal per attempt, on onFailure like upstream.
      expect(listener.calls.length).assertEqual(1);
      expect(listener.countStartingWith('failure:')).assertEqual(1);
      // Measured at 41 ms. The reconnect backoff assumes a refusal is reported
      // promptly rather than after a multi-second connect timeout; if that ever
      // changes, the first retry would fire far later than the policy intends.
      expect(listener.firstCallAfterMs > 0 && listener.firstCallAfterMs < 2000).assertTrue();
      // No onOpen and, per divergence 4, no onClosed after the failure.
      expect(listener.countStartingWith('open')).assertEqual(0);
      expect(listener.countStartingWith('closed:')).assertEqual(0);
      // Divergence 4: the handle is gone, so a send cannot be enqueued.
      expect(await client.sendLegacyPing()).assertFalse();
      // Idempotent: releasing already happened, so this must not throw.
      await client.disconnect();
    });

    it('clientIsReusableAfterAFailedHandshake', 0, async () => {
      // A reconnect loop reuses one client for all 15 attempts; a wedged handle
      // would turn a transient failure into a permanent one.
      const client = new ListenTogetherWebSocketClient();
      const first = new RecordingListener();
      const second = new RecordingListener();
      await client.connect('ws://127.0.0.1:1/api/rooms/ABC234/ws', first);
      await sleep(2000);
      await client.connect('ws://127.0.0.1:1/api/rooms/ABC234/ws', second);
      await sleep(2000);
      // Each attempt reports its own single failure; a listener from a
      // superseded generation must never be called again.
      expect(first.countStartingWith('failure:')).assertEqual(1);
      expect(second.countStartingWith('failure:')).assertEqual(1);
      expect(first.calls.length).assertEqual(1);
      expect(second.calls.length).assertEqual(1);
      await client.disconnect();
    });

    it('invalidBaseUrlIsRejectedWithoutTouchingTheNetwork', 0, async () => {
      const api = new ListenTogetherApi();
      const result = await api.testServerAvailability('worker.example');
      expect(result.ok).assertFalse();
      expect(result.message).assertEqual(LISTEN_TOGETHER_TEST_INVALID_BASE_URL);
    });

    it('defaultServerHealthzAnswersWithTheWorkerMarker', 0, async () => {
      // Real request through the app's HTTP path (UA + proxy settings), so a
      // broken proxy or a moved default host fails here rather than in the UI.
      const api = new ListenTogetherApi();
      const result = await api.testServerAvailability(resolveListenTogetherBaseUrl(null));
      expect(result.message).assertEqual(LISTEN_TOGETHER_TEST_REACHABLE);
      expect(result.ok).assertTrue();
    });
  });
}
