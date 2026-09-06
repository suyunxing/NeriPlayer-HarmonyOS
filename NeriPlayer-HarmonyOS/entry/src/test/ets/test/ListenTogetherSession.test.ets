import { describe, it, expect } from '@ohos/hypium';
import {
  LISTEN_TOGETHER_ROLE_CONTROLLER,
  LISTEN_TOGETHER_ROLE_LISTENER,
  ListenTogetherConnectionState,
  ListenTogetherSessionState,
  cloneListenTogetherSessionState
} from '../../../main/ets/listentogether/protocol/ListenTogetherSessionModels';
import {
  ListenTogetherRoomState,
  createListenTogetherRoomState
} from '../../../main/ets/listentogether/protocol/ListenTogetherRoomModels';
import {
  ListenTogetherMembershipCredential,
  listenTogetherMembershipCredentialEquals,
  listenTogetherMembershipCredentialOrNull,
  resolveReusableListenTogetherMembershipCredential
} from '../../../main/ets/listentogether/session/ListenTogetherMembershipCredential';
import {
  resolveListenTogetherSessionRole
} from '../../../main/ets/listentogether/session/ListenTogetherSessionRole';
import {
  LISTEN_TOGETHER_JOIN_AUTO_PAUSE_CAUSE,
  resolveListenTogetherJoinAutoPauseCause
} from '../../../main/ets/listentogether/session/ListenTogetherJoinPolicy';

const BASE_URL: string = 'https://example.com';
const ROOM_ID: string = 'ABC234';
const USER_UUID: string = '5458c5ab-1234-4321-8888-abcdefabcdef';
// Synthetic fixtures: never reuse a real token or member secret in a test.
const FAKE_TOKEN: string = 'fixture-token';
const FAKE_MEMBER_SECRET: string = 'fixture-member-secret';

function joinedSession(): ListenTogetherSessionState {
  const session = new ListenTogetherSessionState();
  session.baseUrl = BASE_URL;
  session.roomId = ROOM_ID;
  session.userUuid = USER_UUID;
  session.token = FAKE_TOKEN;
  session.memberSecret = FAKE_MEMBER_SECRET;
  session.connectionState = ListenTogetherConnectionState.CONNECTED;
  return session;
}

function retainedCredential(roomId: string): ListenTogetherMembershipCredential {
  return new ListenTogetherMembershipCredential(
    BASE_URL, roomId, USER_UUID, null, FAKE_MEMBER_SECRET, null);
}

function roomWithController(
  controllerUserUuid: string | null,
  controllerUserId: string | null = null
): ListenTogetherRoomState {
  const state = createListenTogetherRoomState(ROOM_ID, 1);
  state.controllerUserUuid = controllerUserUuid;
  state.controllerUserId = controllerUserId;
  return state;
}

