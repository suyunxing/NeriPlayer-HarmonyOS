import { describe, it, expect } from '@ohos/hypium';
import {
  buildYtmLoopbackResponseHeaders,
  normalizeYtmRange,
  parseYtmLoopbackRequest,
  serializeYtmLoopbackResponseHeaders
} from '../../../main/ets/network/ytm/YtmLoopbackHttp';

export default function ytmLoopbackHttpTest(): void {
  describe('YtmLoopbackHttp', () => {
    it('parsesGetAndRange', 0, () => {
      const request = parseYtmLoopbackRequest('GET /ytm-stream HTTP/1.1\r\nRange: bytes=123-456\r\n\r\n');
      expect(request !== null).assertTrue();
      expect(request!.method).assertEqual('GET');
      expect(request!.path).assertEqual('/ytm-stream');
      expect(request!.range).assertEqual('bytes=123-456');
    });

    it('rejectsMalformedOrUnsupportedRanges', 0, () => {
      expect(parseYtmLoopbackRequest('garbage')).assertNull();
      expect(normalizeYtmRange('bytes=10-20')).assertEqual('bytes=10-20');
      expect(normalizeYtmRange('bytes=10-')).assertEqual('bytes=10-');
      expect(normalizeYtmRange('bytes=-20')).assertEqual('');
      expect(normalizeYtmRange('bytes=10-20,30-40')).assertEqual('');
    });

    it('serializesPartialResponseHeaders', 0, () => {
      const response = buildYtmLoopbackResponseHeaders({
        'content-type': 'audio/mp4',
        'content-length': '334',
        'content-range': 'bytes 123-456/1000',
        'accept-ranges': 'bytes',
        'etag': 'abc'
      });
      expect(response.statusCode).assertEqual(206);
      const text = serializeYtmLoopbackResponseHeaders(response);
      expect(text.includes('206 Partial Content')).assertTrue();
      expect(text.includes('Content-Length: 334')).assertTrue();
      expect(text.includes('Content-Range: bytes 123-456/1000')).assertTrue();
      expect(text.endsWith('\r\n\r\n')).assertTrue();
    });
  });
}
