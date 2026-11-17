import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/pages/liuguang/film_tmdb_login_page.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/liuguang/film_accounts.dart';

/// Batch 254 built this section for the film zone's
/// settings; batch 257 extracted it unchanged so the
/// user center's profile page hosts the very same
/// TMDB / Bangumi connection rows (one implementation,
/// no drift).

/// Batch 254: account connections — TMDB (web-approved
/// session) and Bangumi (the app-wide access token the
/// anime zone's sync uses; connecting here connects
/// there too). Connected accounts unlock detail-page
/// sync actions and the cloud lists page.
class FilmAccountSection extends StatefulWidget {
  const FilmAccountSection({super.key});

  @override
  State<FilmAccountSection> createState() => _FilmAccountSectionState();
}

class _FilmAccountSectionState extends State<FilmAccountSection> {
  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // A connected Bangumi account whose display name was
    // never fetched (e.g. connected from the anime side)
    // resolves it quietly.
    if (BangumiAccount.connected && BangumiAccount.username.isEmpty) {
      BangumiAccount.verify().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _connectTmdb() async {
    final ok = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const FilmTmdbLoginPage()));
    if (mounted && ok == true) setState(() {});
  }

  Future<void> _disconnectTmdb() async {
    await TmdbAccount.logout();
    if (mounted) setState(() {});
  }

  Future<void> _disconnectBangumi() async {
    await BangumiAccount.disconnect();
    if (mounted) setState(() {});
  }

  Future<void> _connectBangumi() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        var busy = false;
        String? error;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              final value = controller.text.trim();
              if (value.isEmpty || busy) return;
              setDialogState(() {
                busy = true;
                error = null;
              });
              final verified = await BangumiAccount.verify(candidate: value);
              if (verified == null) {
                setDialogState(() {
                  busy = false;
                  error = S.t('令牌验证失败，请确认令牌无误、网络可用。');
                });
                return;
              }
              await BangumiAccount.saveToken(value);
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop(verified);
              }
            }

            return AlertDialog(
              title: Text(S.t('连接 Bangumi 账户')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.t('粘贴你的 Bangumi 访问令牌（与动漫区同步用的是同一个账号）。')),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => launchUrl(
                      Uri.parse('https://next.bgm.tv/demo/access-token'),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Text(
                      S.t('点此打开 Bangumi 令牌页获取'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      labelText: S.t('访问令牌'),
                      border: const OutlineInputBorder(),
                    ),
                    obscureText: true,
                    maxLines: 1,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(S.t('取消')),
                ),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: Text(busy ? S.t('验证中…') : S.t('验证并连接')),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    if (!mounted) return;
    if (name != null) {
      setState(() {});
      AnikumoDialog.showToast(
        context: context,
        message: S.f('已连接 Bangumi 账户 @{}', [name]),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tmdbOn = TmdbAccount.connected;
    final bgmOn = BangumiAccount.connected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, S.t('账户')),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(AnikumoIcons.movie_rounded),
          title: Text(S.t('TMDB 账户')),
          subtitle: Text(
            tmdbOn
                ? S.f('已连接 @{}——详情页可同步收藏 / 想看', [TmdbAccount.username])
                : S.t('未连接——连接后可把收藏、想看同步到你的 TMDB 账户'),
          ),
          trailing: TextButton(
            onPressed: tmdbOn ? _disconnectTmdb : _connectTmdb,
            child: Text(tmdbOn ? S.t('断开') : S.t('连接')),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(AnikumoIcons.collections_bookmark_rounded),
          title: Text(S.t('Bangumi 账户')),
          subtitle: Text(
            bgmOn
                ? S.f('已连接{}——详情页可同步收藏状态（与动漫区共用账号）', [
                    BangumiAccount.username.isEmpty
                        ? ''
                        : ' @${BangumiAccount.username}',
                  ])
                : S.t('未连接——用访问令牌连接，详情页可同步收藏状态（与动漫区共用账号）'),
          ),
          trailing: TextButton(
            onPressed: bgmOn ? _disconnectBangumi : _connectBangumi,
            child: Text(bgmOn ? S.t('断开') : S.t('连接')),
          ),
        ),
        if (tmdbOn || bgmOn)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(AnikumoIcons.cloud_rounded),
            title: Text(S.t('我的云端片单')),
            subtitle: Text(S.t('TMDB 想看 / 收藏与 Bangumi 收藏，点开即可在本应用里找源观看、下载')),
            trailing: const Icon(AnikumoIcons.chevron_right_rounded),
            onTap: () => context.pushNamed('/film/cloud'),
          ),
      ],
    );
  }
}
