import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:anikumo/modules/danmaku/danmaku_module.dart';

/// Batch 272 (#33): parses a local danmaku file the user
/// mounts onto a playing video. Supported shapes:
///
/// - Bilibili-style XML — the same `<d p="time,mode,
///   color,...">text</d>` format the app itself writes
///   next to downloaded episodes.
/// - JSON — a list of entries with time/text keys
///   ({time, text|message, color?, mode|type?}), or the
///   comment objects the danmaku APIs return ({t, c, m}).
/// - ASS — Dialogue lines become scroll entries at
///   their start time (override tags are stripped).
///
/// Mode mapping follows the shared entry convention:
/// 1 = scroll, 4 = bottom, 5 = top. Colors are decimal
/// RGB ints in the XML/JSON shapes, as the writers emit.
List<DanmakuEntry> parseLocalDanmakuFile(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return const [];
  final entries = <DanmakuEntry>[];
  if (trimmed.startsWith('<')) {
    entries.addAll(_parseXml(trimmed));
  } else if (trimmed.contains('Dialogue:')) {
    // ASS before JSON: an ASS file opens with [Script
    // Info] / [Events] sections, not data.
    entries.addAll(_parseAss(trimmed));
  } else if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
    entries.addAll(_parseJson(trimmed));
  }
  entries.sort((a, b) => a.time.compareTo(b.time));
  return entries;
}

DanmakuEntry _entry({
  required double time,
  required String message,
  required int mode,
  required int colorValue,
}) {
  return DanmakuEntry(
    message: message,
    time: time < 0 ? 0 : time,
    type: mode == 4 || mode == 5 ? mode : 1,
    color: Color(0xFF000000 | (colorValue & 0xFFFFFF)),
    source: 'Local file',
  );
}

final _xmlItemPattern = RegExp(r'<d p="([^"]*)">([^<]*)</d>');

Iterable<DanmakuEntry> _parseXml(String content) sync* {
  for (final match in _xmlItemPattern.allMatches(content)) {
    final parts = match.group(1)!.split(',');
    if (parts.length < 3) continue;
    final time = double.tryParse(parts[0]);
    if (time == null) continue;
    final mode = int.tryParse(parts[1]) ?? 1;
    final color = int.tryParse(parts[2]) ?? 16777215;
    final text = _xmlUnescape(match.group(2)!).trim();
    if (text.isEmpty) continue;
    yield _entry(time: time, message: text, mode: mode, colorValue: color);
  }
}

String _xmlUnescape(String raw) => raw
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

Iterable<DanmakuEntry> _parseJson(String content) sync* {
  dynamic decoded;
  try {
    decoded = jsonDecode(content);
  } catch (_) {
    return;
  }
  final list = decoded is List
      ? decoded
      : (decoded is Map && decoded['comments'] is List
          ? decoded['comments'] as List
          : null);
  if (list == null) return;
  for (final raw in list) {
    if (raw is! Map) continue;
    final time = (raw['time'] as num?)?.toDouble() ??
        (raw['t'] as num?)?.toDouble();
    final text = (raw['text'] ?? raw['message'] ?? raw['m'])?.toString() ?? '';
    if (time == null || text.trim().isEmpty) continue;
    final mode = (raw['mode'] as num?)?.toInt() ??
        (raw['type'] as num?)?.toInt() ??
        1;
    final color = (raw['color'] as num?)?.toInt() ??
        (raw['c'] as num?)?.toInt() ??
        16777215;
    yield _entry(
      time: time,
      message: text.trim(),
      mode: mode,
      colorValue: color,
    );
  }
}

final _assTimePattern = RegExp(r'^(\d+):(\d{2}):(\d{2})\.(\d{2})$');

double? _assTime(String raw) {
  final m = _assTimePattern.firstMatch(raw.trim());
  if (m == null) return null;
  return int.parse(m.group(1)!) * 3600 +
      int.parse(m.group(2)!) * 60 +
      int.parse(m.group(3)!) +
      int.parse(m.group(4)!) / 100;
}

Iterable<DanmakuEntry> _parseAss(String content) sync* {
  for (final line in content.split('\n')) {
    if (!line.startsWith('Dialogue:')) continue;
    // Dialogue: Layer,Start,End,Style,Name,MarginL,
    // MarginR,MarginV,Effect,Text — the text may itself
    // contain commas, so split at most 10 fields.
    final parts = line.substring('Dialogue:'.length).split(',');
    if (parts.length < 10) continue;
    final time = _assTime(parts[1]);
    if (time == null) continue;
    var text = parts.sublist(9).join(',');
    text = text.replaceAll(RegExp(r'\{[^}]*\}'), '').trim();
    if (text.isEmpty) continue;
    // \an8-style top alignment and \pos bottom-ish cues
    // are dropped to plain scroll: the mount is a
    // reading aid, not a typesetting reproduction.
    yield _entry(time: time, message: text, mode: 1, colorValue: 16777215);
  }
}
