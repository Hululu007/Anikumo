import 'dart:convert';

import 'package:anikumo/services/storage/settings_keys.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 270: one reader bookmark — a chapter anchor with
/// an optional user note （批注）.
class NovelBookmark {
  const NovelBookmark({
    required this.chapterIndex,
    required this.chapterTitle,
    required this.excerpt,
    required this.note,
    required this.createdAtMs,
  });

  final int chapterIndex;
  final String chapterTitle;

  /// First readable text of the chapter, so the list stays
  /// recognizable even if the source renames chapters.
  final String excerpt;
  final String note;
  final int createdAtMs;

  Map<String, dynamic> toJson() => {
        'c': chapterIndex,
        't': chapterTitle,
        'e': excerpt,
        'n': note,
        'at': createdAtMs,
      };

  static NovelBookmark? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    return NovelBookmark(
      chapterIndex: (raw['c'] as num?)?.toInt() ?? 0,
      chapterTitle: raw['t'] as String? ?? '',
      excerpt: raw['e'] as String? ?? '',
      note: raw['n'] as String? ?? '',
      createdAtMs: (raw['at'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Batch 270: per-book bookmark store + the markdown export
/// used by the reader's bookmark sheet.
class NovelBookmarks {
  NovelBookmarks._();

  static Map<String, List<NovelBookmark>> decodeAll(String raw) {
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((key, value) {
          final list = <NovelBookmark>[];
          if (value is List) {
            for (final entry in value) {
              final bookmark = NovelBookmark.fromJson(entry);
              if (bookmark != null) list.add(bookmark);
            }
          }
          return MapEntry('$key', list);
        });
      }
    } catch (_) {
      // Corrupt store starts over rather than crashing.
    }
    return {};
  }

  static String encodeAll(Map<String, List<NovelBookmark>> all) =>
      jsonEncode(all.map(
        (key, value) =>
            MapEntry(key, [for (final b in value) b.toJson()]),
      ));

  static List<NovelBookmark> forBook(String storageKey) =>
      decodeAll(GStorage.getSetting(SettingsKeys.novelBookmarksJson))[
          storageKey] ??
      const [];

  static Future<void> _saveAll(
    Map<String, List<NovelBookmark>> all,
  ) async {
    await GStorage.putSetting(
      SettingsKeys.novelBookmarksJson,
      encodeAll(all),
    );
  }

  /// Adds (or replaces, for the same chapter) a bookmark.
  static Future<void> add(String storageKey, NovelBookmark bookmark) async {
    final all = decodeAll(GStorage.getSetting(SettingsKeys.novelBookmarksJson));
    final list = [...(all[storageKey] ?? const <NovelBookmark>[])];
    list.removeWhere((b) => b.chapterIndex == bookmark.chapterIndex);
    list.add(bookmark);
    list.sort((a, b) => a.chapterIndex.compareTo(b.chapterIndex));
    all[storageKey] = list;
    await _saveAll(all);
  }

  static Future<void> remove(String storageKey, int chapterIndex) async {
    final all = decodeAll(GStorage.getSetting(SettingsKeys.novelBookmarksJson));
    final list = [...(all[storageKey] ?? const <NovelBookmark>[])];
    list.removeWhere((b) => b.chapterIndex == chapterIndex);
    if (list.isEmpty) {
      all.remove(storageKey);
    } else {
      all[storageKey] = list;
    }
    await _saveAll(all);
  }

  static Future<void> setNote(
    String storageKey,
    int chapterIndex,
    String note,
  ) async {
    final all = decodeAll(GStorage.getSetting(SettingsKeys.novelBookmarksJson));
    final list = all[storageKey];
    if (list == null) return;
    all[storageKey] = [
      for (final b in list)
        if (b.chapterIndex == chapterIndex)
          NovelBookmark(
            chapterIndex: b.chapterIndex,
            chapterTitle: b.chapterTitle,
            excerpt: b.excerpt,
            note: note,
            createdAtMs: b.createdAtMs,
          )
        else
          b,
    ];
    await _saveAll(all);
  }

  /// Markdown export of one book's bookmarks + notes.
  static String buildExportMarkdown({
    required String bookTitle,
    required List<NovelBookmark> bookmarks,
  }) {
    final out = StringBuffer()
      ..writeln('# 《$bookTitle》书签与批注')
      ..writeln();
    for (final b in bookmarks) {
      out
        ..writeln('## 第 ${b.chapterIndex + 1} 章 · ${b.chapterTitle}')
        ..writeln();
      if (b.excerpt.isNotEmpty) {
        out
          ..writeln('> ${b.excerpt}')
          ..writeln();
      }
      if (b.note.isNotEmpty) {
        out
          ..writeln(b.note)
          ..writeln();
      }
    }
    return out.toString();
  }
}
