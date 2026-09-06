import { describe, it, expect } from '@ohos/hypium';
import { GitHubTransport } from '../../../main/ets/sync/github/GitHubTransport';
import { OhosGhExecutor } from '../../../main/ets/sync/github/OhosGhExecutor';
import { GitHubSyncClient } from '../../../main/ets/sync/github/GitHubSyncClient';
import { GitHubApiError, GitHubErrorKind } from '../../../main/ets/sync/github/GitHubErrors';

/**
 * Real-network smoke for the GitHub transport (M5.3). No credentials are
 * required: the octocat/Hello-World public repo validates the anonymous read
 * path (repo info -> branch head -> raw contents), and both /user calls
 * validate 401 classification (anonymous and an invalid bearer token).
 * The authenticated write pipeline (blob -> tree -> commit -> merges) needs a
 * real PAT and is left for the user to verify through the settings UI.
 */
export default function githubTransportDeviceTest(): void {
  describe('ActsGitHubTransportTest', () => {
    it('anonymousPublicRepoReadWorks', 0, async () => {
      const transport = new GitHubTransport(new OhosGhExecutor(), '');
      const info = await transport.getRepoInfo('octocat', 'Hello-World');
      expect(info.defaultBranch.length > 0).assertTrue();
      expect(info.isPrivate).assertFalse();
      const head = await transport.getBranchHead('octocat', 'Hello-World', info.defaultBranch);
      expect(head.length >= 40).assertTrue();
      const readme = await transport.getFileContent('octocat', 'Hello-World', 'README', head);
      expect(readme !== null).assertTrue();
      if (readme !== null) {
        expect(readme.content.length > 0).assertTrue();
      }
    });

    it('missingFileYieldsNullSnapshot', 0, async () => {
      const transport = new GitHubTransport(new OhosGhExecutor(), '');
      const client = new GitHubSyncClient(transport);
      const snapshot = await client.fetchRemoteSnapshot('octocat', 'Hello-World',
        'backup.json', false);
      expect(snapshot === null).assertTrue();
    });

    it('anonymousUserCallClassifiesAsTokenExpired', 0, async () => {
      const transport = new GitHubTransport(new OhosGhExecutor(), '');
      let kind = '';
      try {
        await transport.validateToken();
      } catch (error) {
        kind = (error as GitHubApiError).kind;
      }
      expect(kind).assertEqual(GitHubErrorKind.TOKEN_EXPIRED);
    });

    it('invalidBearerTokenClassifiesAsTokenExpired', 0, async () => {
      const transport = new GitHubTransport(new OhosGhExecutor(), 'ghp_invalid_token_probe_000');
      let kind = '';
      try {
        await transport.validateToken();
      } catch (error) {
        kind = (error as GitHubApiError).kind;
      }
      expect(kind).assertEqual(GitHubErrorKind.TOKEN_EXPIRED);
    });

    it('patchRequestLineIsAcceptedByGitHub', 0, async () => {
      // A real PATCH through customMethod (@ohos.net.http has no PATCH enum)
      // must be understood by GitHub: with a bad token it answers 401 (auth
      // checked before method/resource). A broken request line would yield
      // 404/405 instead, which would surface as a different error kind.
      const transport = new GitHubTransport(new OhosGhExecutor(), 'ghp_invalid_token_probe_000');
      let kind = '';
      try {
        await transport.updateBranchRef('octocat', 'Hello-World', 'master', '0'.repeat(40));
      } catch (error) {
        kind = (error as GitHubApiError).kind;
      }
      expect(kind).assertEqual(GitHubErrorKind.TOKEN_EXPIRED);
    });
  });
}
