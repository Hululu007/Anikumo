import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:liuguang_models/liuguang_models.dart';
import 'package:anikumo/bean/appbar/sys_app_bar.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/pages/liuguang/film_widgets.dart';
import 'package:anikumo/services/cross_zone/cross_zone_library.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/pages/discover/work_qr_dialog.dart';
import 'package:anikumo/services/privacy/app_lock.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/novel/novel_library.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/utils/constants.dart';

/// Batch 275 (#43): the cross-zone favorites overview —
/// every zone's favorites on one page, grouped by zone
/// with counts, each row opening that zone's own
/// detail page. Read-only aggregation; managing
/// favorites stays in each zone.
class CrossFavoritesPage extends StatefulWidget {
  const CrossFavoritesPage({super.key});

  @override
  State<CrossFavoritesPage> createState() => _CrossFavoritesPageState();
}

class _CrossFavoritesPageState extends State<CrossFavoritesPage> {
  List<Favorite> _filmFavorites = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    VideoEngineService.instance.engine().then((engine) async {
      final favorites = await engine.favorites.list();
      if (mounted) {
        setState(() {
          _filmFavorites = favorites;
          _loaded = true;
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final anime = GStorage.collectibles.values.toList();
    final manga = MangaLibraryStore.loadFavorites();
    final novel = NovelLibraryStore.loadFavorites();
    final theme = Theme.of(context);
    // Batch 275 (#47): guest mode hides the shelves.
    if (PrivacyGate.guestMode) {
      return Scaffold(
        appBar: SysAppBar(title: Text(S.t('全部收藏'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              S.t('访客模式下收藏已隐藏'),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: SysAppBar(title: Text(S.t('全部收藏'))),
      body: ListView(
        padding: const EdgeInsets.all(StyleString.pagePadding),
        children: [
          Text(
            S.f('动漫 {} 部 · 漫画 {} 部 · 小说 {} 部 · 影视 {} 部', [
              anime.length,
              manga.length,
              novel.length,
              _filmFavorites.length,
            ]),
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          _section(
            context,
            icon: AnikumoIcons.smart_display_rounded,
            title: '动漫区',
            emptyText: '还没有追番收藏',
            children: [
              for (final collected in anime)
                ListTile(
                  title: Text(
                    collected.bangumiItem.nameCn.isNotEmpty
                        ? collected.bangumiItem.nameCn
                        : collected.bangumiItem.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: S.t('二维码互传'),
                    icon: const Icon(Icons.qr_code_rounded),
                    onPressed: () => showWorkQrCode(
                      context,
                      title: collected.bangumiItem.nameCn.isNotEmpty
                          ? collected.bangumiItem.nameCn
                          : collected.bangumiItem.name,
                      bangumiId: collected.bangumiItem.id,
                    ),
                  ),
                  onTap: () => context.pushNamed(
                    '/info/',
                    arguments: collected.bangumiItem,
                  ),
                ),
            ],
          ),
          _section(
            context,
            icon: AnikumoIcons.auto_stories_rounded,
            title: '漫画区',
            emptyText: '还没有漫画收藏',
            children: [
              for (final favorite in manga)
                ListTile(
                  title: Text(
                    favorite.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: S.t('二维码互传'),
                    icon: const Icon(Icons.qr_code_rounded),
                    onPressed: () => showWorkQrCode(
                      context,
                      title: favorite.title,
                    ),
                  ),
                  onTap: () => context.pushNamed(
                    '/manga/detail',
                    arguments: MangaItem(
                      id: favorite.id,
                      title: favorite.title,
                      description: '',
                      coverUrl: favorite.coverUrl,
                      author: '',
                      status: '',
                      year: null,
                      tags: const [],
                      source: favorite.source,
                    ),
                  ),
                ),
            ],
          ),
          _section(
            context,
            icon: AnikumoIcons.menu_book_rounded,
            title: '小说区',
            emptyText: '还没有小说收藏',
            children: [
              for (final item in novel)
                ListTile(
                  title: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: S.t('二维码互传'),
                    icon: const Icon(Icons.qr_code_rounded),
                    onPressed: () => showWorkQrCode(
                      context,
                      title: item.title,
                    ),
                  ),
                  onTap: () => context.pushNamed(
                    '/novel/detail',
                    arguments: item,
                  ),
                ),
            ],
          ),
          _section(
            context,
            icon: AnikumoIcons.movie_rounded,
            title: '影视区',
            emptyText: _loaded ? '还没有影视收藏' : '加载中…',
            children: [
              for (final favorite in _filmFavorites)
                if (favorite.mediaSnapshot.isNotEmpty)
                  ListTile(
                    title: Text(
                      TVSeries.mediaFromJson(favorite.mediaSnapshot)
                          .title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: S.t('二维码互传'),
                      icon: const Icon(Icons.qr_code_rounded),
                      onPressed: () => showWorkQrCode(
                        context,
                        title: TVSeries
                            .mediaFromJson(favorite.mediaSnapshot)
                            .title,
                      ),
                    ),
                    onTap: () => openFilmDetail(
                      context,
                      TVSeries.mediaFromJson(favorite.mediaSnapshot),
                    ),
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
    required String emptyText,
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
              const SizedBox(width: 8),
              Text(
                '${children.length}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              S.t(emptyText),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          )
        else
          ...children,
      ],
    );
  }
}
