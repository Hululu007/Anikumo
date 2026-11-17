/// Batch 273 (#7): danmaku density heatmap buckets for
/// the player's progress bar — how many danmaku fall
/// into each slice of the episode, normalized so the
/// busiest slice is 1.0.
///
/// [bySecond] is the danmaku controller's bucket map
/// (second → entries). Pure and total-duration driven
/// so it can be unit-tested without a player.
List<double> danmakuHeatmapBuckets(
  Map<int, List<Object?>> bySecond, {
  required int totalSeconds,
  int buckets = 60,
}) {
  if (totalSeconds <= 0 || buckets <= 0 || bySecond.isEmpty) {
    return const [];
  }
  final counts = List<int>.filled(buckets, 0);
  bySecond.forEach((second, entries) {
    if (second < 0) return;
    final index = (second * buckets / totalSeconds).floor();
    counts[index.clamp(0, buckets - 1)] += entries.length;
  });
  var max = 0;
  for (final c in counts) {
    if (c > max) max = c;
  }
  if (max == 0) return const [];
  return [for (final c in counts) c / max];
}
