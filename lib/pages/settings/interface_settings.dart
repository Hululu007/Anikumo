import 'package:flutter/material.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/bean/settings/settings_detail_scaffold.dart';
import 'package:anikumo/bean/settings/settings_dropdown_tile.dart';
import 'package:anikumo/bean/settings/settings_list.dart';
import 'package:anikumo/modules/collect/collect_layout.dart';
import 'package:anikumo/pages/settings/language_setting_tile.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/utils/device.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

class InterfaceSettingsPage extends StatefulWidget {
  const InterfaceSettingsPage({super.key});

  @override
  State<InterfaceSettingsPage> createState() => _InterfaceSettingsPageState();
}

class _InterfaceSettingsPageState extends State<InterfaceSettingsPage> {
  late bool showRating;
  late String defaultPage;
  late CollectLayout _defaultCollectLayout;
  bool _savingCollectLayout = false;
  static const _exitBehaviorTitles = ['退出 Anikumo', '最小化至托盘', '每次都询问'];
  int _exitBehavior = GStorage.getSetting(SettingsKeys.exitBehavior)
      .clamp(0, _exitBehaviorTitles.length - 1);

  static const Map<String, String> defaultPageMap = {
    '/tab/popular/': '推荐',
    '/tab/featured/': '精选',
    '/tab/discover/': '发现',
    '/tab/timeline/': '时间表',
    '/tab/collect/': '追番',
    '/tab/my/': '我的',
  };

  @override
  void initState() {
    super.initState();
    showRating = GStorage.getSetting(SettingsKeys.showRating);
    defaultPage = GStorage.getSetting(SettingsKeys.defaultStartupPage);
    _defaultCollectLayout = CollectLayout.fromValue(
      GStorage.getSetting(SettingsKeys.defaultCollectLayout),
    );
  }

  void updateDefaultPage(String page) {
    GStorage.putSetting(SettingsKeys.defaultStartupPage, page);
    setState(() {
      defaultPage = page;
    });
  }

  Future<void> _updateDefaultCollectLayout(CollectLayout layout) async {
    if (_savingCollectLayout || layout == _defaultCollectLayout) return;
    setState(() => _savingCollectLayout = true);
    try {
      await GStorage.putSetting(SettingsKeys.defaultCollectLayout, layout.name);
      if (mounted) setState(() => _defaultCollectLayout = layout);
    } catch (_) {
      if (mounted) {
        AnikumoDialog.showToast(message: S.t('追番默认布局保存失败，请重试'));
      }
    } finally {
      if (mounted) setState(() => _savingCollectLayout = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: Text(S.t('界面设置')),
      body: SettingsList(
        sections: [
          SettingsSection(title: Text(S.t('语言')), tiles: [
            const LanguageSettingTile(),
          ]),
          SettingsSection(title: Text(S.t('启动')), tiles: [
            SettingsDropdownTile<String>(
              leading: AnikumoIcons.home_rounded,
              title: Text(S.t('启动界面设置')),
              description: Text(S.t('设置应用开启时的默认页面')),
              value: defaultPage,
              options: {
                for (final entry in defaultPageMap.entries)
                  entry.key: S.t(entry.value),
              },
              fallbackLabel: S.t('推荐'),
              onChanged: updateDefaultPage,
            ),
          ]),
          SettingsSection(title: Text(S.t('展示信息')), tiles: [
            SettingsDropdownTile<CollectLayout>(
              leading: AnikumoIcons.view_agenda_rounded,
              title: Text(S.t('追番默认布局')),
              description: Text(S.t('下次打开追番页时使用，页面内切换不会改变此设置')),
              enabled: !_savingCollectLayout,
              value: _defaultCollectLayout,
              options: {
                for (final layout in CollectLayout.values) layout: layout.label,
              },
              onChanged: _updateDefaultCollectLayout,
            ),
            SettingsTile.switchTile(
              leading: AnikumoIcons.star_rounded,
              onToggle: (value) async {
                showRating = value ?? !showRating;
                await GStorage.putSetting(SettingsKeys.showRating, showRating);
                setState(() {});
              },
              title: Text(S.t('显示评分')),
              description: Text(S.t('关闭后隐藏概览和番剧列表中的评分信息')),
              initialValue: showRating,
            ),
          ]),
          if (isDesktop())
            SettingsSection(
              title: Text(S.t('窗口行为')),
              tiles: [
                SettingsDropdownTile<int>(
                  leading: AnikumoIcons.exit_to_app_rounded,
                  title: Text(S.t('关闭窗口时')),
                  description: Text(S.t('设置点击窗口关闭按钮后的行为')),
                  value: _exitBehavior,
                  options: {
                    for (var i = 0; i < _exitBehaviorTitles.length; i++)
                      i: S.t(_exitBehaviorTitles[i]),
                  },
                  onChanged: (value) {
                    setState(() => _exitBehavior = value);
                    GStorage.putSetting(SettingsKeys.exitBehavior, value);
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}
