import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:anikumo/bean/settings/settings_detail_scaffold.dart';
import 'package:anikumo/bean/widget/state_presentation.dart';
import 'package:anikumo/bean/widget/tonal_card.dart';
import 'package:anikumo/pages/settings/sync/sync_settings_widgets.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/services/sync/webdav.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

class WebDavServerPage extends StatefulWidget {
  const WebDavServerPage({super.key});

  @override
  State<WebDavServerPage> createState() => _WebDavServerPageState();
}

class _WebDavServerPageState extends State<WebDavServerPage> {
  final _formKey = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _passwordVisible = false;
  bool _busy = false;
  bool _failed = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _url.text = GStorage.getSetting(SettingsKeys.webDavURL);
    _username.text = GStorage.getSetting(SettingsKeys.webDavUsername);
    _password.text = GStorage.getSetting(SettingsKeys.webDavPassword);
  }

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _failed = false;
      _message = S.t('正在测试连接…');
    });
    try {
      await GStorage.putSetting(SettingsKeys.webDavURL, _url.text.trim());
      await GStorage.putSetting(
          SettingsKeys.webDavUsername, _username.text.trim());
      await GStorage.putSetting(SettingsKeys.webDavPassword, _password.text);
      await WebDav().init();
      _message = S.t('连接成功，配置已保存');
    } catch (e) {
      AnikumoLogger().w('WebDAV configuration failed', error: e);
      await WebDav().setEnabled(false);
      _failed = true;
      _message = S.t('连接失败，同步已关闭。请检查服务器地址、账号和密码后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: SettingsDetailScaffold(
          title: Text(S.t('同步服务器')),
          body: SyncPageBody(
            maxWidth: 640,
            children: [
              SyncPageIntro(
                icon: AnikumoIcons.dns_rounded,
                title: S.t('连接 WebDAV'),
                description: S.t('填写云盘或服务器提供的连接信息。'),
              ),
              TonalCard(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  onChanged: () {
                    if (_message != null && !_busy) {
                      setState(() => _message = null);
                    }
                  },
                  child: Column(
                    spacing: 20,
                    children: [
                      TextFormField(
                        controller: _url,
                        enabled: !_busy,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: S.t('服务器地址'),
                          hintText: 'https://example.com/dav/',
                          border: const OutlineInputBorder(),
                          errorMaxLines: 3,
                        ),
                        validator: (value) {
                          final uri = Uri.tryParse(value?.trim() ?? '');
                          if (uri == null ||
                              !['http', 'https'].contains(uri.scheme) ||
                              uri.host.isEmpty) {
                            return S.t('请输入完整的 http:// 或 https:// 地址');
                          }
                          return null;
                        },
                      ),
                      TextFormField(
                        controller: _username,
                        enabled: !_busy,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: S.t('用户名'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      TextFormField(
                        controller: _password,
                        enabled: !_busy,
                        obscureText: !_passwordVisible,
                        autocorrect: false,
                        enableSuggestions: false,
                        onFieldSubmitted: (_) => _save(),
                        decoration: InputDecoration(
                          labelText: S.t('密码或应用授权码'),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _passwordVisible ? S.t('隐藏密码') : S.t('显示密码'),
                            onPressed: () => setState(
                                () => _passwordVisible = !_passwordVisible),
                            icon: Icon(_passwordVisible
                                ? AnikumoIcons.visibility_off_rounded
                                : AnikumoIcons.visibility_rounded),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              StateActionButton(
                onPressed: _busy ? null : _save,
                text: _busy ? S.t('正在测试连接…') : S.t('保存并测试'),
                icon: AnikumoIcons.cloud_done_rounded,
              ),
              if (_message != null)
                SyncFeedback(message: _message!, error: _failed, busy: _busy),
              if (_message != null && !_busy && !_failed)
                TextButton(
                  onPressed: () => context.maybePop(),
                  child: Text(S.t('返回同步设置')),
                ),
            ],
          ),
        ),
      );
}
