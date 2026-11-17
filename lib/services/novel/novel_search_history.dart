import 'dart:convert';

import 'package:anikumo/services/storage/settings_keys.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 270: novel search history. Most recent first,
/// de-duplicated, capped. The list transforms are pure so
/// they can be unit-tested without storage.
class NovelSearchHistory {
  NovelSearchHistory._();

  static const maxEntries = 20;

  static List<String> record(List<String> history, String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return history;
    return <String>[
      trimmed,
      for (final entry in history)
        if (entry != trimmed) entry,
    ].take(maxEntries).toList();
  }

  static List<String> decode(String raw) {
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return [
          for (final entry in decoded)
            if (entry is String && entry.isNotEmpty) entry,
        ];
      }
    } catch (_) {
      // Corrupt history just starts over.
    }
    return const [];
  }

  static List<String> load() =>
      decode(GStorage.getSetting(SettingsKeys.novelSearchHistoryJson));

  static Future<void> add(String query) async {
    final next = record(load(), query);
    await GStorage.putSetting(
      SettingsKeys.novelSearchHistoryJson,
      jsonEncode(next),
    );
  }

  static Future<void> clear() async {
    await GStorage.putSetting(SettingsKeys.novelSearchHistoryJson, '');
  }
}
