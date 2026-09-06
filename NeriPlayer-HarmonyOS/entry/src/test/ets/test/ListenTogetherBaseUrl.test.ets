import { describe, it, expect } from '@ohos/hypium';
import {
  ListenTogetherInvite
} from '../../../main/ets/listentogether/invite/ListenTogetherInvite';
import {
  DEFAULT_LISTEN_TOGETHER_BASE_URL,
  configuredListenTogetherBaseUrlOrNull,
  configuredListenTogetherInviteBaseUrlOrNull,
  isDefaultListenTogetherBaseUrl,
  resolveListenTogetherBaseUrl,
  resolveListenTogetherInviteJoinBaseUrl
} from '../../../main/ets/listentogether/invite/ListenTogetherBaseUrlResolver';
import {
  parseListenTogetherInvite
} from '../../../main/ets/listentogether/invite/ListenTogetherInviteParser';
import {
  buildListenTogetherInviteUri,
  listenTogetherNicknameFromUuid
} from '../../../main/ets/listentogether/invite/ListenTogetherInviteBuilder';
import {
  hasIllegalUriCharacters,
  normalizeListenTogetherBaseUrl,
  normalizedListenTogetherHttpBaseUrlOrNull
} from '../../../main/ets/listentogether/network/ListenTogetherBaseUrl';
import {
  buildListenTogetherWsUrl,
  listenTogetherRoomWsPath,
  redactListenTogetherWsUrlForLog,
  resolveListenTogetherWsUrl
} from '../../../main/ets/listentogether/network/ListenTogetherWsUrl';

const WORKER_BASE_URL: string = 'https://neriplayerltw.cwuomcwuom.workers.dev';

function nonNullInvite(rawText: string): ListenTogetherInvite {
  const invite = parseListenTogetherInvite(rawText);
  if (invite === null) {
    throw new Error(`expected an invite for: ${rawText}`);
  }
  return invite;
}

