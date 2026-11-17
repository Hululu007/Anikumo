import 'package:anikumo/modules/history/history_module.dart';

/// One month of viewing, aggregated for the 观看报告 page.
class MonthlyReport {
  const MonthlyReport({
    required this.episodes,
    required this.minutes,
    required this.activeDays,
    required this.topTags,
    required this.busiestWeekday,
  });

  /// Episode-progress entries touched during the month.
  final int episodes;

  /// Sum of recorded progress for those entries, in minutes (same
  /// approximation the watch-stats page uses for total watch time).
  final int minutes;

  /// Distinct calendar days with any viewing activity.
  final int activeDays;

  /// Most frequent bangumi tags that month, most frequent first.
  final List<({String name, int count})> topTags;

  /// Weekday (1 = Monday … 7 = Sunday) with the most activity, or 0.
  final int busiestWeekday;

  static const MonthlyReport empty = MonthlyReport(
    episodes: 0,
    minutes: 0,
    activeDays: 0,
    topTags: [],
    busiestWeekday: 0,
  );
}

/// Pure aggregation over [histories] for one calendar month.
MonthlyReport computeMonthlyReport(
  List<History> histories, {
  required int year,
  required int month,
}) {
  var episodes = 0;
  var minutes = 0;
  final days = <int>{};
  final tagCounts = <String, int>{};
  final weekdayCounts = List<int>.filled(8, 0);
  for (final history in histories) {
    var touchedThisMonth = false;
    for (final progress in history.progresses.values) {
      final updatedMs = progress.effectiveUpdatedAtMs(history.lastWatchTime);
      final updated = DateTime.fromMillisecondsSinceEpoch(updatedMs);
      if (updated.year != year || updated.month != month) continue;
      touchedThisMonth = true;
      episodes += 1;
      minutes += progress.progress.inMinutes;
      days.add(updated.day);
      weekdayCounts[updated.weekday] += 1;
    }
    if (touchedThisMonth) {
      for (final tag in history.bangumiItem.tags) {
        if (tag.name.isEmpty) continue;
        tagCounts[tag.name] = (tagCounts[tag.name] ?? 0) + 1;
      }
    }
  }
  if (episodes == 0) return MonthlyReport.empty;
  final topTags = tagCounts.entries
      .map((entry) => (name: entry.key, count: entry.value))
      .toList()
    ..sort((a, b) => b.count.compareTo(a.count));
  var busiestWeekday = 0;
  var best = 0;
  for (var weekday = 1; weekday <= 7; weekday++) {
    if (weekdayCounts[weekday] > best) {
      best = weekdayCounts[weekday];
      busiestWeekday = weekday;
    }
  }
  return MonthlyReport(
    episodes: episodes,
    minutes: minutes,
    activeDays: days.length,
    topTags: topTags.take(3).toList(),
    busiestWeekday: busiestWeekday,
  );
}

/// One year of viewing, aggregated for the 观看年报
/// (Batch 273, #9) — the yearly counterpart of
/// [MonthlyReport], plus the distinct-title count and
/// the busiest month that only make sense at year
/// scale.
class YearlyReport {
  const YearlyReport({
    required this.episodes,
    required this.minutes,
    required this.activeDays,
    required this.titles,
    required this.topTags,
    required this.busiestMonth,
  });

  final int episodes;
  final int minutes;
  final int activeDays;

  /// Distinct series with any activity that year.
  final int titles;
  final List<({String name, int count})> topTags;

  /// Month (1–12) with the most activity, or 0.
  final int busiestMonth;

  static const YearlyReport empty = YearlyReport(
    episodes: 0,
    minutes: 0,
    activeDays: 0,
    titles: 0,
    topTags: [],
    busiestMonth: 0,
  );
}

/// Pure aggregation over [histories] for one calendar
/// year, mirroring [computeMonthlyReport]'s rules.
YearlyReport computeYearlyReport(
  List<History> histories, {
  required int year,
}) {
  var episodes = 0;
  var minutes = 0;
  final days = <int>{};
  final tagCounts = <String, int>{};
  final monthCounts = List<int>.filled(13, 0);
  final titleIds = <int>{};
  for (final history in histories) {
    var touchedThisYear = false;
    for (final progress in history.progresses.values) {
      final updatedMs = progress.effectiveUpdatedAtMs(history.lastWatchTime);
      final updated = DateTime.fromMillisecondsSinceEpoch(updatedMs);
      if (updated.year != year) continue;
      touchedThisYear = true;
      episodes += 1;
      minutes += progress.progress.inMinutes;
      days.add(updated.month * 100 + updated.day);
      monthCounts[updated.month] += 1;
    }
    if (touchedThisYear) {
      titleIds.add(history.bangumiItem.id);
      for (final tag in history.bangumiItem.tags) {
        if (tag.name.isEmpty) continue;
        tagCounts[tag.name] = (tagCounts[tag.name] ?? 0) + 1;
      }
    }
  }
  if (episodes == 0) return YearlyReport.empty;
  final topTags = tagCounts.entries
      .map((entry) => (name: entry.key, count: entry.value))
      .toList()
    ..sort((a, b) => b.count.compareTo(a.count));
  var busiestMonth = 0;
  var best = 0;
  for (var month = 1; month <= 12; month++) {
    if (monthCounts[month] > best) {
      best = monthCounts[month];
      busiestMonth = month;
    }
  }
  return YearlyReport(
    episodes: episodes,
    minutes: minutes,
    activeDays: days.length,
    titles: titleIds.length,
    topTags: topTags.take(3).toList(),
    busiestMonth: busiestMonth,
  );
}

/// Episodes touched per calendar day for the last [days] days,
/// keyed by date-only [DateTime], for the heatmap on the report page.
/// Days without activity are present with a 0 count.
Map<DateTime, int> dailyEpisodeCounts(
  List<History> histories, {
  required DateTime today,
  int days = 84,
}) {
  final start = DateTime(today.year, today.month, today.day)
      .subtract(Duration(days: days - 1));
  final result = <DateTime, int>{
    for (var i = 0; i < days; i++) start.add(Duration(days: i)): 0,
  };
  for (final history in histories) {
    for (final progress in history.progresses.values) {
      final updatedMs = progress.effectiveUpdatedAtMs(history.lastWatchTime);
      final updated = DateTime.fromMillisecondsSinceEpoch(updatedMs);
      final day = DateTime(updated.year, updated.month, updated.day);
      if (result.containsKey(day)) {
        result[day] = result[day]! + 1;
      }
    }
  }
  return result;
}
