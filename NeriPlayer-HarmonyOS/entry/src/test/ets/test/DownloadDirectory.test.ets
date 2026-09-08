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
