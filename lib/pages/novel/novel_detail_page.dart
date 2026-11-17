import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:anikumo/bean/widget/companion_state_row.dart';
import 'package:anikumo/bean/theme/violet_glass.dart';
import 'package:flutter_modular/flutter_modular.dart';

import '../../bean/dialog/dialog.dart';
import '../../models/novel_item.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import '../../modules/bangumi/bangumi_item.dart';
import '../../modules/manga/manga_item.dart';
import '../../request/apis/bangumi_api.dart';
import '../../services/manga/cross_media.dart';
import '../../services/manga/manga_api.dart';
import '../../services/manga/manga_search_utils.dart';
import '../../services/novel/novel_api.dart';
import '../../services/novel/novel_downloads.dart';
import '../../services/novel/novel_exporter.dart';
import '../../services/novel/novel_library.dart';
import '../../services/novel/novel_sources.dart';
import 'novel_widgets.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// Novel detail: info header, intro, companion anime/manga
/// rails, and the chapter list.
class NovelDetailPage extends StatefulWidget {
  const NovelDetailPage({super.key, required this.novel});

  final NovelItem novel;

  @override
  State<NovelDetailPage> createState() => _NovelDetailPageState();
}

class _NovelDetailPageState extends State<NovelDetailPage> {
  late NovelItem _item = widget.novel;
  List<NovelChapter> _chapters = const [];
  bool _loadingChapters = true;
  String? _chaptersError;
  bool _isFavorite = false;
  bool _descending = false;
  bool _showAllChapters = false;
  bool _introExpanded = false;
  List<BangumiItem> _pairedAnime = const [];
  List<MangaItem> _pairedManga = const [];
  bool _companionsLoaded = false;

  // Batch 31: chapter downloads (parity with the manga zone).
  Set<String> _downloadedKeys = const {};
  final Map<String, double> _downloadProgress = {};

  NovelProgress? get _progress =>
      NovelLibraryStore.loadProgressMap()[_item.storageKey];

  // Batch 42: readable-edition auto-switch (mirrors the
  // manga detail) — when this book's source serves no
  // chapters, swap _item to a verified edition elsewhere.
  bool _autoSwitchTried = false;
  bool _switchingSource = false;
  String? _switchedFromName;

  String _sourceNameOf(NovelItem item) {
    final byId = NovelSources.byId(item.source)?.name ?? '';
    if (byId.isNotEmpty) return byId;
    return item.sourceName.isNotEmpty ? item.sourceName : item.source;
  }

  Future<bool> _tryAutoSwitch() async {
    if (_autoSwitchTried) return false;
    _autoSwitchTried = true;
    if (mounted) setState(() => _switchingSource = true);
    final fromName = _sourceNameOf(_item);
    final found = await NovelApi.findReadableEdition(_item);
    if (!mounted) return true;
    if (found == null) {
      setState(() => _switchingSource = false);
      return false;
    }
    setState(() {
      _item = found;
      _switchedFromName = fromName;
      _switchingSource = false;
      _isFavorite = NovelLibraryStore.isFavorite(found);
      _chapters = const [];
      _loadingChapters = true;
      _chaptersError = null;
    });
    AnikumoDialog.showToast(
      message: S.f('原源无可读章节，已自动切换到 {}', [_sourceNameOf(found)]),
    );
    NovelDownloadStore.downloadedKeys().then((keys) {
      if (mounted) setState(() => _downloadedKeys = keys);
    });
    _loadInfo();
    await _loadChapters();
    return true;
  }

  @override
  void initState() {
    super.initState();
    _isFavorite = NovelLibraryStore.isFavorite(widget.novel);
    NovelDownloadStore.downloadedKeys().then((keys) {
      if (mounted) setState(() => _downloadedKeys = keys);
    });
    _loadInfo();
    _loadChapters();
    _loadCompanions();
  }

