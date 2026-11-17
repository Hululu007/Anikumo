import 'dart:async';

import 'package:flutter_modular/flutter_modular.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:anikumo/navigation.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/logging/logger.dart';

/// Batch 276 (#62): launcher long-press shortcuts
/// (Android App Shortcuts / iOS Home Screen quick
/// actions). Three static destinations, navigated
/// through the same root-navigator path the deep
/// links use. Mobile only — the plugin no-ops on
/// desktop platforms.
abstract final class AppShortcuts {
  static const _search = 'shortcut_search';
  static const _favorites = 'shortcut_favorites';
  static const _ranks = 'shortcut_ranks';

  static final QuickActions _actions = const QuickActions();
  static bool _initialized = false;
  static bool _ready = false;
  static String? _pendingType;

  /// Where each shortcut type lands.
  static String routeFor(String type) => switch (type) {
        _search => '/search/',
        _favorites => '/tab/discover/cross-favorites/',
        _ranks => '/tab/discover/cross-ranks/',
        _ => '/',
      };

  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    try {
      _actions.initialize((type) {
        if (_ready) {
          _open(type);
        } else {
          _pendingType = type;
        }
      });
      unawaited(
        _actions.setShortcutItems([
          ShortcutItem(
            type: _search,
            localizedTitle: S.t('搜索'),
            icon: 'ic_shortcut_search',
          ),
          ShortcutItem(
            type: _favorites,
            localizedTitle: S.t('全部收藏'),
            icon: 'ic_shortcut_favorites',
          ),
          ShortcutItem(
            type: _ranks,
            localizedTitle: S.t('四区热门榜'),
            icon: 'ic_shortcut_ranks',
          ),
        ]).catchError((Object e) {
          AnikumoLogger().w('Shortcuts: set items failed', error: e);
        }),
      );
    } catch (e) {
      AnikumoLogger().w('Shortcuts: initialize failed', error: e);
    }
  }

  /// Called once the shell is up (same point as the
  /// deep links' markReady): a shortcut that cold-
  /// launched the app is honored now.
  static void markReady() {
    _ready = true;
    final pending = _pendingType;
    _pendingType = null;
    if (pending != null) _open(pending);
  }

  static void _open(String type) {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null || !navigator.mounted) return;
    if (!popForExternalNavigation(navigator)) return;
    unawaited(navigator.context.pushNamed(routeFor(type)));
  }
}
