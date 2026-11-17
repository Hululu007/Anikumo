import 'dart:io';

import 'package:home_widget/home_widget.dart';
import 'package:anikumo/services/cross_zone/cross_zone_library.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/logging/logger.dart';

/// Batch 276 (#61): publishes the freshest continue-
/// watching entry to the Android home-screen widget
/// (ContinueWidgetProvider). Runs deferred after
/// startup; Android only, everything failure-silent —
/// a phone without the widget placed simply stores
/// the values.
String _zoneLabel(String zone) => switch (zone) {
      'manga' => '漫画区',
      'novel' => '小说区',
      'film' => '影视区',
      _ => '动漫区',
    };

abstract final class HomeWidgetPublisher {
  static Future<void> publishContinue() async {
    if (!Platform.isAndroid) return;
    try {
      final entries = await CrossZoneLibrary.continueEntries();
      final top = entries.isEmpty ? null : entries.first;
      await HomeWidget.saveWidgetData<String>(
        'hw_title',
        top?.title ?? 'Anikumo',
      );
      await HomeWidget.saveWidgetData<String>(
        'hw_subtitle',
        top == null
            ? S.t('打开 App 继续你的观看')
            : '${S.t(_zoneLabel(top.zone))} · ${top.subtitle}',
      );
      await HomeWidget.updateWidget(
        qualifiedAndroidName: 'com.anikumo.app.ContinueWidgetProvider',
      );
    } catch (e) {
      AnikumoLogger().w('HomeWidget: publish failed', error: e);
    }
  }
}
