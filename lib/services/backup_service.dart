/// Encrypted backup/restore of all accounts ("SIBLEBAK1" envelope format).
///
/// File layout (binary):
/// ```
/// bytes  0..8   magic "SIBLEBAK1" (9 ASCII bytes)
/// bytes  9..24  PBKDF2 salt (16 random bytes)
/// bytes 25..36  AES-GCM nonce/IV (12 random bytes)
/// bytes 37..    AES-256-GCM ciphertext || 16-byte auth tag
/// ```
/// Key = PBKDF2-HMAC-SHA256(password, salt, 100000 iterations, 32 bytes).
/// The whole envelope is also exposed base64-wrapped at 76 columns so it can
/// be shared as plain text (paste into chat/e-mail); [importFromFile] accepts
/// both the raw binary form and the base64-wrapped text form.
///
/// This service never touches account persistence itself: the caller injects
/// `exportAll` / `importAll` closures (see [BackupService] ctor docs) so the
/// storage layer stays swappable and the crypto stays pure and unit-testable.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';

/// Failure thrown by [BackupService] with a stable machine-readable [code].
class BackupException implements Exception {
  /// The provided password failed GCM tag verification.
  static const String wrongPassword = 'WRONG_PASSWORD';

  /// The file is not a valid SIBLEBAK1 envelope (magic/JSON/shape broken).
  static const String corruptFile = 'CORRUPT_FILE';

  /// File picker / filesystem interaction failed.
  static const String ioError = 'IO_ERROR';

  /// Envelope written by a newer app version (formatVersion > supported).
  static const String unsupportedVersion = 'UNSUPPORTED_VERSION';

  /// Stable error code, one of the static constants above.
  final String code;

  /// Human-readable details (safe to show in a snackbar).
  final String message;

  const BackupException(this.code, this.message);

  @override
  String toString() => 'BackupException($code): $message';
}

/// Outcome of a successful restore via [BackupService.importFromFile].
class BackupResult {
  /// Accounts written to the local store.
  final int imported;

  /// Accounts skipped (duplicate id or invalid payload).
  final int skipped;

  /// One entry per skipped account (best-effort, store-dependent detail).
  final List<String> skippedReasons;

  const BackupResult({
    required this.imported,
    required this.skipped,
    this.skippedReasons = const [],
  });

  /// Convenience for "nothing happened" (dialog cancelled / empty backup).
  bool get isEmpty => imported == 0 && skipped == 0;
}

/// Exports all accounts into an AES-256-GCM encrypted `.siblebak` file and
/// restores them again, without knowing anything about the storage layer.
///
/// The caller injects two closures:
///  * [exportAll] - reads every account (profile + secrets) from the store
///    and returns them as JSON-encodable maps.
///  * [importAll] - receives decoded account maps and persists them,
///    returning how many were imported and how many were skipped.
///
/// Wiring (main app): `exportAll` = iterate `AccountStore.listAccountIds()` +
/// `readProfile`/`readSecrets`; `importAll` = write profiles/secrets via
/// `AccountStore` (skip ids that already exist), then
/// `AccountManager.loadAll()` to refresh in-memory state.
class BackupService {
  /// ASCII magic at the start of every backup file.
  static final Uint8List magic = Uint8List.fromList(utf8.encode('SIBLEBAK1'));

  /// PBKDF2 salt length.
  static const int saltLen = 16;

  /// AES-GCM nonce length.
  static const int ivLen = 12;

  /// Derived key length (AES-256).
  static const int keyLen = 32;

  /// PBKDF2 iteration count (OWASP 2023 guidance for PBKDF2-SHA256).
  static const int iterations = 100000;

  /// GCM auth tag length.
  static const int tagLen = 16;

  /// magic(9) + salt(16) + iv(12).
  static const int headerLen = 37;

  /// Envelope `app` marker.
  static const String appTag = 'sible-mobile';

  /// Envelope schema version produced by this build.
  static const int formatVersion = 1;

  /// Base64 wrap width for the text-sharing representation.
  static const int base64WrapWidth = 76;

  final Future<List<Map<String, dynamic>>> Function() exportAll;

  final Future<({int imported, int skipped})> Function(
      List<Map<String, dynamic>> accounts) importAll;

  BackupService({required this.exportAll, required this.importAll});

  // ---------------------------------------------------------------------------
  // Pure helpers (no plugins - safe for unit tests)
  // ---------------------------------------------------------------------------

