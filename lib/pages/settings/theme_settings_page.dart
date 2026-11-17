import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/card/palette_card.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/bean/settings/theme_provider.dart';
import 'package:anikumo/bean/settings/color_type.dart';
import 'package:anikumo/bean/settings/settings_detail_scaffold.dart';
import 'package:anikumo/bean/settings/settings_dropdown_tile.dart';
import 'package:anikumo/bean/settings/settings_list.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:window_manager/window_manager.dart';
import 'package:anikumo/utils/device.dart';
import 'package:anikumo/utils/theme.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/bean/widget/zone_switcher.dart';

class ThemeSettingsPage extends StatefulWidget {
  const ThemeSettingsPage({super.key});

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  late dynamic defaultThemeMode;
  late dynamic defaultThemeColor;
  late bool oledEnhance;
  late bool useDynamicColor;
  late bool showWindowButton;
  late bool useSystemFont;
  late String zoneSwitcherStyleKey;
  late final ThemeProvider themeProvider;

  @override
  void initState() {
    super.initState();
    defaultThemeMode = GStorage.getSetting(SettingsKeys.themeMode);
    defaultThemeColor = GStorage.getSetting(SettingsKeys.themeColor);
    oledEnhance = GStorage.getSetting(SettingsKeys.oledEnhance);
    useDynamicColor = GStorage.getSetting(SettingsKeys.useDynamicColor);
    showWindowButton = GStorage.getSetting(SettingsKeys.showWindowButton);
    useSystemFont = GStorage.getSetting(SettingsKeys.useSystemFont);
    zoneSwitcherStyleKey = currentZoneSwitcherStyle().key;
    themeProvider = context.read<ThemeProvider>();
  }

  void setTheme(Color? color) {
    var defaultDarkTheme = ThemeData(
        useMaterial3: true,
        fontFamily: themeProvider.currentFontFamily,
        brightness: Brightness.dark,
        colorSchemeSeed: color,
        progressIndicatorTheme: progressIndicatorTheme2024,
        sliderTheme: sliderTheme2024,
        pageTransitionsTheme: pageTransitionsTheme2024);
    var oledTheme = oledDarkTheme(defaultDarkTheme);
    themeProvider.setTheme(
      ThemeData(
          useMaterial3: true,
          fontFamily: themeProvider.currentFontFamily,
          brightness: Brightness.light,
          colorSchemeSeed: color,
          progressIndicatorTheme: progressIndicatorTheme2024,
          sliderTheme: sliderTheme2024,
          pageTransitionsTheme: pageTransitionsTheme2024),
      oledEnhance ? oledTheme : defaultDarkTheme,
    );
    defaultThemeColor = color?.toARGB32().toRadixString(16) ?? 'default';
    GStorage.putSetting(SettingsKeys.themeColor, defaultThemeColor);
  }

  void resetTheme() {
    var defaultDarkTheme = ThemeData(
        useMaterial3: true,
        fontFamily: themeProvider.currentFontFamily,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.green,
        progressIndicatorTheme: progressIndicatorTheme2024,
        sliderTheme: sliderTheme2024,
        pageTransitionsTheme: pageTransitionsTheme2024);
    var oledTheme = oledDarkTheme(defaultDarkTheme);
    themeProvider.setTheme(
      ThemeData(
          useMaterial3: true,
          fontFamily: themeProvider.currentFontFamily,
          brightness: Brightness.light,
          colorSchemeSeed: Colors.green,
          progressIndicatorTheme: progressIndicatorTheme2024,
          sliderTheme: sliderTheme2024,
          pageTransitionsTheme: pageTransitionsTheme2024),
      oledEnhance ? oledTheme : defaultDarkTheme,
    );
    defaultThemeColor = 'default';
    GStorage.putSetting(SettingsKeys.themeColor, 'default');
  }

