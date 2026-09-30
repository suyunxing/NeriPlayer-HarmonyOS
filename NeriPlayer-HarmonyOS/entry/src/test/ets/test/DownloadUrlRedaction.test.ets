import { describe, it, expect } from '@ohos/hypium';
import { redactUrlForLog } from '../../../main/ets/download/DownloadSupport';

export default function downloadUrlRedactionTest(): void {
  describe('DownloadUrlRedaction', () => {
    it('stripsQueryAndPathFromCdnUrls', 0, () => {
      // Resolved CDN URLs embed expiring signatures in the query string and
      // opaque ticket segments in the path — neither may reach hilog.
      expect(redactUrlForLog('https://m804.music.126.net/2024/abc/def.mp3?authKey=SECRET&xyz=1'))
        .assertEqual('https://m804.music.126.net/<path:38>');
      expect(redactUrlForLog('http://host.example/stream'))
        .assertEqual('http://host.example/<path:7>');
      expect(redactUrlForLog('https://upos-sz-mirror.bilivideo.com/media?e=token'))
        .assertEqual('https://upos-sz-mirror.bilivideo.com/<path:14>');
    });

    it('handlesDegenerateInputs', 0, () => {
      expect(redactUrlForLog('')).assertEqual('<no-scheme:0>');
      expect(redactUrlForLog('not a url')).assertEqual('<no-scheme:9>');
      expect(redactUrlForLog('https://host.example')).assertEqual('https://host.example/<path:0>');
      // Query-only URL: no path segment, the credential must still be cut.
      expect(redactUrlForLog('https://host.example?authKey=SECRET'))
        .assertEqual('https://host.example/<path:15>');
      expect(redactUrlForLog('https://host.example#frag=1'))
        .assertEqual('https://host.example/<path:7>');
    });
  });
}