  Future<void> _loadInfo() async {
    try {
      final enriched = await NovelApi.bookInfo(_item);
      if (!mounted) return;
      setState(() => _item = enriched);
    } catch (_) {
      // Enrichment is optional; the search-result data is
      // already on screen.
    }
  }

  Future<void> _loadChapters() async {
    setState(() {
      _loadingChapters = true;
      _chaptersError = null;
    });
    try {
      final chapters = await NovelApi.chapters(_item);
      if (chapters.isEmpty && await _tryAutoSwitch()) return;
      if (!mounted) return;
      setState(() {
        _chapters = chapters;
        _loadingChapters = false;
      });
    } catch (e) {
      // Batch 46: chapter-level hard failures feed the
      // dead-source registry too, not just home explores.
      if (NovelSources.isHardDeadError(e.toString())) {
        NovelSources.recordDead(_item.source);
      }
      if (await _tryAutoSwitch()) return;
      if (!mounted) return;
      setState(() {
        _loadingChapters = false;
        _chaptersError = e.toString();
      });
    }
  }

  /// Companion rails: the anime adaptation and the manga
  /// counterpart of this novel, matched by title with the
  /// cross-media rankers, strict relevance only.
  Future<void> _loadCompanions() async {
    final title = widget.novel.title;
    try {
      for (final query in buildCrossQueries(primary: title)) {
        final page = await BangumiApi.bangumiSearch(query, limit: 12);
        if (page == null || page.items.isEmpty) continue;
        final ranked = rankCrossAnime(page.items, title);
        final target = normalizeNovelTitle(stripSeasonSuffix(title));
        final related = [
          for (final item in ranked)
            if (normalizeNovelTitle(item.nameCn).contains(target) ||
                normalizeNovelTitle(item.name).contains(target) ||
                target.contains(normalizeNovelTitle(item.nameCn)) ||
                target.contains(normalizeNovelTitle(item.name)))
              item,
        ];
        if (related.isNotEmpty) {
          if (mounted) setState(() => _pairedAnime = related.take(10).toList());
          break;
        }
      }
    } catch (_) {}
    try {
      final results = await MangaApi.searchManga(title, limit: 18);
      final relevant = filterRelevantMangaResults(
        rankMangaResults(results, title),
        title,
        strict: true,
      );
      if (mounted && relevant.isNotEmpty) {
        setState(() => _pairedManga = relevant.take(10).toList());
      }
    } catch (_) {}
    if (mounted) setState(() => _companionsLoaded = true);
  }

  Future<void> _downloadChapter(NovelChapter chapter, int index) async {
    if (chapter.webView) {
      AnikumoDialog.showToast(message: S.t('网页模式章节无法下载'));
      return;
    }
    final key = NovelDownloadStore.keyFor(_item, chapter);
    setState(() => _downloadProgress[chapter.url] = 0);
    NovelDownloadEntry? entry;
    String? failureReason;
    try {
      entry = await NovelDownloadStore.downloadChapter(
        item: _item,
        chapter: chapter,
        chapterIndex: index,
        onProgress: (done, total) {
          if (mounted) {
            setState(
              () => _downloadProgress[chapter.url] = done / total,
            );
          }
        },
      );
    } catch (e) {
      entry = null;
      failureReason = e.toString();
    }
    if (!mounted) return;
    setState(() {
      _downloadProgress.remove(chapter.url);
      if (entry != null) _downloadedKeys = {..._downloadedKeys, key};
    });
    AnikumoDialog.showToast(
      message: entry != null
          ? S.t('下载完成，可离线阅读')
          : S.f('下载失败：{}', [failureReason ?? S.t('未知原因')]),
    );
  }

