import 'package:flutter_test/flutter_test.dart';
import 'package:sible_mobile/services/sible_api.dart';

void main() {
  group('Envelope.parse', () {
    test('parses success envelope', () {
      final env = Envelope.parse(
          '{"success":true,"data":{"hello":"world"},"requestId":"r1"}', 200);
      expect(env.success, isTrue);
      expect(env.data, isA<Map>());
      expect((env.data as Map)['hello'], 'world');
    });

    test('parses error envelope', () {
      final env = Envelope.parse(
          '{"success":false,"error":{"code":"OTP_REQUIRED","message":"otp needed"}}',
          400);
      expect(env.success, isFalse);
      expect(env.errorCode, 'OTP_REQUIRED');
      expect(env.errorMessage, 'otp needed');
    });

    test('throws on invalid JSON', () {
      expect(() => Envelope.parse('not json', 200),
          throwsA(isA<SibleApiException>()));
    });

    test('throws on missing success field', () {
      expect(() => Envelope.parse('{"data":{}}', 200),
          throwsA(isA<SibleApiException>()));
    });
  });

  group('AuthTokens.fromData', () {
    test('reads tokens.{accessToken,refreshToken}', () {
      final t = AuthTokens.fromData({
        'tokens': {'accessToken': 'a', 'refreshToken': 'r'},
        'user': {'id': 1},
      });
      expect(t, isNotNull);
      expect(t!.accessToken, 'a');
      expect(t.refreshToken, 'r');
    });

    test('reads flat accessToken', () {
      final t =
          AuthTokens.fromData({'accessToken': 'flat', 'refreshToken': 'r2'});
      expect(t!.accessToken, 'flat');
    });

    test('returns null when missing', () {
      expect(AuthTokens.fromData({'user': {}}), isNull);
    });
  });
}
