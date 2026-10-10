import { describe, it, expect } from '@ohos/hypium';
import { DownloadDirectory } from '../../../main/ets/download/DownloadDirectory';

export default function downloadDirectoryTest(): void {
  describe('DownloadDirectory', () => {
    it('isCustomUriAcceptsPickedFolderUri', 0, () => {
      expect(DownloadDirectory.isCustomUri('file://docs/storage/Users/currentUser/Music')).assertTrue();
    });

    it('isCustomUriRejectsEmptySandboxAndBareScheme', 0, () => {
      expect(DownloadDirectory.isCustomUri('')).assertFalse();
      expect(DownloadDirectory.isCustomUri('/data/storage/el2/base/files/Download/NeriPlayer')).assertFalse();
      expect(DownloadDirectory.isCustomUri('file://')).assertFalse();
      expect(DownloadDirectory.isCustomUri('file:///')).assertFalse();
    });

    it('resolveActiveDirPrefersCustomUriAndFallsBackToSandbox', 0, () => {
      const filesDir = '/data/storage/el2/base/files';
      const custom = 'file://docs/storage/Users/currentUser/Music';
      expect(DownloadDirectory.resolveActiveDir(custom, filesDir)).assertEqual(custom);
      expect(DownloadDirectory.resolveActiveDir('', filesDir))
        .assertEqual(`${filesDir}/Download/NeriPlayer`);
      expect(DownloadDirectory.resolveActiveDir('/not/a/uri', filesDir))
        .assertEqual(`${filesDir}/Download/NeriPlayer`);
    });

    it('sandboxDefaultDirAppendsSuffix', 0, () => {
      expect(DownloadDirectory.sandboxDefaultDir('/data/storage/el2/base/files'))
        .assertEqual('/data/storage/el2/base/files/Download/NeriPlayer');
    });

    it('mergeHistoryUrisPutsNewestFirstAndDeduplicates', 0, () => {
      const old = 'file://docs/storage/Users/currentUser/Music';
      const fresh = 'file://docs/storage/Users/currentUser/Download';
      expect(DownloadDirectory.mergeHistoryUris(old, fresh))
        .assertEqual(`${fresh}\n${old}`);
      // Re-applying the same directory must not duplicate it.
      expect(DownloadDirectory.mergeHistoryUris(`${fresh}\n${old}`, fresh))
        .assertEqual(`${fresh}\n${old}`);
      // Empty/garbage history lines are dropped on merge.
      expect(DownloadDirectory.mergeHistoryUris(`\n${old}\n/sandbox/path`, fresh))
        .assertEqual(`${fresh}\n${old}`);
    });

    it('mergeHistoryUrisCapsTheListAtDefaultEight', 0, () => {
      let stored = '';
      const expected: string[] = [];
      for (let i = 0; i < 10; i++) {
        const uri = `file://docs/storage/Users/currentUser/dir${i}`;
        stored = DownloadDirectory.mergeHistoryUris(stored, uri);
        expected.unshift(uri);
      }
      const kept = DownloadDirectory.historyUrisOf(stored);
      expect(kept.length).assertEqual(8);
      expect(kept[0]).assertEqual('file://docs/storage/Users/currentUser/dir9');
      expect(kept.indexOf('file://docs/storage/Users/currentUser/dir1') < 0).assertTrue();
      expect(kept[7]).assertEqual('file://docs/storage/Users/currentUser/dir2');
    });

    it('historyUrisOfFiltersNonUriLines', 0, () => {
      const uris = DownloadDirectory.historyUrisOf(
        'file://docs/storage/a\n\n/sandbox/path\nfile://docs/storage/b');
      expect(uris.length).assertEqual(2);
      expect(uris[0]).assertEqual('file://docs/storage/a');
      expect(uris[1]).assertEqual('file://docs/storage/b');
    });

    it('labelFromUriTakesDecodedLastSegment', 0, () => {
      expect(DownloadDirectory.labelFromUri('file://docs/storage/Users/currentUser/Music'))
        .assertEqual('Music');
      expect(DownloadDirectory.labelFromUri('file://docs/storage/Users/currentUser/Music/'))
        .assertEqual('Music');
      expect(DownloadDirectory.labelFromUri('file://docs/storage/Users/currentUser/%E9%9F%B3%E4%B9%90'))
        .assertEqual('音乐');
      expect(DownloadDirectory.labelFromUri('file://docs/storage/Users/currentUser/My%20Music'))
        .assertEqual('My Music');
    });

    it('labelFromUriReturnsEmptyForInvalidInput', 0, () => {
      expect(DownloadDirectory.labelFromUri('')).assertEqual('');
      expect(DownloadDirectory.labelFromUri('/data/storage/el2/base')).assertEqual('');
    });

    it('describeDirectoryPrefersStoredLabelThenDerivedThenDefault', 0, () => {
      expect(DownloadDirectory.describeDirectory('', 'whatever'))
        .assertEqual(DownloadDirectory.DEFAULT_DESCRIPTION);
      const uri = 'file://docs/storage/Users/currentUser/Music';
      expect(DownloadDirectory.describeDirectory(uri, 'My Music')).assertEqual('My Music');
      expect(DownloadDirectory.describeDirectory(uri, '')).assertEqual('Music');
      expect(DownloadDirectory.describeDirectory(uri, '   ')).assertEqual('Music');
    });

    it('fileInDirJoinsWithoutDoublingSeparator', 0, () => {
      expect(DownloadDirectory.fileInDir('/a/b', 'x.mp3')).assertEqual('/a/b/x.mp3');
      expect(DownloadDirectory.fileInDir('file://docs/a/', 'x.mp3')).assertEqual('file://docs/a/x.mp3');
    });
  });
}
