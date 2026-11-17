import 'package:anikumo/request/core/dio_factory.dart';
import 'package:anikumo/services/i18n/app_language.dart';
import 'package:anikumo/services/tmdb/tmdb_episodes.dart';

/// Batch 272 (#30/#34): the TMDB catalog endpoints the
/// episode-stills service never needed — TV detail with
/// its season list, full season episode lists, single
/// episode detail, and similar / recommended works for
/// the film detail page's recommendation rail.
///
/// Everything degrades silently to empty results when
/// no key is configured or anything fails, exactly like
/// the stills service: enrichment must never break a page.
class TmdbCatalogEntry {
  final int id;
  final bool isSeries;
  final String title;
  final String originalTitle;
  final String year;
  final String posterUrl;
  final String overview;
  final double score;

  const TmdbCatalogEntry({
    required this.id,
    required this.isSeries,
    required this.title,
    required this.originalTitle,
    required this.year,
    required this.posterUrl,
    required this.overview,
    required this.score,
  });

  static TmdbCatalogEntry? fromJson(dynamic json, {bool? series}) {
    if (json is! Map) return null;
    final id = (json['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) return null;
    final isSeries = series ??
        (json['media_type']?.toString() == 'tv' ||
            json.containsKey('first_air_date'));
    final title = (json['name'] ?? json['title'])?.toString() ?? '';
    final original =
        (json['original_name'] ?? json['original_title'])?.toString() ?? '';
    if (title.isEmpty && original.isEmpty) return null;
    final date =
        (json['first_air_date'] ?? json['release_date'])?.toString() ?? '';
    final poster = json['poster_path']?.toString() ?? '';
    return TmdbCatalogEntry(
      id: id,
      isSeries: isSeries,
      title: title.isNotEmpty ? title : original,
      originalTitle: original,
      year: date.length >= 4 ? date.substring(0, 4) : '',
      posterUrl:
          poster.isEmpty ? '' : 'https://image.tmdb.org/t/p/w342$poster',
      overview: json['overview']?.toString() ?? '',
      score: (json['vote_average'] as num?)?.toDouble() ?? 0,
    );
  }
}

class TmdbSeasonInfo {
  final int number;
  final String name;
  final int episodeCount;
  final String airDate;
  final String overview;
  final String posterUrl;

  const TmdbSeasonInfo({
    required this.number,
    required this.name,
    required this.episodeCount,
    required this.airDate,
    required this.overview,
    required this.posterUrl,
  });

  static TmdbSeasonInfo? fromJson(dynamic json) {
    if (json is! Map) return null;
    final number = (json['season_number'] as num?)?.toInt();
    if (number == null) return null;
    final poster = json['poster_path']?.toString() ?? '';
    return TmdbSeasonInfo(
      number: number,
      name: json['name']?.toString() ?? '',
      episodeCount: (json['episode_count'] as num?)?.toInt() ?? 0,
      airDate: json['air_date']?.toString() ?? '',
      overview: json['overview']?.toString() ?? '',
      posterUrl:
          poster.isEmpty ? '' : 'https://image.tmdb.org/t/p/w342$poster',
    );
  }
}

class TmdbTvDetail {
  final TmdbCatalogEntry entry;
  final List<TmdbSeasonInfo> seasons;
  final int numberOfSeasons;
  final int numberOfEpisodes;
  final String status;

  const TmdbTvDetail({
    required this.entry,
    required this.seasons,
    required this.numberOfSeasons,
    required this.numberOfEpisodes,
    required this.status,
  });
}

abstract final class TmdbCatalogService {
  static const String _apiBase = 'https://api.themoviedb.org/3';

  static bool get hasKey => TmdbEpisodeService.hasKey;

  static Future<dynamic> _get(String path) async {
    final dio = DioFactory.apiDio;
    final response = await dio.get(
      '$_apiBase$path',
      queryParameters: {
        'api_key': TmdbEpisodeService.effectiveKey,
        'language': tmdbLanguageForCurrentMode(),
      },
    );
    return response.data;
  }

  /// TV detail including the full season list (#30).
  static Future<TmdbTvDetail?> tvDetail(int tmdbId) async {
    if (!hasKey || tmdbId <= 0) return null;
    try {
      final data = await _get('/tv/$tmdbId');
      if (data is! Map) return null;
      final entry = TmdbCatalogEntry.fromJson(data, series: true);
      if (entry == null) return null;
      final seasons = <TmdbSeasonInfo>[];
      final rawSeasons = data['seasons'];
      if (rawSeasons is List) {
        for (final raw in rawSeasons) {
          final season = TmdbSeasonInfo.fromJson(raw);
          if (season != null) seasons.add(season);
        }
      }
      return TmdbTvDetail(
        entry: entry,
        seasons: seasons,
        numberOfSeasons: (data['number_of_seasons'] as num?)?.toInt() ?? 0,
        numberOfEpisodes: (data['number_of_episodes'] as num?)?.toInt() ?? 0,
        status: data['status']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// Movie detail (#30).
  static Future<TmdbCatalogEntry?> movieDetail(int tmdbId) async {
    if (!hasKey || tmdbId <= 0) return null;
    try {
      final data = await _get('/movie/$tmdbId');
      return TmdbCatalogEntry.fromJson(data, series: false);
    } catch (_) {
      return null;
    }
  }

  /// A season's full episode list (#30) — number → still
  /// record, the same shape the stills service parses.
  static Future<Map<int, TmdbEpisodeStill>> seasonEpisodes(
    int tmdbId,
    int season,
  ) async {
    if (!hasKey || tmdbId <= 0) return const {};
    try {
      final data = await _get('/tv/$tmdbId/season/$season');
      if (data is! Map) return const {};
      return parseTmdbSeasonEpisodes(data.cast<String, dynamic>());
    } catch (_) {
      return const {};
    }
  }

  /// One episode's detail (#30): still record for a
  /// single episode, or null.
  static Future<TmdbEpisodeStill?> episodeDetail(
    int tmdbId,
    int season,
    int episode,
  ) async {
    if (!hasKey || tmdbId <= 0) return null;
    try {
      final data = await _get('/tv/$tmdbId/season/$season/episode/$episode');
      if (data is! Map) return null;
      final parsed = parseTmdbSeasonEpisodes({
        'episodes': [data],
      });
      return parsed[episode];
    } catch (_) {
      return null;
    }
  }

  /// Similar works, falling back to recommendations
  /// when the similar list is empty (#34).
  static Future<List<TmdbCatalogEntry>> similarWorks({
    required int tmdbId,
    required bool isSeries,
    int limit = 12,
  }) async {
    if (!hasKey || tmdbId <= 0) return const [];
    final kind = isSeries ? 'tv' : 'movie';
    var entries = await _list('/$kind/$tmdbId/similar', isSeries);
    if (entries.isEmpty) {
      entries = await _list('/$kind/$tmdbId/recommendations', isSeries);
    }
    return entries.take(limit).toList();
  }

  static Future<List<TmdbCatalogEntry>> _list(
    String path,
    bool isSeries,
  ) async {
    try {
      final data = await _get(path);
      final results = data is Map ? data['results'] : null;
      if (results is! List) return const [];
      return [
        for (final raw in results)
          if (TmdbCatalogEntry.fromJson(raw, series: isSeries)
              case final entry?)
            entry,
      ];
    } catch (_) {
      return const [];
    }
  }
}
