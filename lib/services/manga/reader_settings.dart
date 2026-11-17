// Reader settings model for the manga zone, mirroring Venera's
// reading options: gallery (paged) modes in both directions plus
// a continuous (webtoon) mode.

import 'dart:convert';

import 'package:anikumo/services/storage/settings_keys.dart';
import 'package:anikumo/services/storage/storage.dart';

abstract final class MangaReaderModes {
  /// Paged, pages advance left → right (manhua / western style).
  static const galleryLtr = 'galleryLTR';

  /// Paged, pages advance right → left (manga style).
  static const galleryRtl = 'galleryRTL';

  /// Continuous vertical scroll.
  static const continuous = 'continuous';

  static const labels = <String, String>{
    galleryLtr: '分页 · 从左到右',
    galleryRtl: '分页 · 从右到左（日漫）',
    continuous: '连续滚动 · 条漫',
  };
}

/// Normalizes a stored reader mode, migrating the first version's
/// 'paged' / 'scroll' values to the Venera-style mode names.
String normalizeMangaReaderMode(String raw) {
  return switch (raw) {
    MangaReaderModes.galleryLtr ||
    MangaReaderModes.galleryRtl ||
    MangaReaderModes.continuous =>
      raw,
    'scroll' => MangaReaderModes.continuous,
    _ => MangaReaderModes.galleryLtr,
  };
}

/// Batch 271: per-work reader-mode memory. A vertical-scroll
/// webtoon and a right-to-left manga want different modes;
/// the reader's mode button stores the choice against the
/// work's key and it wins over the global mode on entry.
abstract final class MangaReaderModeMemory {
  /// The pure map transform behind [modeForWork] (tested).
  static String? modeInMap(Map<String, dynamic> map, String workKey) {
    final value = map[workKey];
    if (value is! String || value.isEmpty) return null;
    return normalizeMangaReaderMode(value);
  }

  static Map<String, dynamic> decodeMap(String raw) {
    if (raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return const {};
  }

  static String? modeForWork(String workKey) {
    return modeInMap(
      decodeMap(GStorage.getSetting(SettingsKeys.mangaReaderModeByWorkJson)),
      workKey,
    );
  }

  static Future<void> setModeForWork(String workKey, String? mode) async {
    final map = Map<String, dynamic>.from(
      decodeMap(GStorage.getSetting(SettingsKeys.mangaReaderModeByWorkJson)),
    );
    if (mode == null) {
      map.remove(workKey);
    } else {
      map[workKey] = normalizeMangaReaderMode(mode);
    }
    await GStorage.putSetting(
      SettingsKeys.mangaReaderModeByWorkJson,
      jsonEncode(map),
    );
  }
}

/// Content ratings requested from MangaDex for listings.
List<String> mangaContentRatings(bool allowSuggestive) {
  return allowSuggestive ? const ['safe', 'suggestive'] : const ['safe'];
}
