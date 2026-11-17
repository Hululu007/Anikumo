import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/pages/player/player_controller.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/player/audio_eq.dart';
import 'package:anikumo/services/player/video_bookmarks.dart';
import 'package:anikumo/utils/format.dart';

/// Batch 273 (#8, #51): the subtitle sheet — primary
/// and secondary (dual) subtitle selection over the
/// player's embedded tracks plus external files.
///
/// The primary track goes through media_kit's
/// setSubtitleTrack (which also handles URI tracks via
/// sub-add). The secondary rides mpv's `secondary-sid`
/// property, which is how mpv renders two subtitle
/// streams at once.
Future<void> showSubtitleSheet(
  BuildContext context, {
  required PlayerController playerController,
}) async {
  final player = playerController.playback.mediaPlayer;
  if (player == null) {
    AnikumoDialog.showToast(message: S.t('暂未获取到播放器，请等视频显示后重试'));
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _SubtitleSheet(player: player),
  );
}

class _SubtitleSheet extends StatefulWidget {
  const _SubtitleSheet({required this.player});

  final Player player;

  @override
  State<_SubtitleSheet> createState() => _SubtitleSheetState();
}

class _SubtitleSheetState extends State<_SubtitleSheet> {
  String? _secondaryId;
  bool _busy = false;

  Player get _player => widget.player;

  String _trackLabel(SubtitleTrack track) {
    final title = track.title?.trim() ?? '';
    final language = track.language?.trim() ?? '';
    if (title.isNotEmpty && language.isNotEmpty && title != language) {
      return '$title ($language)';
    }
    if (title.isNotEmpty) return title;
    if (language.isNotEmpty) return language;
    return S.f('字幕轨 {}', [track.id]);
  }

