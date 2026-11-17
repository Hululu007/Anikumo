import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/services/i18n/app_strings.dart';

/// Batch 276 (#59): the watch-report share card — the
/// period's headline numbers rendered as one image,
/// saved through the system file picker (same capture
/// path as the player's screenshot/GIF flows).
Future<void> showReportShareCard(
  BuildContext context, {
  required String periodLabel,
  required int episodes,
  required int minutes,
  required int activeDays,
  required List<String> topTags,
}) async {
  final boundaryKey = GlobalKey();
  Future<void> save() async {
    try {
      final boundary = boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final path = await FilePicker.platform.saveFile(
        dialogTitle: S.t('保存分享卡'),
        fileName: 'anikumo-report.png',
        type: FileType.custom,
        allowedExtensions: const ['png'],
        bytes: data.buffer.asUint8List(),
      );
      if (context.mounted) {
        AnikumoDialog.showToast(
          context: context,
          message: path == null ? S.t('已取消导出') : S.t('分享卡已保存'),
        );
      }
    } catch (_) {
      if (context.mounted) {
        AnikumoDialog.showToast(
          context: context,
          message: S.t('导出失败，请稍后重试'),
        );
      }
    }
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RepaintBoundary(
            key: boundaryKey,
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6C4BD8), Color(0xFF3E2A84)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ANIKUMO',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    periodLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      _cardStat(S.f('{} 集', [episodes]), S.t('观看集数')),
                      _cardStat(
                        S.f('{} 小时', [(minutes / 60).toStringAsFixed(1)]),
                        S.t('观看时长'),
                      ),
                      _cardStat(S.f('{} 天', [activeDays]), S.t('活跃天数')),
                    ],
                  ),
                  if (topTags.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag in topTags.take(3))
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(S.t('关闭')),
        ),
        FilledButton(
          onPressed: save,
          child: Text(S.t('保存图片')),
        ),
      ],
    ),
  );
}

Widget _cardStat(String value, String label) {
  return Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    ),
  );
}
