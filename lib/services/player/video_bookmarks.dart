import 'dart:convert';

import 'package:anikumo/services/storage/settings_keys.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 273 (#12): timestamp bookmarks inside the
/// video player — a note pinned to a playback position
/// of one episode, stored per episode key.
///
/// The episode key is supplied by the player page:
/// `anime:<bangumiId>:<episode>` for anime sessions,
/// `ext:<title>:<episode label>` for external (film)
/// sessions, so both zones share the store without
/// sharing any zone code.
class VideoBookmark {
  final int seconds;
  final String note;
  final int createdAtMs;

  const VideoBookmark({
    required this.seconds,
    required this.note,
    required this.createdAtMs,
  });

  Map<String, dynamic> toJson() => {
        's': seconds,
        'n': note,
        'at': createdAtMs,
      };

  static VideoBookmark? fromJson(dynamic json) {
    if (json is! Map) return null;
    final seconds = (json['s'] as num?)?.toInt();
    if (seconds == null) return null;
    return VideoBookmark(
      seconds: seconds,
      note: json['n']?.toString() ?? '',
      createdAtMs: (json['at'] as num?)?.toInt() ?? 0,
    );
  }
}

abstract final class VideoBookmarks {
  static Map<String, List<VideoBookmark>> decodeAll(String raw) {
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return {
          for (final e in decoded.entries)
            e.key.toString(): [
              for (final raw in (e.value as List? ?? const []))
                if (VideoBookmark.fromJson(raw) case final b?) b,
            ]..sort((a, b) => a.seconds.compareTo(b.seconds)),
        };
      }
    } catch (_) {}
    return {};
  }

  static Map<String, List<VideoBookmark>> _all() =>
      decodeAll(GStorage.getSetting(SettingsKeys.videoBookmarksJson));

  static List<VideoBookmark> forEpisode(String episodeKey) =>
      _all()[episodeKey] ?? const [];

  static Future<void> _saveAll(
    Map<String, List<VideoBookmark>> all,
  ) {
    return GStorage.putSetting(
      SettingsKeys.videoBookmarksJson,
      jsonEncode({
        for (final e in all.entries)
          if (e.value.isNotEmpty)
            e.key: [for (final b in e.value) b.toJson()],
      }),
    );
  }

  /// Adds (or replaces, within the same second) a
  /// bookmark for [episodeKey].
  static Future<List<VideoBookmark>> add(
    String episodeKey,
    VideoBookmark bookmark,
  ) async {
    final all = _all();
    final list = [
      for (final b in all[episodeKey] ?? const <VideoBookmark>[])
        if (b.seconds != bookmark.seconds) b,
      bookmark,
    ]..sort((a, b) => a.seconds.compareTo(b.seconds));
    all[episodeKey] = list;
    await _saveAll(all);
    return list;
  }

  static Future<List<VideoBookmark>> remove(
    String episodeKey,
    int seconds,
  ) async {
    final all = _all();
    final list = [
      for (final b in all[episodeKey] ?? const <VideoBookmark>[])
        if (b.seconds != seconds) b,
    ];
    all[episodeKey] = list;
    await _saveAll(all);
    return list;
  }
}