  Future<void> _setPrimary(SubtitleTrack track) async {
    setState(() => _busy = true);
    try {
      await _player.setSubtitleTrack(track);
    } catch (e) {
      AnikumoLogger().w('Subtitle: set primary failed', error: e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _setSecondary(String? mpvId) async {
    setState(() => _busy = true);
    try {
      final platform = _player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty('secondary-sid', mpvId ?? 'no');
      }
      _secondaryId = mpvId;
    } catch (e) {
      AnikumoLogger().w('Subtitle: set secondary failed', error: e);
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Picks an external subtitle file and stages it in
  /// the temp dir (mpv needs a real path it can read
  /// for the whole session).
  Future<String?> _pickExternalSubtitle() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'ass', 'ssa', 'vtt', 'sub'],
      withData: true,
    );
    final file = picked?.files.singleOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return null;
    final dir = await getTemporaryDirectory();
    final target = File(
      p.join(
        dir.path,
        'anikumo_sub_${DateTime.now().millisecondsSinceEpoch}'
        '_${file.name}',
      ),
    );
    await target.writeAsBytes(bytes);
    return target.path;
  }

  Future<void> _externalPrimary() async {
    final path = await _pickExternalSubtitle();
    if (path == null) return;
    await _setPrimary(SubtitleTrack.uri(path));
    if (mounted) {
      AnikumoDialog.showToast(message: S.t('已加载外挂字幕'));
    }
  }

  Future<void> _externalSecondary() async {
    final path = await _pickExternalSubtitle();
    if (path == null) return;
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    setState(() => _busy = true);
    try {
      // 'auto' loads the file without selecting it;
      // the new track then shows up in the track list
      // titled by file name.
      await platform.command(['sub-add', path, 'auto']);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final base = p.basename(path);
      SubtitleTrack? added;
      for (final track in _player.state.tracks.subtitle) {
        if (track.title == base) added = track;
      }
      if (added != null) {
        await platform.setProperty('secondary-sid', added.id);
        _secondaryId = added.id;
      } else {
        AnikumoDialog.showToast(message: S.t('外挂字幕加载失败'));
      }
    } catch (e) {
      AnikumoLogger().w('Subtitle: external secondary failed', error: e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _player.state.tracks.subtitle;
    final current = _player.state.track.subtitle;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              S.t('字幕'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              S.t('主字幕'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          RadioGroup<String>(
            groupValue: current.id,
            onChanged: (_) {},
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Radio<String>(value: 'no'),
                  title: Text(S.t('关闭')),
                  onTap: _busy
                      ? null
                      : () => _setPrimary(SubtitleTrack.no()),
                ),
                for (final track in tracks)
                  ListTile(
                    leading: Radio<String>(value: track.id),
                    title: Text(_trackLabel(track)),
                    onTap: _busy ? null : () => _setPrimary(track),
                  ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: Text(S.t('外挂字幕文件…')),
            onTap: _busy ? null : _externalPrimary,
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              S.t('副字幕（双字幕同显）'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          RadioGroup<String?>(
            groupValue: _secondaryId,
            onChanged: (_) {},
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Radio<String?>(value: null),
                  title: Text(S.t('关闭')),
                  onTap: _busy ? null : () => _setSecondary(null),
                ),
                for (final track in tracks)
                  ListTile(
                    leading: Radio<String?>(value: track.id),
                    title: Text(_trackLabel(track)),
                    onTap: _busy ? null : () => _setSecondary(track.id),
                  ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: Text(S.t('外挂字幕文件…')),
            onTap: _busy ? null : _externalSecondary,
          ),
        ],
      ),
    );
  }
}

/// Batch 273 (#52): the equalizer sheet — five gain
/// sliders applied live through the mpv `af` chain and
/// persisted for future players.
Future<void> showAudioEqSheet(
  BuildContext context, {
  required PlayerController playerController,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _AudioEqSheet(playerController: playerController),
  );
}

class _AudioEqSheet extends StatefulWidget {
  const _AudioEqSheet({required this.playerController});

  final PlayerController playerController;

  @override
  State<_AudioEqSheet> createState() => _AudioEqSheetState();
}

class _AudioEqSheetState extends State<_AudioEqSheet> {
  late AudioEqSettings _settings = AudioEqSettings.load();

  Future<void> _apply(AudioEqSettings next) async {
    setState(() => _settings = next);
    await AudioEqSettings.save(next);
    final player = widget.playerController.playback.mediaPlayer;
    final platform = player?.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty('af', buildMpvAudioFilterChain(next));
      } catch (e) {
        AnikumoLogger().w('AudioEq: apply failed', error: e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  S.t('音频均衡器'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Switch(
                  value: _settings.enabled,
                  onChanged: (value) =>
                      _apply(_settings.copyWith(enabled: value)),
                ),
              ],
            ),
            for (var i = 0; i < AudioEqSettings.bandFrequencies.length; i++)
              Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      AudioEqSettings.bandFrequencies[i] >= 1000
                          ? '${AudioEqSettings.bandFrequencies[i] ~/ 1000}k Hz'
                          : '${AudioEqSettings.bandFrequencies[i]} Hz',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: _settings.gains[i],
                      min: -12,
                      max: 12,
                      divisions: 24,
                      label:
                          '${_settings.gains[i].toStringAsFixed(0)} dB',
                      onChanged: _settings.enabled
                          ? (value) {
                              final gains = [..._settings.gains];
                              gains[i] = value;
                              _apply(_settings.copyWith(gains: gains));
                            }
                          : null,
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${_settings.gains[i].toStringAsFixed(1)} dB',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _apply(
                  AudioEqSettings(
                    enabled: _settings.enabled,
                    gains: const [0, 0, 0, 0, 0],
                  ),
                ),
                child: Text(S.t('重置')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Batch 273 (#12): the timestamp-bookmark sheet for
/// the current episode — add at the playhead, tap to
/// seek, swipe the row's delete button to remove.
Future<void> showVideoBookmarksSheet(
  BuildContext context, {
  required PlayerController playerController,
  required String episodeKey,
  required String episodeLabel,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _VideoBookmarksSheet(
      playerController: playerController,
      episodeKey: episodeKey,
      episodeLabel: episodeLabel,
    ),
  );
}

class _VideoBookmarksSheet extends StatefulWidget {
  const _VideoBookmarksSheet({
    required this.playerController,
    required this.episodeKey,
    required this.episodeLabel,
  });

  final PlayerController playerController;
  final String episodeKey;
  final String episodeLabel;

  @override
  State<_VideoBookmarksSheet> createState() => _VideoBookmarksSheetState();
}

class _VideoBookmarksSheetState extends State<_VideoBookmarksSheet> {
  late List<VideoBookmark> _bookmarks =
      VideoBookmarks.forEpisode(widget.episodeKey);
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final position = widget.playerController.playback.currentPosition;
    final next = await VideoBookmarks.add(
      widget.episodeKey,
      VideoBookmark(
        seconds: position.inSeconds,
        note: _noteController.text.trim(),
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _noteController.clear();
    if (mounted) setState(() => _bookmarks = next);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.f('时间点书签 · {}', [widget.episodeLabel]),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _noteController,
                    decoration: InputDecoration(
                      hintText: S.t('给当前位置加个备注（可空）'),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _add,
                  child: Text(S.t('添加书签')),
                ),
              ],
            ),
            if (_bookmarks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  S.t('这一集还没有书签'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final bookmark in _bookmarks)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.bookmark_outline),
                        title: Text(
                          durationToString(
                            Duration(seconds: bookmark.seconds),
                          ),
                        ),
                        subtitle: bookmark.note.isEmpty
                            ? null
                            : Text(bookmark.note),
                        trailing: IconButton(
                          tooltip: S.t('删除'),
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final next = await VideoBookmarks.remove(
                              widget.episodeKey,
                              bookmark.seconds,
                            );
                            if (mounted) {
                              setState(() => _bookmarks = next);
                            }
                          },
                        ),
                        onTap: () {
                          widget.playerController
                              .seek(Duration(seconds: bookmark.seconds));
                          Navigator.of(context).pop();
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
