import 'package:flutter/material.dart';
import 'package:liuguang_core/liuguang_core.dart';

import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/pages/liuguang/film_widgets.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/liuguang/tvmaze_calendar.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';

/// Batch 272 (#31): 追剧日历 — the next two weeks of
/// episode air dates for the user's favorited series,
/// resolved against TVmaze's public schedule data.
/// Movies and unresolvable titles simply do not appear;
/// the empty state says so plainly.
class FilmCalendarPage extends StatefulWidget {
  const FilmCalendarPage({super.key});

  @override
  State<FilmCalendarPage> createState() => _FilmCalendarPageState();
}

class _FilmCalendarPageState extends State<FilmCalendarPage> {
  List<TvmazeCalendarEntry> _entries = const [];
  bool _loading = true;
  bool _hadSeries = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final engine = await VideoEngineService.instance.engine();
      final favorites = await engine.favorites.list();
      final titles = <String>[];
      for (final f in favorites) {
        if (f.mediaSnapshot.isEmpty) continue;
        final item = TVSeries.mediaFromJson(f.mediaSnapshot);
        if (item.mediaType == MediaType.series) {
          titles.add(item.title);
        }
      }
      _hadSeries = titles.isNotEmpty;
      if (titles.isNotEmpty) {
        _entries = await TvmazeCalendar.upcoming(titles: titles, days: 14);
      }
    } catch (_) {
      _entries = const [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = day.difference(today).inDays;
    final date = '${day.month}月${day.day}日';
    if (diff == 0) return '今天 · $date';
    if (diff == 1) return '明天 · $date';
    if (diff == 2) return '后天 · $date';
    return date;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('追剧日历'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? FilmEmptyState(
                  icon: AnikumoIcons.date_range_outlined,
                  title: S.t('追剧日历'),
                  message: _hadSeries
                      ? S.t('未来两周没有查到收藏剧集的播出安排。')
                      : S.t('先在影视区收藏剧集，这里会显示它们的播出时间。'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: _entries.length,
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    final showHeader = index == 0 ||
                        _entries[index - 1].airDate != entry.airDate;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showHeader)
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              4,
                              index == 0 ? 0 : 20,
                              4,
                              8,
                            ),
                            child: Text(
                              _dayLabel(entry.airDate),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        Card(
                          child: ListTile(
                            leading: const Icon(
                              AnikumoIcons.live_tv_rounded,
                            ),
                            title: Text(
                              entry.showTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              [
                                entry.code,
                                if (entry.episodeName.isNotEmpty)
                                  entry.episodeName,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              [
                                if (entry.airTime.isNotEmpty) entry.airTime,
                                if (entry.runtimeMinutes != null)
                                  '${entry.runtimeMinutes} min',
                              ].join('\n'),
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
    );
  }
}
