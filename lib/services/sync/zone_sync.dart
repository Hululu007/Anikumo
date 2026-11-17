import 'dart:convert';

import 'package:liuguang_models/liuguang_models.dart';
import 'package:anikumo/services/liuguang/film_favorites_io.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/novel/novel_library.dart';
import 'package:anikumo/services/storage/settings_keys.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 274 (#36–#39): WebDAV sync for the manga,
/// novel and film zones, which historically only had
/// local backup. Each zone syncs one JSON bundle:
///
/// - manga: the favorites + progress settings strings
/// - novel: favorites + progress + bookmarks strings
/// - film: the favorites export document (snapshots)
///
/// Merge policy is deliberately simple and lossless:
/// a bundle-level last-writer-wins decided by content
/// hashes against the last synced state. When BOTH
/// sides changed since the last sync, nothing is
/// overwritten — the remote bundle is parked as a
/// conflict (see [SyncConflicts]) for the user to
/// resolve on the conflicts page (#39).

/// Deterministic FNV-1a 64-bit hash (hex) of a payload
/// string — stable across runs, unlike hashCode.
String zonePayloadHash(String payload) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(payload)) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

enum ZoneSyncDecision { none, upload, download, conflict }

/// The pure sync decision. [lastSyncedHash] is the
/// hash both sides agreed on at the last successful
/// sync ('' when never synced).
ZoneSyncDecision decideZoneSync({
  required String localHash,
  required String? remoteHash,
  required String lastSyncedHash,
  required bool localIsEmpty,
}) {
  if (remoteHash == null) return ZoneSyncDecision.upload;
  final localChanged = localHash != lastSyncedHash;
  final remoteChanged = remoteHash != lastSyncedHash;
  if (!localChanged && !remoteChanged) return ZoneSyncDecision.none;
  if (localChanged && remoteChanged) {
    // A fresh device whose local side is still empty
    // has nothing to lose: take the remote bundle.
    return localIsEmpty
        ? ZoneSyncDecision.download
        : ZoneSyncDecision.conflict;
  }
  return localChanged
      ? ZoneSyncDecision.upload
      : ZoneSyncDecision.download;
}

class ZoneBundle {
  final String zone;
  final int updatedAtMs;
  final Map<String, String> payload;

  const ZoneBundle({
    required this.zone,
    required this.updatedAtMs,
    required this.payload,
  });

  String get payloadText => jsonEncode(payload);
  String get hash => zonePayloadHash(payloadText);

  String encode() => jsonEncode({
        'zone': zone,
        'updatedAtMs': updatedAtMs,
        'payload': payload,
      });

  static ZoneBundle? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['payload'] is Map) {
        return ZoneBundle(
          zone: decoded['zone']?.toString() ?? '',
          updatedAtMs: (decoded['updatedAtMs'] as num?)?.toInt() ?? 0,
          payload: {
            for (final e in (decoded['payload'] as Map).entries)
              e.key.toString(): e.value?.toString() ?? '',
          },
        );
      }
    } catch (_) {}
    return null;
  }
}

/// One parked sync conflict (#39).
class SyncConflict {
  final String zone;
  final int detectedAtMs;
  final int remoteUpdatedAtMs;
  final Map<String, String> remotePayload;

  const SyncConflict({
    required this.zone,
    required this.detectedAtMs,
    required this.remoteUpdatedAtMs,
    required this.remotePayload,
  });

  Map<String, dynamic> toJson() => {
        'zone': zone,
        'at': detectedAtMs,
        'remoteAt': remoteUpdatedAtMs,
        'payload': remotePayload,
      };

  static SyncConflict? fromJson(dynamic json) {
    if (json is! Map || json['payload'] is! Map) return null;
    return SyncConflict(
      zone: json['zone']?.toString() ?? '',
      detectedAtMs: (json['at'] as num?)?.toInt() ?? 0,
      remoteUpdatedAtMs: (json['remoteAt'] as num?)?.toInt() ?? 0,
      remotePayload: {
        for (final e in (json['payload'] as Map).entries)
          e.key.toString(): e.value?.toString() ?? '',
      },
    );
  }
}

abstract final class SyncConflicts {
  static List<SyncConflict> load() {
    try {
      final decoded =
          jsonDecode(GStorage.getSetting(SettingsKeys.syncConflictsJson));
      if (decoded is List) {
        return [
          for (final raw in decoded)
            if (SyncConflict.fromJson(raw) case final c?) c,
        ];
      }
    } catch (_) {}
    return [];
  }

  static Future<void> _save(List<SyncConflict> conflicts) {
    return GStorage.putSetting(
      SettingsKeys.syncConflictsJson,
      jsonEncode([for (final c in conflicts) c.toJson()]),
    );
  }

  /// Parks (or replaces) the conflict for [zone].
  static Future<void> park(SyncConflict conflict) async {
    final all = [
      for (final c in load())
        if (c.zone != conflict.zone) c,
      conflict,
    ];
    await _save(all);
  }

  static Future<void> drop(String zone) async {
    await _save([for (final c in load()) if (c.zone != zone) c]);
  }
}

