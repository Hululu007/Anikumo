import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:anikumo/bean/widget/error_widget.dart';
import 'package:anikumo/bean/widget/loading_indicator.dart';
import 'package:anikumo/bean/widget/state_presentation.dart';
import 'package:anikumo/services/platform/app_exit.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/services/i18n/app_strings.dart';

class StorageErrorPage extends StatelessWidget {
  const StorageErrorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t('内部错误')),
      ),
      body: FutureBuilder<Directory>(
        future: getApplicationSupportDirectory(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            final path = snapshot.data?.path ?? S.t('未知路径');
            return GeneralErrorWidget(
              title: S.t('无法初始化本地存储'),
              icon: AnikumoIcons.storage_rounded,
              errMsg: S.f('当前存储位置：\n{}\n\n可在退出后删除该目录以重置本地存储，此操作会清除本地数据。', [path]),
              actions: [
                StateActionButton(
                  onPressed: AppExit.quit,
                  text: S.t('退出程序'),
                  icon: AnikumoIcons.close_rounded,
                ),
              ],
            );
          } else {
            return const Center(child: LoadingIndicator());
          }
        },
      ),
    );
  }
}
