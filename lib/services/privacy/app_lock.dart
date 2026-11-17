import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/storage/settings_keys.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 275 (#46/#47): privacy gates.
///
/// #46 app lock — when enabled, the app asks for the
/// device's biometric / PIN at cold start and again
/// after five minutes in the background. Authentication
/// is delegated entirely to the OS (local_auth); the
/// app never sees or stores a credential.
///
/// #47 guest mode — a display-only mode that hides the
/// personal surfaces (history, favorites overview,
/// continue rails) when the phone is handed to someone
/// else. Data is never touched, only hidden.
abstract final class PrivacyGate {
  static bool get appLockEnabled {
    try {
      return GStorage.getSetting(SettingsKeys.appLockEnabled);
    } catch (_) {
      return false;
    }
  }

  static bool get guestMode {
    try {
      return GStorage.getSetting(SettingsKeys.guestMode);
    } catch (_) {
      return false;
    }
  }

  static final LocalAuthentication _auth = LocalAuthentication();

  /// True when this device can authenticate at all
  /// (biometrics enrolled or a device PIN set).
  static Future<bool> canAuthenticate() async {
    try {
      return await _auth.canCheckBiometrics ||
          await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: S.t('验证身份后继续使用'),
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      AnikumoLogger().w('AppLock: authenticate failed', error: e);
      return false;
    }
  }
}

/// The lock screen shown by the app-lock gate. One
/// button: retry authentication.
class AppLockScreen extends StatelessWidget {
  const AppLockScreen({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                S.t('应用已锁定'),
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                S.t('验证指纹、面容或设备密码后继续'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onRetry,
                child: Text(S.t('验证身份')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Batch 275 (#46): the standalone biometric gate, used
/// when the biometric lock is on but no PIN is set (with
/// a PIN, the PIN gate itself offers the biometric
/// shortcut). Locks at cold start and again after five
/// minutes in the background.
class BiometricLockGate extends StatefulWidget {
  const BiometricLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<BiometricLockGate> createState() => _BiometricLockGateState();
}

class _BiometricLockGateState extends State<BiometricLockGate>
    with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _prompting = false;
  DateTime? _backgroundedAt;

  bool get _active =>
      PrivacyGate.appLockEnabled &&
      GStorage.getSetting(SettingsKeys.pinLockHash).isEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_active) _prompt();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed && _active) {
      final away = _backgroundedAt == null
          ? Duration.zero
          : DateTime.now().difference(_backgroundedAt!);
      if (_unlocked && away >= const Duration(minutes: 5)) {
        setState(() => _unlocked = false);
        _prompt();
      }
    }
  }

  Future<void> _prompt() async {
    if (_prompting || _unlocked) return;
    _prompting = true;
    final ok = await PrivacyGate.authenticate();
    _prompting = false;
    if (ok && mounted) setState(() => _unlocked = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_active || _unlocked) return widget.child;
    return AppLockScreen(onRetry: _prompt);
  }
}
