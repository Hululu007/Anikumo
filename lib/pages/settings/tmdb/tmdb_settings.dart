import 'package:flutter/material.dart';

import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/bean/settings/settings_detail_scaffold.dart';
import 'package:anikumo/bean/settings/settings_list.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/services/tmdb/tmdb_episodes.dart';
import 'package:anikumo/services/tmdb/tmdb_key.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// Batch 129: settings for the per-episode stills feature —
/// the user's own TMDB API key plus the legally required
/// attribution. Without a key the episode picker simply
/// keeps using the series cover (batch 127 behaviour).
class TmdbSettingsPage extends StatefulWidget {
  const TmdbSettingsPage({super.key});

  @override
  State<TmdbSettingsPage> createState() => _TmdbSettingsPageState();
}

class _TmdbSettingsPageState extends State<TmdbSettingsPage> {
  late String _apiKey;

  @override
  void initState() {
    super.initState();
    _apiKey = GStorage.getSetting(SettingsKeys.tmdbApiKey);
  }

  Future<void> _editApiKey() async {
    final controller = TextEditingController(text: _apiKey);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.t('TMDB API 密钥')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: S.t('在 themoviedb.org 注册后，设置 → API 中复制（v3）'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(S.t('保存')),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    final value = controller.text.trim();
    await GStorage.putSetting(SettingsKeys.tmdbApiKey, value);
    // A new key may resolve different matches; drop them.
    TmdbEpisodeService.clearCache();
    setState(() => _apiKey = value);
  }

  Future<void> _clearCache() async {
    TmdbEpisodeService.clearCache();
    AnikumoDialog.showToast(message: S.t('已清除剧照缓存'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SettingsDetailScaffold(
      title: Text(S.t('剧集图片')),
      body: SettingsList(
        sections: [
          SettingsSection(
            title: Text(S.t('接口凭据')),
            tiles: [
              SettingsTile(
                leading: AnikumoIcons.key_rounded,
                title: Text(S.t('API 密钥')),
                description: Text(
                  _apiKey.isNotEmpty
                      ? S.t('已设置（内容隐藏）— 优先用你自己的密钥')
                      : builtinTmdbKey.isNotEmpty
                          ? S.t('未设置 — 正在使用内置密钥（可在此换成你自己的）')
                          : S.t('未设置 — 选集继续使用番剧封面'),
                ),
                onPressed: (_) => _editApiKey(),
              ),
              SettingsTile(
                leading: AnikumoIcons.cached_rounded,
                title: Text(S.t('清除剧照缓存')),
                description: Text(S.t('匹配到的剧集图片会缓存下来，匹配错了可以清掉重来')),
                onPressed: (_) => _clearCache(),
              ),
            ],
          ),
          SettingsSection(
            title: Text(S.t('说明')),
            tiles: [
              SettingsTile(
                leading: AnikumoIcons.info_outline_rounded,
                title: Text(S.t('这个功能做什么')),
                description: Text(
                  S.t('动漫详情页的选集里，每一集会显示它自己的剧照、时长和播出日期；没匹配上时自动退回番剧封面，不影响选集本身。内置密钥开箱可用，也可以在上面换成你自己的。'),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Text(
              S.t('剧集图片与资料由 TMDB 提供。本产品使用 TMDB API，但未经 TMDB 背书或认证。'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
