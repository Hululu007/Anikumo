import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:anikumo/services/backup/local_backup.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/storage/settings_keys.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 274 (#41): scheduled local backups. On app
/// start (deferred, like the notification checks), if
/// the schedule is enabled and the interval has
/// elapsed, a plain JSON backup lands in the
/// app-private `anikumo_backups` folder; the newest
/// [keepCount] are kept. Auto backups are NOT
/// encrypted — the folder is app-private, and storing
/// a backup password would defeat the point of #40's
/// user-held password; the settings copy says so.
abstract final class AutoBackupService {
  static const int keepCount = 3;

  static bool isDue({required int nowMs, required int lastMs, required int intervalDays}) {
    if (lastMs <= 0) return true;
    return nowMs - lastMs >= intervalDays * Duration.millisecondsPerDay;
  }

  static Future<Directory> backupDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/anikumo_backups');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<List<File>> listBackups() async {
    final dir = await backupDirectory();
    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        files.add(entity);
      }
    }
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// Runs a backup right now regardless of the
  /// schedule (the settings page's manual button).
  static Future<bool> runNow() async {
    await GStorage.putSetting(SettingsKeys.lastAutoBackupMs, 0);
    await GStorage.putSetting(SettingsKeys.autoBackupEnabled, true);
    return runIfDue();
  }

  /// Runs one automatic backup when due; returns true
  /// when a file was written.
  static Future<bool> runIfDue() async {
    try {
      if (!GStorage.getSetting(SettingsKeys.autoBackupEnabled)) {
        return false;
      }
      final now = DateTime.now();
      final due = isDue(
        nowMs: now.millisecondsSinceEpoch,
        lastMs: GStorage.getSetting(SettingsKeys.lastAutoBackupMs),
        intervalDays:
            GStorage.getSetting(SettingsKeys.autoBackupIntervalDays),
      );
      if (!due) return false;
      final json = await LocalBackup.exportJson();
      final dir = await backupDirectory();
      final stamp = '${now.year}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}'
          '-${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}';
      final file = File('${dir.path}/auto-backup-$stamp.json');
      await file.writeAsString(json, flush: true);
      await GStorage.putSetting(
        SettingsKeys.lastAutoBackupMs,
        now.millisecondsSinceEpoch,
      );
      final all = await listBackups();
      for (final old in all.skip(keepCount)) {
        try {
          await old.delete();
        } catch (_) {}
      }
      return true;
    } catch (e) {
      AnikumoLogger().w('AutoBackup: failed', error: e);
      return false;
    }
  }
}
