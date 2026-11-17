import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:anikumo/bean/dialog/announcement_dialog.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 267: in-app announcements, published from the
/// Discord community.
///
/// The announcement lives as one JSON file in the app's
/// public repository (`announcement.json` on main). The
/// Discord bot's /announcement command rewrites that file
/// (new id every publish); the app fetches it once per cold
/// start and shows it when its id differs from the one the
/// user muted with 「下次不再显示」. Everything fails
/// silently — offline or a missing file simply means no
/// announcement.
const kAnnouncementJsonUrl =
    'https://raw.githubusercontent.com/xyu3032-commits/Anikumo/main/announcement.json';

/// The official Discord community invite, also linked from
/// 设置 → 关于 → 官方社区.
const kDiscordCommunityInvite = 'https://discord.gg/dBwruBWyKE';

class AppAnnouncement {
  const AppAnnouncement({
    required this.id,
    required this.title,
    required this.content,
    required this.publishedAt,
    required this.enabled,
  });

  final String id;
  final String title;
  final String content;
  final String publishedAt;
  final bool enabled;

  static AppAnnouncement? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id']?.toString().trim() ?? '';
    final content = json['content']?.toString().trim() ?? '';
    if (id.isEmpty || content.isEmpty) return null;
    return AppAnnouncement(
      id: id,
      title: json['title']?.toString().trim() ?? '',
      content: content,
      publishedAt: json['publishedAt']?.toString().trim() ?? '',
      // Anything but an explicit false counts as enabled,
      // so a hand-written file without the flag still works.
      enabled: json['enabled'] != false,
    );
  }
}

/// Whether [announcement] should be shown to a user who
/// muted [dismissedId] ('' when nothing was ever muted).
bool shouldShowAnnouncement(AppAnnouncement? announcement, String dismissedId) {
  if (announcement == null) return false;
  if (!announcement.enabled) return false;
  return announcement.id != dismissedId;
}

Future<AppAnnouncement?> fetchAnnouncement({Dio? dio}) async {
  final client = dio ??
      Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 6),
      ));
  try {
    final response = await client.get<String>(kAnnouncementJsonUrl);
    final data = response.data;
    if (data == null || data.isEmpty) return null;
    return AppAnnouncement.fromJson(jsonDecode(data));
  } catch (e) {
    AnikumoLogger().w('Announcement: fetch failed', error: e);
    return null;
  }
}

/// Startup entry, mirroring runStartupUpdateCheck: the
/// scheduling page is disposed by the time this runs, so
/// nothing here may depend on a page's State. Waits a bit
/// longer than the update check so the two dialogs do not
/// race on the rare launches where both have news.
Future<void> runStartupAnnouncementCheck({
  Duration delay = const Duration(seconds: 2),
}) async {
  await Future<void>.delayed(delay);
  try {
    final announcement = await fetchAnnouncement();
    if (announcement == null) return;
    final dismissedId =
        GStorage.getSetting(SettingsKeys.announcementDismissedId);
    if (!shouldShowAnnouncement(announcement, dismissedId)) return;
    final choice = await AnikumoDialog.show<String>(
      builder: (context) => AnnouncementDialog(announcement: announcement),
    );
    if (choice == 'dismiss') {
      await GStorage.putSetting(
          SettingsKeys.announcementDismissedId, announcement.id);
    }
  } catch (e) {
    AnikumoLogger().w('Announcement: startup check failed', error: e);
  }
}
