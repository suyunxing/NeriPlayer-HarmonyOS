import { describe, it, expect } from '@ohos/hypium';
import { DownloadLyricSidecar } from '../../../main/ets/download/DownloadLyricSidecar';
import { LrcParser } from '../../../main/ets/lyrics/LrcParser';
import { LyricLine } from '../../../main/ets/model/LyricLine';

export default function downloadLyricSidecarTest(): void {
  describe('DownloadLyricSidecar', () => {
    it('derivesSidecarPathFromAudioPath', 0, () => {
      expect(DownloadLyricSidecar.sidecarPath('/files/Download/NeriPlayer/song.m4a'))
        .assertEqual('/files/Download/NeriPlayer/song.lrc');
      expect(DownloadLyricSidecar.sidecarPath('file:///files/a/b/c.mp3'))
        .assertEqual('/files/a/b/c.lrc');
      expect(DownloadLyricSidecar.sidecarPath('/files/noext'))
        .assertEqual('/files/noext.lrc');
      // Dots in the directory must not be mistaken for the extension dot.
      expect(DownloadLyricSidecar.sidecarPath('/files/v1.2/song.flac'))
        .assertEqual('/files/v1.2/song.lrc');
    });

    it('buildsLrcTextWithTranslationCompanionLines', 0, () => {
      const first = new LyricLine(1000, '歌词一', '');
      first.translated = 'lyric one';
      const second = new LyricLine(5000, '歌词二', '');
      const third = new LyricLine(9000, '', '');
      third.translated = 'translation-only line';
      const text = DownloadLyricSidecar.buildSidecarText([first, second, third]);
      const lines = text.split('\n');
      // Two main lines + one translation companion; the translation-only
      // line survives once via its translated text.
      expect(lines.length).assertEqual(4);
      expect(lines[0]).assertEqual('[00:01.000]歌词一');
      expect(lines[1]).assertEqual('[00:05.000]歌词二');
      expect(lines[2]).assertEqual('[00:09.000]translation-only line');
      expect(lines[3]).assertEqual('[00:01.000]lyric one');
    });

    it('sidecarTextRoundTripsThroughLrcParser', 0, () => {
      const first = new LyricLine(12580, '难以忘记', '');
      first.translated = 'hard to forget';
      const second = new LyricLine(16050, '初次见你', '');
      const text = DownloadLyricSidecar.buildSidecarText([first, second]);
      const parsed = LrcParser.parse(text);
      // Main lines parse with exact timestamps…
      expect(parsed.length).assertEqual(3);
      expect(parsed[0].timeMs).assertEqual(12580);
      expect(parsed[0].text).assertEqual('难以忘记');
      // …and the same-timestamp translation companion merges back in.
      const merged = LrcParser.mergeTranslation(parsed, text);
      expect(merged[0].translated).assertEqual('hard to forget');
    });

    it('emptyLinesProduceEmptyText', 0, () => {
      expect(DownloadLyricSidecar.buildSidecarText([])).assertEqual('');
      const blank = new LyricLine(0, '   ', '');
      expect(DownloadLyricSidecar.buildSidecarText([blank])).assertEqual('');
    });
  });
}
