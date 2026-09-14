#!/usr/bin/env python3
"""Prepend SPDX GPL-3.0 license headers to .ets sources.

Classification:
- core modules ported from the Android upstream (player/download/sync/lyrics/
  listentogether/network + related model/data/util files) get an upstream
  attribution line;
- everything else (view/, app/, entryability/, pages/, remaining self-written
  files) gets a plain GPL-3.0 header without the upstream line.

Skips files that already carry a GPL notice (e.g. SwatchData.ets keeps its MIT
dataset note untouched). Preserves each file's original line endings.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'NeriPlayer-HarmonyOS' / 'entry' / 'src' / 'main' / 'ets'

PORTED_DIRS = ('player/', 'download/', 'sync/', 'lyrics/', 'listentogether/', 'network/')
# model/data/util files whose semantics follow the Android upstream closely
PORTED_FILES = {
    'model/SongItem.ets', 'model/SongIdentity.ets', 'model/LyricModels.ets',
    'model/DownloadModels.ets', 'model/QueueState.ets', 'model/PersistedPlaybackState.ets',
    'data/SettingsRepository.ets', 'data/HistoryRepository.ets', 'data/PlaylistRepository.ets',
    'data/PlaybackStateRepository.ets', 'data/UsageRepository.ets',
    'util/Breakpoint.ets', 'util/NetworkStatus.ets',
}

PORTED_LINES = [
    '// SPDX-License-Identifier: GPL-3.0',
    '// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).',
]
SELF_LINES = [
    '// SPDX-License-Identifier: GPL-3.0',
]


def is_ported(rel: str) -> bool:
    return rel.startswith(PORTED_DIRS) or rel in PORTED_FILES


def main() -> int:
    changed = skipped = 0
    for path in sorted(SRC.rglob('*.ets')):
        rel = path.relative_to(SRC).as_posix()
        raw = path.read_bytes()
        if b'GNU General Public' in raw[:400] or b'SPDX-License-Identifier' in raw[:400]:
            skipped += 1
            continue
        crlf = b'\r\n' in raw[:raw.find(b'\n') + 2] if b'\n' in raw else False
        nl = '\r\n' if crlf else '\n'
        lines = PORTED_LINES if is_ported(rel) else SELF_LINES
        header = nl.join(lines) + nl + nl
        path.write_bytes(header.encode('utf-8') + raw)
        changed += 1
    print(f'changed={changed} skipped={skipped}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
