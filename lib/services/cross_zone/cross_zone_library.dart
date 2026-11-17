import 'package:flutter/widgets.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:liuguang_models/liuguang_models.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/pages/liuguang/film_widgets.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/novel/novel_library.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 275 (#43/#45): cross-zone aggregation of the
/// user's own library — one mixed "continue" list for
/// the home rail (#45) and per-zone favorite shelves
/// for the overview page (#43). Read-only: every entry
/// opens the owning zone's own detail page through
/// that zone's established route, and nothing here
/// writes to any zone's store.

class ContinueEntry {
  final String zone; // 'anime' | 'manga' | 'novel' | 'film'
  final String title;
  final String subtitle;
  final String coverUrl;
  final int updatedAtMs;
  final void Function(BuildContext context) open;

  const ContinueEntry({
    required this.zone,
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.updatedAtMs,
    required this.open,
  });
}

/// Merges per-zone continue lists into one rail order:
/// most recently touched first, capped per zone so one
/// binge cannot flood the rail.
List<ContinueEntry> mergeContinueEntries(
  List<ContinueEntry> all, {
  int perZoneCap = 6,
  int totalCap = 12,
}) {
  final sorted = [...all]
    ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
  final counts = <String, int>{};
  final out = <ContinueEntry>[];
  for (final entry in sorted) {
    final count = counts[entry.zone] ?? 0;
    if (count >= perZoneCap) continue;
    counts[entry.zone] = count + 1;
    out.add(entry);
    if (out.length >= totalCap) break;
  }
  return out;
}

abstract final class CrossZoneLibrary {
  /// The mixed continue list (#45). Film entries need
  /// the engine, hence async; failures in one zone
  /// never sink the others.
  static Future<List<ContinueEntry>> continueEntries() async {
    final entries = <ContinueEntry>[];

    // Anime: watch history.
    try {
      final histories = [...GStorage.histories.values]
        ..sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
      for (final history in histories.take(8)) {
        final item = history.bangumiItem;
        entries.add(
          ContinueEntry(
            zone: 'anime',
            title: item.nameCn.isNotEmpty ? item.nameCn : item.name,
            subtitle: history.lastWatchEpisodeName.isNotEmpty
                ? history.lastWatchEpisodeName
                : '第 ${history.lastWatchEpisode} 集',
            coverUrl: item.images['common'] ?? '',
            updatedAtMs: history.lastWatchTime.millisecondsSinceEpoch,
            open: (context) =>
                context.pushNamed('/info/', arguments: item),
          ),
        );
      }
    } catch (_) {}

    // Manga: reading progress.
    try {
      final progress = [...MangaLibraryStore.loadProgressList()]
        ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
      for (final entry in progress.take(8)) {
        final item = MangaItem(
          id: entry.mangaId,
          title: entry.mangaTitle,
          description: '',
          coverUrl: entry.coverUrl,
          author: '',
          status: '',
          year: null,
          tags: const [],
          source: entry.mangaSource,
        );
        entries.add(
          ContinueEntry(
            zone: 'manga',
            title: entry.mangaTitle,
            subtitle: entry.chapterLabel,
            coverUrl: entry.coverUrl,
            updatedAtMs: entry.updatedAtMs,
            open: (context) =>
                context.pushNamed('/manga/detail', arguments: item),
          ),
        );
      }
    } catch (_) {}

    // Novel: reading progress.
    try {
      final progress = [...NovelLibraryStore.loadProgressList()]
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      for (final entry in progress.take(8)) {
        final NovelItem item = entry.item;
        entries.add(
          ContinueEntry(
            zone: 'novel',
            title: item.title,
            subtitle: entry.chapterTitle,
            coverUrl: item.coverUrl,
            updatedAtMs: entry.updatedAt,
            open: (context) =>
                context.pushNamed('/novel/detail', arguments: item),
          ),
        );
      }
    } catch (_) {}

    // Film: engine continue-watching.
    try {
      final engine = await VideoEngineService.instance.engine();
      final rows = await engine.history.continueWatching(limit: 8);
      final favorites = await engine.favorites.list();
      final snapshots = <String, Map<String, dynamic>>{
        for (final f in favorites)
          if (f.mediaSnapshot.isNotEmpty) f.mediaId: f.mediaSnapshot,
      };
      for (final row in rows) {
        final snapshot = snapshots[row.mediaId];
        entries.add(
          ContinueEntry(
            zone: 'film',
            title: row.title,
            subtitle: row.episodeId ?? '',
            coverUrl: snapshot?['coverUrl']?.toString() ?? '',
            updatedAtMs: row.lastPlayedAt.millisecondsSinceEpoch,
            open: (context) {
              if (snapshot != null) {
                openFilmDetail(
                  context,
                  TVSeries.mediaFromJson(snapshot),
                );
              } else {
                context.pushNamed('/film/history');
              }
            },
          ),
        );
      }
    } catch (_) {}

    return mergeContinueEntries(entries);
  }

  /// Per-zone favorite counts for the overview header.
  static Future<Map<String, int>> favoriteCounts() async {
    var filmCount = 0;
    try {
      final engine = await VideoEngineService.instance.engine();
      filmCount = (await engine.favorites.list()).length;
    } catch (_) {}
    return {
      'anime': GStorage.collectibles.length,
      'manga': MangaLibraryStore.loadFavorites().length,
      'novel': NovelLibraryStore.loadFavorites().length,
      'film': filmCount,
    };
  }
}