  Widget _chapterTrailing(NovelChapter chapter, int index) {
    final progress = _downloadProgress[chapter.url];
    if (progress != null) {
      return SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          value: progress == 0 ? null : progress,
          strokeWidth: 2,
        ),
      );
    }
    if (_downloadedKeys.contains(NovelDownloadStore.keyFor(_item, chapter))) {
      return Icon(
        AnikumoIcons.download_done_rounded,
        size: 20,
        color: Theme.of(context).colorScheme.primary,
      );
    }
    return IconButton(
      tooltip: S.t('下载这一章'),
      icon: const Icon(AnikumoIcons.download_outlined, size: 20),
      onPressed: () => _downloadChapter(chapter, index),
    );
  }

  Future<void> _toggleFavorite() async {
    final nowFavorite = await NovelLibraryStore.toggleFavorite(_item);
    if (!mounted) return;
    setState(() => _isFavorite = nowFavorite);
    AnikumoDialog.showToast(
        message: nowFavorite ? S.t('已收藏') : S.t('已取消收藏'));
  }

  /// Batch 270: whole-book export. Picks a format, fetches
  /// every chapter's text with a cancellable progress
  /// dialog, then saves TXT or EPUB through the system
  /// save dialog. Chapters that fail to load are skipped
  /// and counted in the final toast.
  Future<void> _exportBook() async {
    final format = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(S.t('导出全书')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'txt'),
            child: Text(S.t('导出为 TXT')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'epub'),
            child: Text(S.t('导出为 EPUB')),
          ),
        ],
      ),
    );
    if (format == null || !mounted) return;

    final progress = ValueNotifier<int>(0);
    var cancelled = false;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(S.t('正在导出')),
          content: ValueListenableBuilder<int>(
            valueListenable: progress,
            builder: (context, done, _) => Text(
              S.f('已处理 {} / {} 章', [done, _chapters.length]),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                cancelled = true;
                Navigator.pop(dialogContext);
              },
              child: Text(S.t('取消')),
            ),
          ],
        ),
      ),
    );

    final exported = <ExportChapter>[];
    var failed = 0;
    for (final chapter in _chapters) {
      if (cancelled) break;
      try {
        final blocks = await NovelApi.content(_item, chapter);
        exported.add(
          ExportChapter(
            title: chapter.title,
            paragraphs: [
              for (final block in blocks)
                if (block is NovelTextBlock) block.text,
            ],
          ),
        );
      } catch (_) {
        failed++;
      }
      progress.value++;
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (cancelled) return;
    if (exported.isEmpty) {
      AnikumoDialog.showToast(message: S.t('导出失败'));
      return;
    }
    try {
      if (format == 'txt') {
        await FilePicker.platform.saveFile(
          dialogTitle: S.t('导出全书'),
          fileName: '${_item.title}.txt',
          bytes: utf8.encode(
            NovelExporter.buildTxt(
              bookTitle: _item.title,
              author: _item.author,
              chapters: exported,
            ),
          ),
        );
      } else {
        await FilePicker.platform.saveFile(
          dialogTitle: S.t('导出全书'),
          fileName: '${_item.title}.epub',
          bytes: Uint8List.fromList(
            NovelExporter.buildEpub(
              bookTitle: _item.title,
              author: _item.author,
              chapters: exported,
            ),
          ),
        );
      }
      if (!mounted) return;
      AnikumoDialog.showToast(
        message: failed > 0
            ? S.f('导出完成，{} 章加载失败已跳过', [failed])
            : S.t('导出完成'),
      );
    } catch (_) {
      if (mounted) {
        AnikumoDialog.showToast(message: S.t('导出失败'));
      }
    }
  }

  void _openReader(int chapterIndex) {
    if (_chapters.isEmpty) return;
    context.pushNamed(
      '/novel/reader',
      arguments: (
        item: _item,
        chapters: _chapters,
        chapterIndex: chapterIndex,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _progress;
    final displayed = _descending ? _chapters.reversed.toList() : _chapters;
    // Batch 30: cap eagerly built rows (long web novels run
    // to thousands of chapters); the rest is one tap away.
    final visible = _showAllChapters
        ? displayed
        : displayed.take(300).toList();
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ── Immersive hero (batch 38, Violet Glass) — same
          // language as the manga detail page.
          SizedBox(
            height: 252,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Batch 49: boundary — see manga detail.
                RepaintBoundary(
                  child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                  child: NovelCover(
                    url: _item.coverUrl,
                    width: MediaQuery.sizeOf(context).width,
                    height: 252,
                    radius: 0,
                  ),
                  ),
                ),
                ColoredBox(color: Colors.black.withValues(alpha: 0.38)),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        VioletGlass.background(context),
                      ],
                      stops: const [0.45, 1],
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: S.t('返回'),
                            onPressed: () => context.pop(),
                            icon: const Icon(AnikumoIcons.arrow_back_rounded,
                                color: Colors.white),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: S.t('导出全书'),
                            icon: const Icon(
                              AnikumoIcons.ios_share_rounded,
                              color: Colors.white,
                            ),
                            onPressed:
                                _chapters.isEmpty ? null : _exportBook,
                          ),
                          IconButton(
                            tooltip:
                                _isFavorite ? S.t('取消收藏') : S.t('收藏'),
                            icon: Icon(
                              _isFavorite
                                  ? AnikumoIcons.bookmark
                                  : AnikumoIcons.bookmark_outline,
                              color: _isFavorite
                                  ? VioletGlass.lavender
                                  : Colors.white,
                            ),
                            onPressed: _toggleFavorite,
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            NovelCover(
                              url: _item.coverUrl,
                              width: 88,
                              height: 128,
                              radius: 12,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _item.title,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleLarge
                                        ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      height: 1.25,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  if (_item.author.isNotEmpty)
                                    Text(
                                      S.f('作者：{}', [_item.author]),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                  if (_item.lastChapter.isNotEmpty)
                                    Text(
                                      S.f('最新章节：{}', [_item.lastChapter]),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                  if (_item.wordCount.isNotEmpty)
                                    Text(
                                      S.f('字数：{}', [_item.wordCount]),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      if (_item.sourceName.isNotEmpty)
                                        Chip(
                                          label: Text(_item.sourceName),
                                          visualDensity:
                                              VisualDensity.compact,
                                        ),
                                      for (final kind in _item.kind
                                          .split(RegExp(r'[,，、/ ]'))
                                          .where((k) => k.trim().isNotEmpty)
                                          .take(4))
                                        Chip(
                                          label: Text(kind.trim()),
                                          visualDensity:
                                              VisualDensity.compact,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: FilledButton.icon(
              onPressed: _chapters.isEmpty
                  ? null
                  : () => _openReader(
                        progress?.chapterIndex.clamp(
                              0,
                              _chapters.length - 1,
                            ) ??
                            0,
                      ),
              icon: const Icon(AnikumoIcons.menu_book_rounded),
              // Batch 30: a long current-chapter title used to
              // overflow the button row; it ellipsizes now.
              label: Flexible(
                child: Text(
                  progress == null
                      ? S.t('开始阅读')
                      : S.f('继续阅读 · {}', [progress.chapterTitle]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          if (_item.intro.isNotEmpty) ...[
            NovelSectionHeader(title: S.t('简介')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InkWell(
                onTap: () =>
                    setState(() => _introExpanded = !_introExpanded),
                child: Text(
                  _item.intro,
                  maxLines: _introExpanded ? null : 4,
                  overflow:
                      _introExpanded ? null : TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                ),
              ),
            ),
          ],
          NovelSectionHeader(title: S.t('配套动漫')),
          if (!_companionsLoaded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child:
                  CompanionLoadingRow(label: S.t('正在动漫库里查找同名作品…')),
            )
          else if (_pairedAnime.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CompanionEmptyRow(
                message: S.t('动漫库里暂未找到同名作品'),
                actionLabel: S.t('去动漫区搜索'),
                onAction: () => context.pushNamed(
                  '/search/${Uri.encodeComponent(widget.novel.title)}',
                ),
              ),
            )
          else
            SizedBox(
              height: 206,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _pairedAnime.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final anime = _pairedAnime[index];
                  return _AnimeRailCard(item: anime);
                },
              ),
            ),
          NovelSectionHeader(title: S.t('配套漫画')),
          if (!_companionsLoaded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child:
                  CompanionLoadingRow(label: S.t('正在漫画源里查找同名作品…')),
            )
          else if (_pairedManga.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CompanionEmptyRow(
                message: S.t('漫画源里暂未找到同名作品'),
                actionLabel: S.t('去漫画区搜索'),
                onAction: () => context.pushNamed(
                  '/manga/search',
                  arguments: widget.novel.title,
                ),
              ),
            )
          else
            SizedBox(
              height: 218,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _pairedManga.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final manga = _pairedManga[index];
                  return SizedBox(
                    width: 104,
                    child: InkWell(
                      onTap: () => context.pushNamed(
                        '/manga/detail',
                        arguments: manga,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          NovelCover(
                            url: manga.coverUrl,
                            width: 104,
                            height: 140,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            manga.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          if (_switchingSource)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    S.t('原源不可读，正在自动切换源…'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          if (_switchedFromName != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  Icon(
                    AnikumoIcons.swap_horiz_rounded,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      S.f('已从「{}」自动切换到「{}」（原源无可读章节）',
                          [_switchedFromName, _sourceNameOf(_item)]),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          NovelSectionHeader(
            title: S.t('章节'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_chapters.isNotEmpty)
                  Text(
                    S.f('共 {} 章', [_chapters.length]),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                IconButton(
                  tooltip: _descending ? S.t('正序') : S.t('倒序'),
                  icon: Icon(
                    _descending ? AnikumoIcons.arrow_upward : AnikumoIcons.arrow_downward,
                  ),
                  onPressed: () => setState(() {
                        _descending = !_descending;
                        _showAllChapters = false;
                      }),
                ),
              ],
            ),
          ),
          if (_loadingChapters)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_chaptersError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: NovelErrorState(
                message: _chaptersError!,
                onRetry: _loadChapters,
              ),
            )
          else if (_chapters.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Center(child: Text(S.t('这个源暂时没有可读的章节'))),
            )
          else ...[
            for (var i = 0; i < visible.length; i++)
              ListTile(
                dense: true,
                title: Text(
                  displayed[i].title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: progress != null &&
                            (_descending
                                    ? _chapters.length - 1 - i
                                    : i) <=
                                progress.chapterIndex
                        ? theme.colorScheme.outline
                        : null,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _chapterTrailing(
                      displayed[i],
                      _descending ? _chapters.length - 1 - i : i,
                    ),
                    const Icon(AnikumoIcons.chevron_right, size: 18),
                  ],
                ),
                onTap: () => _openReader(
                  _descending ? _chapters.length - 1 - i : i,
                ),
              ),
            if (!_showAllChapters && displayed.length > 300)
              ListTile(
                title: Text(
                  S.f('展开全部 {} 章', [displayed.length]),
                  style: TextStyle(color: theme.colorScheme.primary),
                ),
                trailing: const Icon(AnikumoIcons.expand_more),
                onTap: () => setState(() => _showAllChapters = true),
              ),
          ],
        ],
      ),
    );
  }
}

/// A small anime card for the companion rail.
class _AnimeRailCard extends StatelessWidget {
  const _AnimeRailCard({required this.item});

  final BangumiItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = item.nameCn.isNotEmpty ? item.nameCn : item.name;
    return SizedBox(
      width: 104,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => context.pushNamed('/info/', arguments: item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NovelCover(
              url: item.images['large'] ?? item.images['common'] ?? '',
              width: 104,
              height: 140,
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
