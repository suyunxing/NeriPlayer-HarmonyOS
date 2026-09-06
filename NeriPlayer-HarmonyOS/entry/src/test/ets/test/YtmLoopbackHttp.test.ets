import { describe, it, expect } from '@ohos/hypium';
import {
  buildYtmServedResponseHeaders,
  normalizeYtmRange,
  parseYtmContentRangeTotal,
  parseYtmLoopbackRequest,
  planYtmUpstreamChunks,
  readYtmHeader,
  resolveYtmServedRange,
  serializeYtmLoopbackResponseHeaders,
  summarizeYtmLoopbackHeaders,
  YTM_UPSTREAM_CHUNK_BYTES,
  YtmServedRange
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
      const response = buildYtmServedResponseHeaders(
        { start: 123, end: 456, total: 1000, partial: true }, 'audio/mp4'
      );
      expect(response.statusCode).assertEqual(206);
      expect(response.contentLength).assertEqual(334);
      const text = serializeYtmLoopbackResponseHeaders(response);
      expect(text.includes('206 Partial Content')).assertTrue();
      expect(text.includes('Content-Length: 334')).assertTrue();
      expect(text.includes('Content-Range: bytes 123-456/1000')).assertTrue();
      expect(text.includes('Accept-Ranges: bytes')).assertTrue();
      expect(text.endsWith('\r\n\r\n')).assertTrue();
    });

    it('serializesWholeEntityResponseAsPlainOk', 0, () => {
      const response = buildYtmServedResponseHeaders(
        { start: 0, end: 999, total: 1000, partial: false }, ''
      );
      expect(response.statusCode).assertEqual(200);
      expect(response.contentType).assertEqual('audio/mp4');
      const text = serializeYtmLoopbackResponseHeaders(response);
      expect(text.includes('200 OK')).assertTrue();
      expect(text.includes('Content-Length: 1000')).assertTrue();
      expect(text.includes('Content-Range')).assertFalse();
    });

    it('readsEntityTotalFromContentRange', 0, () => {
      expect(parseYtmContentRangeTotal('bytes 0-1/3112528')).assertEqual(3112528);
      expect(parseYtmContentRangeTotal(' bytes 8192-16383/3112528 ')).assertEqual(3112528);
      // A rejection carries no Content-Range, and `*` totals are unusable.
      expect(parseYtmContentRangeTotal('')).assertEqual(-1);
      expect(parseYtmContentRangeTotal('bytes */3112528')).assertEqual(3112528);
      expect(parseYtmContentRangeTotal('bytes 0-1/*')).assertEqual(-1);
    });

    it('resolvesRangesAgainstTheEntityTotal', 0, () => {
      const closed = resolveYtmServedRange('bytes=100-199', 1000) as YtmServedRange;
      expect(closed.start).assertEqual(100);
      expect(closed.end).assertEqual(199);
      expect(closed.partial).assertTrue();
      // `bytes=N-` clamps to the last byte rather than staying open-ended,
      // because googlevideo refuses open-ended ranges with a 403.
      const openEnded = resolveYtmServedRange('bytes=100-', 1000) as YtmServedRange;
      expect(openEnded.end).assertEqual(999);
      // An end past the entity clamps too.
      const overshoot = resolveYtmServedRange('bytes=100-99999', 1000) as YtmServedRange;
      expect(overshoot.end).assertEqual(999);
      // No Range at all serves the whole entity as a 200.
      const whole = resolveYtmServedRange('', 1000) as YtmServedRange;
      expect(whole.start).assertEqual(0);
      expect(whole.end).assertEqual(999);
      expect(whole.partial).assertFalse();
      // Unsatisfiable and unknown-total cases have no served interval.
      expect(resolveYtmServedRange('bytes=1000-1200', 1000)).assertNull();
      expect(resolveYtmServedRange('bytes=0-10', 0)).assertNull();
    });

    it('splitsServedRangesIntoChunksGooglevideoAccepts', 0, () => {
      expect(planYtmUpstreamChunks(0, 9, 4).join(' ')).assertEqual('bytes=0-3 bytes=4-7 bytes=8-9');
      // An exact multiple must not emit a trailing empty chunk.
      expect(planYtmUpstreamChunks(0, 7, 4).join(' ')).assertEqual('bytes=0-3 bytes=4-7');
      expect(planYtmUpstreamChunks(5, 5, 4).join(' ')).assertEqual('bytes=5-5');
      expect(planYtmUpstreamChunks(10, 9, 4).length).assertEqual(0);
      expect(planYtmUpstreamChunks(0, 9, 0).length).assertEqual(0);
    });

    it('keepsEveryChunkInsideTheMeasuredGooglevideoLimit', 0, () => {
      // AVPlayer's own failing request was exactly 2 MiB, which googlevideo
      // answered with a single 403 because its end offset sits past the prefix
      // an anonymous URL will serve. Splitting it lets the part that is inside
      // the prefix through, so the chunks must tile the interval exactly.
      const served = resolveYtmServedRange('bytes=8192-2105343', 3112528) as YtmServedRange;
      const chunks = planYtmUpstreamChunks(served.start, served.end, YTM_UPSTREAM_CHUNK_BYTES);
      expect(chunks.length).assertEqual(2);
      let covered = 0;
      let previousEnd = served.start - 1;
      for (const chunk of chunks) {
        const match = /^bytes=(\d+)-(\d+)$/.exec(chunk);
        expect(match !== null).assertTrue();
        const start = Number(match![1]);
        const end = Number(match![2]);
        // Contiguous and gap-free: a hole would corrupt the stitched body.
        expect(start).assertEqual(previousEnd + 1);
        previousEnd = end;
        expect(end - start + 1 <= YTM_UPSTREAM_CHUNK_BYTES).assertTrue();
        covered += end - start + 1;
      }
      expect(previousEnd).assertEqual(served.end);
      expect(covered).assertEqual(served.end - served.start + 1);
    });

    it('readsHeadersCaseInsensitively', 0, () => {
      expect(readYtmHeader({ 'Content-Type': 'audio/mp4' }, 'content-type')).assertEqual('audio/mp4');
      expect(readYtmHeader({ 'content-range': 'bytes 0-1/9' }, 'Content-Range')).assertEqual('bytes 0-1/9');
      expect(readYtmHeader({}, 'content-type')).assertEqual('');
    });

    it('redactsCredentialBearingHeadersInDiagnostics', 0, () => {
      const summary = summarizeYtmLoopbackHeaders({
        'Content-Type': 'text/plain',
        'Location': 'https://rr3---sn-abc.googlevideo.com/videoplayback?expire=1&sig=SECRET',
        'Set-Cookie': 'GPS=1; Domain=.googlevideo.com'
      });
      expect(summary.includes('content-type=text/plain')).assertTrue();
      expect(summary.includes('location=<rr3---sn-abc.googlevideo.com>')).assertTrue();
      expect(summary.includes('SECRET')).assertFalse();
      expect(summary.includes('videoplayback')).assertFalse();
      expect(summary.includes('set-cookie=<redacted>')).assertTrue();
    });
  });
}
