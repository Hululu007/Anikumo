import 'package:anikumo/services/i18n/app_strings.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/services/logging/logger.dart';

class TimedShutdownService {
  static final TimedShutdownService _instance =
      TimedShutdownService._internal();
  factory TimedShutdownService() => _instance;
  TimedShutdownService._internal();

  Timer? _shutdownTimer;
  int _remainingSeconds = 0;
  AnikumoDialogHandle<void>? _expiryDialog;
  int _lastSetMinutes = 0;
  VoidCallback? _onExpiredCallback;

  final ValueNotifier<int> remainingSecondsNotifier = ValueNotifier<int>(0);

  /// Bumped every time the timer actually expires, so the mounted player panel
  /// can drop its resume ownership without the service holding a stale widget.
  final ValueNotifier<int> expiryTicks = ValueNotifier<int>(0);
  final ValueNotifier<int> setMinutesNotifier = ValueNotifier<int>(0);

  bool get isActive => _shutdownTimer != null && _shutdownTimer!.isActive;
  int get setMinutes => setMinutesNotifier.value;

  void start(int minutes, {VoidCallback? onExpired}) {
    cancel();
    if (minutes <= 0) return;

    _lastSetMinutes = minutes;
    _remainingSeconds = minutes * 60;
    remainingSecondsNotifier.value = _remainingSeconds;
    setMinutesNotifier.value = minutes;
    _onExpiredCallback = onExpired;
    _shutdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        _remainingSeconds--;
        remainingSecondsNotifier.value = _remainingSeconds;
      }

      if (_remainingSeconds <= 0) {
        timer.cancel();
        _shutdownTimer = null;
        _onTimerExpired();
      }
    });
  }

  void cancel() {
    _shutdownTimer?.cancel();
    _shutdownTimer = null;
    _remainingSeconds = 0;
    _onExpiredCallback = null;
    if (remainingSecondsNotifier.value != 0) {
      remainingSecondsNotifier.value = 0;
    }
    if (setMinutesNotifier.value != 0) {
      setMinutesNotifier.value = 0;
    }
    _expiryDialog?.dismiss();
    _expiryDialog = null;
  }

  void _onTimerExpired() {
    setMinutesNotifier.value = 0;
    expiryTicks.value++;
    try {
      _onExpiredCallback?.call();
    } catch (e) {
      AnikumoLogger()
          .e('TimedShutdownService: onExpired callback failed', error: e);
    }

    _showTimerExpiredDialog();
  }

  void _showTimerExpiredDialog() {
    if (_expiryDialog?.isActive ?? false) return;
    final dialog = _expiryDialog = AnikumoDialogHandle<void>();

    AnikumoDialog.show<void>(
      handle: dialog,
      clickMaskDismiss: false,
      onDismiss: () {
        if (identical(_expiryDialog, dialog)) _expiryDialog = null;
      },
      builder: (context) {
        return AlertDialog(
          title: Text(S.t('定时关闭')),
          content: Text(S.t('定时时间已到，视频已暂停')),
          actions: [
            TextButton(
              onPressed: () {
                start(_lastSetMinutes, onExpired: _onExpiredCallback);
                AnikumoDialog.showToast(message: S.f('已重新开始 {} 分钟定时', [_lastSetMinutes]));
              },
              child: Text(S.t('重复')),
            ),
            TextButton(
              onPressed: () {
                dialog.dismiss();
              },
              child: Text(
                S.t('关闭'),
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
          ],
        );
      },
    );
  }

  String formatRemainingTime() {
    int totalSeconds = remainingSecondsNotifier.value;
    if (totalSeconds <= 0) return '00:00';
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String formatMinutesToDisplay(int totalMinutes) {
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours > 0 && minutes > 0) {
      return S.f('{} 小时 {} 分钟', [hours, minutes]);
    } else if (hours > 0) {
      return S.f('{} 小时', [hours]);
    } else {
      return S.f('{} 分钟', [minutes]);
    }
  }

  static void showCustomTimerDialog({
    VoidCallback? onExpired,
  }) {
    AnikumoDialog.show(
      builder: (context) => _CustomTimerDialog(
        onExpired: onExpired,
      ),
    );
  }
}

class _CustomTimerDialog extends StatefulWidget {
  const _CustomTimerDialog({
    required this.onExpired,
  });

  final VoidCallback? onExpired;

  @override
  State<_CustomTimerDialog> createState() => _CustomTimerDialogState();
}

class _CustomTimerDialogState extends State<_CustomTimerDialog> {
  late final FixedExtentScrollController _hoursController;
  late final FixedExtentScrollController _minutesController;
  int _selectedHours = 0;
  int _selectedMinutes = 0;

  @override
  void initState() {
    super.initState();
    _hoursController = FixedExtentScrollController(initialItem: _selectedHours);
    _minutesController =
        FixedExtentScrollController(initialItem: _selectedMinutes);
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  void _confirm() {
    final totalMinutes = _selectedHours * 60 + _selectedMinutes;
    if (totalMinutes <= 0) {
      AnikumoDialog.showToast(message: S.t('请选择有效的时间'));
      return;
    }
    AnikumoDialog.dismiss(context: context);
    TimedShutdownService().start(totalMinutes, onExpired: widget.onExpired);
    AnikumoDialog.showToast(
      message:
          S.f('已设置 {} 后定时关闭', [TimedShutdownService().formatMinutesToDisplay(totalMinutes)]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.t('自定义定时')),
      content: SizedBox(
        height: 200,
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Text(S.t('时'), style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: _hoursController,
                      itemExtent: 40,
                      onSelectedItemChanged: (index) {
                        setState(() => _selectedHours = index);
                      },
                      children: List.generate(
                        25,
                        (index) => Center(
                          child: Text(
                            index.toString().padLeft(2, '0'),
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Text(
              ':',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(S.t('分'), style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: _minutesController,
                      itemExtent: 40,
                      onSelectedItemChanged: (index) {
                        setState(() => _selectedMinutes = index);
                      },
                      children: List.generate(
                        60,
                        (index) => Center(
                          child: Text(
                            index.toString().padLeft(2, '0'),
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => AnikumoDialog.dismiss(context: context),
          child: Text(
            S.t('取消'),
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        TextButton(
          onPressed: _confirm,
          child: Text(S.t('确定')),
        ),
      ],
    );
  }
}
