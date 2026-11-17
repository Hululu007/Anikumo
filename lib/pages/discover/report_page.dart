import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/bean/glass/glass_surface.dart';
import 'package:anikumo/repositories/history_repository.dart';
import 'package:anikumo/services/stats/report_stats.dart';
import 'package:anikumo/services/stats/watch_stats.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/pages/discover/report_share_card.dart';
import 'package:anikumo/services/i18n/app_strings.dart';

const _weekdayNames = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const _goalOptions = [3, 5, 7, 10, 15, 20, 30];

/// 观看报告： the current month's viewing — episodes, minutes,
/// active days, favourite tags, busiest weekday — plus the weekly
/// goal progress and a 12-week activity heatmap.
class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  late int _year;
  late int _month;

  /// Batch 273 (#9): month report vs year report.
  bool _yearMode = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
  }

  void _shiftMonth(int delta) {
    setState(() {
      var month = _month + delta;
      var year = _year;
      while (month < 1) {
        month += 12;
        year -= 1;
      }
      while (month > 12) {
        month -= 12;
        year += 1;
      }
      _month = month;
      _year = year;
    });
  }

  Future<void> _editGoal(int currentGoal, int weekEpisodes) async {
    final picked = await AnikumoDialog.show<int>(
      builder: (dialogContext) => SimpleDialog(
        title: Text(S.t('每周观看目标')),
        children: [
          for (final option in _goalOptions)
            SimpleDialogOption(
              onPressed: () =>
                  AnikumoDialog.dismiss(context: dialogContext, popWith: option),
              child: Text(S.f('每周 {} 集', [option])),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await GStorage.putSetting(SettingsKeys.weeklyGoalEpisodes, picked);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final histories = inject<IHistoryRepository>().getAllHistories();
    final report =
        computeMonthlyReport(histories, year: _year, month: _month);
    final yearReport = _yearMode
        ? computeYearlyReport(histories, year: _year)
        : YearlyReport.empty;
    // Unified numbers for the shared tiles below.
    final periodEpisodes = _yearMode ? yearReport.episodes : report.episodes;
    final periodMinutes = _yearMode ? yearReport.minutes : report.minutes;
    final periodDays = _yearMode ? yearReport.activeDays : report.activeDays;
    final periodTags = _yearMode ? yearReport.topTags : report.topTags;
    final stats = computeWatchStats(histories);
    final weekEpisodes =
        stats.last7DaysEpisodes.fold<int>(0, (sum, count) => sum + count);
    final goal = GStorage.getSetting(SettingsKeys.weeklyGoalEpisodes);
    final heatmap = dailyEpisodeCounts(histories, today: DateTime.now());
    final maxHeat = heatmap.values.fold<int>(0, (a, b) => a > b ? a : b);

    return Scaffold(
      appBar: AppBar(
        title: Text(S.t('观看报告')),
        actions: [
          // Batch 276 (#59): share card for this period.
          IconButton(
            tooltip: S.t('分享卡'),
            icon: const Icon(AnikumoIcons.ios_share_rounded),
            onPressed: () => showReportShareCard(
              context,
              periodLabel: _yearMode
                  ? S.f('{} 年观看报告', [_year])
                  : S.f('{} 年 {} 月观看报告', [_year, _month]),
              episodes: periodEpisodes,
              minutes: periodMinutes,
              activeDays: periodDays,
              topTags: [for (final tag in periodTags) tag.name],
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          StyleString.pagePadding,
          8,
          StyleString.pagePadding,
          StyleString.sectionSpace,
        ),
        children: [
          Center(
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(S.t('月报'))),
                ButtonSegment(value: true, label: Text(S.t('年报'))),
              ],
              selected: {_yearMode},
              onSelectionChanged: (selection) =>
                  setState(() => _yearMode = selection.first),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () =>
                    _yearMode ? setState(() => _year -= 1) : _shiftMonth(-1),
                icon: const Icon(AnikumoIcons.chevron_left_rounded),
              ),
              Text(
                _yearMode
                    ? S.f('{} 年', [_year])
                    : S.f('{} 年 {} 月', [_year, _month]),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              IconButton(
                onPressed: () =>
                    _yearMode ? setState(() => _year += 1) : _shiftMonth(1),
                icon: const Icon(AnikumoIcons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GlassSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: _StatTile(
                    label: _yearMode ? S.t('本年集数') : S.t('本月集数'),
                    value: '$periodEpisodes',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GlassSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: _StatTile(
                    label: _yearMode ? S.t('本年时长') : S.t('本月时长'),
                    value: periodMinutes >= 60
                        ? S.f('{} 小时', [(periodMinutes / 60).toStringAsFixed(1)])
                        : S.f('{} 分钟', [periodMinutes]),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GlassSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: _StatTile(
                    label: S.t('活跃天数'),
                    value: '$periodDays',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GlassSurface(
            onTap: () => _editGoal(goal, weekEpisodes),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(AnikumoIcons.flag_rounded,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      S.f('本周目标：{} / {} 集', [weekEpisodes, goal]),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text(
                      weekEpisodes >= goal ? S.t('已达成') : S.t('点此修改'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: goal <= 0
                      ? 0
                      : (weekEpisodes / goal).clamp(0, 1).toDouble(),
                ),
              ],
            ),
          ),
          if (_yearMode && yearReport.episodes > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GlassSurface(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: _StatTile(
                      label: S.t('追番部数'),
                      value: '${yearReport.titles}',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GlassSurface(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: _StatTile(
                      label: S.t('最忙的月份'),
                      value: yearReport.busiestMonth > 0
                          ? S.f('{} 月', [yearReport.busiestMonth])
                          : '—',
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (periodTags.isNotEmpty) ...[
            const SizedBox(height: 12),
            GlassSurface(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _yearMode ? S.t('本年最常看的类型') : S.t('本月最常看的类型'),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final tag in periodTags)
                        Chip(
                          label: Text('${tag.name} · ${tag.count}'),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  if (!_yearMode && report.busiestWeekday > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      S.f('最爱在{}看番', [S.t(_weekdayNames[report.busiestWeekday])]),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            S.t('近 12 周观看热力'),
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 12,
              mainAxisSpacing: 3,
              crossAxisSpacing: 3,
            ),
            itemCount: heatmap.length,
            itemBuilder: (context, index) {
              final count = heatmap.values.elementAt(index);
              final intensity =
                  maxHeat == 0 ? 0.0 : (count / maxHeat).clamp(0.0, 1.0);
              return Container(
                decoration: BoxDecoration(
                  color: count == 0
                      ? theme.colorScheme.surfaceContainerHighest
                      : theme.colorScheme.primary
                          .withValues(alpha: 0.25 + 0.75 * intensity),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            S.t('颜色越深，那天看得越多'),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      ],
    );
  }
}
