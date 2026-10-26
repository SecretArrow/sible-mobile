/// Pure unit tests for the SIBLEBAK1 backup envelope (crypto + validation).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sible_mobile/services/backup_service.dart';

Matcher failsWith(String code) => throwsA(
      predicate(
        (e) => e is BackupException && e.code == code,
        'BackupException($code)',
      ),
    );

void main() {
  const password = 'correct horse battery';
  const envelopeJson = '{"app":"sible-mobile","formatVersion":1,'
      '"exportedAt":"2025-01-01T00:00:00.000Z","accounts":['
      '{"id":"abc123","email":"a@b.c"}]}';

  Uint8List encrypt() => BackupService.encryptEnvelope(envelopeJson, password);

  group('encryptEnvelope / decryptEnvelope roundtrip', () {
    test('decrypts what it encrypted', () {
      expect(BackupService.decryptEnvelope(encrypt(), password), envelopeJson);
    });

    test('writes the SIBLEBAK1 binary layout', () {
      final enc = encrypt();
      expect(
        enc.length,
        greaterThanOrEqualTo(BackupService.headerLen + BackupService.tagLen),
      );
      expect(utf8.decode(enc.sublist(0, 9)), 'SIBLEBAK1');
      // Salt/IV are random: two envelopes never match byte-for-byte.
      expect(encrypt(), isNot(equals(enc)));
    });

    test('base64-wrapped text form round-trips (76-col lines)', () {
      final wrapped = BackupService.toBase64Wrapped(encrypt());
      for (final line in wrapped.split('\n')) {
        expect(line.length, lessThanOrEqualTo(BackupService.base64WrapWidth));
      }
      expect(
          BackupService.decryptEnvelope(
              BackupService.fromBase64Wrapped(wrapped), password),
          envelopeJson);
      // Decoding the raw text bytes (as read from a .txt file) works too.
      expect(BackupService.decryptEnvelope(utf8.encode(wrapped), password),
          envelopeJson);
    });
  });

  group('failure modes', () {
    test('wrong password -> WRONG_PASSWORD', () {
      expect(
        () => BackupService.decryptEnvelope(encrypt(), 'wrong-pass-123'),
        failsWith(BackupException.wrongPassword),
      );
    });

    test('corrupted magic -> CORRUPT_FILE', () {
      final broken = Uint8List.fromList(encrypt());
      broken[0] = 0x58; // 'S' -> 'X'
      expect(
        () => BackupService.decryptEnvelope(broken, password),
        failsWith(BackupException.corruptFile),
      );
    });

    test('truncated file -> CORRUPT_FILE', () {
      final enc = encrypt();
      expect(
        () => BackupService.decryptEnvelope(enc.sublist(0, 20), password),
        failsWith(BackupException.corruptFile),
      );
    });

    test('tampered tag -> WRONG_PASSWORD', () {
      final tampered = Uint8List.fromList(encrypt());
      tampered[tampered.length - 1] ^= 0x01;
      expect(
        () => BackupService.decryptEnvelope(tampered, password),
        failsWith(BackupException.wrongPassword),
      );
    });

    test('tampered ciphertext -> WRONG_PASSWORD', () {
      final tampered = Uint8List.fromList(encrypt());
      tampered[BackupService.headerLen] ^= 0xFF;
      expect(
        () => BackupService.decryptEnvelope(tampered, password),
        failsWith(BackupException.wrongPassword),
      );
    });
  });

  group('envelope validation (parseEnvelope / buildEnvelopeJson)', () {
    test('accepts a valid envelope and returns its accounts', () {
      final accounts = BackupService.parseEnvelope(envelopeJson);
      expect(accounts, hasLength(1));
      expect(accounts.first['id'], 'abc123');
      expect(accounts.first['email'], 'a@b.c');
    });

    test('buildEnvelopeJson output parses back with fixed metadata', () {
      final json = BackupService.buildEnvelopeJson(
        [
          {'id': 'x1', 'email': 'x@s.io'},
        ],
        now: DateTime.utc(2025, 2, 3),
      );
      final meta = jsonDecode(json) as Map<String, dynamic>;
      expect(meta['app'], BackupService.appTag);
      expect(meta['formatVersion'], BackupService.formatVersion);
      expect(meta['exportedAt'], '2025-02-03T00:00:00.000Z');
      expect(BackupService.parseEnvelope(json).first['email'], 'x@s.io');
    });

    test('broken JSON -> CORRUPT_FILE', () {
      expect(() => BackupService.parseEnvelope('not json'),
          failsWith(BackupException.corruptFile));
      expect(() => BackupService.parseEnvelope('[1,2,3]'),
          failsWith(BackupException.corruptFile));
    });

    test('wrong app marker -> CORRUPT_FILE', () {
      expect(
        () => BackupService.parseEnvelope(
            '{"app":"other","formatVersion":1,"accounts":[]}'),
        failsWith(BackupException.corruptFile),
      );
    });

    test('newer formatVersion -> UNSUPPORTED_VERSION', () {
      expect(
        () => BackupService.parseEnvelope(
            '{"app":"sible-mobile","formatVersion":2,"accounts":[]}'),
        failsWith(BackupException.unsupportedVersion),
      );
    });

    test('missing/invalid formatVersion -> CORRUPT_FILE', () {
      expect(
        () =>
            BackupService.parseEnvelope('{"app":"sible-mobile","accounts":[]}'),
        failsWith(BackupException.corruptFile),
      );
    });

    test('missing accounts array -> CORRUPT_FILE', () {
      expect(
        () => BackupService.parseEnvelope(
            '{"app":"sible-mobile","formatVersion":1}'),
        failsWith(BackupException.corruptFile),
      );
    });

    test('non-object account entry -> CORRUPT_FILE', () {
      expect(
        () => BackupService.parseEnvelope(
            '{"app":"sible-mobile","formatVersion":1,"accounts":["nope"]}'),
        failsWith(BackupException.corruptFile),
      );
    });
  });
}
