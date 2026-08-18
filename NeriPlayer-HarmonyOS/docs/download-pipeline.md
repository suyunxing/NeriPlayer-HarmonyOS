# Download pipeline port status

## Scope

- `network/HttpClient.ets`
  - Added `HttpBinaryResponse` and `HttpClient.getBytes()` for raw `ArrayBuffer`
    GET requests with full status/header visibility.
- `model/DownloadTask.ets`
  - Added `filePath`, `etag`, `lastModified` fields for resumable transfers.
- `download/DownloadFileStore.ets` (new)
  - Sandbox `filesDir/downloads` storage, `.part` staging files, chunk writes at
    explicit offsets, final-file commit, sidecar writer.
- `download/DownloadManager.ets` (new)
  - Global queue with configurable concurrency (1-8).
  - Range chunked download (`bytes=start-end`, 2 MiB chunks).
  - Servers that ignore Range fall back to a single 200 body.
  - 416 handling resets a stale partial file and restarts.
  - Pause / resume / retry / delete / clear-all operations.
  - Startup recovery: `DOWNLOADING` tasks become `QUEUED` and resume automatically.
  - Local songs are copied into the download directory instead of re-fetched.
  - On completion writes optional `.lrc` (NetEase / LRCLIB) and `.song.json`
    sidecars controlled by `np.download_match_lyrics`.
  - Progress is persisted with a 500 ms throttle and published through
    `AppStorage.downloads.revision`.
- `data/DownloadsRepository.ets`
  - Catalog mutations are serialized to avoid lost updates from concurrent workers.
  - Task deletion also deletes `.part` and final sandbox files.
- `view/components/SongRow.ets`
  - The download menu item now enqueues into `DownloadManager` and shows a toast.
- `view/pages/DownloadsPage.ets`
  - Live progress bar, pause/continue/retry actions, offline playback for
    completed tasks.
- `entryability/EntryAbility.ets`
  - Initializes `DownloadManager` on ability creation.

## Behavior notes

- Files stay in the app sandbox for now. Directory picker / media-library export
  is a later migration step.
- NetEase stream URLs are resolved once per task. If a URL expires between
  resume attempts, retry re-resolves the stream before continuing.
- YouTube Music downloads still depend on the YouTube stream resolver; they fail
  gracefully and can be retried once that resolver is ported.
- Completed tasks play offline by converting the cached `SongItem` to
  `MusicPlatform.LOCAL` and pointing `localFilePath` at the sandbox file.
