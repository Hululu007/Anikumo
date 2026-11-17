import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:anikumo/services/i18n/app_strings.dart';

/// Batch 276 (#60): the payload a work's QR code
/// carries — the app's own deep link, so any camera
/// or scanner app on the other phone opens Anikumo
/// straight at the work (bangumi link when an id is
/// known, title search otherwise).
String workDeepLink({required String title, int bangumiId = 0}) {
  if (bangumiId > 0) return 'anikumo://bangumi/$bangumiId';
  return 'anikumo://search?query=${Uri.encodeComponent(title)}';
}

/// Shows a work's QR code for device-to-device
/// passing: the other phone scans it with its camera
/// and lands on the same work in Anikumo.
Future<void> showWorkQrCode(
  BuildContext context, {
  required String title,
  int bangumiId = 0,
}) {
  final link = workDeepLink(title: title, bangumiId: bangumiId);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(S.t('二维码互传')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrImageView(
            data: link,
            version: QrVersions.auto,
            size: 220,
            backgroundColor: Colors.white,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(dialogContext).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            S.t('用另一台手机的相机扫一扫，在那台设备上打开这部作品'),
            textAlign: TextAlign.center,
            style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                  color: Theme.of(dialogContext).colorScheme.outline,
                ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(S.t('完成')),
        ),
      ],
    ),
  );
}
