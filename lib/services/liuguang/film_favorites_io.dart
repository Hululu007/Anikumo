import 'dart:convert';

/// Batch 272 (#32): film-favorites file interchange.
///
/// Export writes the favorites' media snapshots as one
/// JSON document; import accepts that document back
/// (full fidelity — the snapshots carry source + id, so
/// a restored favorite is playable as-is), or a plain
/// text file with one title per line, which the caller
/// matches against the enabled sources by search.
sealed class FilmFavoritesImport {
  const FilmFavoritesImport();
}

/// Snapshots from an exported JSON file.
class FilmFavoritesSnapshots extends FilmFavoritesImport {
  final List<Map<String, dynamic>> snapshots;
  const FilmFavoritesSnapshots(this.snapshots);
}

/// Titles from a plain-text list (one per line).
class FilmFavoritesTitles extends FilmFavoritesImport {
  final List<String> titles;
  const FilmFavoritesTitles(this.titles);
}

String buildFilmFavoritesExport(List<Map<String, dynamic>> snapshots) {
  return const JsonEncoder.withIndent('  ').convert({
    'app': 'anikumo',
    'kind': 'film-favorites',
    'version': 1,
    'exportedAt': DateTime.now().toIso8601String(),
    'items': snapshots,
  });
}

/// Parses an import file's text. Returns null when the
/// content is neither an export document nor a usable
/// title list.
FilmFavoritesImport? parseFilmFavoritesImport(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('{')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map && decoded['items'] is List) {
        final snapshots = <Map<String, dynamic>>[];
        for (final raw in decoded['items'] as List) {
          if (raw is Map) {
            snapshots.add(raw.cast<String, dynamic>());
          } else if (raw is String && raw.isNotEmpty) {
            // Tolerate snapshots stored as JSON strings.
            try {
              final inner = jsonDecode(raw);
              if (inner is Map) snapshots.add(inner.cast<String, dynamic>());
            } catch (_) {}
          }
        }
        if (snapshots.isNotEmpty) return FilmFavoritesSnapshots(snapshots);
      }
    } catch (_) {
      // Not JSON after all — fall through to titles.
    }
  }
  final titles = <String>[];
  for (final line in trimmed.split('\n')) {
    final title = line.trim();
    if (title.isEmpty || title.startsWith('#')) continue;
    if (!titles.contains(title)) titles.add(title);
  }
  if (titles.isEmpty) return null;
  return FilmFavoritesTitles(titles);
}
