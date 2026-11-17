import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:anikumo/services/i18n/app_strings.dart';
import '../../bean/dialog/dialog.dart';
import '../../services/build_info.dart';
import '../../services/manga/manga_source_health.dart';
import '../../services/manga/manga_sources.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// Batch 33: manga source diagnostics.
///
/// Two builds in a row, device-only manga failures (home
/// sections stuck, chapters unreadable) could not be reproduced
/// off-device: the JS engine is fine under the QuickJS harness,
/// so the missing evidence is the DEVICE's error text. This
/// page runs the full read path for every installed source —
/// popular → info → chapters → first chapter pages — and shows
/// each step's real result or real error, with a one-tap copy
/// of the whole report.
class MangaDiagnosticsPage extends StatefulWidget {
  const MangaDiagnosticsPage({super.key});

  @override
  State<MangaDiagnosticsPage> createState() => _MangaDiagnosticsPageState();
}

class _MangaDiagnosticsPageState extends State<MangaDiagnosticsPage> {
  bool _running = false;
  String _report = '';

  String _stamp() =>
      '${DateTime.now().toIso8601String().substring(11, 19)}';

  Future<String> _step(
    String label,
    Future<dynamic> Function() run,
    String Function(dynamic value) describe,
  ) async {
    final watch = Stopwatch()..start();
    try {
      final value = await run();
      watch.stop();
      return '  [$label] 成功 · ${describe(value)} · '
          '${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s';
    } catch (e) {
      watch.stop();
      return '  [$label] 失败 · '
          '${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s · $e';
    }
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _report = '';
    });
    final lines = <String>[
      'anikumo 漫画源诊断 · 构建 $kAnikumoBuildStamp · ${_stamp()}',
    ];
    final sources = MangaSources.all();
    lines.add('已装源 ${sources.length} 个');
    for (final source in sources) {
      lines.add('');
      lines.add('== ${source.name}（${source.id}）==');
      dynamic first;
      lines.add(await _step('热门/推荐', () async {
        final items = await source.popular(limit: 3);
        if (items.isNotEmpty) first = items.first;
        return items;
      }, (v) => '${(v as List).length} 条'));
      if (first == null) {
        lines.add('  （无条目，后续步骤跳过）');
        continue;
      }
      dynamic chapters;
      lines.add(await _step('章节列表', () async {
        chapters = await source.chapters(first);
        return chapters;
      }, (v) => '${(v as List).length} 章'));
      if (chapters == null || (chapters as List).isEmpty) {
        lines.add('  （无章节，后续步骤跳过）');
        continue;
      }
      lines.add(await _step('第一章页图', () async {
        final chapter = (chapters as List).first;
        return source.pages(first, chapter);
      }, (v) => '${(v as List).length} 页'));
    }
    lines.add('');
    lines.add('（完）');
    if (!mounted) return;
    setState(() {
      _running = false;
      _report = lines.join('\n');
    });
  }

  /// Batch 271: accumulated health from real usage
  /// (MangaSourceHealth), one row per source that has
  /// served at least one measured call.
  List<Widget> _buildHealthSection(BuildContext context) {
    final snapshot = MangaSourceHealth.snapshot();
    if (snapshot.isEmpty) return const [];
    final entries = snapshot.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              S.t('源健康度（实际使用统计）'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          TextButton(
            onPressed: () {
              MangaSourceHealth.clear();
              setState(() {});
            },
            child: Text(S.t('清空统计')),
          ),
        ],
      ),
      for (final entry in entries)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(
            MangaSources.byId(entry.key)?.name ?? entry.key,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            _healthLine(entry.value),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: entry.value.successRate == null
              ? null
              : Text(
                  '${(entry.value.successRate! * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: entry.value.successRate! >= 0.8
                        ? Colors.green
                        : Colors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
    ];
  }

  String _healthLine(SourceHealthStats stats) {
    final parts = <String>[
      S.f('成功 {} · 失败 {}', [stats.okCount, stats.failCount]),
      if (stats.averageMs != null) S.f('平均 {} ms', [stats.averageMs!]),
    ];
    if (stats.lastError.isNotEmpty) {
      parts.add(S.f('最近错误：{}', [stats.lastError]));
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('漫画源诊断'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            S.f('构建 {}', [kAnikumoBuildStamp]),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          ..._buildHealthSection(context),
          const SizedBox(height: 8),
          Text(
            S.t('逐个源跑完整阅读链（热门 → 详情 → 章节 → 页图），每步显示真实结果或真实错误。跑完可点「复制报告」，把报告发给开发者协助排查。'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _running ? null : _run,
                icon: _running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(AnikumoIcons.play_arrow_rounded),
                label: Text(_running ? S.t('诊断中…') : S.t('开始诊断')),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _report.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: _report),
                        );
                        AnikumoDialog.showToast(message: S.t('报告已复制'));
                      },
                icon: const Icon(AnikumoIcons.copy_rounded),
                label: Text(S.t('复制报告')),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_report.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                _report,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.5,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}
