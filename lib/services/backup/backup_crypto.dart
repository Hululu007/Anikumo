import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:liuguang_download/liuguang_download.dart';

/// Batch 274 (#40): password encryption for local
/// backup files. Format (a text file, so it survives
/// the same pickers and shares as the plain backup):
///
///   ANIKUMO-ENC1
///   <base64 of: 16-byte IV || AES-128-CBC ciphertext>
///
/// The key is the first 16 bytes of SHA-256(password)
/// — a backup-grade KDF for a user-chosen password,
/// using the same pure-Dart AES-128 the download
/// engine ships (B272). A wrong password fails the
/// PKCS#7 padding check (and, failing that, the JSON
/// parse downstream), never silently.
abstract final class BackupCrypto {
  static const String header = 'ANIKUMO-ENC1';

  static bool isEncrypted(String text) =>
      text.trimLeft().startsWith(header);

  static Uint8List _key(String password) {
    final digest = sha256.convert(utf8.encode(password)).bytes;
    return Uint8List.fromList(digest.sublist(0, 16));
  }

  static String encrypt(String plainText, String password) {
    final iv = Uint8List.fromList(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    final cipher = Aes128(_key(password))
        .encryptCbc(utf8.encode(plainText), iv);
    final packed = Uint8List(iv.length + cipher.length)
      ..setRange(0, iv.length, iv)
      ..setRange(iv.length, iv.length + cipher.length, cipher);
    return '$header\n${base64Encode(packed)}';
  }

  /// Throws [FormatException] on a wrong password or
  /// a malformed file.
  static String decrypt(String text, String password) {
    final trimmed = text.trim();
    if (!trimmed.startsWith(header)) {
      throw const FormatException('not an encrypted backup');
    }
    final body = trimmed.substring(header.length).trim();
    final packed = base64Decode(body);
    if (packed.length <= 16 || (packed.length - 16) % 16 != 0) {
      throw const FormatException('encrypted backup is truncated');
    }
    final plain = Aes128(_key(password)).decryptCbc(
      packed.sublist(16),
      packed.sublist(0, 16),
    );
    return utf8.decode(plain);
  }
}
