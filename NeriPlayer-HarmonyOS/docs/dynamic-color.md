# Dynamic cover color port status

- `util/CoverColorExtractor.ets` (new)
  - Downloads cover bytes through `HttpClient.getBytes`.
  - Decodes a 12x12 RGBA PixelMap with Image Kit.
  - Picks the highest-saturation pixel within an acceptable luminance range,
    falling back to the average visible color.
- `view/pages/NowPlayingPage.ets`
  - Extracts the accent after song/lyric load when `np.dynamic_color` is enabled.
  - Applies the accent to the progress Slider and passes it into `LyricView`.
- `view/components/LyricView.ets`
  - New `accentColor` prop; the active lyric line uses it when available.
- `view/pages/SettingsPage.ets`
  - Dynamic-color row now reflects the implemented cover sampler.

Remaining for full Material You parity: wallpaper seed extraction, seed-based
palette generation for global Theme, and persisted per-cover accents.
