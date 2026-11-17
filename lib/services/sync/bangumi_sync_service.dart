import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:flutter/foundation.dart';
import 'package:anikumo/modules/collect/collect_sync_merger.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/modules/bangumi/sync_priority.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/services/anime/anime_features.dart';
import 'package:anikumo/request/core/network_exception.dart';
import 'package:anikumo/utils/async_serial_queue.dart';

class BangumiSyncService extends ChangeNotifier {
  String _username = '';
  String get username => initialized ? _username : '';

  String? _verifiedToken;
  bool get initialized =>
      _verifiedToken != null && _verifiedToken == _configuredToken;

  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;

  String? _lastError;
  String? get lastError => _lastError;

  final _operations = AsyncSerialQueue();

  String get _configuredToken =>
      GStorage.getSetting(SettingsKeys.bangumiAccessToken).trim();

  BangumiSyncService._internal();
  static final BangumiSyncService _instance = BangumiSyncService._internal();
  factory BangumiSyncService() => _instance;

  @visibleForTesting
  void resetForTesting() {
    _verifiedToken = null;
    _username = '';
    _lastError = null;
    notifyListeners();
  }

  Future<void> ping() => _operations.run(_connectConfiguredToken);

  Future<void> setEnabled(bool enabled) {
    return _operations.run(() async {
      if (enabled) {
        await _connectConfiguredToken();
      }
      await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, enabled);
      notifyListeners();
    });
  }

  Future<String> _validateToken(String token) async {
    if (token.isEmpty) {
      throw StateError(S.t('请先连接 Bangumi 账号'));
    }
    final user = await BangumiApi.getCurrentUser(accessToken: token);
    final name = user?.username;
    if (name == null || name.trim().isEmpty) {
      throw FormatException(S.t('Bangumi 用户信息不完整'));
    }
    return name;
  }

  Future<void> _connectConfiguredToken() async {
    _isConnecting = true;
    _lastError = null;
    notifyListeners();
    try {
      final token = _configuredToken;
      final name = await _validateToken(token);
      _verifiedToken = token;
      _username = name;
    } catch (e) {
      _verifiedToken = null;
      _username = '';
      _lastError = describeError(e);
      AnikumoLogger().w('Bangumi: connection failed', error: e);
      rethrow;
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  // Validate draft credentials before exposing them to other requests.
  Future<void> saveToken(String value) {
    return _operations.run(() async {
      final token = value.trim();
      _isConnecting = true;
      notifyListeners();
      try {
        final name = await _validateToken(token);
        await GStorage.putSetting(SettingsKeys.bangumiAccessToken, token);
        _verifiedToken = token;
        _username = name;
        _lastError = null;
      } catch (e) {
        if (token == _configuredToken) {
          _verifiedToken = null;
          _username = '';
          _lastError = describeError(e);
        }
        rethrow;
      } finally {
        _isConnecting = false;
        notifyListeners();
      }
    });
  }

  static String describeError(Object error) {
    if (error is NetworkException) {
      switch (error.statusCode) {
        case 401:
          return S.t('Access Token 无效或已过期，请在「Bangumi 账号」中更换');
        case 403:
          return S.t('Bangumi 拒绝访问，请检查 Token 权限或稍后重试');
        case 429:
          return S.t('Bangumi 请求过于频繁，请稍后重试');
      }
      if (error.statusCode != null) {
        return S.f('Bangumi 服务请求失败（HTTP {}），请稍后重试', [error.statusCode]);
      }
      return error.message;
    }
    if (error is FormatException || error is TypeError) {
      return S.t('Bangumi 返回的用户信息格式异常，请稍后重试');
    }
    if (error is StateError) return error.message.toString();
    return S.t('Bangumi 操作失败，请稍后重试');
  }

  /// Batch 233 （单集进度同步 pack): report [episodeNumber]
  /// of [bangumiId] as watched on Bangumi. Gated by the
  /// pack, the sync switch and the persisted already-sent
  /// set; resolves Bangumi's episode id from its episode
  /// list. Returns true only when a report was sent (or
  /// had already been sent earlier).
  Future<bool> syncEpisodeProgress(int bangumiId, int episodeNumber) {
    return _operations.run(() async {
      if (!AnimeFeatures.isInstalled(AnimeFeatures.bgmProgressId)) {
        return false;
      }
      if (!GStorage.getSetting(SettingsKeys.bangumiSyncEnable)) {
        return false;
      }
      if (_configuredToken.isEmpty) return false;
      if (AnimeBgmSyncedStore.contains(bangumiId, episodeNumber)) {
        return true;
      }
      if (!initialized) await _connectConfiguredToken();
      final episodes = await BangumiApi.getBangumiEpisodesByID(bangumiId);
      int? episodeId;
      for (final e in episodes) {
        if (e.type == 0 && e.episode == episodeNumber) {
          episodeId = e.id;
          break;
        }
      }
      if (episodeId == null) return false;
      final ok = await BangumiApi.markBangumiEpisodeWatched(
        bangumiId,
        episodeId,
      );
      if (ok) await AnimeBgmSyncedStore.add(bangumiId, episodeNumber);
      return ok;
    });
  }

  Future<bool> syncCollectibleWhenIdle(int bangumiId, int localType) {
    return _operations.run(() async {
      if (!initialized) await _connectConfiguredToken();
      return BangumiApi.updateBangumiByType(
        bangumiId,
        localType,
      );
    });
  }

  Future<void> _applyLocalMutation(BangumiLocalMutation mutation) async {
    await GStorage.putCollectible(mutation.collectible);
    // Remote changes must also reach WebDAV's incremental change log.
    await GStorage.appendCollectChange(
      bangumiId: mutation.collectible.bangumiItem.id,
      action: mutation.changeAction,
      type: mutation.collectible.type,
    );
  }

  Future<void> syncCollectibles({
    void Function(String message, int current, int total)? onProgress,
  }) {
    return _operations.run(() async {
      try {
        if (!GStorage.getSetting(SettingsKeys.bangumiSyncEnable)) {
          throw StateError(S.t('请先开启 Bangumi 同步'));
        }
        await _connectConfiguredToken();
        onProgress?.call(S.t('开始同步 Bangumi 状态'), 0, 0);

        final priority = BangumiSyncPriority.fromValue(
          GStorage.getSetting(SettingsKeys.bangumiSyncPriority),
        );

        final remoteCollection = await BangumiApi.getBangumiCollectibles(
          username: username,
          limit: 50,
          onProgress: onProgress,
        );

        final mergePlan = CollectSyncMerger.planBangumi(
          localCollectibles: GStorage.collectibles.values.toList(),
          remoteCollections: remoteCollection,
          priority: priority,
        );
        final totalOperations = mergePlan.totalOperations;

        if (totalOperations == 0) {
          onProgress?.call(S.t('未发现状态差异，无需同步'), 1, 1);
          return;
        }

        int syncedCount = 0;
        if (mergePlan.localOnlyUploads.isNotEmpty) {
          onProgress?.call(S.t('正在上传本地新增状态'), syncedCount, totalOperations);
          for (final upload in mergePlan.localOnlyUploads) {
            final updated = await BangumiApi.updateBangumiByType(
              upload.bangumiId,
              upload.type,
            );
            if (!updated) {
              onProgress?.call(S.t('上传本地新增状态失败'), syncedCount, totalOperations);
              throw Exception(S.f('同步失败：条目 {} 上传到 Bangumi 失败', [upload.bangumiId]));
            }
            syncedCount++;
            onProgress?.call(S.t('正在上传本地新增状态'), syncedCount, totalOperations);
          }
        }

        if (mergePlan.remoteOnlyPuts.isNotEmpty) {
          onProgress?.call(S.t('正在补全本地缺失状态'), syncedCount, totalOperations);
          for (final mutation in mergePlan.remoteOnlyPuts) {
            await _applyLocalMutation(mutation);
            syncedCount++;
            onProgress?.call(S.t('正在补全本地缺失状态'), syncedCount, totalOperations);
          }
        }

        if (mergePlan.conflictUploads.isNotEmpty) {
          onProgress?.call(
              S.f('{}：正在上传冲突状态', [S.t(priority.label)]), syncedCount, totalOperations);
          for (final upload in mergePlan.conflictUploads) {
            final updated = await BangumiApi.updateBangumiByType(
              upload.bangumiId,
              upload.type,
            );
            if (!updated) {
              throw Exception(S.f('同步失败：条目 {} 上传到 Bangumi 失败', [upload.bangumiId]));
            }
            syncedCount++;
            onProgress?.call(
                S.f('{}：正在上传冲突状态', [S.t(priority.label)]), syncedCount, totalOperations);
          }
        }
        if (mergePlan.conflictLocalUpdates.isNotEmpty) {
          onProgress?.call(
              S.f('{}：正在更新本地冲突状态', [S.t(priority.label)]), syncedCount, totalOperations);
          for (final mutation in mergePlan.conflictLocalUpdates) {
            await _applyLocalMutation(mutation);
            syncedCount++;
            onProgress?.call(
                S.f('{}：正在更新本地冲突状态', [S.t(priority.label)]), syncedCount, totalOperations);
          }
        }
        onProgress?.call(S.t('Bangumi 状态同步完成'), 1, 1);
      } catch (e) {
        AnikumoLogger().e('Bangumi sync failed', error: e);
        rethrow;
      }
    });
  }
}
