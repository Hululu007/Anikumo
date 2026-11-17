import 'package:flutter/material.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/bean/settings/settings_detail_scaffold.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/sync/webdav.dart';
import 'package:anikumo/services/sync/zone_sync.dart';

String _stamp(DateTime time) {
  String pad(int v) => v.toString().padLeft(2, '0');
  return '${time.year}-${pad(time.month)}-${pad(time.day)} '
      '${pad(time.hour)}:${pad(time.minute)}';
}

/// Batch 274 (#39): parked zone-sync conflicts. A
/// conflict means this device and the server copy both
/// changed since the last agreed sync — nothing was
/// overwritten. The user picks per zone: apply the
/// server copy, or keep the local data (the next sync
/// then uploads it).
class SyncConflictsPage extends StatefulWidget {
  const SyncConflictsPage({super.key});

  @override
  State<SyncConflictsPage> createState() => _SyncConflictsPageState();
}

class _SyncConflictsPageState extends State<SyncConflictsPage> {
  late List<SyncConflict> _conflicts = SyncConflicts.load();
  bool _busy = false;

  Future<void> _applyRemote(SyncConflict conflict) async {
    setState(() => _busy = true);
    try {
      await WebDav().resolveZoneConflictWithRemote(conflict.zone);
      if (mounted) {
        AnikumoDialog.showToast(
          context: context,
          message: S.t('已采用服务器数据'),
        );
      }
    } catch (e) {
      AnikumoLogger().w('SyncConflicts: apply remote failed', error: e);
      if (mounted) {
        AnikumoDialog.showToast(
          context: context,
          message: S.t('处理失败，请稍后重试'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _conflicts = SyncConflicts.load();
        });
      }
    }
  }

  Future<void> _keepLocal(SyncConflict conflict) async {
    setState(() => _busy = true);
    await SyncConflicts.drop(conflict.zone);
    // Re-base on the REMOTE hash: the local payload
    // then counts as "changed since the agreement" and
    // the remote as unchanged, so the next sync
    // uploads the local data instead of conflicting
    // (or worse, downloading over it).
    await ZoneSyncService.markSynced(
      conflict.zone,
      ZoneSyncService.hashOfPayload(conflict.remotePayload),
    );
    if (mounted) {
      setState(() {
        _busy = false;
        _conflicts = SyncConflicts.load();
      });
      AnikumoDialog.showToast(
        context: context,
        message: S.t('已保留本机数据，下次同步将上传'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: Text(S.t('同步冲突')),
      body: _conflicts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  S.t('没有待处理的同步冲突'),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  S.t('以下分区在本机和服务器上都有新改动，尚未自动合并：'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                for (final conflict in _conflicts)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            S.t(ZoneSyncService.zoneLabel(conflict.zone)),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            S.f('服务器数据更新于 {}', [
                              _stamp(
                                DateTime.fromMillisecondsSinceEpoch(
                                  conflict.remoteUpdatedAtMs,
                                ),
                              ),
                            ]),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              FilledButton(
                                onPressed: _busy
                                    ? null
                                    : () => _applyRemote(conflict),
                                child: Text(S.t('采用服务器数据')),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed:
                                    _busy ? null : () => _keepLocal(conflict),
                                child: Text(S.t('保留本机数据')),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
