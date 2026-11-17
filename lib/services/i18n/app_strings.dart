import 'dart:ui' as ui;

import 'package:anikumo/services/i18n/app_language.dart';
import 'package:anikumo/services/i18n/strings_en.dart';
import 'package:anikumo/services/i18n/strings_ja.dart';
import 'package:anikumo/services/i18n/strings_zh_hant.dart';

/// Batch 262: source-keyed UI string lookup.
///
/// The app's original language is Simplified Chinese, so the
/// Chinese source string IS the key: `S.t('设置')` renders
/// 设置 under zh-Hans, "Settings" under English, and so on.
/// A string with no dictionary entry falls back to the
/// Chinese source — never blank, never a crash — so coverage
/// can grow file by file without breaking untranslated pages.
///
/// [AppWidget] calls [applyLocale] on every build with the
/// [LocaleProvider]'s resolved locale, and changing the
/// locale rebuilds MaterialApp, so lookups stay in sync
/// without per-widget listeners.
class S {
  S._();

  static ui.Locale _locale = AppLanguage.zhHans.fixedLocale;

  static void applyLocale(ui.Locale locale) => _locale = locale;

  static ui.Locale get locale => _locale;

  /// 'zhHans' | 'en' | 'ja' | 'zhHant' for the live locale.
  static String get languageCode => appLanguageCodeOf(_locale);

  static bool get isZhHans => languageCode == 'zhHans';

  static Map<String, String> get _dict => switch (languageCode) {
        'en' => kStringsEn,
        'ja' => kStringsJa,
        'zhHant' => kStringsZhHant,
        _ => const <String, String>{},
      };

  /// Translates a Chinese source string into the live
  /// language; falls back to the source itself.
  static String t(String zh) {
    if (isZhHans) return zh;
    return _dict[zh] ?? zh;
  }

  /// Formatted variant: the template uses `{}` placeholders,
  /// filled in order from [args] after translation, e.g.
  /// `S.f('第 {} 集', [3])`.
  static String f(String template, [List<Object?> args = const []]) {
    var out = t(template);
    for (final arg in args) {
      out = out.replaceFirst('{}', '$arg');
    }
    return out;
  }
}
