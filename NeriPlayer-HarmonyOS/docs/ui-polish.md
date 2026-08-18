# UI polish pass

## Fixed UI bugs

- MiniPlayer progress now uses `positionMs / durationMs` with an explicit
  `total`, so the bar fills correctly.
- Queue sheet now compares the current song by queue index and maps the tapped
  queue index through the shuffle order before calling `playAt`; shuffle-mode
  highlight and tap-to-play are correct.
- Click propagation stopped on MiniPlayer play/next buttons, SongRow overflow
  menu, queue/sleep sheets, and create/rename/add dialogs so inner taps no
  longer trigger the outer row/overlay action.
- LyricView now owns a `Scroller` and follows the active lyric line during
  playback instead of staying at the top of the scroll area.
- NowPlaying primary control keeps the high-contrast white-on-purple style
  while honoring the selected theme elsewhere.

## Emoji icon migration

The first UI pass used emoji glyphs as placeholders. Those glyphs are now
mapped in `util/IconCatalog.ets` to ported/material-style SVG assets and
rendered as `Image` components by `SectionHeader`, `EmptyState`, `SettingRow`,
`StatCard`, and `StatTile`.

Direct `♫` placeholders in Loading, Onboarding, Home, MiniPlayer, NowPlaying,
SongRow, PlaylistDetail, Library, Stats, and Downloads pages were replaced with
`ic_music_note_24.svg` / `ic_neriplayer.svg`.

New SVG assets under `resources/base/media`:
`ic_music_note_24`, `ic_library_music_24`, `ic_history_24`, `ic_bar_chart_24`,
`ic_dark_mode_24`, `ic_palette_24`, `ic_auto_awesome_24`,
`ic_signal_cellular_alt_24`, `ic_storage_24`, `ic_person_24`, `ic_sync_24`,
`ic_group_24`, `ic_settings_24`, `ic_build_24`, `ic_info_24`,
`ic_translate_24`, `ic_mic_24`, `ic_blur_on_24`, `ic_image_24`,
`ic_folder_24`, `ic_delete_24`, `ic_text_fields_24`, `ic_bedtime_24`,
`ic_queue_music_24`, `ic_chevron_right_24`, `ic_close_24`, `ic_star_24`,
`ic_cloud_off_24`, `ic_error_outline_24`, `ic_warning_24`, `ic_add_24`,
`ic_more_horiz_24`.
