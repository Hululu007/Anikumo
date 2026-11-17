import 'package:anikumo/services/i18n/app_strings.dart';
import 'dart:io';

import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/services/player/external_player.dart';

class ExternalPlaybackLauncher {
  final String Function() videoUrl;
  final String Function() referer;

  ExternalPlaybackLauncher({
    required this.videoUrl,
    required this.referer,
  });

  Future<void> launch() async {
    final currentVideoUrl = videoUrl();
    final currentReferer = referer();
    if ((Platform.isAndroid || Platform.isWindows) && currentReferer.isEmpty) {
      if (await ExternalPlayer.launchUrlWithMime(
          currentVideoUrl, 'video/mp4')) {
        AnikumoDialog.showToast(
          message: S.t('尝试唤起外部播放器'),
        );
      } else {
        AnikumoDialog.showToast(
          message: S.t('唤起外部播放器失败'),
        );
      }
    } else if (Platform.isMacOS || Platform.isIOS) {
      if (await ExternalPlayer.launchUrlWithReferer(
          currentVideoUrl, currentReferer)) {
        AnikumoDialog.showToast(
          message: S.t('尝试唤起外部播放器'),
        );
      } else {
        AnikumoDialog.showToast(
          message: S.t('唤起外部播放器失败'),
        );
      }
    } else if (Platform.isLinux && currentReferer.isEmpty) {
      final result =
          await ExternalPlayer.launchLinuxDesktopPlayer(currentVideoUrl);
      switch (result) {
        case LinuxExternalPlayerResult.launched:
          AnikumoDialog.showToast(message: S.t('尝试唤起外部播放器'));
        case LinuxExternalPlayerResult.cancelled:
          break;
        case LinuxExternalPlayerResult.unavailable:
          AnikumoDialog.showToast(message: S.t('系统应用选择器不可用'));
        case LinuxExternalPlayerResult.failed:
          AnikumoDialog.showToast(message: S.t('唤起外部播放器失败'));
      }
    } else {
      if (currentReferer.isEmpty) {
        AnikumoDialog.showToast(
          message: S.t('暂不支持该设备'),
        );
      } else {
        AnikumoDialog.showToast(
          message: S.t('暂不支持该规则'),
        );
      }
    }
  }
}
