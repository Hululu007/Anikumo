import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/services/announcement/announcement_service.dart';
import 'package:anikumo/services/i18n/app_strings.dart';

/// Batch 267: the startup announcement dialog.
///
/// Returns 'dismiss' when the user picks 「下次不再显示」
/// (the caller persists the announcement id so this one
/// never shows again; a NEW announcement id still shows),
/// and 'ok' for a plain acknowledgement (the announcement
/// shows again on the next launch until muted or replaced).
/// The community button opens the Discord invite in the
/// browser without closing the dialog.
class AnnouncementDialog extends StatelessWidget {
  const AnnouncementDialog({super.key, required this.announcement});

  final AppAnnouncement announcement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        announcement.title.isEmpty ? S.t('公告') : announcement.title,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(announcement.content),
            if (announcement.publishedAt.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                announcement.publishedAt,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(AnikumoIcons.forum_rounded, size: 18),
          label: Text(S.t('加入官方社区')),
          onPressed: () => launchUrl(
            Uri.parse(kDiscordCommunityInvite),
            mode: LaunchMode.externalApplication,
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop('dismiss'),
          child: Text(S.t('下次不再显示')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop('ok'),
          child: Text(S.t('知道了')),
        ),
      ],
    );
  }
}
