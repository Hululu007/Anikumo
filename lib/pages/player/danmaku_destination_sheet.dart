import 'package:flutter/material.dart';

import 'package:anikumo/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:anikumo/bean/dialog/material_bottom_sheet.dart';
import 'package:anikumo/bean/widget/split_list_row.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/services/i18n/app_strings.dart';

enum DanmakuDestination {
  chatRoom,
  remoteDanmaku,
}

Future<DanmakuDestination?> showDanmakuDestinationSheet(BuildContext context) {
  return showAdaptiveBottomSheet<DanmakuDestination>(
    context: context,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MaterialBottomSheetHeader(
          title: S.t('发送到'),
          onClose: () => Navigator.of(context).pop(),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: materialBottomSheetContentPadding,
            child: SplitListGroup(
              children: [
                ListTile(
                  leading: const Icon(AnikumoIcons.groups_rounded),
                  title: Text(S.t('一起看聊天室')),
                  subtitle: Text(S.t('与同房间的朋友聊天')),
                  onTap: () =>
                      Navigator.of(context).pop(DanmakuDestination.chatRoom),
                ),
                ListTile(
                  leading: const Icon(AnikumoIcons.subtitles_outlined),
                  title: Text(S.t('视频弹幕')),
                  subtitle: Text(S.t('保存在本机，在这集播放时显示')),
                  onTap: () => Navigator.of(context)
                      .pop(DanmakuDestination.remoteDanmaku),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
