/**
 * Compatibility icon mapper. The first HarmonyOS UI pass used emoji glyphs as
 * placeholder icons; this catalog maps those legacy glyphs to the ported SVG
 * assets so every placeholder now renders with the original vector style.
 * Ported from the "ch" icon pass; the final block covers glyphs only present
 * in the newer "su" UI.
 */
export function iconForLegacy(icon: string, fallback: Resource): Resource {
  if (icon === '▶') {
    return $r('app.media.round_play_arrow_24');
  }
  if (icon === '⤓') {
    return $r('app.media.ic_download');
  }
  if (icon === '♪' || icon === '🎵' || icon === '♫') {
    return $r('app.media.ic_music_note_24');
  }
  if (icon === '◐') {
    return $r('app.media.ic_dark_mode_24');
  }
  if (icon === '🎨') {
    return $r('app.media.ic_palette_24');
  }
  if (icon === '✨') {
    return $r('app.media.ic_auto_awesome_24');
  }
  if (icon === '📶') {
    return $r('app.media.ic_signal_cellular_alt_24');
  }
  if (icon === '🗄') {
    return $r('app.media.ic_storage_24');
  }
  if (icon === '👤') {
    return $r('app.media.ic_person_24');
  }
  if (icon === '⇄' || icon === '🔄') {
    return $r('app.media.ic_sync_24');
  }
  if (icon === '👥') {
    return $r('app.media.ic_group_24');
  }
  if (icon === '⚙') {
    return $r('app.media.ic_settings_24');
  }
  if (icon === '🔧') {
    return $r('app.media.ic_build_24');
  }
  if (icon === 'ℹ') {
    return $r('app.media.ic_info_24');
  }
  if (icon === '❤') {
    return $r('app.media.ic_baseline_favorite_24');
  }
  if (icon === '⏱') {
    return $r('app.media.ic_history_24');
  }
  if (icon === '📊') {
    return $r('app.media.ic_bar_chart_24');
  }
  if (icon === '🗂') {
    return $r('app.media.ic_library_music_24');
  }
  if (icon === '📺') {
    return $r('app.media.ic_bilibili');
  }
  if (icon === '🔀') {
    return $r('app.media.ic_shuffle_24');
  }
  if (icon === '📁') {
    return $r('app.media.ic_folder_24');
  }
  if (icon === '🔠') {
    return $r('app.media.ic_text_fields_24');
  }
  if (icon === '🌐') {
    return $r('app.media.ic_translate_24');
  }
  if (icon === '🗣') {
    return $r('app.media.ic_mic_24');
  }
  if (icon === '🌫') {
    return $r('app.media.ic_blur_on_24');
  }
  if (icon === '🖼') {
    return $r('app.media.ic_image_24');
  }
  if (icon === '🧹') {
    return $r('app.media.ic_delete_24');
  }
  if (icon === '📴') {
    return $r('app.media.ic_cloud_off_24');
  }
  if (icon === '!') {
    return $r('app.media.ic_error_outline_24');
  }
  if (icon === '⚠') {
    return $r('app.media.ic_warning_24');
  }
  if (icon === '↻') {
    return $r('app.media.outline_refresh_24');
  }
  if (icon === '★') {
    return $r('app.media.ic_star_24');
  }
  if (icon === '🌙') {
    return $r('app.media.ic_bedtime_24');
  }
  if (icon === '📃') {
    return $r('app.media.ic_queue_music_24');
  }
  // su-only glyphs, mapped to the closest assets from the ported icon set.
  if (icon === '🐙') {
    return $r('app.media.ic_github');
  }
  if (icon === '📋' || icon === '📝') {
    return $r('app.media.ic_text_fields_24');
  }
  return fallback;
}
