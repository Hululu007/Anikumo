import 'dart:convert';

import 'package:anikumo/services/storage/settings_keys.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 273 (#52): the audio equalizer, expressed as
/// an mpv audio-filter chain. Five bands over the
/// classic `equalizer` filter; the chain always keeps
/// the player's baseline `scaletempo2` filter in front
/// (the playback controller sets it at creation for
/// high-rate playback), so enabling the EQ never costs
/// that behavior.
///
/// Gains are decibels in [-12, 12]. Everything here is
/// pure string building + a settings record, so the
/// exact filter text is unit-testable.
class AudioEqSettings {
  final bool enabled;
  final List<double> gains; // 5 bands

  const AudioEqSettings({required this.enabled, required this.gains});

  static const List<int> bandFrequencies = [60, 230, 910, 3600, 14000];

  static const AudioEqSettings flat = AudioEqSettings(
    enabled: false,
    gains: [0, 0, 0, 0, 0],
  );

  AudioEqSettings copyWith({bool? enabled, List<double>? gains}) =>
      AudioEqSettings(
        enabled: enabled ?? this.enabled,
        gains: gains ?? this.gains,
      );

  Map<String, dynamic> toJson() => {'on': enabled, 'g': gains};

  static AudioEqSettings fromJson(Map<String, dynamic> json) {
    final raw = json['g'];
    final gains = <double>[
      for (var i = 0; i < bandFrequencies.length; i++)
        if (raw is List && i < raw.length && raw[i] is num)
          (raw[i] as num).toDouble().clamp(-12, 12)
        else
          0,
    ];
    return AudioEqSettings(enabled: json['on'] == true, gains: gains);
  }

  static AudioEqSettings load() {
    try {
      final raw = GStorage.getSetting(SettingsKeys.audioEqJson);
      if (raw.isEmpty) return flat;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return fromJson(decoded.cast<String, dynamic>());
      }
    } catch (_) {}
    return flat;
  }

  static Future<void> save(AudioEqSettings settings) {
    return GStorage.putSetting(
      SettingsKeys.audioEqJson,
      jsonEncode(settings.toJson()),
    );
  }
}

/// The full `af` property value: baseline tempo filter
/// plus, when enabled, one equalizer stage per band
/// with a non-zero gain.
String buildMpvAudioFilterChain(AudioEqSettings settings) {
  final parts = <String>['scaletempo2=max-speed=8'];
  if (settings.enabled) {
    for (var i = 0; i < AudioEqSettings.bandFrequencies.length; i++) {
      final gain = i < settings.gains.length ? settings.gains[i] : 0.0;
      if (gain == 0) continue;
      parts.add(
        'equalizer=f=${AudioEqSettings.bandFrequencies[i]}'
        ':width_type=o:width=2:g=${gain.toStringAsFixed(1)}',
      );
    }
  }
  return parts.join(',');
}
