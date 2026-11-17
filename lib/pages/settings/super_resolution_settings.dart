import 'package:flutter/material.dart';
import 'package:anikumo/bean/settings/settings_detail_scaffold.dart';
import 'package:anikumo/pages/player/controller/player_super_resolution.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/bean/settings/settings_list.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

class SuperResolutionSettings extends StatefulWidget {
  const SuperResolutionSettings({super.key});

  @override
  State<SuperResolutionSettings> createState() =>
      _SuperResolutionSettingsState();
}

class _SuperResolutionSettingsState extends State<SuperResolutionSettings> {
  late bool disableWarning;
  late SuperResolutionMode superResolutionMode;

  @override
  void initState() {
    super.initState();
    disableWarning = GStorage.getSetting<bool>(
      SettingsKeys.disableSuperResolutionWarning,
    );
    superResolutionMode = SuperResolutionMode.fromStorageValue(
      GStorage.getSetting<int>(SettingsKeys.defaultSuperResolutionMode),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: Text(S.t('超分辨率')),
      body: SettingsList(
        sections: [
          SettingsRadioSection<SuperResolutionMode>(
            title: Text(S.t('超分辨率需要启用硬件解码, 若启用硬件解码后仍然不生效, 尝试切换视频渲染器为 gpu')),
            groupValue: superResolutionMode,
            onChanged: (SuperResolutionMode? value) {
              if (value == null) return;
              GStorage.putSetting<int>(
                SettingsKeys.defaultSuperResolutionMode,
                value.storageValue,
              );
              setState(() {
                superResolutionMode = value;
              });
            },
            tiles: [
              for (final mode in SuperResolutionMode.values)
                SettingsTile<SuperResolutionMode>.radioTile(
                  title: Text(S.t(mode.label)),
                  description: Text(S.t(mode.description)),
                  radioValue: mode,
                ),
            ],
          ),
          SettingsSection(
            title: Text(S.t('默认行为')),
            tiles: [
              SettingsTile.switchTile(
                leading: AnikumoIcons.notifications_off_rounded,
                title: Text(S.t('关闭提示')),
                description: Text(S.t('关闭每次启用超分辨率时的提示')),
                initialValue: disableWarning,
                onToggle: (value) async {
                  disableWarning = value ?? !disableWarning;
                  await GStorage.putSetting<bool>(
                    SettingsKeys.disableSuperResolutionWarning,
                    disableWarning,
                  );
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