/// Per-zone payload adapters + the sync state ledger.
abstract final class ZoneSyncService {
  static const List<String> zones = ['manga', 'novel', 'film'];

  static String zoneLabel(String zone) => switch (zone) {
        'manga' => '漫画区',
        'novel' => '小说区',
        'film' => '影视区',
        _ => zone,
      };

  // ------------------------------------------------------------
  // Payload build / apply
  // ------------------------------------------------------------

  static Future<Map<String, String>> buildPayload(String zone) async {
    switch (zone) {
      case 'manga':
        return {
          'mangaFavoritesJson':
              GStorage.getSetting(SettingsKeys.mangaFavoritesJson),
          'mangaProgressJson':
              GStorage.getSetting(SettingsKeys.mangaProgressJson),
        };
      case 'novel':
        return {
          'novelFavoritesJson':
              GStorage.getSetting(SettingsKeys.novelFavoritesJson),
          'novelProgressJson':
              GStorage.getSetting(SettingsKeys.novelProgressJson),
          'novelBookmarksJson':
              GStorage.getSetting(SettingsKeys.novelBookmarksJson),
        };
      case 'film':
        final engine = await VideoEngineService.instance.engine();
        final favorites = await engine.favorites.list();
        return {
          'favoritesExport': buildFilmFavoritesExport([
            for (final f in favorites)
              if (f.mediaSnapshot.isNotEmpty) f.mediaSnapshot,
          ]),
        };
      default:
        return {};
    }
  }

  static bool payloadIsEmpty(String zone, Map<String, String> payload) {
    switch (zone) {
      case 'manga':
        return _jsonListIsEmpty(payload['mangaFavoritesJson']) &&
            _jsonMapIsEmpty(payload['mangaProgressJson']);
      case 'novel':
        return _jsonListIsEmpty(payload['novelFavoritesJson']) &&
            _jsonListIsEmpty(payload['novelProgressJson']);
      case 'film':
        final parsed =
            parseFilmFavoritesImport(payload['favoritesExport'] ?? '');
        return parsed is! FilmFavoritesSnapshots ||
            parsed.snapshots.isEmpty;
      default:
        return true;
    }
  }

  static bool _jsonListIsEmpty(String? raw) {
    if (raw == null || raw.isEmpty) return true;
    try {
      final decoded = jsonDecode(raw);
      return decoded is! List || decoded.isEmpty;
    } catch (_) {
      return true;
    }
  }

  static bool _jsonMapIsEmpty(String? raw) {
    if (raw == null || raw.isEmpty) return true;
    try {
      final decoded = jsonDecode(raw);
      return decoded is! Map || decoded.isEmpty;
    } catch (_) {
      return true;
    }
  }

  static Future<void> applyPayload(
    String zone,
    Map<String, String> payload,
  ) async {
    switch (zone) {
      case 'manga':
        await GStorage.putSetting(
          SettingsKeys.mangaFavoritesJson,
          payload['mangaFavoritesJson'] ?? '',
        );
        await GStorage.putSetting(
          SettingsKeys.mangaProgressJson,
          payload['mangaProgressJson'] ?? '',
        );
        MangaLibraryStore.bumpRevisionForSync();
      case 'novel':
        await GStorage.putSetting(
          SettingsKeys.novelFavoritesJson,
          payload['novelFavoritesJson'] ?? '',
        );
        await GStorage.putSetting(
          SettingsKeys.novelProgressJson,
          payload['novelProgressJson'] ?? '',
        );
        await GStorage.putSetting(
          SettingsKeys.novelBookmarksJson,
          payload['novelBookmarksJson'] ?? '',
        );
        NovelLibraryStore.bumpRevisionForSync();
      case 'film':
        // Union semantics (same as the file import):
        // remote favorites are added, local ones are
        // never removed by a sync.
        final parsed =
            parseFilmFavoritesImport(payload['favoritesExport'] ?? '');
        if (parsed is FilmFavoritesSnapshots) {
          final engine = await VideoEngineService.instance.engine();
          for (final snapshot in parsed.snapshots) {
            try {
              final item = TVSeries.mediaFromJson(snapshot);
              if (await engine.favorites.isFavorite(item.id)) continue;
              await engine.favorites.add(item);
            } catch (e) {
              AnikumoLogger().w(
                'ZoneSync: film apply skipped one',
                error: e,
              );
            }
          }
        }
    }
  }

  // ------------------------------------------------------------
  // Sync state ledger
  // ------------------------------------------------------------

  static Map<String, dynamic> _state() {
    try {
      final decoded =
          jsonDecode(GStorage.getSetting(SettingsKeys.zoneSyncStateJson));
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return {};
  }

  static String hashOfPayload(Map<String, String> payload) =>
      zonePayloadHash(jsonEncode(payload));

  static String lastSyncedHash(String zone) =>
      _state()[zone]?['syncedHash']?.toString() ?? '';

  static Future<void> markSynced(String zone, String hash) async {
    final state = _state();
    state[zone] = {
      'syncedHash': hash,
      'at': DateTime.now().millisecondsSinceEpoch,
    };
    await GStorage.putSetting(
      SettingsKeys.zoneSyncStateJson,
      jsonEncode(state),
    );
  }
}
