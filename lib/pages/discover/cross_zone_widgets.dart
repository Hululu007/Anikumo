import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/services/cross_zone/cross_zone_library.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/privacy/app_lock.dart';

/// Batch 275 (#45): the mixed continue rail on the
/// anime home — the newest in-progress title from ANY
/// zone, each card badged with its zone and opening
/// that zone's detail page. Renders nothing while
/// loading or when there is no progress anywhere.
class CrossZoneContinueRail extends StatefulWidget {
  const CrossZoneContinueRail({super.key});

  @override
  State<CrossZoneContinueRail> createState() =>
      _CrossZoneContinueRailState();
}

class _CrossZoneContinueRailState extends State<CrossZoneContinueRail> {
  List<ContinueEntry> _entries = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    CrossZoneLibrary.continueEntries().then((entries) {
      if (mounted) {
        setState(() {
          _entries = entries;
          _loaded = true;
        });
      }
    });
  }

  static IconData _zoneIcon(String zone) => switch (zone) {
        'manga' => AnikumoIcons.auto_stories_rounded,
        'novel' => AnikumoIcons.menu_book_rounded,
        'film' => AnikumoIcons.movie_rounded,
        _ => AnikumoIcons.smart_display_rounded,
      };

  static String _zoneLabel(String zone) => switch (zone) {
        'manga' => '漫画区',
        'novel' => '小说区',
        'film' => '影视区',
        _ => '动漫区',
      };

  @override
  Widget build(BuildContext context) {
    // Batch 275 (#47): guest mode hides the rail.
    if (PrivacyGate.guestMode) return const SizedBox.shrink();
    if (!_loaded || _entries.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
          child: Row(
            children: [
              const Icon(AnikumoIcons.play_circle_rounded, size: 20),
              const SizedBox(width: 8),
              Text(
                S.t('继续观看 · 全部专区'),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: _entries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final entry = _entries[index];
              return SizedBox(
                width: 104,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => entry.open(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 104,
                          height: 104,
                          child: entry.coverUrl.isEmpty
                              ? ColoredBox(
                                  color:
                                      theme.colorScheme.surfaceContainerHigh,
                                  child: Icon(_zoneIcon(entry.zone)),
                                )
                              : CachedNetworkImage(
                                  imageUrl: entry.coverUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => ColoredBox(
                                    color: theme
                                        .colorScheme.surfaceContainerHigh,
                                    child: Icon(_zoneIcon(entry.zone)),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${S.t(_zoneLabel(entry.zone))} · ${entry.subtitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
