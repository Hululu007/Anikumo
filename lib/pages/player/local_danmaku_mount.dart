import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/modules/danmaku/danmaku_module.dart';
import 'package:anikumo/pages/player/controller/player_danmaku_controller.dart';
import 'package:anikumo/services/danmaku/local_danmaku_file.dart';
import 'package:anikumo/services/i18n/app_strings.dart';

/// Batch 272 (#33): mounts a local danmaku file onto
/// the playing video — the film zone's danmaku source,
/// since external sessions never query the anime
/// danmaku services. The parsed entries replace the
/// current danmaku load, like picking a new source
/// would in the anime zone.
Future<void> mountLocalDanmakuFile(
  BuildContext context, {
  required PlayerDanmakuController danmakuController,
}) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xml', 'json', 'ass'],
    withData: true,
  );
  final bytes = picked?.files.singleOrNull?.bytes;
  if (bytes == null) return;
  List<DanmakuEntry> entries;
  try {
    entries = parseLocalDanmakuFile(utf8.decode(bytes));
  } catch (_) {
    entries = const [];
  }
  if (!context.mounted) return;
  if (entries.isEmpty) {
    AnikumoDialog.showToast(message: S.t('没有从文件里读到弹幕'));
    return;
  }
  danmakuController.beginDanmakuLoad();
  danmakuController.applyDanmakuLoad(
    DanmakuLoadResult.success(
      danmakus: entries,
      bangumiID: danmakuController.bangumiID,
    ),
    enableDanmaku: true,
  );
  AnikumoDialog.showToast(
    message: S.f('已挂载 {} 条本地弹幕', [entries.length]),
  );
}