  /// Batch 275 (#44): reorder dialog — up/down buttons
  /// per zone, persisted immediately as the order CSV.
  Future<void> _showZoneOrderDialog() async {
    var order = orderedZones();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.t('专区顺序')),
        content: StatefulBuilder(
          builder: (context, setDialogState) => SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < order.length; i++)
                  ListTile(
                    leading: Icon(order[i].icon),
                    title: Text(S.t(order[i].label)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            AnikumoIcons.arrow_upward_rounded,
                          ),
                          tooltip: S.t('上移'),
                          onPressed: i == 0
                              ? null
                              : () async {
                                  final next = [...order];
                                  final moved = next.removeAt(i);
                                  next.insert(i - 1, moved);
                                  await GStorage.putSetting(
                                    SettingsKeys.zoneOrderCsv,
                                    next.map((z) => z.name).join(','),
                                  );
                                  setDialogState(() => order = next);
                                },
                        ),
                        IconButton(
                          icon: const Icon(
                            AnikumoIcons.arrow_downward_rounded,
                          ),
                          tooltip: S.t('下移'),
                          onPressed: i == order.length - 1
                              ? null
                              : () async {
                                  final next = [...order];
                                  final moved = next.removeAt(i);
                                  next.insert(i + 1, moved);
                                  await GStorage.putSetting(
                                    SettingsKeys.zoneOrderCsv,
                                    next.map((z) => z.name).join(','),
                                  );
                                  setDialogState(() => order = next);
                                },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await GStorage.putSetting(SettingsKeys.zoneOrderCsv, '');
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: Text(S.t('恢复默认')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.t('完成')),
          ),
        ],
      ),
    );
  }

  void updateTheme(String theme) async {
    if (theme == 'dark') {
      themeProvider.setThemeMode(ThemeMode.dark);
    }
    if (theme == 'light') {
      themeProvider.setThemeMode(ThemeMode.light);
    }
    if (theme == 'system') {
      themeProvider.setThemeMode(ThemeMode.system);
    }
    await GStorage.putSetting(SettingsKeys.themeMode, theme);
    setState(() {
      defaultThemeMode = theme;
    });

    // Update Windows title bar theme
    if (Platform.isWindows) {
      await windowManager.setBrightness(
          themeProvider.isEffectiveDark() ? Brightness.dark : Brightness.light);
    }
  }

  void updateOledEnhance() {
    dynamic color;
    oledEnhance = GStorage.getSetting(SettingsKeys.oledEnhance);
    if (defaultThemeColor == 'default') {
      color = Colors.green;
    } else {
      color = Color(int.parse(defaultThemeColor, radix: 16));
    }
    setTheme(color);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: Text(S.t('外观设置')),
      body: SettingsList(
        sections: [
          SettingsSection(
            title: Text(S.t('外观')),
            tiles: [
              SettingsDropdownTile<String>(
                leading: AnikumoIcons.dark_mode_rounded,
                title: Text(S.t('深色模式')),
                value: defaultThemeMode,
                fallbackLabel: S.t('跟随系统'),
                options: {
                  'system': S.t('跟随系统'),
                  'light': S.t('浅色'),
                  'dark': S.t('深色'),
                },
                onChanged: updateTheme,
              ),
              SettingsDropdownTile<String>(
                leading: AnikumoIcons.swap_horiz_rounded,
                title: Text(S.t('专区切换样式')),
                value: zoneSwitcherStyleKey,
                fallbackLabel: S.t('上拉面板'),
                options: {
                  for (final s in ZoneSwitcherStyle.values) s.key: S.t(s.label),
                },
                onChanged: (key) async {
                  await setZoneSwitcherStyle(ZoneSwitcherStyle.fromKey(key));
                  setState(() => zoneSwitcherStyleKey = key);
                },
              ),
              // Batch 275 (#44): custom zone order.
              SettingsTile(
                leading: AnikumoIcons.swap_horiz_rounded,
                title: Text(S.t('专区顺序')),
                description: Text(S.t('调整切换器里四个专区的排列顺序')),
                trailing: const Icon(AnikumoIcons.chevron_right_rounded),
                onPressed: (_) => _showZoneOrderDialog(),
              ),
              SettingsTile(
                leading: AnikumoIcons.palette_rounded,
                enabled: !useDynamicColor,
                onPressed: (_) async {
                  AnikumoDialog.show(builder: (context) {
                    return AlertDialog(
                      title: Text(S.t('配色方案')),
                      content: StatefulBuilder(builder:
                          (BuildContext context, StateSetter setState) {
                        final List<Map<String, dynamic>> colorThemes =
                            colorThemeTypes;
                        return Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: isDesktop() ? 8 : 0,
                          children: [
                            ...colorThemes.map(
                              (e) {
                                final index = colorThemes.indexOf(e);
                                return GestureDetector(
                                  onTap: () {
                                    index == 0
                                        ? resetTheme()
                                        : setTheme(e['color']);
                                    AnikumoDialog.dismiss();
                                  },
                                  child: Column(
                                    children: [
                                      PaletteCard(
                                        color: e['color'],
                                        selected: (e['color']
                                                    .value
                                                    .toRadixString(16) ==
                                                defaultThemeColor ||
                                            (defaultThemeColor == 'default' &&
                                                index == 0)),
                                      ),
                                      Text(S.t(e['label'])),
                                    ],
                                  ),
                                );
                              },
                            )
                          ],
                        );
                      }),
                    );
                  });
                },
                title: Text(S.t('配色方案')),
              ),
              SettingsTile.switchTile(
                leading: AnikumoIcons.colorize_rounded,
                enabled: !Platform.isIOS,
                onToggle: (value) async {
                  useDynamicColor = value ?? !useDynamicColor;
                  await GStorage.putSetting(
                      SettingsKeys.useDynamicColor, useDynamicColor);
                  themeProvider.setDynamic(useDynamicColor);
                  setState(() {});
                },
                title: Text(S.t('动态配色')),
                initialValue: useDynamicColor,
              ),
              SettingsTile.switchTile(
                leading: AnikumoIcons.font_download_rounded,
                onToggle: (value) async {
                  useSystemFont = value ?? !useSystemFont;
                  await GStorage.putSetting(
                      SettingsKeys.useSystemFont, useSystemFont);
                  themeProvider.setFontFamily(useSystemFont);
                  dynamic color;
                  if (defaultThemeColor == 'default') {
                    color = Colors.green;
                  } else {
                    color = Color(int.parse(defaultThemeColor, radix: 16));
                  }
                  setTheme(color);
                  setState(() {});
                },
                title: Text(S.t('使用系统字体')),
                description: Text(S.t('关闭后使用 MI Sans 字体')),
                initialValue: useSystemFont,
              ),
            ],
            bottomInfo: Text(S.t('动态配色仅支持安卓12及以上和桌面平台')),
          ),
          SettingsSection(
            title: Text(S.t('显示')),
            tiles: [
              SettingsTile.switchTile(
                leading: AnikumoIcons.contrast_rounded,
                onToggle: (value) async {
                  oledEnhance = value ?? !oledEnhance;
                  await GStorage.putSetting(
                      SettingsKeys.oledEnhance, oledEnhance);
                  updateOledEnhance();
                  setState(() {});
                },
                title: Text(S.t('OLED优化')),
                description: Text(S.t('深色模式下使用纯黑背景')),
                initialValue: oledEnhance,
              ),
            ],
          ),
          if (isDesktop())
            SettingsSection(
              title: Text(S.t('窗口')),
              tiles: [
                SettingsTile.switchTile(
                  leading: AnikumoIcons.web_asset_rounded,
                  onToggle: (value) async {
                    showWindowButton = value ?? !showWindowButton;
                    await GStorage.putSetting(
                        SettingsKeys.showWindowButton, showWindowButton);
                    setState(() {});
                  },
                  title: Text(S.t('使用系统标题栏')),
                  description: Text(S.t('重启应用生效')),
                  initialValue: showWindowButton,
                ),
              ],
            ),
          if (Platform.isAndroid)
            SettingsSection(
              title: Text(S.t('屏幕')),
              tiles: [
                SettingsTile(
                  leading: AnikumoIcons.sixty_fps_rounded,
                  onPressed: (_) async {
                    context.pushNamed('/settings/theme/display');
                  },
                  title: Text(S.t('屏幕帧率')),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
