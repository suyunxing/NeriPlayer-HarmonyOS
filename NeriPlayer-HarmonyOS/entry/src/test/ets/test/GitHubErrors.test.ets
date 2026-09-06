import { describe, it, expect } from '@ohos/hypium';
import {
  GitHubApiError,
  GitHubErrorKind,
  GhClassifyOptions,
  classifyGitHubFailure,
  ghBodyErrorMessage,
  trimErrorMessage,
  rateLimitRetryMs
} from '../../../main/ets/sync/github/GitHubErrors';

function headersOf(pairs: Record<string, string>): Map<string, string> {
  const map = new Map<string, string>();
  const keys = Object.keys(pairs);
  for (const key of keys) {
    map.set(key, pairs[key]);
  }
  return map;
}

export default function githubErrorsTest(): void {
  describe('GitHubErrors', () => {
    it('classifies401AsTokenExpired', 0, () => {
      const error = classifyGitHubFailure('validateToken', 401, '{"message":"Bad credentials"}',
        new Map<string, string>(), new GhClassifyOptions());
      expect(error.kind).assertEqual(GitHubErrorKind.TOKEN_EXPIRED);
      expect(error.statusCode).assertEqual(401);
    });

    it('classifies409AsContentConflictWhenDetecting', 0, () => {
      const options = new GhClassifyOptions();
      options.detectConflict = true;
      const error = classifyGitHubFailure('mergeIntoBranch', 409, 'conflict',
        new Map<string, string>(), options);
      expect(error.kind).assertEqual(GitHubErrorKind.CONTENT_CONFLICT);
    });

    it('classifies422WithReferenceBodyAsConflict', 0, () => {
      const options = new GhClassifyOptions();
      options.detectConflict = true;
      const body = '{"message":"Update is not a fast forward","documentation_url":"..."}';
      const withReference = classifyGitHubFailure('updateRef', 422,
        'Reference does not exist', new Map<string, string>(), options);
      const withoutReference = classifyGitHubFailure('updateRef', 422, body,
        new Map<string, string>(), options);
      expect(withReference.kind).assertEqual(GitHubErrorKind.CONTENT_CONFLICT);
      expect(withoutReference.kind).assertEqual(GitHubErrorKind.API);
    });

    it('classifies403RateLimitExhausted', 0, () => {
      const now = 1700000000000;
      const reset = Math.floor(now / 1000) + 40;
      const error = classifyGitHubFailure('getFileContent', 403,
        '{"message":"API rate limit exceeded"}',
        headersOf({ 'x-ratelimit-remaining': '0', 'x-ratelimit-reset': `${reset}` }),
        new GhClassifyOptions(), now);
      expect(error.kind).assertEqual(GitHubErrorKind.RATE_LIMITED);
      expect(error.retryAfterMs > 30000 && error.retryAfterMs <= 41000).assertTrue();
    });

    it('classifies429WithRetryAfterHeader', 0, () => {
      const error = classifyGitHubFailure('createBinaryBlob', 429, 'too many requests',
        headersOf({ 'retry-after': '30' }), new GhClassifyOptions());
      expect(error.kind).assertEqual(GitHubErrorKind.RATE_LIMITED);
      expect(error.retryAfterMs).assertEqual(30000);
    });

    it('keeps403WithoutRateLimitEvidenceAsApiError', 0, () => {
      const error = classifyGitHubFailure('getRepoInfo', 403, 'forbidden',
        headersOf({ 'x-ratelimit-remaining': '52' }), new GhClassifyOptions());
      expect(error.kind).assertEqual(GitHubErrorKind.API);
    });

    it('classifies404ByContext', 0, () => {
      const fileOptions = new GhClassifyOptions();
      fileOptions.notFoundKind = GitHubErrorKind.FILE_NOT_FOUND;
      const repoOptions = new GhClassifyOptions();
      repoOptions.notFoundKind = GitHubErrorKind.REPO_NOT_FOUND;
      const fileError = classifyGitHubFailure('getFileContent', 404, 'not found',
        new Map<string, string>(), fileOptions);
      const repoError = classifyGitHubFailure('getRepoInfo', 404, 'not found',
        new Map<string, string>(), repoOptions);
      expect(fileError.kind).assertEqual(GitHubErrorKind.FILE_NOT_FOUND);
      expect(repoError.kind).assertEqual(GitHubErrorKind.REPO_NOT_FOUND);
    });

    it('extractsMessageFromGitHubErrorBody', 0, () => {
      expect(ghBodyErrorMessage('{"message":"Bad credentials","doc":"x"}'))
        .assertEqual('Bad credentials');
      expect(ghBodyErrorMessage('plain text failure')).assertEqual('plain text failure');
      expect(ghBodyErrorMessage('')).assertEqual('no response body');
      expect(ghBodyErrorMessage('   ')).assertEqual('no response body');
    });

    it('trimsLongMessagesTo240', 0, () => {
      const long = 'x'.repeat(500);
      expect(trimErrorMessage(long).length).assertEqual(240);
      const fromBody = ghBodyErrorMessage(`{"message":"${long}"}`);
      expect(fromBody.length).assertEqual(240);
    });

    it('retryAfterFallsBackWhenResetHeaderMissing', 0, () => {
      const info = rateLimitRetryMs(headersOf({ 'x-ratelimit-remaining': '0' }), 1700000000000);
      expect(info.retryAfterMs).assertEqual(0);
      const retryInfo = rateLimitRetryMs(headersOf({ 'retry-after': '7' }), 1700000000000);
      expect(retryInfo.retryAfterMs).assertEqual(7000);
    });
  });
}
