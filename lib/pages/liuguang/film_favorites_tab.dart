import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:liuguang_core/liuguang_core.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/pages/liuguang/film_widgets.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/liuguang/film_favorites_io.dart';
import 'package:anikumo/services/liuguang/film_prefs.dart';
import 'package:anikumo/services/liuguang/film_auto_update.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';

/// Batch 205: 收藏 — the engine favorites repository's
/// snapshots, as a poster grid. Long-press removes.
class FilmFavoritesTab extends StatefulWidget {
  const FilmFavoritesTab({super.key});

  @override
  State<FilmFavoritesTab> createState() => _FilmFavoritesTabState();
}

class _FilmFavoritesTabState extends State<FilmFavoritesTab> {
  List<MediaItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    VideoEngineService.instance.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    VideoEngineService.instance.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final engine = await VideoEngineService.instance.engine();
      final favorites = await engine.favorites.list();
      _items = favorites
          .where((f) => f.mediaSnapshot.isNotEmpty)
          .map((f) => TVSeries.mediaFromJson(f.mediaSnapshot))
          .toList();
    } catch (_) {
      _items = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(MediaItem item) async {
    final engine = await VideoEngineService.instance.engine();
    await engine.favorites.remove(item.id);
    await _reload();
  }

  bool _importing = false;

  /// Batch 272 (#32): export the favorites as one JSON
  /// file (snapshots included, restores exactly).
  Future<void> _exportFavorites() async {
    try {
      final engine = await VideoEngineService.instance.engine();
      final favorites = await engine.favorites.list();
      final snapshots = [
        for (final f in favorites)
          if (f.mediaSnapshot.isNotEmpty) f.mediaSnapshot,
      ];
      if (snapshots.isEmpty) {
        _toast(S.t('还没有收藏'));
        return;
      }
      final bytes = utf8.encode(buildFilmFavoritesExport(snapshots));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: S.t('导出片单'),
        fileName: 'anikumo-film-favorites.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      if (path != null && !Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes);
      }
      if (path != null) _toast(S.f('已导出 {} 部', [snapshots.length]));
    } catch (e) {
      _toast(S.f('导出失败：{}', [e]));
    }
  }

  /// Batch 272 (#32): import a favorites file — an
  /// exported JSON restores directly; a plain-text
  /// title list is matched against the enabled sources
  /// by search (first 30 titles).
  Future<void> _importFavorites() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'txt'],
      withData: true,
    );
    final file = picked?.files.singleOrNull;
    if (file?.bytes == null) return;
    final parsed = parseFilmFavoritesImport(utf8.decode(file!.bytes!));
    if (parsed == null) {
      _toast(S.t('这个文件里没有可导入的内容'));
      return;
    }
    setState(() => _importing = true);
    try {
      final engine = await VideoEngineService.instance.engine();
      var added = 0;
      var skipped = 0;
      if (parsed is FilmFavoritesSnapshots) {
        for (final snapshot in parsed.snapshots) {
          try {
            final item = TVSeries.mediaFromJson(snapshot);
            if (await engine.favorites.isFavorite(item.id)) {
              skipped++;
            } else {
              await engine.favorites.add(item);
              added++;
            }
          } catch (_) {
            skipped++;
          }
        }
      } else if (parsed is FilmFavoritesTitles) {
        final titles = parsed.titles.take(30).toList();
        skipped = parsed.titles.length - titles.length;
        for (final title in titles) {
          try {
            final page = await engine.search(SearchRequest(keyword: title));
            final match = page.items
                .where((it) => it.title == title)
                .firstOrNull ??
                page.items.firstOrNull;
            if (match == null ||
                await engine.favorites.isFavorite(match.id)) {
              skipped++;
            } else {
              await engine.favorites.add(match);
              added++;
            }
          } catch (_) {
            skipped++;
          }
        }
      }
      _toast(S.f('导入完成：新增 {} 部，跳过 {} 条', [added, skipped]));
      await _reload();
    } catch (e) {
      _toast(S.f('导入失败：{}', [e]));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  bool _checking = false;

  /// Batch 207 （自选功能）: 追剧更新检查 — compares each
  /// favorite's current remarks （更新至X集） against the
  /// stamp from the last check and reports what moved.
  /// First-ever check seeds the stamps silently.
  Future<void> _checkUpdates() async {
    if (_checking || _items.isEmpty) return;
    setState(() => _checking = true);
    try {
      final engine = await VideoEngineService.instance.engine();
      final stamps = FilmPrefs.favoriteStamps();
      final updated = <String>[];
      var seeded = 0;
      for (final item in _items) {
        final detail = await engine.getDetail(item.id);
        final remarks =
            detail?.item.raw['remarks']?.toString() ??
            item.raw['remarks']?.toString() ??
            '';
        final previous = stamps[item.id];
        if (previous == null) {
          stamps[item.id] = remarks;
          seeded++;
        } else if (previous != remarks && remarks.isNotEmpty) {
          updated.add('「${item.title}」$previous → $remarks');
          stamps[item.id] = remarks;
        }
      }
      await FilmPrefs.setFavoriteStamps(stamps);
      if (!mounted) return;
      final message = updated.isNotEmpty
          ? S.f('有更新：\n{}', [updated.join('\n')])
          : seeded == _items.length && stamps.length <= _items.length
          ? S.t('已记录当前进度，下次检查会对比是否有更新。')
          : S.t('收藏的剧集暂时没有更新。');
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(S.t('追剧更新检查')),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(S.t('知道了')),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(S.f('检查失败：{}', [e]))));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return FilmEmptyState(
        icon: AnikumoIcons.favorite_rounded,
        title: S.t('还没有收藏'),
        message: S.t('在影片详情页点收藏后，会出现在这里。'),
        actionLabel: S.t('导入片单'),
        onAction: _importing ? null : _importFavorites,
      );
    }
    return Column(
      children: [
        // Batch 221: editorial title bar.
        FilmEditorialTitle(
          eyebrow: S.t('COLLECTION · 收藏'),
          title: filmHeadline(context, S.t('收藏')),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 8, 0),
          child: Row(
            children: [
              Text(
                S.f('共 {} 部', [_items.length]),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: S.t('追剧日历'),
                onPressed: () => context.pushNamed('/film/calendar'),
                icon: const Icon(AnikumoIcons.date_range_outlined, size: 20),
              ),
              IconButton(
                tooltip: S.t('导入片单'),
                onPressed: _importing ? null : _importFavorites,
                icon: const Icon(AnikumoIcons.upload_outlined, size: 20),
              ),
              IconButton(
                tooltip: S.t('导出片单'),
                onPressed: _exportFavorites,
                icon: const Icon(AnikumoIcons.file_download_outlined, size: 20),
              ),
              TextButton.icon(
                onPressed: _checking ? null : _checkUpdates,
                icon: _checking
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(AnikumoIcons.system_update_rounded, size: 18),
                label: Text(S.t('检查更新')),
              ),
            ],
          ),
        ),
        if (FilmAutoUpdate.pendingUpdates().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                child: Row(
                  children: [
                    const Icon(AnikumoIcons.system_update_rounded, size: 19),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        S.f('有更新：{}', [
                          FilmAutoUpdate.pendingUpdates().join('；'),
                        ]),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await FilmAutoUpdate.clearPending();
                        if (mounted) setState(() {});
                      },
                      child: Text(S.t('知道了')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(child: _grid(context)),
      ],
    );
  }

  Widget _grid(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
        childAspectRatio: 0.56,
      ),
      itemCount: _items.length,
      itemBuilder: (context, i) {
        final item = _items[i];
        return GestureDetector(
          onLongPress: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: Text(S.t('取消收藏')),
                content: Text(S.f('不再收藏「{}」？', [item.title])),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: Text(S.t('保留')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: Text(S.t('取消收藏')),
                  ),
                ],
              ),
            );
            if (ok == true) await _remove(item);
          },
          child: FilmPosterCard(
            item: item,
            onTap: () => openFilmDetail(context, item),
          ),
        );
      },
    );
  }
}
