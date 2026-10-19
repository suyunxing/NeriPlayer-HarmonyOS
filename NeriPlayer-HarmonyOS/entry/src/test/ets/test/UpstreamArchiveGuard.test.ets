// SPDX-License-Identifier: GPL-3.0

import { describe, it, expect } from '@ohos/hypium';
import { utf8EncodeText } from '../../../main/ets/sync/SyncDataJsonCodec';
import {
  UPSTREAM_ARCHIVE_MANIFEST_FILE_NAME,
  describeUpstreamArchiveProtocolForUser,
  isUpstreamArchiveManifest,
  upstreamArchiveProtocolVersion
} from '../../../main/ets/sync/UpstreamArchiveGuard';
import { webDavSiblingFileUrl } from '../../../main/ets/sync/webdav/WebDavTransport';

export default function upstreamArchiveGuardTest(): void {
  describe('UpstreamArchiveGuard', () => {
    it('manifestFileNameMatchesUpstreamLayout', 0, () => {
      expect(UPSTREAM_ARCHIVE_MANIFEST_FILE_NAME).assertEqual('neriplayer-sync-v3.manifest');
    });

    it('recognizesV3AndV4Magic', 0, () => {
      expect(upstreamArchiveProtocolVersion(utf8EncodeText('NPSYNC03rest')))
        .assertEqual(3);
      expect(upstreamArchiveProtocolVersion(utf8EncodeText('NPSYNC04rest')))
        .assertEqual(4);
      expect(isUpstreamArchiveManifest(utf8EncodeText('NPSYNC04rest'))).assertTrue();
    });

    it('rejectsLegacyPayloadShapes', 0, () => {
      expect(isUpstreamArchiveManifest(utf8EncodeText('{"playlists":[]}'))).assertFalse();
      expect(isUpstreamArchiveManifest(utf8EncodeText('H4sIAAAAA'))).assertFalse();
      expect(isUpstreamArchiveManifest(utf8EncodeText('NPSYNC0'))).assertFalse();
      expect(isUpstreamArchiveManifest(utf8EncodeText('NPSYN'))).assertFalse();
      expect(isUpstreamArchiveManifest(new Uint8Array(0))).assertFalse();
      // Magic without a trailing protocol digit is not decodable.
      expect(upstreamArchiveProtocolVersion(utf8EncodeText('NPSYNC0X'))).assertEqual(-1);
    });

    it('userMessageNamesProtocol', 0, () => {
      expect(describeUpstreamArchiveProtocolForUser(4).includes('v4')).assertTrue();
      expect(describeUpstreamArchiveProtocolForUser(4).includes('数据分叉')).assertTrue();
    });

    it('webDavSiblingUrlReplacesLastSegment', 0, () => {
      expect(webDavSiblingFileUrl('https://dav.example/dav/neriplayer-sync.json',
        UPSTREAM_ARCHIVE_MANIFEST_FILE_NAME))
        .assertEqual('https://dav.example/dav/neriplayer-sync-v3.manifest');
      expect(webDavSiblingFileUrl('https://dav.example/file', 'x.manifest'))
        .assertEqual('https://dav.example/x.manifest');
    });
  });
}
