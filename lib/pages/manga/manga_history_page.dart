import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/utils/tap_debouncer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/pages/manga/manga_widgets.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// Full reading-history list — where the home tab's 历史 card
/// leads. Most recently read first.
class MangaHistoryPage extends StatefulWidget {
  const MangaHistoryPage({super.key});

  @override
  State<MangaHistoryPage> createState() => _MangaHistoryPageState();
}

class _MangaHistoryPageState extends State<MangaHistoryPage> {
  /// Batch 98: browsing-history deletion — per-row delete
  /// and clear-all, both confirmed (a misclick must not
  /// eat a reading position silently).
  Future<bool> _confirm(String title, String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.t('删除')),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _deleteOne(MangaProgress entry) async {
    if (!await _confirm(
      S.t('删除这条记录？'),
      S.f('将移除《{}》的阅读进度，此操作无法撤销。', [entry.mangaTitle]),
    )) {
      return;
    }
    await MangaLibraryStore.removeProgress(entry.key);
    if (!mounted) return;
    setState(() {});
    AnikumoDialog.showToast(message: S.t('已删除'));
  }

  Future<void> _clearAll(int count) async {
    if (!await _confirm(
      S.t('清空全部阅读历史？'),
      S.f('将删除全部 {} 条漫画阅读记录，此操作无法撤销。', [count]),
    )) {
      return;
    }
    await MangaLibraryStore.clearProgress();
    if (!mounted) return;
    setState(() {});
    AnikumoDialog.showToast(message: S.t('阅读历史已清空'));
  }

  @override
  Widget build(BuildContext context) {
    final progress = MangaLibraryStore.loadProgressList();
    return Scaffold(
      appBar: AppBar(
        title: Text(S.f('阅读历史（{}）', [progress.length])),
        actions: [
          if (progress.isNotEmpty)
            IconButton(
              tooltip: S.t('清空全部'),
              icon: const Icon(AnikumoIcons.delete_sweep_outlined),
              onPressed: () => _clearAll(progress.length),
            ),
        ],
      ),
      body: progress.isEmpty
          ? Center(child: Text(S.t('还没有阅读记录')))
          : ListView.builder(
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
              padding: const EdgeInsets.symmetric(
                horizontal: StyleString.pagePadding,
                vertical: 8,
              ),
              itemCount: progress.length,
              itemBuilder: (context, index) {
                final entry = progress[index];
                final item = MangaItem(
                  id: entry.mangaId,
                  title: entry.mangaTitle,
                  description: '',
                  coverUrl: entry.coverUrl,
                  author: '',
                  status: '',
                  year: null,
                  tags: const [],
                  source: entry.mangaSource,
                );
                return InkWell(
                  onTap: () {
                    if (TapDebouncer.accept(
                        'manga:${item.source}:${item.id}')) {
                      context
                          .pushNamed('/manga/detail', arguments: item)
                          .then((_) => mounted ? setState(() {}) : null);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        MangaCover(
                          url: entry.coverUrl,
                          width: 44,
                          height: 62,
                          radius: 6,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.mangaTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                S.f('读到 {} · 第 {} / {} 页', [entry.chapterLabel, entry.page + 1, entry.totalPages]),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: S.t('删除记录'),
                          icon: const Icon(AnikumoIcons.delete_outline_rounded),
                          onPressed: () => _deleteOne(entry),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
