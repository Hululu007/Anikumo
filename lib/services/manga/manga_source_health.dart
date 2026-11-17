import 'dart:async';
import 'dart:convert';

import 'package:anikumo/services/storage/settings_keys.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 271: accumulated per-source health from REAL
/// usage — the diagnostics page's on-demand test says
/// whether a source works right now; this says how it has
/// been behaving for the user lately (success rate, last
/// error, typical latency).
///
/// Recording is best-effort and cheap: counters live in
/// memory, persistence is debounced, and a recording
/// failure never affects the call being measured.
class MangaSourceHealth {
  MangaSourceHealth._();

  static final Map<String, SourceHealthStats> _stats = {};
  static bool _loaded = false;
  static Timer? _persistTimer;

  static void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = GStorage.getSetting(SettingsKeys.mangaSourceHealthJson);
      if (raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((key, value) {
          if (key is String && value is Map) {
            _stats[key] = SourceHealthStats.fromJson(
              value.cast<String, dynamic>(),
            );
          }
        });
      }
    } catch (_) {
      // Corrupt stats are disposable.
    }
  }

  /// A snapshot for display, best sources first by volume.
  static Map<String, SourceHealthStats> snapshot() {
    _ensureLoaded();
    return Map.unmodifiable(_stats);
  }

  static void record(
    String sourceId, {
    required bool ok,
    required int elapsedMs,
    String? error,
  }) {
    if (sourceId.isEmpty) return;
    try {
      _ensureLoaded();
      final stats = _stats.putIfAbsent(sourceId, SourceHealthStats.new);
      stats.record(ok: ok, elapsedMs: elapsedMs, error: error);
      _persistTimer?.cancel();
      _persistTimer = Timer(const Duration(seconds: 5), _persist);
    } catch (_) {}
  }

  static void _persist() {
    try {
      GStorage.putSetting(
        SettingsKeys.mangaSourceHealthJson,
        jsonEncode({
          for (final entry in _stats.entries) entry.key: entry.value.toJson(),
        }),
      );
    } catch (_) {}
  }

  static void clear() {
    _ensureLoaded();
    _stats.clear();
    _persist();
  }
}

/// Counters for one source. Pure value type; the recording
/// math is unit-tested.
class SourceHealthStats {
  SourceHealthStats({
    this.okCount = 0,
    this.failCount = 0,
    this.totalMs = 0,
    this.lastError = '',
    this.lastErrorAtMs = 0,
    this.lastOkAtMs = 0,
  });

  int okCount;
  int failCount;
  int totalMs;
  String lastError;
  int lastErrorAtMs;
  int lastOkAtMs;

  int get total => okCount + failCount;

  double? get successRate => total == 0 ? null : okCount / total;

  int? get averageMs => total == 0 ? null : (totalMs / total).round();

  void record({required bool ok, required int elapsedMs, String? error}) {
    totalMs += elapsedMs;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (ok) {
      okCount++;
      lastOkAtMs = now;
    } else {
      failCount++;
      lastError = (error ?? '').trim();
      if (lastError.length > 200) {
        lastError = lastError.substring(0, 200);
      }
      lastErrorAtMs = now;
    }
  }

  Map<String, dynamic> toJson() => {
        'ok': okCount,
        'fail': failCount,
        'ms': totalMs,
        'err': lastError,
        'errAt': lastErrorAtMs,
        'okAt': lastOkAtMs,
      };

  factory SourceHealthStats.fromJson(Map<String, dynamic> json) {
    int readInt(String key) {
      final value = json[key];
      return value is num ? value.toInt() : 0;
    }

    return SourceHealthStats(
      okCount: readInt('ok'),
      failCount: readInt('fail'),
      totalMs: readInt('ms'),
      lastError: json['err']?.toString() ?? '',
      lastErrorAtMs: readInt('errAt'),
      lastOkAtMs: readInt('okAt'),
    );
  }
}
