import 'dart:convert';

import 'package:liuguang_network/liuguang_network.dart';

import 'package:anikumo/services/liuguang/tvmaze_covers.dart';
import 'package:anikumo/services/storage/settings_keys.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 272 (#31): 追剧日历 — upcoming episode air
/// dates for favorited series, from TVmaze's public
/// schedule data (the same source the zone's series
/// covers come from; no account or key).
///
/// Resolution is deliberately conservative, mirroring
/// the cover matcher: a show only joins the calendar
/// when TVmaze's top search hit matches the title
/// confidently. Resolved show ids are cached so opening
/// the calendar does not re-search every favorite.
class TvmazeCalendarEntry {
  final String showTitle;
  final int season;
  final int number;
  final String episodeName;
  final DateTime airDate;
  final String airTime;
  final int? runtimeMinutes;

  const TvmazeCalendarEntry({
    required this.showTitle,
    required this.season,
    required this.number,
    required this.episodeName,
    required this.airDate,
    required this.airTime,
    required this.runtimeMinutes,
  });

  String get code => 'S${season}E$number';
}

/// Picks the TVmaze show id for [title] out of a decoded
/// /search/shows payload: the best-scoring entry whose
/// name matches the (normalized) title exactly, or null.
int? pickTvmazeShowId(dynamic decoded, {required String title}) {
  if (decoded is! List) return null;
  final wanted = tvmazeSearchTitle(title).toLowerCase();
  int? bestId;
  var bestScore = -1.0;
  for (final entry in decoded) {
    if (entry is! Map) continue;
    final show = entry['show'];
    if (show is! Map) continue;
    final name = show['name']?.toString().toLowerCase() ?? '';
    if (name != wanted) continue;
    final score = (entry['score'] as num?)?.toDouble() ?? 0;
    final id = (show['id'] as num?)?.toInt();
    if (id != null && score > bestScore) {
      bestScore = score;
      bestId = id;
    }
  }
  return bestId;
}

/// Parses a decoded /shows/{id}/episodes payload into
/// calendar entries airing inside [from, to] (inclusive
/// by calendar day).
List<TvmazeCalendarEntry> parseTvmazeEpisodes(
  dynamic decoded, {
  required String showTitle,
  required DateTime from,
  required DateTime to,
}) {
  if (decoded is! List) return const [];
  final fromDay = DateTime(from.year, from.month, from.day);
  final toDay = DateTime(to.year, to.month, to.day);
  final out = <TvmazeCalendarEntry>[];
  for (final raw in decoded) {
    if (raw is! Map) continue;
    final airdate = raw['airdate']?.toString() ?? '';
    final parsed = DateTime.tryParse(airdate);
    if (parsed == null) continue;
    final day = DateTime(parsed.year, parsed.month, parsed.day);
    if (day.isBefore(fromDay) || day.isAfter(toDay)) continue;
    out.add(
      TvmazeCalendarEntry(
        showTitle: showTitle,
        season: (raw['season'] as num?)?.toInt() ?? 0,
        number: (raw['number'] as num?)?.toInt() ?? 0,
        episodeName: raw['name']?.toString() ?? '',
        airDate: day,
        airTime: raw['airtime']?.toString() ?? '',
        runtimeMinutes: (raw['runtime'] as num?)?.toInt(),
      ),
    );
  }
  out.sort((a, b) {
    final byDay = a.airDate.compareTo(b.airDate);
    if (byDay != 0) return byDay;
    final byTime = a.airTime.compareTo(b.airTime);
    if (byTime != 0) return byTime;
    return a.showTitle.compareTo(b.showTitle);
  });
  return out;
}

abstract final class TvmazeCalendar {
  static const String _ua = 'Anikumo';

  static Map<String, int> _idCache() {
    try {
      final raw =
          GStorage.getSetting(SettingsKeys.tvmazeCalendarShowIdsJson);
      if (raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return {
          for (final e in decoded.entries)
            if (e.value is num) e.key.toString(): (e.value as num).toInt(),
        };
      }
    } catch (_) {}
    return {};
  }

  /// Upcoming episodes for [titles] over the next
  /// [days] days (including today). Shows that cannot
  /// be resolved confidently are skipped silently.
  static Future<List<TvmazeCalendarEntry>> upcoming({
    required List<String> titles,
    required int days,
    DateTime? now,
  }) async {
    final client = LiuGuangHttpClient();
    final from = now ?? DateTime.now();
    final to = from.add(Duration(days: days));
    final cache = _idCache();
    var cacheDirty = false;
    final entries = <TvmazeCalendarEntry>[];
    for (final title in titles) {
      try {
        var showId = cache[title];
        if (showId == null) {
          final query = Uri.encodeQueryComponent(tvmazeSearchTitle(title));
          final decoded = await client.getJson(
            'https://api.tvmaze.com/search/shows?q=$query',
            headers: const {'User-Agent': _ua},
          );
          showId = pickTvmazeShowId(decoded, title: title);
          if (showId == null) continue;
          cache[title] = showId;
          cacheDirty = true;
        }
        final episodes = await client.getJson(
          'https://api.tvmaze.com/shows/$showId/episodes',
          headers: const {'User-Agent': _ua},
        );
        entries.addAll(
          parseTvmazeEpisodes(
            episodes,
            showTitle: title,
            from: from,
            to: to,
          ),
        );
      } catch (_) {
        // One bad show must not sink the whole calendar.
        continue;
      }
    }
    if (cacheDirty) {
      await GStorage.putSetting(
        SettingsKeys.tvmazeCalendarShowIdsJson,
        jsonEncode(cache),
      );
    }
    entries.sort((a, b) {
      final byDay = a.airDate.compareTo(b.airDate);
      if (byDay != 0) return byDay;
      final byTime = a.airTime.compareTo(b.airTime);
      if (byTime != 0) return byTime;
      return a.showTitle.compareTo(b.showTitle);
    });
    return entries;
  }
}
