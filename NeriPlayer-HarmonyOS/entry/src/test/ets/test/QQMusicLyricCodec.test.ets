import { describe, it, expect } from '@ohos/hypium';
import {
  decodeQQMusicBase64Lyric,
  decodeQQMusicLyricPayload,
  htmlUnescapeQQMusic,
  stripUntranslatedPlaceholderLines
} from '../../../main/ets/network/QQMusicLyricCodec';
import { decodeBase64, encodeBase64, utf8Decode } from '../../../main/ets/util/Base64';

export default function qqMusicLyricCodecTest(): void {
  describe('QQMusicLyricCodec', () => {
    // ---- decodeQQMusicLyricPayload --------------------------------------
    it('passesPlainLrcThrough', 0, () => {
      expect(decodeQQMusicLyricPayload('[00:00.00]hello')).assertEqual('[00:00.00]hello');
    });

    it('unescapesHtmlEntitiesInPlainText', 0, () => {
      expect(htmlUnescapeQQMusic('a&#39;b&apos;c&quot;d&amp;e')).assertEqual("a'b'c\"d&e");
    });

    it('rejectsInvalidBase64InsteadOfReturningThePayload', 0, () => {
      expect(decodeQQMusicLyricPayload('not-a-lyric')).assertEqual('');
      // "hello" alone decodes to valid base64 but carries no LRC timestamp.
      expect(decodeQQMusicLyricPayload('aGVsbG8=')).assertEqual('');
    });

    it('decodesOnlyBase64PayloadsThatContainLrcTimestamps', 0, () => {
      expect(decodeQQMusicLyricPayload('WzAwOjAxLjAwXWhlbGxv')).assertEqual('[00:01.00]hello');
      expect(decodeQQMusicBase64Lyric('aGVsbG8gd29ybGQ=')).assertEqual('');
    });

    it('decodesMultibyteBase64Payloads', 0, () => {
      // base64("[00:01.00]夜に駆ける")
      expect(decodeQQMusicLyricPayload('WzAwOjAxLjAwXeWknOOBq+mnhuOBkeOCiw=='))
        .assertEqual('[00:01.00]夜に駆ける');
    });

    it('emptyInputYieldsEmptyOutput', 0, () => {
      expect(decodeQQMusicLyricPayload('')).assertEqual('');
      expect(decodeQQMusicLyricPayload('   ')).assertEqual('');
    });

    // ---- stripUntranslatedPlaceholderLines -------------------------------
    it('preservesAndNormalizesPlaceholderLinesForMatcherAlignment', 0, () => {
      const normalized = stripUntranslatedPlaceholderLines(
        '[ti:夜に駆ける]\n[00:00.00]／／\n[00:01.80]像是沉溺溶化一般\n[00:09.20]//\n[00:31.58]你只留下了一句「再见了」'
      );
      expect(normalized).assertEqual(
        '[ti:夜に駆ける]\n[00:00.00]//\n[00:01.80]像是沉溺溶化一般\n[00:09.20]//\n[00:31.58]你只留下了一句「再见了」'
      );
    });

    it('keepsTranslationLinesThatMerelyContainSlashes', 0, () => {
      expect(stripUntranslatedPlaceholderLines('[00:01.00]AC//DC 现场'))
        .assertEqual('[00:01.00]AC//DC 现场');
    });

    it('keepsPlaceholderOnlyTranslationForMatcherAlignment', 0, () => {
      expect(stripUntranslatedPlaceholderLines('[00:00.00]//\n[00:01.00]//'))
        .assertEqual('[00:00.00]//\n[00:01.00]//');
    });

    it('returnsEmptyForMissingTranslation', 0, () => {
      expect(stripUntranslatedPlaceholderLines('')).assertEqual('');
      expect(stripUntranslatedPlaceholderLines('   ')).assertEqual('');
    });

    // ---- util/Base64 decode round-trip (new helper) ----------------------
    it('base64DecodeRoundTripsUtf8', 0, () => {
      const source = '你好，世界！';
      const encoded = encodeBase64(new Uint8Array([0xe4, 0xbd, 0xa0, 0xe5, 0xa5, 0xbd]));
      expect(encoded).assertEqual('5L2g5aW9');
      const bytes = decodeBase64('5L2g5aW977yM5LiW55WM77yB');
      expect(bytes === null).assertFalse();
      if (bytes !== null) {
        expect(utf8Decode(bytes)).assertEqual(source);
      }
    });

    it('base64DecodeRejectsBrokenInput', 0, () => {
      expect(decodeBase64('abc')).assertNull();
      expect(decodeBase64('a=b=c=d')).assertNull();
      expect(decodeBase64('abcd=efgh')).assertNull();
    });
  });
}
