import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

import 'package:anikumo/services/i18n/app_strings.dart';
import '../../bean/dialog/dialog.dart';
import '../../services/manga/js/js_manga_source.dart';
import '../../services/manga/js/mangakit_host.dart';
import '../../services/manga/manga_sources.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// Batch 271: WebView login for JS manga sources.
///
/// The form login page covers sources whose own
/// `account.login` function exists; plenty of sites only
/// offer a web sign-in (OAuth, captcha-gated forms). This
/// page mirrors the novel zone's browser login: the user
/// signs in on the source's real site in a WebView, and
/// 「保存登录状态」 harvests the session cookies into the
/// engines' shared jar (the same jar the verification
/// page plants into), so later source calls ride the
/// session. Nothing is typed into a host form and no
/// credential is stored by the app.
class MangaWebLoginPage extends StatefulWidget {
  const MangaWebLoginPage({super.key, required this.sourceId});

  final String sourceId;

  @override
  State<MangaWebLoginPage> createState() => _MangaWebLoginPageState();
}

class _MangaWebLoginPageState extends State<MangaWebLoginPage> {
  PlatformInAppWebViewWidget? _webView;
  String _startUrl = '';
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _resolveStartUrl();
  }

  Future<void> _resolveStartUrl() async {
    final source = MangaSources.byId(widget.sourceId);
    var url = '';
    if (source is JsBackedMangaSource) {
      url = source.declaredUrl ?? '';
      if (url.isEmpty) {
        try {
          final info = await source.accountInfo();
          url = info?.registerWebsite ?? '';
        } catch (_) {}
      }
    }
    if (!mounted) return;
    if (url.isEmpty || !url.startsWith('http')) {
      AnikumoDialog.showToast(message: S.t('这个源没有提供可打开的网站地址'));
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _startUrl = url;
      _webView = PlatformInAppWebViewWidget(
        PlatformInAppWebViewWidgetCreationParams(
          initialUrlRequest: URLRequest(url: WebUri(url)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            useWideViewPort: true,
            loadWithOverviewMode: true,
          ),
        ),
      );
    });
  }

  Future<void> _save() async {
    if (_saving || _startUrl.isEmpty) return;
    setState(() => _saving = true);
    var planted = 0;
    try {
      final manager =
          PlatformCookieManager(const PlatformCookieManagerCreationParams());
      final host = Uri.tryParse(_startUrl)?.host ?? '';
      final urls = <String>{
        _startUrl,
        if (host.isNotEmpty) 'https://$host/',
      };
      final raw = <String>[];
      for (final url in urls) {
        final cookies = await manager.getCookies(url: WebUri(url));
        for (final cookie in cookies) {
          final name = cookie.name;
          final value = cookie.value?.toString() ?? '';
          if (name.isEmpty || value.isEmpty) continue;
          final domain = (cookie.domain ?? '').replaceFirst(
            RegExp(r'^\.'),
            '',
          );
          raw.add(
            domain.isEmpty ? '$name=$value' : '$name=$value; Domain=$domain',
          );
        }
      }
      planted = raw.length;
      MangaKitRuntime.instance.plantRawSetCookies(_startUrl, raw);
    } catch (_) {
      // Best-effort, same as the verification harvest.
    }
    if (!mounted) return;
    AnikumoDialog.showToast(
      message: planted > 0
          ? S.f('已保存登录状态（{} 条会话记录）', [planted])
          : S.t('没有读到登录会话，请确认已在页面里完成登录'),
    );
    if (planted > 0) Navigator.of(context).pop();
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(S.t('源站网页登录'))),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Text(
              S.t('在源站页面里完成登录后，点「保存登录状态」把会话同步给内容源。账号密码只输入在源站页面里，应用不保存。'),
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: _webView?.build(context) ??
                const Center(child: CircularProgressIndicator()),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(AnikumoIcons.check_rounded, size: 18),
                  label: Text(_saving ? S.t('正在同步…') : S.t('保存登录状态')),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