  /// Builds the plaintext envelope JSON for [accounts].
  static String buildEnvelopeJson(
    List<Map<String, dynamic>> accounts, {
    DateTime? now,
  }) =>
      jsonEncode(<String, dynamic>{
        'app': appTag,
        'formatVersion': formatVersion,
        'exportedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
        'accounts': accounts,
      });

  /// Validates an envelope JSON string and returns its account maps.
  ///
  /// Throws [BackupException] with [BackupException.corruptFile] when the
  /// JSON shape is wrong and [BackupException.unsupportedVersion] when the
  /// envelope was produced by a newer app version.
  static List<Map<String, dynamic>> parseEnvelope(String json) {
    dynamic decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const BackupException(
          BackupException.corruptFile, 'Envelope is not valid JSON');
    }
    if (decoded is! Map) {
      throw const BackupException(
          BackupException.corruptFile, 'Envelope must be a JSON object');
    }
    if (decoded['app'] != appTag) {
      throw const BackupException(
          BackupException.corruptFile, 'Envelope app marker mismatch');
    }
    final v = decoded['formatVersion'];
    if (v is! int) {
      throw const BackupException(
          BackupException.corruptFile, 'Envelope has no numeric formatVersion');
    }
    if (v != formatVersion) {
      throw BackupException(BackupException.unsupportedVersion,
          'Envelope formatVersion $v is not supported');
    }
    final accounts = decoded['accounts'];
    if (accounts is! List) {
      throw const BackupException(
          BackupException.corruptFile, 'Envelope has no accounts array');
    }
    final out = <Map<String, dynamic>>[];
    for (final a in accounts) {
      if (a is Map<String, dynamic>) {
        out.add(a);
      } else if (a is Map) {
        out.add(Map<String, dynamic>.from(a));
      } else {
        throw const BackupException(BackupException.corruptFile,
            'Envelope contains a non-object account');
      }
    }
    return out;
  }

  /// Encrypts [json] into the full binary SIBLEBAK1 envelope.
  static Uint8List encryptEnvelope(String json, String password) {
    final rnd = Random.secure();
    final salt = _randomBytes(rnd, saltLen);
    final iv = _randomBytes(rnd, ivLen);
    return _seal(utf8.encode(json), password, salt, iv);
  }

  /// Decrypts a SIBLEBAK1 envelope (binary or base64-wrapped text) back to
  /// the plaintext envelope JSON.
  ///
  /// Throws [BackupException] ([BackupException.corruptFile]) for broken
  /// envelopes and ([BackupException.wrongPassword]) when the GCM tag does
  /// not verify (wrong password or tampered data).
  static String decryptEnvelope(Uint8List bytes, String password) {
    final raw = _normalizeInput(bytes);
    if (raw.length < headerLen + tagLen) {
      throw const BackupException(
          BackupException.corruptFile, 'File too short to be a backup');
    }
    if (!_startsWithMagic(raw)) {
      throw const BackupException(
          BackupException.corruptFile, 'Missing SIBLEBAK1 magic header');
    }
    final salt =
        Uint8List.sublistView(raw, magic.length, magic.length + saltLen);
    final iv = Uint8List.sublistView(raw, magic.length + saltLen, headerLen);
    final cipherAndTag = Uint8List.sublistView(raw, headerLen);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, _params(password, salt, iv));
    final Uint8List plain;
    try {
      plain = cipher.process(cipherAndTag);
    } on InvalidCipherTextException {
      throw const BackupException(
          BackupException.wrongPassword, 'GCM tag check failed');
    }
    try {
      return utf8.decode(plain);
    } on FormatException {
      throw const BackupException(
          BackupException.corruptFile, 'Decrypted payload is not UTF-8');
    }
  }

  /// Base64-wraps [bytes] at [base64WrapWidth] columns for text sharing.
  static String toBase64Wrapped(Uint8List bytes) {
    final b64 = base64.encode(bytes);
    final lines = <String>[];
    for (var i = 0; i < b64.length; i += base64WrapWidth) {
      final end = min(i + base64WrapWidth, b64.length);
      lines.add(b64.substring(i, end));
    }
    return lines.join('\n');
  }

  /// Reverses [toBase64Wrapped] (tolerates arbitrary whitespace).
  static Uint8List fromBase64Wrapped(String text) {
    try {
      return base64.decode(text.replaceAll(RegExp(r'\s'), ''));
    } on FormatException {
      throw const BackupException(
          BackupException.corruptFile, 'Not a valid base64 backup blob');
    }
  }

  // ---------------------------------------------------------------------------
  // Plugin-backed flows (file_picker)
  // ---------------------------------------------------------------------------

  /// Builds + encrypts the envelope and asks the user where to save it.
  ///
  /// Returns the chosen absolute path, or the empty string when the user
  /// cancelled the save dialog. Throws [BackupException] on failure.
  Future<String> exportToFile({required String password}) async {
    try {
      final accounts = await exportAll();
      final bytes = encryptEnvelope(buildEnvelopeJson(accounts), password);
      final now = DateTime.now();
      p2(int v) => v.toString().padLeft(2, '0');
      final name =
          'sible-backup-${now.year}${p2(now.month)}${p2(now.day)}.siblebak';

      String? path;
      try {
        path = await FilePicker.platform.saveFile(
          fileName: name,
          bytes: bytes,
        );
      } on Exception catch (e) {
        throw BackupException(
            BackupException.ioError, 'Save dialog failed: $e');
      }
      if (path == null || path.isEmpty) return '';

      // Defensive: some platform/channel combos hand back a path without
      // having written the bytes themselves.
      try {
        final f = File(path);
        if (!await f.exists() || await f.length() == 0) {
          await f.writeAsBytes(bytes, flush: true);
        }
      } on IOException catch (e) {
        debugPrint('[backup] post-save write check skipped: $e');
      }
      return path;
    } on BackupException {
      rethrow;
    } on Exception catch (e) {
      throw BackupException(BackupException.ioError, 'Export failed: $e');
    }
  }

  /// Asks the user to pick a `.siblebak` file, decrypts + validates it and
  /// hands the account maps to [importAll].
  ///
  /// Returns a zero [BackupResult] when the user cancels the picker.
  /// Throws [BackupException] on failure.
  Future<BackupResult> importFromFile({required String password}) async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['siblebak', 'txt'],
        withData: true,
      );
    } on Exception catch (e) {
      throw BackupException(BackupException.ioError, 'File dialog failed: $e');
    }
    if (picked == null || picked.files.isEmpty) {
      return const BackupResult(imported: 0, skipped: 0);
    }
    final pf = picked.files.single;
    Uint8List bytes;
    if (pf.bytes != null && pf.bytes!.isNotEmpty) {
      bytes = pf.bytes!;
    } else if (pf.path != null) {
      try {
        bytes = await File(pf.path!).readAsBytes();
      } on Exception catch (e) {
        throw BackupException(
            BackupException.ioError, 'Cannot read picked file: $e');
      }
    } else {
      throw const BackupException(
          BackupException.ioError, 'Picked file has no readable data');
    }

    final accounts = parseEnvelope(decryptEnvelope(bytes, password));
    if (accounts.isEmpty) return const BackupResult(imported: 0, skipped: 0);
    try {
      final res = await importAll(accounts);
      return BackupResult(
        imported: res.imported,
        skipped: res.skipped,
        skippedReasons: List<String>.generate(
          res.skipped,
          (_) => 'skipped by store (duplicate id or invalid payload)',
          growable: false,
        ),
      );
    } on BackupException {
      rethrow;
    } on Exception catch (e) {
      throw BackupException(BackupException.ioError, 'Import failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Crypto internals
  // ---------------------------------------------------------------------------

  static Uint8List _seal(
      List<int> plain, String password, Uint8List salt, Uint8List iv) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, _params(password, salt, iv));
    final ct = cipher.process(Uint8List.fromList(plain));
    final out = Uint8List(magic.length + saltLen + ivLen + ct.length);
    var off = 0;
    void put(List<int> part) {
      out.setRange(off, off + part.length, part);
      off += part.length;
    }

    put(magic);
    put(salt);
    put(iv);
    put(ct);
    return out;
  }

  static AEADParameters<KeyParameter> _params(
      String password, Uint8List salt, Uint8List iv) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, keyLen));
    return AEADParameters<KeyParameter>(
      KeyParameter(derivator.process(utf8.encode(password))),
      128, // macSize in bits -> 16-byte tag
      iv,
      Uint8List(0), // no associated data
    );
  }

  static Uint8List _randomBytes(Random rnd, int len) =>
      Uint8List.fromList(List<int>.generate(len, (_) => rnd.nextInt(256)));

  static bool _startsWithMagic(Uint8List bytes) {
    if (bytes.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  /// Accepts either the binary envelope or its base64-wrapped text form.
  static Uint8List _normalizeInput(Uint8List bytes) {
    if (_startsWithMagic(bytes)) return bytes;
    try {
      final text = utf8.decode(bytes);
      final decoded = base64.decode(text.replaceAll(RegExp(r'\s'), ''));
      if (_startsWithMagic(decoded)) return Uint8List.fromList(decoded);
    } on FormatException {
      // fall through to magic check for a precise error
    }
    return bytes;
  }
}
