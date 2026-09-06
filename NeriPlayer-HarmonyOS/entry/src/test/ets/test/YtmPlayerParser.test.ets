import { describe, it, expect } from '@ohos/hypium';
import {
  YtmAudioCandidate,
  YtmPlayerResponseNode,
  collectYtmAudioCandidates,
  parseYtmBootstrapHtml,
  parseYtmPlayability
} from '../../../main/ets/network/ytm/YtmPlayerParser';

function playerRoot(json: string): YtmPlayerResponseNode {
  return JSON.parse(json) as YtmPlayerResponseNode;
}

/** Spike-shaped IOS player payload with sanitized values. */
const OK_RESPONSE = `{
  "playabilityStatus": {"status": "OK"},
  "videoDetails": {"videoId": "fbvvS8e1KgI", "title": "Sample", "lengthSeconds": "212"},
  "streamingData": {
    "adaptiveFormats": [
      {"itag": 251, "mimeType": "audio/webm; codecs=\\"opus\\"", "bitrate": 140517,
       "audioSampleRate": "44100", "contentLength": "3717234", "approxDurationMs": "212000",
       "url": "https://rr.example.com/videoplayback?itag=251"},
      {"itag": 140, "mimeType": "audio/mp4; codecs=\\"mp4a.40.2\\"", "bitrate": 130268,
       "averageBitrate": 128905, "audioSampleRate": "44100", "contentLength": "3420000",
       "url": "https://rr.example.com/videoplayback?itag=140"},
      {"itag": 302, "mimeType": "video/webm; codecs=\\"vp9\\"", "bitrate": 500000}
    ],
    "formats": [
      {"itag": 249, "mimeType": "audio/webm; codecs=\\"opus\\"", "bitrate": 50125,
       "audioSampleRate": "44100", "signatureCipher": "s=AAA&url=https%3A%2F%2Frr.example.com%2Fvideoplayback"}
    ]
  }
}`;

export default function ytmPlayerParserTest(): void {
  describe('YtmPlayerParser', () => {
    it('playabilityOkAndMissingStatusPass', 0, () => {
      expect(parseYtmPlayability(playerRoot(OK_RESPONSE)).ok).assertTrue();
      expect(parseYtmPlayability(playerRoot('{}')).ok).assertTrue();
    });

    it('loginRequiredCarriesStatusAndReason', 0, () => {
      const root = playerRoot(
        `{"playabilityStatus": {"status": "LOGIN_REQUIRED", "reason": "This video is private"}}`
      );
      const verdict = parseYtmPlayability(root);
      expect(verdict.ok).assertFalse();
      expect(verdict.status).assertEqual('LOGIN_REQUIRED');
      expect(verdict.reason).assertEqual('This video is private');
    });

    it('messagesJoinWithReasonAndDeduplicate', 0, () => {
      const root = playerRoot(
        `{"playabilityStatus": {"status": "UNPLAYABLE", "reason": "Embedded disabled",
          "messages": ["Please sign in", "Embedded disabled"]}}`
      );
      const verdict = parseYtmPlayability(root);
      expect(verdict.reason).assertEqual('Embedded disabled | Please sign in');
    });

    it('collectsAudioFromBothListsAndFiltersVideo', 0, () => {
      const candidates = collectYtmAudioCandidates(playerRoot(OK_RESPONSE));
      // 251 + 140 from adaptiveFormats, 249 from formats; the vp9 video row drops.
      expect(candidates.length).assertEqual(3);
      const byItag = new Map<number, string>();
      for (const c of candidates) {
        byItag.set(c.itag, c.mimeType);
      }
      expect(byItag.has(302)).assertFalse();
      expect(byItag.get(251)!.startsWith('audio/webm')).assertTrue();
      expect(byItag.get(140)!.startsWith('audio/mp4')).assertTrue();
    });

    it('parsesNumericStringFieldsAndBitrateFallback', 0, () => {
      const candidates = collectYtmAudioCandidates(playerRoot(OK_RESPONSE));
      let itag140: YtmAudioCandidate | null = null;
      for (const c of candidates) {
        if (c.itag === 140) {
          itag140 = c;
        }
      }
      expect(itag140!.audioSampleRateHz).assertEqual(44100);
      expect(itag140!.contentLength).assertEqual(3420000);
      // bitrate field wins over averageBitrate when present.
      expect(itag140!.bitrate).assertEqual(130268);
    });

    it('marksCipherOnlyCandidates', 0, () => {
      const candidates = collectYtmAudioCandidates(playerRoot(OK_RESPONSE));
      let itag249: YtmAudioCandidate | null = null;
      for (const c of candidates) {
        if (c.itag === 249) {
          itag249 = c;
        }
      }
      expect(itag249!.directUrl).assertEqual('');
      expect(itag249!.hasCipher).assertTrue();
      // Direct rows never carry the cipher flag.
      let itag251: YtmAudioCandidate | null = null;
      for (const c of candidates) {
        if (c.itag === 251) {
          itag251 = c;
        }
      }
      expect(itag251!.hasCipher).assertFalse();
    });

    it('parsesBootstrapMarkersFromHomePageHtml', 0, () => {
      const html = `"INNERTUBE_API_KEY":"AIzaSyEXAMPLE","VISITOR_DATA":"CgtExample%3D",
        "STS":20681,"LOGGED_IN":false`;
      const bootstrap = parseYtmBootstrapHtml(html);
      expect(bootstrap !== null).assertTrue();
      expect(bootstrap!.apiKey).assertEqual('AIzaSyEXAMPLE');
      expect(bootstrap!.visitorData).assertEqual('CgtExample%3D');
      expect(bootstrap!.signatureTimestamp).assertEqual(20681);
    });

    it('bootstrapRequiresApiKeyAndFallsBackStsKey', 0, () => {
      expect(parseYtmBootstrapHtml('"VISITOR_DATA":"x"')).assertNull();
      const html = '"INNERTUBE_API_KEY":"k","signatureTimestamp":19999';
      const bootstrap = parseYtmBootstrapHtml(html);
      expect(bootstrap !== null).assertTrue();
      expect(bootstrap!.signatureTimestamp).assertEqual(19999);
      // Missing STS degrades to 0 (the caller then omits the field).
      const noSts = parseYtmBootstrapHtml('"INNERTUBE_API_KEY":"k"');
      expect(noSts!.signatureTimestamp).assertEqual(0);
    });

    it('bootstrapReadsEomVisitorDataFromCurrentPages', 0, () => {
      // 2026-08-16+ pages ship "EOM_VISITOR_DATA"; classic VISITOR_DATA is gone
      // and an empty visitor still works for IOS player requests.
      const bootstrap = parseYtmBootstrapHtml('"INNERTUBE_API_KEY":"k","EOM_VISITOR_DATA":"CgtExample"');
      expect(bootstrap !== null).assertTrue();
      expect(bootstrap!.visitorData).assertEqual('CgtExample');
      const classicWins = parseYtmBootstrapHtml(
        '"INNERTUBE_API_KEY":"k","VISITOR_DATA":"classic","EOM_VISITOR_DATA":"eom"'
      );
      expect(classicWins!.visitorData).assertEqual('classic');
    });
  });
}
