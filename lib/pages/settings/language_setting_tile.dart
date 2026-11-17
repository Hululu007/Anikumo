import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/services/i18n/app_language.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 264/266: the shared 「界面语言」 settings row.
///
/// One global language setting backs every zone, so this
/// same tile is dropped into each zone's settings surface
/// （设置 / 漫画设置 / 小说设置 / 影视设置） and always edits the
/// one [LocaleProvider]. Language names render in their own
/// language; only the "follow system" entry is translated.
///
/// The provider MUST be resolved through flutter_modular's
/// scoped lookup (the mechanism the whole app — AppWidget,
/// ThemeProvider — uses): the app registers its change
/// notifiers with ModularApp's `provide`, which is a
/// modular-scoped inherited widget, NOT a package:provider
/// registration. Batch 264's first version looked the
/// provider up through package:provider, never found it,
/// and silently took the storage-only fallback below — so
/// switching language persisted the choice but notified
/// nobody, and the new language only appeared after a full
/// app restart (device-reported). The try/catch fallback
/// stays for bare widget tests, which pump settings pages
/// without a ModularApp above them.
class LanguageSettingTile extends StatelessWidget {
  const LanguageSettingTile({super.key});

  static String _labelFor(AppLanguage language) =>
      language == AppLanguage.system
          ? S.t(language.nativeLabel)
          : language.nativeLabel;

  static AppLanguage _storedSelection() {
    try {
      return AppLanguage.fromStorage(
          GStorage.getSetting(SettingsKeys.appLanguage));
    } catch (_) {
      // Storage never initialized (bare test surface).
      return AppLanguage.system;
    }
  }

  /// The app-scoped [LocaleProvider], or null when this
  /// tree has no ModularApp scope (bare test surfaces).
  static LocaleProvider? _scopedProvider(BuildContext context,
      {required bool listen}) {
    try {
      return listen ? context.watch<LocaleProvider>() : context.read<LocaleProvider>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _pick(BuildContext context, LocaleProvider? provider) async {
    final current = provider?.selection ?? _storedSelection();
    final picked = await showDialog<AppLanguage>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(S.t('界面语言')),
        children: [
          for (final language in AppLanguage.values)
            RadioListTile<AppLanguage>(
              value: language,
              groupValue: current,
              title: Text(_labelFor(language)),
              onChanged: (value) => Navigator.of(dialogContext).pop(value),
            ),
        ],
      ),
    );
    if (picked == null || picked == current) return;
    final live = provider ?? _scopedProvider(context, listen: false);
    if (live != null) {
      // Notifies AppWidget, which re-applies S and rebuilds
      // MaterialApp under the new locale — the whole app
      // switches language immediately, no restart.
      await live.setLanguage(picked);
    } else {
      // No scope in this tree (bare test surface): write
      // the selection and apply it to the string layer so
      // the row still behaves; the app root provider picks
      // the same value up on the next real launch.
      await GStorage.putSetting(
          SettingsKeys.appLanguage, picked.storageValue);
      S.applyLocale(resolveAppLocale(
          picked, ui.PlatformDispatcher.instance.locale));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = _scopedProvider(context, listen: true);
    final selection = provider?.selection ?? _storedSelection();
    return ListTile(
      leading: const Icon(AnikumoIcons.language_rounded),
      title: Text(S.t('界面语言')),
      subtitle: Text(_labelFor(selection)),
      trailing: const Icon(AnikumoIcons.arrow_drop_down_rounded),
      onTap: () => _pick(context, provider),
    );
  }
}
