/// M3U8 parsing used by the download engine: media-playlist
/// segments (with their EXT-X-KEY state), master-playlist
/// variants, live detection. Anything the engine cannot
/// handle faithfully is surfaced on the result so the
/// caller can fail loudly instead of producing garbage.
class M3u8Segment {
  final String uri;

  /// Resolved EXT-X-KEY URI in force for this segment,
  /// when the playlist encrypts it with AES-128.
  final String? keyUri;

  /// Explicit IV from the EXT-X-KEY tag, when present.
  /// Null means the IV is the segment's media sequence.
  final List<int>? keyIv;

  /// Media sequence number of this segment.
  final int sequence;

  const M3u8Segment({
    required this.uri,
    this.keyUri,
    this.keyIv,
    required this.sequence,
  });
}

class M3u8Variant {
  final int bandwidth;
  final String uri;
  const M3u8Variant({required this.bandwidth, required this.uri});
}

class M3u8Playlist {
  final List<M3u8Segment> segments;
  final List<M3u8Variant> variants;
  final bool isMaster;
  final bool hasEndList;
  final String? keyMethod;

  const M3u8Playlist({
    required this.segments,
    required this.variants,
    required this.isMaster,
    required this.hasEndList,
    this.keyMethod,
  });

  List<String> get segmentUris => [for (final s in segments) s.uri];
  bool get isLive => !hasEndList;
  bool get isEncrypted => keyMethod != null && keyMethod != 'NONE';

  /// The variant a download should use: highest bandwidth.
  M3u8Variant? get bestVariant {
    if (variants.isEmpty) return null;
    var best = variants.first;
    for (final v in variants) {
      if (v.bandwidth > best.bandwidth) best = v;
    }
    return best;
  }
}

List<int>? _parseIv(String raw) {
  var hex = raw.trim();
  if (hex.startsWith('0x') || hex.startsWith('0X')) hex = hex.substring(2);
  if (hex.isEmpty || hex.length > 32) return null;
  hex = hex.padLeft(32, '0');
  final out = <int>[];
  for (var i = 0; i < 32; i += 2) {
    final byte = int.tryParse(hex.substring(i, i + 2), radix: 16);
    if (byte == null) return null;
    out.add(byte);
  }
  return out;
}

String? _attr(String line, String name) {
  final m = RegExp('$name=("(?:[^"]*)"|[^,]+)').firstMatch(line);
  if (m == null) return null;
  var value = m.group(1)!;
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    value = value.substring(1, value.length - 1);
  }
  return value;
}

M3u8Playlist parseM3u8(String text, {Uri? base}) {
  String resolve(String uri) =>
      base == null ? uri : base.resolve(uri).toString();
  final lines = text.split('\n').map((l) => l.trim()).toList();
  var isMaster = false;
  var hasEndList = false;
  String? keyMethod;
  String? currentKeyUri;
  List<int>? currentKeyIv;
  var mediaSequence = 0;
  final segments = <M3u8Segment>[];
  final variants = <M3u8Variant>[];
  var expectSegment = false;
  int? pendingBandwidth;
  for (final line in lines) {
    if (line.isEmpty) continue;
    if (line.startsWith('#EXT-X-STREAM-INF')) {
      isMaster = true;
      pendingBandwidth =
          int.tryParse(_attr(line, 'BANDWIDTH') ?? '') ?? 0;
      continue;
    }
    if (line.startsWith('#EXT-X-ENDLIST')) {
      hasEndList = true;
      continue;
    }
    if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
      mediaSequence =
          int.tryParse(line.substring('#EXT-X-MEDIA-SEQUENCE:'.length)) ?? 0;
      continue;
    }
    if (line.startsWith('#EXT-X-KEY:')) {
      keyMethod = _attr(line, 'METHOD');
      if (keyMethod == 'NONE') {
        currentKeyUri = null;
        currentKeyIv = null;
      } else {
        final uri = _attr(line, 'URI');
        currentKeyUri = uri == null ? null : resolve(uri);
        final iv = _attr(line, 'IV');
        currentKeyIv = iv == null ? null : _parseIv(iv);
      }
      continue;
    }
    if (line.startsWith('#EXTINF')) {
      expectSegment = true;
      continue;
    }
    if (line.startsWith('#')) continue;
    if (isMaster && pendingBandwidth != null) {
      variants.add(
        M3u8Variant(bandwidth: pendingBandwidth, uri: resolve(line)),
      );
      pendingBandwidth = null;
      continue;
    }
    if (expectSegment || !isMaster) {
      segments.add(
        M3u8Segment(
          uri: resolve(line),
          keyUri: keyMethod == 'AES-128' ? currentKeyUri : null,
          keyIv: keyMethod == 'AES-128' ? currentKeyIv : null,
          sequence: mediaSequence + segments.length,
        ),
      );
      expectSegment = false;
    }
  }
  return M3u8Playlist(
    segments: segments,
    variants: variants,
    isMaster: isMaster,
    hasEndList: hasEndList,
    keyMethod: keyMethod,
  );
}