export default function listenTogetherSessionTest(): void {
  describe('ListenTogetherMembershipCredential', () => {
    it('requiresARoomIdentityAndOneProof', 0, () => {
      const credential = listenTogetherMembershipCredentialOrNull(joinedSession());

      expect(credential !== null).assertTrue();
      const minted = credential as ListenTogetherMembershipCredential;
      expect(minted.baseUrl).assertEqual(BASE_URL);
      expect(minted.roomId).assertEqual(ROOM_ID);
      expect(minted.userUuid).assertEqual(USER_UUID);
      expect(minted.token).assertEqual(FAKE_TOKEN);
      expect(minted.memberSecret).assertEqual(FAKE_MEMBER_SECRET);
      expect(minted.joinSecret).assertNull();
    });

    it('acceptsEitherProofOnItsOwn', 0, () => {
      const tokenOnly = joinedSession();
      tokenOnly.memberSecret = null;
      expect((listenTogetherMembershipCredentialOrNull(tokenOnly) as
        ListenTogetherMembershipCredential).memberSecret).assertNull();

      const secretOnly = joinedSession();
      secretOnly.token = '   ';
      expect((listenTogetherMembershipCredentialOrNull(secretOnly) as
        ListenTogetherMembershipCredential).token).assertNull();
    });

    it('returnsNullWhenAnythingRequiredIsMissing', 0, () => {
      expect(listenTogetherMembershipCredentialOrNull(new ListenTogetherSessionState()))
        .assertNull();

      const withoutProof = joinedSession();
      withoutProof.token = null;
      withoutProof.memberSecret = '   ';
      expect(listenTogetherMembershipCredentialOrNull(withoutProof)).assertNull();

      const withoutBaseUrl = joinedSession();
      withoutBaseUrl.baseUrl = '   ';
      expect(listenTogetherMembershipCredentialOrNull(withoutBaseUrl)).assertNull();

      const withoutRoomId = joinedSession();
      withoutRoomId.roomId = null;
      expect(listenTogetherMembershipCredentialOrNull(withoutRoomId)).assertNull();

      const withoutUser = joinedSession();
      withoutUser.userUuid = null;
      expect(listenTogetherMembershipCredentialOrNull(withoutUser)).assertNull();
    });

    it('trimsEveryFieldItKeeps', 0, () => {
      const padded = joinedSession();
      padded.baseUrl = ` ${BASE_URL} `;
      padded.roomId = ` ${ROOM_ID} `;
      padded.joinSecret = ' fixture-join-secret ';

      const minted = listenTogetherMembershipCredentialOrNull(padded) as
        ListenTogetherMembershipCredential;
      expect(minted.baseUrl).assertEqual(BASE_URL);
      expect(minted.roomId).assertEqual(ROOM_ID);
      expect(minted.joinSecret).assertEqual('fixture-join-secret');
      expect(listenTogetherMembershipCredentialEquals(
        minted, listenTogetherMembershipCredentialOrNull(joinedSession()) as
          ListenTogetherMembershipCredential)).assertFalse();
    });

    it('comparesCredentialsFieldByField', 0, () => {
      const left = retainedCredential(ROOM_ID);
      expect(listenTogetherMembershipCredentialEquals(left, retainedCredential(ROOM_ID)))
        .assertTrue();
      expect(listenTogetherMembershipCredentialEquals(left, retainedCredential('OTHER12')))
        .assertFalse();
    });
  });

  describe('ListenTogetherReusableCredential', () => {
    it('prefersTheLiveSessionOverTheRetainedCredential', 0, () => {
      const reused = resolveReusableListenTogetherMembershipCredential(
        joinedSession(), retainedCredential(ROOM_ID), BASE_URL, ROOM_ID, USER_UUID);

      expect((reused as ListenTogetherMembershipCredential).token).assertEqual(FAKE_TOKEN);
    });

    it('fallsBackToTheRetainedCredentialForTheSameRoom', 0, () => {
      const withoutProof = joinedSession();
      withoutProof.token = null;
      withoutProof.memberSecret = null;

      const reused = resolveReusableListenTogetherMembershipCredential(
        withoutProof, retainedCredential(ROOM_ID), ` ${BASE_URL} `, ` ${ROOM_ID} `, USER_UUID);

      expect(reused !== null).assertTrue();
      expect((reused as ListenTogetherMembershipCredential).token).assertNull();
      expect((reused as ListenTogetherMembershipCredential).memberSecret)
        .assertEqual(FAKE_MEMBER_SECRET);
    });

    it('neverReusesACredentialMintedForAnotherRoom', 0, () => {
      const withoutProof = joinedSession();
      withoutProof.token = null;
      withoutProof.memberSecret = null;

      expect(resolveReusableListenTogetherMembershipCredential(
        withoutProof, retainedCredential('OTHER12'), BASE_URL, ROOM_ID, USER_UUID)).assertNull();
      expect(resolveReusableListenTogetherMembershipCredential(
        withoutProof, null, BASE_URL, ROOM_ID, USER_UUID)).assertNull();
      expect(resolveReusableListenTogetherMembershipCredential(
        joinedSession(), null, BASE_URL, ROOM_ID, 'another-user-uuid')).assertNull();
      expect(resolveReusableListenTogetherMembershipCredential(
        joinedSession(), null, 'https://other.example.com', ROOM_ID, USER_UUID)).assertNull();
    });

    it('matchesTheRoomFieldsCaseInsensitively', 0, () => {
      const reused = resolveReusableListenTogetherMembershipCredential(
        joinedSession(), null, BASE_URL.toUpperCase(), ROOM_ID.toLowerCase(),
        USER_UUID.toUpperCase());

      expect(reused !== null).assertTrue();
      // The stored casing is what gets replayed to the server.
      expect((reused as ListenTogetherMembershipCredential).roomId).assertEqual(ROOM_ID);
    });
  });

  describe('ListenTogetherSessionRole', () => {
    it('letsTheRoomStateDecideWhoHoldsControl', 0, () => {
      expect(resolveListenTogetherSessionRole(
        USER_UUID, LISTEN_TOGETHER_ROLE_LISTENER, roomWithController(USER_UUID)))
        .assertEqual(LISTEN_TOGETHER_ROLE_CONTROLLER);
      expect(resolveListenTogetherSessionRole(
        USER_UUID, LISTEN_TOGETHER_ROLE_CONTROLLER, roomWithController('someone-else')))
        .assertEqual(LISTEN_TOGETHER_ROLE_LISTENER);
      expect(resolveListenTogetherSessionRole(
        ` ${USER_UUID} `, null, roomWithController(` ${USER_UUID} `)))
        .assertEqual(LISTEN_TOGETHER_ROLE_CONTROLLER);
    });

    it('readsTheLegacyControllerUserIdWhenTheUuidIsAbsent', 0, () => {
      expect(resolveListenTogetherSessionRole(USER_UUID, null, roomWithController('   ', USER_UUID)))
        .assertEqual(LISTEN_TOGETHER_ROLE_CONTROLLER);
    });

    it('keepsTheCachedRoleWhenEitherSideIsUnknown', 0, () => {
      expect(resolveListenTogetherSessionRole(
        null, LISTEN_TOGETHER_ROLE_LISTENER, roomWithController(USER_UUID)))
        .assertEqual(LISTEN_TOGETHER_ROLE_LISTENER);
      expect(resolveListenTogetherSessionRole(USER_UUID, LISTEN_TOGETHER_ROLE_CONTROLLER, null))
        .assertEqual(LISTEN_TOGETHER_ROLE_CONTROLLER);
      expect(resolveListenTogetherSessionRole(
        USER_UUID, LISTEN_TOGETHER_ROLE_LISTENER, roomWithController(null)))
        .assertEqual(LISTEN_TOGETHER_ROLE_LISTENER);
      expect(resolveListenTogetherSessionRole('   ', null, roomWithController(USER_UUID)))
        .assertNull();
    });
  });

  describe('ListenTogetherJoinPolicy', () => {
    it('onlyExplainsAnAlreadyPausedRoom', 0, () => {
      const paused = createListenTogetherRoomState(ROOM_ID, 1);
      const playing = createListenTogetherRoomState(ROOM_ID, 1);
      playing.playback.state = 'playing';

      expect(resolveListenTogetherJoinAutoPauseCause(
        true, LISTEN_TOGETHER_ROLE_LISTENER, paused))
        .assertEqual(LISTEN_TOGETHER_JOIN_AUTO_PAUSE_CAUSE);
      expect(LISTEN_TOGETHER_JOIN_AUTO_PAUSE_CAUSE).assertEqual('JOIN_AUTO_PAUSE');
      // A playing room must never be paused just because the flag is set.
      expect(resolveListenTogetherJoinAutoPauseCause(
        true, LISTEN_TOGETHER_ROLE_LISTENER, playing)).assertNull();
    });

    it('ignoresTheFlagForTheControllerAndWhenUnset', 0, () => {
      const paused = createListenTogetherRoomState(ROOM_ID, 1);

      expect(resolveListenTogetherJoinAutoPauseCause(
        true, LISTEN_TOGETHER_ROLE_CONTROLLER, paused)).assertNull();
      expect(resolveListenTogetherJoinAutoPauseCause(
        false, LISTEN_TOGETHER_ROLE_LISTENER, paused)).assertNull();
      expect(resolveListenTogetherJoinAutoPauseCause(true, null, paused)).assertNull();
    });
  });

  describe('ListenTogetherSessionStateSnapshot', () => {
    it('clonesEveryFieldSoTheUiNeverSeesAHalfUpdate', 0, () => {
      const session = joinedSession();
      session.nickname = 'Neri猫';
      session.role = LISTEN_TOGETHER_ROLE_LISTENER;
      session.expectedPositionMs = 45000;
      session.roomNotice = '主持人已离线';

      const copy = cloneListenTogetherSessionState(session);
      copy.role = LISTEN_TOGETHER_ROLE_CONTROLLER;
      copy.connectionState = ListenTogetherConnectionState.DISCONNECTED;
      copy.lastError = '连接已断开';

      expect(copy.nickname).assertEqual('Neri猫');
      expect(copy.expectedPositionMs).assertEqual(45000);
      expect(copy.roomNotice).assertEqual('主持人已离线');
      expect(session.role).assertEqual(LISTEN_TOGETHER_ROLE_LISTENER);
      expect(session.connectionState).assertEqual(ListenTogetherConnectionState.CONNECTED);
      expect(session.lastError).assertNull();
      expect(copy.connectionState).assertEqual(ListenTogetherConnectionState.DISCONNECTED);
    });
  });
}
