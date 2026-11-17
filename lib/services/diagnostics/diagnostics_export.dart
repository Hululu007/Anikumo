import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:anikumo/services/build_info.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/novel/novel_library.dart';
import 'package:anikumo/services/storage/settings_keys.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 276 (#64): one-tap diagnostics bundle — a zip
/// with the app log tail, a version/platform manifest
/// and a REDACTED settings summary (feature toggles and
/// library counts only; never server addresses,
/// tokens, passwords or file paths beyond the app
/// documents root name). Built for attaching to a bug
/// report.
abstract final class DiagnosticsExport {
  static Future<Uint8List> buildBundle() async {
    final archive = Archive();

    final info = await PackageInfo.fromPlatform();
    final manifest = StringBuffer()
      ..writeln('Anikumo diagnostics bundle')
      ..writeln('app: ${info.appName} ${info.version}+${info.buildNumber}')
      ..writeln('build stamp: $kAnikumoBuildStamp')
      ..writeln('platform: ${Platform.operatingSystem} '
          '${Platform.operatingSystemVersion}')
      ..writeln('dart: ${Platform.version}')
      ..writeln('generated: ${DateTime.now().toIso8601String()}');
    final manifestBytes = utf8.encode(manifest.toString());
    archive.addFile(
      ArchiveFile('manifest.txt', manifestBytes.length, manifestBytes),
    );

    final summaryBytes = utf8.encode(buildSettingsSummary());
    archive.addFile(
      ArchiveFile('summary.txt', summaryBytes.length, summaryBytes),
    );

    // The log tail (last ~200 KB) — enough for a bug
    // report without shipping the whole file.
    try {
      final support = await getApplicationSupportDirectory();
      final logFile = File(p.join(support.path, 'logs', 'anikumo_logs.log'));
      if (await logFile.exists()) {
        final bytes = await logFile.readAsBytes();
        final tail = bytes.length > 200 * 1024
            ? bytes.sublist(bytes.length - 200 * 1024)
            : bytes;
        archive.addFile(ArchiveFile('anikumo_logs_tail.log', tail.length, tail));
      }
    } catch (_) {
      // A missing log never sinks the bundle.
    }

    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// The redacted summary: counts and boolean toggles
  /// only. Kept pure (beyond storage reads) so the
  /// redaction contract is unit-testable.
  static String buildSettingsSummary() {
    bool flag(SettingKey<bool> key) {
      try {
        return GStorage.getSetting(key);
      } catch (_) {
        return false;
      }
    }

    final buffer = StringBuffer()
      ..writeln('library counts:')
      ..writeln('  anime collectibles: ${GStorage.collectibles.length}')
      ..writeln('  anime histories: ${GStorage.histories.length}')
      ..writeln('  manga favorites: '
          '${MangaLibraryStore.loadFavorites().length}')
      ..writeln('  novel favorites: '
          '${NovelLibraryStore.loadFavorites().length}')
      ..writeln('feature toggles:')
      ..writeln('  scheduledDark: ${flag(SettingsKeys.scheduledDark)}')
      ..writeln('  appLockEnabled: ${flag(SettingsKeys.appLockEnabled)}')
      ..writeln('  guestMode: ${flag(SettingsKeys.guestMode)}')
      ..writeln('  autoBackupEnabled: '
          '${flag(SettingsKeys.autoBackupEnabled)}')
      ..writeln('  webdavEnabled: ${flag(SettingsKeys.webDavEnable)}');
    return buffer.toString();
  }
}
