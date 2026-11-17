import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/modules/bangumi/episode_item.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/novel/novel_api.dart';
import 'package:anikumo/services/novel/novel_library.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 269: 追番 / 追更 update notifications.
///
/// Scope, stated plainly: checks run when the app launches
/// (throttled to one run per 3 hours) — there is no
/// background executor, so a phone that never opens the app
/// gets no pings. When a check finds that a watching anime
/// has aired more episodes than last time, or a favorite
/// novel has more chapters, a local notification is posted.
/// The first sighting of any work only records the baseline;
/// enabling the feature never spams the back-catalogue.
class UpdateNotificationService {
  UpdateNotificationService._();

  static const _channelId = 'anikumo_updates';
  static const _maxAnimePerRun = 30;
  static const _maxNovelsPerRun = 15;
  static const _throttle = Duration(hours: 3);

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool? _available;

  // ---- pure helpers (unit-tested) ----

  /// Episodes that have aired by [now]. Bangumi lists
  /// announced episodes with air dates; an episode counts
  /// once its air date is today or earlier. When no episode
  /// carries a parseable date at all, fall back to the list
  /// length (some subjects only carry announced counts).
  static int airedCount(List<EpisodeInfo> episodes, DateTime now) {
    var dated = 0;
    var aired = 0;
    final today = DateTime(now.year, now.month, now.day);
    for (final ep in episodes) {
      final parsed = DateTime.tryParse(ep.airDate);
      if (parsed == null) continue;
      dated++;
      final day = DateTime(parsed.year, parsed.month, parsed.day);
      if (!day.isAfter(today)) aired++;
    }
    return dated == 0 ? episodes.length : aired;
  }

  /// The diff core: given the previously known count for a
  /// work (null = never seen) and the current count, decide
  /// whether to notify. Baselines never notify.
  static bool shouldNotify(int? known, int current) =>
      known != null && current > known;

  static Map<String, int> decodeKnown(String raw) {
    if (raw.isEmpty) return <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry('$key', (value as num?)?.toInt() ?? 0),
        );
      }
    } catch (_) {
      // A corrupt baseline just re-baselines everything.
    }
    return <String, int>{};
  }

  static String encodeKnown(Map<String, int> known) => jsonEncode(known);

  // ---- plugin plumbing ----

  static Future<bool> _ensurePlugin() async {
    if (_available != null) return _available!;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings();
      const linux = LinuxInitializationSettings(
        defaultActionName: 'Open',
      );
      const windows = WindowsInitializationSettings(
        appName: 'Anikumo',
        appUserModelId: 'com.anikumo.app',
        guid: 'a4f1c2e0-3b5d-4e6f-8a9b-0c1d2e3f4a5b',
      );
      await _plugin.initialize(
        const InitializationSettings(
          android: android,
          iOS: darwin,
          macOS: darwin,
          linux: linux,
          windows: windows,
        ),
      );
      _available = true;
    } catch (e) {
      AnikumoLogger().w('UpdateNotify: plugin init failed', error: e);
      _available = false;
    }
    return _available!;
  }

  /// Ask for the Android 13+ notification permission. Called
  /// when the user turns a toggle on; harmless elsewhere.
  static Future<void> requestPermission() async {
    if (!await _ensurePlugin()) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      AnikumoLogger().w('UpdateNotify: permission request failed', error: e);
    }
  }

  static Future<void> _show({
    required String key,
    required String title,
    required String body,
  }) async {
    try {
      await _plugin.show(
        key.hashCode & 0x7fffffff,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            '更新提醒',
            channelDescription: '追番与追更的新内容提醒',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      AnikumoLogger().w('UpdateNotify: show failed', error: e);
    }
  }

  // ---- checks ----

  /// Launch entry point: honors both toggles and the
  /// throttle. [force] skips the throttle (toggle-on path).
  static Future<void> runChecksIfEnabled({bool force = false}) async {
    final animeOn = GStorage.getSetting(SettingsKeys.notifyAnimeUpdates);
    final novelOn = GStorage.getSetting(SettingsKeys.notifyNovelUpdates);
    if (!animeOn && !novelOn) return;
    if (!force) {
      final last = GStorage.getSetting(SettingsKeys.notifyLastCheckMs);
      final elapsed = DateTime.now().millisecondsSinceEpoch - last;
      if (last > 0 && elapsed < _throttle.inMilliseconds) return;
    }
    if (!await _ensurePlugin()) return;
    await GStorage.putSetting(
      SettingsKeys.notifyLastCheckMs,
      DateTime.now().millisecondsSinceEpoch,
    );
    if (animeOn) await _checkAnime();
    if (novelOn) await _checkNovels();
  }

  static Future<void> _checkAnime() async {
    try {
      final watching = GStorage.collectibles.values
          .where((c) => c.type == 1)
          .take(_maxAnimePerRun)
          .toList();
      if (watching.isEmpty) return;
      final known = decodeKnown(
        GStorage.getSetting(SettingsKeys.notifyKnownAnimeJson),
      );
      var changed = false;
      final now = DateTime.now();
      for (final entry in watching) {
        final item = entry.bangumiItem;
        List<EpisodeInfo> episodes;
        try {
          episodes = await BangumiApi.getBangumiEpisodesByID(item.id);
        } catch (_) {
          continue; // one bad subject never blocks the rest
        }
        if (episodes.isEmpty) continue;
        final aired = airedCount(episodes, now);
        final key = '${item.id}';
        final prev = known[key];
        if (prev == null) {
          known[key] = aired;
          changed = true;
          continue;
        }
        if (shouldNotify(prev, aired)) {
          known[key] = aired;
          changed = true;
          final name = item.nameCn.isNotEmpty ? item.nameCn : item.name;
          await _show(
            key: 'anime:${item.id}',
            title: S.t('追番更新'),
            body: S.f('《{}》更新至第 {} 集', [name, aired]),
          );
        }
      }
      if (changed) {
        await GStorage.putSetting(
          SettingsKeys.notifyKnownAnimeJson,
          encodeKnown(known),
        );
      }
    } catch (e) {
      AnikumoLogger().w('UpdateNotify: anime check failed', error: e);
    }
  }

  static Future<void> _checkNovels() async {
    try {
      final favorites =
          NovelLibraryStore.loadFavorites().take(_maxNovelsPerRun).toList();
      if (favorites.isEmpty) return;
      final known = decodeKnown(
        GStorage.getSetting(SettingsKeys.notifyKnownNovelJson),
      );
      var changed = false;
      for (final book in favorites) {
        List<NovelChapter> chapters;
        try {
          chapters = await NovelApi.chapters(book);
        } catch (_) {
          continue;
        }
        if (chapters.isEmpty) continue;
        final key = book.storageKey;
        final prev = known[key];
        if (prev == null) {
          known[key] = chapters.length;
          changed = true;
          continue;
        }
        if (shouldNotify(prev, chapters.length)) {
          known[key] = chapters.length;
          changed = true;
          await _show(
            key: 'novel:$key',
            title: S.t('小说更新'),
            body: S.f('《{}》更新至第 {} 章', [book.title, chapters.length]),
          );
        }
      }
      if (changed) {
        await GStorage.putSetting(
          SettingsKeys.notifyKnownNovelJson,
          encodeKnown(known),
        );
      }
    } catch (e) {
      AnikumoLogger().w('UpdateNotify: novel check failed', error: e);
    }
  }
}
