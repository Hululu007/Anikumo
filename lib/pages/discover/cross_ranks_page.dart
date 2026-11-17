import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:liuguang_core/liuguang_core.dart';
import 'package:anikumo/bean/appbar/sys_app_bar.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/pages/liuguang/film_widgets.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';
import 'package:anikumo/services/manga/manga_api.dart';
import 'package:anikumo/services/novel/novel_sources.dart';
import 'package:anikumo/utils/constants.dart';

/// Batch 276 (#58): the cross-zone hot chart — each
/// zone's own hot list on one page: anime from the
/// Bangumi trend list, manga from the popular feed,
/// novels from the first explore-capable source's
/// first category, films from the enabled sources'
/// default list. Every section loads and fails on its
/// own; a zone with no data shows a hint, never an
/// error for the whole page.
class CrossRanksPage extends StatefulWidget {
  const CrossRanksPage({super.key});

  @override
  State<CrossRanksPage> createState() => _CrossRanksPageState();
}

class _CrossRanksPageState extends State<CrossRanksPage> {
  List<BangumiItem> _anime = const [];
  List<MangaItem> _manga = const [];
  List<NovelItem> _novels = const [];
  List<MediaItem> _films = const [];
  final Set<String> _failed = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Future<void> leg(String zone, Future<void> Function() run) async {
      try {
        await run();
      } catch (_) {
        _failed.add(zone);
      }
      if (mounted) setState(() {});
    }

    await Future.wait([
      leg('anime', () async {
        _anime = await BangumiApi.getBangumiTrendsList(limit: 10);
      }),
      leg('manga', () async {
        _manga = await MangaApi.fetchPopular(limit: 10);
      }),
      leg('novel', () async {
        for (final source in NovelSources.all()) {
          final categories = source.exploreCategories;
          if (categories.isEmpty) continue;
          _novels = await source.explore(categories.first, page: 1);
          if (_novels.isNotEmpty) break;
        }
      }),
      leg('film', () async {
        final engine = await VideoEngineService.instance.engine();
        final page = await engine.search(
          const SearchRequest(keyword: ''),
        );
        _films = page.items.take(10).toList();
      }),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(title: Text(S.t('四区热门榜'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(StyleString.pagePadding),
              children: [
                _section(
                  context,
                  icon: AnikumoIcons.smart_display_rounded,
                  title: '动漫区',
                  failed: _failed.contains('anime'),
                  empty: _anime.isEmpty,
                  children: [
                    for (var i = 0; i < _anime.length; i++)
                      _rankTile(
                        context,
                        rank: i + 1,
                        title: _anime[i].nameCn.isNotEmpty
                            ? _anime[i].nameCn
                            : _anime[i].name,
                        coverUrl: _anime[i].images['common'] ?? '',
                        onTap: () => context.pushNamed(
                          '/info/',
                          arguments: _anime[i],
                        ),
                      ),
                  ],
                ),
                _section(
                  context,
                  icon: AnikumoIcons.auto_stories_rounded,
                  title: '漫画区',
                  failed: _failed.contains('manga'),
                  empty: _manga.isEmpty,
                  children: [
                    for (var i = 0; i < _manga.length; i++)
                      _rankTile(
                        context,
                        rank: i + 1,
                        title: _manga[i].title,
                        coverUrl: _manga[i].coverUrl,
                        onTap: () => context.pushNamed(
                          '/manga/detail',
                          arguments: _manga[i],
                        ),
                      ),
                  ],
                ),
                _section(
                  context,
                  icon: AnikumoIcons.menu_book_rounded,
                  title: '小说区',
                  failed: _failed.contains('novel'),
                  empty: _novels.isEmpty,
                  children: [
                    for (var i = 0; i < _novels.length; i++)
                      _rankTile(
                        context,
                        rank: i + 1,
                        title: _novels[i].title,
                        coverUrl: _novels[i].coverUrl,
                        onTap: () => context.pushNamed(
                          '/novel/detail',
                          arguments: _novels[i],
                        ),
                      ),
                  ],
                ),
                _section(
                  context,
                  icon: AnikumoIcons.movie_rounded,
                  title: '影视区',
                  failed: _failed.contains('film'),
                  empty: _films.isEmpty,
                  children: [
                    for (var i = 0; i < _films.length; i++)
                      _rankTile(
                        context,
                        rank: i + 1,
                        title: _films[i].title,
                        coverUrl: _films[i].artwork.poster ?? '',
                        onTap: () => openFilmDetail(context, _films[i]),
                      ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _section(
    BuildContext context, {
    required IconData icon,
    required String title,
    required bool failed,
    required bool empty,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(
                S.t(title),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        if (failed || empty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              S.t('暂时取不到这一区的热门榜'),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          )
        else
          ...children,
      ],
    );
  }

  Widget _rankTile(
    BuildContext context, {
    required int rank,
    required String title,
    required String coverUrl,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 64,
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '$rank',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: rank <= 3 ? theme.colorScheme.primary : null,
                ),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 36,
                height: 48,
                child: coverUrl.isEmpty
                    ? ColoredBox(
                        color: theme.colorScheme.surfaceContainerHigh,
                      )
                    : CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => ColoredBox(
                          color: theme.colorScheme.surfaceContainerHigh,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }
}