export default function listenTogetherBaseUrlTest(): void {
  describe('ListenTogetherConfiguredBaseUrl', () => {
    it('keepsValidCustomServer', 0, () => {
      expect(configuredListenTogetherBaseUrlOrNull(' https://example.com/ '))
        .assertEqual('https://example.com');
    });

    it('keepsValidCleartextCustomServer', 0, () => {
      expect(configuredListenTogetherBaseUrlOrNull(' http://192.168.1.10:8787/ '))
        .assertEqual('http://192.168.1.10:8787');
    });

    it('rejectsInvalidCustomServer', 0, () => {
      expect(configuredListenTogetherBaseUrlOrNull('example.com')).assertNull();
      expect(configuredListenTogetherBaseUrlOrNull(null)).assertNull();
      expect(configuredListenTogetherBaseUrlOrNull('   ')).assertNull();
    });

    it('fallsBackToDefaultForBlankInput', 0, () => {
      expect(resolveListenTogetherBaseUrl(' ')).assertEqual('https://neriplayer.hancat.work');
      expect(resolveListenTogetherBaseUrl(null)).assertEqual('https://neriplayer.hancat.work');
      expect(isDefaultListenTogetherBaseUrl(DEFAULT_LISTEN_TOGETHER_BASE_URL)).assertTrue();
      expect(isDefaultListenTogetherBaseUrl('https://example.com')).assertFalse();
    });

    it('enforcesHttpsOnlyForInviteBaseUrls', 0, () => {
      expect(configuredListenTogetherInviteBaseUrlOrNull(' https://example.com/ '))
        .assertEqual('https://example.com');
      expect(configuredListenTogetherInviteBaseUrlOrNull('http://192.168.1.10:8787')).assertNull();
      expect(configuredListenTogetherInviteBaseUrlOrNull('example.com')).assertNull();
    });

    it('normalizesPathsAndRejectsQueries', 0, () => {
      expect(normalizedListenTogetherHttpBaseUrlOrNull('https://example.com/api/../ltw/'))
        .assertEqual('https://example.com/ltw');
      expect(normalizedListenTogetherHttpBaseUrlOrNull('https://example.com?token=1')).assertNull();
      expect(normalizedListenTogetherHttpBaseUrlOrNull('wss://example.com')).assertNull();
      expect(normalizedListenTogetherHttpBaseUrlOrNull('https://')).assertNull();
      expect(hasIllegalUriCharacters('https://example.com/a b')).assertTrue();
      expect(hasIllegalUriCharacters('https://example.com/a%2')).assertTrue();
      expect(hasIllegalUriCharacters('https://example.com/a%20b')).assertFalse();
    });

    it('throwsFromTheNonNullNormalizer', 0, () => {
      let message: string | null = null;
      try {
        normalizeListenTogetherBaseUrl('example.com');
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message).assertEqual('ListenTogether baseUrl must use http or https');
    });
  });

  describe('ListenTogetherInviteParser', () => {
    it('normalizesValidCustomServer', 0, () => {
      const invite = nonNullInvite(
        'neriplayer://listen-together/join?roomId=P8BAEV' +
        '&baseUrl=https%3A%2F%2Fexample.com%2F&secret=secret-value'
      );

      expect(invite.baseUrl).assertEqual('https://example.com');
      expect(invite.hasInvalidBaseUrl).assertFalse();
    });

    it('keepsEncodedWorkerBaseUrlFromSharedText', 0, () => {
      const invite = nonNullInvite(
        'Neri5458C5 邀请你在 NeriPlayer 中加入房间 GTV42X。复制后打开 App 加入。\n' +
        'neriplayer://listen-together/join?roomId=GTV42X&inviter=Neri5458C5' +
        '&baseUrl=https%3A%2F%2Fneriplayerltw.cwuomcwuom.workers.dev&secret=secret-value'
      );

      expect(invite.roomId).assertEqual('GTV42X');
      expect(invite.inviterNickname).assertEqual('Neri5458C5');
      expect(invite.baseUrl).assertEqual(WORKER_BASE_URL);
      expect(invite.hasInvalidBaseUrl).assertFalse();
    });

    it('carriesRoomJoinSecret', 0, () => {
      const invite = nonNullInvite(
        'neriplayer://listen-together/join?roomId=GTV42X&secret=secret-value'
      );

      expect(invite.joinSecret).assertEqual('secret-value');
      expect(invite.baseUrl).assertNull();
      expect(invite.hasInvalidBaseUrl).assertFalse();
    });

    it('rejectsMissingRoomJoinSecret', 0, () => {
      expect(parseListenTogetherInvite('neriplayer://listen-together/join?roomId=GTV42X'))
        .assertNull();
    });

    it('rejectsTextWithoutAnInvitation', 0, () => {
      expect(parseListenTogetherInvite(null)).assertNull();
      expect(parseListenTogetherInvite('roomId=GTV42X&secret=secret-value')).assertNull();
      expect(parseListenTogetherInvite('   ')).assertNull();
      expect(parseListenTogetherInvite('https://listen-together/join?roomId=GTV42X&secret=s'))
        .assertNull();
    });

    it('decodesEncodedInviter', 0, () => {
      const invite = nonNullInvite(
        'neriplayer://listen-together/join?roomId=P8BAEV&inviter=Neri%E7%8C%AB&secret=secret-value'
      );

      expect(invite.inviterNickname).assertEqual('Neri猫');
    });

    it('rejectsMalformedQueryEncodingWithoutThrowing', 0, () => {
      expect(parseListenTogetherInvite('neriplayer://listen-together/join?roomId=%')).assertNull();
    });

    it('flagsInvalidCustomServer', 0, () => {
      const invite = nonNullInvite(
        'neriplayer://listen-together/join?roomId=P8BAEV&baseUrl=example.com&secret=secret-value'
      );

      expect(invite.baseUrl).assertNull();
      expect(invite.hasInvalidBaseUrl).assertTrue();
    });

    it('rejectsCleartextHttpServer', 0, () => {
      const invite = nonNullInvite(
        'neriplayer://listen-together/join?roomId=P8BAEV' +
        '&baseUrl=http%3A%2F%2F192.168.1.10%3A8787%2F&secret=secret-value'
      );

      expect(invite.baseUrl).assertNull();
      expect(invite.hasInvalidBaseUrl).assertTrue();
    });
  });

  describe('ListenTogetherInviteJoinBaseUrl', () => {
    it('prefersInviteServerOverSavedServer', 0, () => {
      const invite = new ListenTogetherInvite('GTV42X', null, WORKER_BASE_URL);

      expect(resolveListenTogetherInviteJoinBaseUrl(
        invite,
        'https://saved.example.com',
        'https://normalized.example.com'
      )).assertEqual(WORKER_BASE_URL);
    });

    it('fallsBackToSavedServerWhenInviteHasNone', 0, () => {
      const invite = new ListenTogetherInvite('GTV42X');

      expect(resolveListenTogetherInviteJoinBaseUrl(
        invite,
        'https://saved.example.com/',
        null
      )).assertEqual('https://saved.example.com');
      expect(resolveListenTogetherInviteJoinBaseUrl(invite, null, 'https://stored.example.com/'))
        .assertEqual('https://stored.example.com');
      expect(resolveListenTogetherInviteJoinBaseUrl(invite, null, null))
        .assertEqual('https://neriplayer.hancat.work');
    });
  });

  describe('ListenTogetherInviteBuilder', () => {
    it('buildsALinkThatParsesBackIntoTheSameInvite', 0, () => {
      const uri = buildListenTogetherInviteUri(
        'p8baev',
        ' secret-value ',
        'Neri猫',
        'https://example.com/'
      );

      expect(uri).assertEqual(
        'neriplayer://listen-together/join?roomId=P8BAEV&inviter=Neri%E7%8C%AB' +
        '&baseUrl=https%3A%2F%2Fexample.com&secret=secret-value'
      );

      const invite = nonNullInvite(uri);
      expect(invite.roomId).assertEqual('P8BAEV');
      expect(invite.inviterNickname).assertEqual('Neri猫');
      expect(invite.baseUrl).assertEqual('https://example.com');
      expect(invite.joinSecret).assertEqual('secret-value');
      expect(invite.signature)
        .assertEqual('P8BAEV|Neri猫|https://example.com|secret-value|false');
    });

    it('omitsTheDefaultServerFromTheLink', 0, () => {
      const uri = buildListenTogetherInviteUri(
        'P8BAEV',
        'secret-value',
        null,
        DEFAULT_LISTEN_TOGETHER_BASE_URL
      );

      expect(uri).assertEqual(
        'neriplayer://listen-together/join?roomId=P8BAEV&secret=secret-value'
      );
      expect(nonNullInvite(uri).baseUrl).assertNull();
    });

    it('derivesTheFallbackNicknameFromAUuid', 0, () => {
      expect(listenTogetherNicknameFromUuid('5458c5ab-1234-4321-8888-abcdefabcdef'))
        .assertEqual('Neri5458C5');
    });
  });

  describe('ListenTogetherRoomSocketUrl', () => {
    it('replacesTheBasePathAndUpgradesTheScheme', 0, () => {
      expect(listenTogetherRoomWsPath('ABC234')).assertEqual('/api/rooms/ABC234/ws');
      expect(buildListenTogetherWsUrl('https://example.com/ltw/', 'ABC234', 'plain-token'))
        .assertEqual('wss://example.com/api/rooms/ABC234/ws?token=plain-token');
      expect(buildListenTogetherWsUrl('http://192.168.1.10:8787', 'ABC234', 'plain-token'))
        .assertEqual('ws://192.168.1.10:8787/api/rooms/ABC234/ws?token=plain-token');
    });

    it('percentEncodesTheToken', 0, () => {
      expect(buildListenTogetherWsUrl('https://example.com', 'ABC234', 'a+b/c=d'))
        .assertEqual('wss://example.com/api/rooms/ABC234/ws?token=a%2Bb%2Fc%3Dd');
    });

    it('rebuildsInternalWorkerWebsocketPlaceholders', 0, () => {
      expect(resolveListenTogetherWsUrl(
        'https://worker.example', 'ABC234', 'token-1', 'wss://public.example/room'))
        .assertEqual('wss://public.example/room');
      expect(resolveListenTogetherWsUrl(
        'https://worker.example', 'ABC234', 'token-1', 'wss://room.internal/api/rooms/ABC234/ws'))
        .assertEqual('wss://worker.example/api/rooms/ABC234/ws?token=token-1');
      expect(resolveListenTogetherWsUrl(
        'https://worker.example', 'ABC234', null, 'wss://room.internal:8787/ws'))
        .assertNull();
    });

    it('neverLeavesTheTokenInALogLine', 0, () => {
      const url = buildListenTogetherWsUrl('https://example.com', 'ABC234', 'super-secret-token');
      const redacted = redactListenTogetherWsUrlForLog(url);

      expect(redacted).assertEqual('wss://example.com/api/rooms/ABC234/ws?token=<redacted>');
      expect((redacted as string).includes('super-secret-token')).assertFalse();
      expect(redactListenTogetherWsUrlForLog(null)).assertNull();
      expect(redactListenTogetherWsUrlForLog('wss://example.com/api/rooms/ABC234/ws'))
        .assertEqual('wss://example.com/api/rooms/ABC234/ws?token=<redacted>');
    });
  });
}
