import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 262: the app's UI language selection.
///
/// The stored value is one global setting shared by every
/// zone; each zone's settings surface edits the same key.
/// [system] follows the platform locale, resolving to one of
/// the four supported languages with Simplified Chinese as
/// the fallback (the app's original language).
enum AppLanguage {
  system,
  zhHans,
  en,
  ja,
  zhHant;

  static AppLanguage fromStorage(String? raw) => switch (raw) {
        'zhHans' => AppLanguage.zhHans,
        'en' => AppLanguage.en,
        'ja' => AppLanguage.ja,
        'zhHant' => AppLanguage.zhHant,
        _ => AppLanguage.system,
      };

  String get storageValue => name;

  /// The fixed locale for an explicit selection. [system]
  /// maps to the fallback; use [resolveAppLocale] for the
  /// platform-aware answer.
  ui.Locale get fixedLocale => switch (this) {
        AppLanguage.en => const ui.Locale('en', 'US'),
        AppLanguage.ja => const ui.Locale('ja', 'JP'),
        AppLanguage.zhHant => const ui.Locale.fromSubtags(
            languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
        _ => const ui.Locale.fromSubtags(
            languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN'),
      };

  /// Language name in its own language (the convention for
  /// language pickers); the "follow system" entry is the one
  /// exception — it is a UI phrase, translated at render time.
  String get nativeLabel => switch (this) {
        AppLanguage.system => '跟随系统',
        AppLanguage.zhHans => '简体中文',
        AppLanguage.en => 'English',
        AppLanguage.ja => '日本語',
        AppLanguage.zhHant => '繁體中文',
      };

  bool get isZhHans => this == AppLanguage.zhHans;
}

/// Every locale the app ships. Order matters: the first one
/// is the fallback [MaterialApp] settles on.
const List<ui.Locale> kSupportedAppLocales = [
  ui.Locale.fromSubtags(
      languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN'),
  ui.Locale('en', 'US'),
  ui.Locale('ja', 'JP'),
  ui.Locale.fromSubtags(
      languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
];

/// Resolves a selection + platform locale to a concrete
/// supported locale. Pure, so tests can pin the mapping.
ui.Locale resolveAppLocale(AppLanguage selection, ui.Locale platform) {
  if (selection != AppLanguage.system) return selection.fixedLocale;
  switch (platform.languageCode) {
    case 'en':
      return AppLanguage.en.fixedLocale;
    case 'ja':
      return AppLanguage.ja.fixedLocale;
    case 'zh':
      final script = platform.scriptCode;
      final country = platform.countryCode;
      if (script == 'Hant' ||
          country == 'TW' ||
          country == 'HK' ||
          country == 'MO') {
        return AppLanguage.zhHant.fixedLocale;
      }
      return AppLanguage.zhHans.fixedLocale;
    default:
      return AppLanguage.zhHans.fixedLocale;
  }
}

/// The concrete language a resolved locale speaks, for
/// dictionary lookup: 'zhHans' | 'en' | 'ja' | 'zhHant'.
String appLanguageCodeOf(ui.Locale locale) {
  switch (locale.languageCode) {
    case 'en':
      return 'en';
    case 'ja':
      return 'ja';
    case 'zh':
      if (locale.scriptCode == 'Hant' ||
          locale.countryCode == 'TW' ||
          locale.countryCode == 'HK' ||
          locale.countryCode == 'MO') {
        return 'zhHant';
      }
      return 'zhHans';
    default:
      return 'zhHans';
  }
}

/// TMDB's `language` parameter for a resolved locale
/// (metadata follows the UI language; the film zone's
/// overseas mode still sends no language at all).
String tmdbLanguageOf(ui.Locale locale) =>
    switch (appLanguageCodeOf(locale)) {
      'en' => 'en-US',
      'ja' => 'ja-JP',
      'zhHant' => 'zh-TW',
      _ => 'zh-CN',
    };

/// The TMDB `language` for the CURRENT UI language
/// selection — what the film zone's domestic mode sends.
/// Reads the stored selection directly (resolving "follow
/// system" against the platform locale) so non-widget
/// services can call it without a BuildContext. Storage
/// reads are guarded exactly like `tmdbOverseasMode`:
/// cover widgets reach this through their cache keys from
/// bare test trees where storage was never initialized,
/// and the pre-B264 domestic default answers there.
String tmdbLanguageForCurrentMode() {
  try {
    return tmdbLanguageOf(resolveAppLocale(
      AppLanguage.fromStorage(GStorage.getSetting(SettingsKeys.appLanguage)),
      ui.PlatformDispatcher.instance.locale,
    ));
  } catch (_) {
    return 'zh-CN';
  }
}

/// Holds the live language selection for the widget tree.
/// Registered next to ThemeProvider in main(); AppWidget
/// watches it and feeds [locale] into MaterialApp.
class LocaleProvider extends ChangeNotifier {
  LocaleProvider() {
    _selection =
        AppLanguage.fromStorage(GStorage.getSetting(SettingsKeys.appLanguage));
    _locale = resolveAppLocale(
        _selection, ui.PlatformDispatcher.instance.locale);
  }

  late AppLanguage _selection;
  late ui.Locale _locale;

  AppLanguage get selection => _selection;
  ui.Locale get locale => _locale;
  String get languageCode => appLanguageCodeOf(_locale);

  Future<void> setLanguage(AppLanguage language) async {
    if (language == _selection) return;
    _selection = language;
    _locale =
        resolveAppLocale(_selection, ui.PlatformDispatcher.instance.locale);
    // Notify first: the UI switches language the moment the
    // user picks one; the storage write must not gate it.
    notifyListeners();
    await GStorage.putSetting(
        SettingsKeys.appLanguage, language.storageValue);
  }

  /// Re-resolves when the platform locale changes while the
  /// selection is [AppLanguage.system].
  void refreshSystemLocale() {
    if (_selection != AppLanguage.system) return;
    final next =
        resolveAppLocale(_selection, ui.PlatformDispatcher.instance.locale);
    if (next == _locale) return;
    _locale = next;
    notifyListeners();
  }
}
