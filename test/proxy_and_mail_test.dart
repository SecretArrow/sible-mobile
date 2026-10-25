import 'package:flutter_test/flutter_test.dart';
import 'package:sible_mobile/core/constants.dart';
import 'package:sible_mobile/models/models.dart';
import 'package:sible_mobile/services/mailtm_service.dart';

void main() {
  group('ProxyEntry.parseRawList', () {
    test('parses host:port lines', () {
      const raw = '''
1.2.3.4:8080
# comment
5.6.7.8:3128

badline
10.0.0.1:99999
10.0.0.2:0
11.22.33.44:1080
''';
      final list = ProxyEntry.parseRawList(raw);
      final keys = list.map((p) => p.key).toList();
      expect(keys,
          containsAll(['1.2.3.4:8080', '5.6.7.8:3128', '11.22.33.44:1080']));
      expect(keys, hasLength(3));
    });
  });

  group('ProxyEntry.parseGeonode', () {
    test('parses geonode JSON', () {
      const body = '''
{"data":[{"ip":"1.1.1.1","port":8080,"protocols":["http","https"]},{"ip":"2.2.2.2","port":3128,"protocols":["http"]}]}
''';
      final list = ProxyEntry.parseGeonode(body);
      expect(list, hasLength(2));
      expect(list.first.key, '1.1.1.1:8080');
      expect(list.first.protocol, ProxyProtocol.https);
    });

    test('tolerates garbage', () {
      expect(ProxyEntry.parseGeonode('!!!'), isEmpty);
    });
  });

  group('ProxyEntry JSON round-trip', () {
    test('keeps all fields', () {
      final p = ProxyEntry(
        host: '9.9.9.9',
        port: 80,
        latencyMs: 432,
        alive: true,
        assignedTo: 'acc1',
        lastChecked: DateTime.utc(2026, 1, 1),
      );
      final back = ProxyEntry.fromJson(p.toJson());
      expect(back.key, p.key);
      expect(back.latencyMs, 432);
      expect(back.alive, isTrue);
      expect(back.assignedTo, 'acc1');
    });
  });

  group('MailTmService.extractOtp', () {
    test('randomPassword always has a letter and a number', () {
      for (var i = 0; i < 300; i++) {
        final p = MailTmService.randomPassword();
        expect(p.contains(RegExp('[A-Za-z]')), isTrue, reason: p);
        expect(p.contains(RegExp('[0-9]')), isTrue, reason: p);
        expect(p.length, greaterThanOrEqualTo(8), reason: p);
      }
    });

    test('finds plain 6-digit code', () {
      expect(
        MailTmService.extractOtp(
            'Your Sible verification code is 481920. Do not share it.'),
        '481920',
      );
    });

    test('finds code inside html', () {
      expect(
        MailTmService.extractOtp('<p>Hello</p> <b>code:</b> 550123 <span/>'),
        '550123',
      );
    });

    test('returns null when absent', () {
      expect(MailTmService.extractOtp('no code here, call 0800-ALPHA'), isNull);
    });
  });

  group('Account isolation', () {
    test('accounts have unique ids and independent files', () {
      final a = Account(id: 'a1', email: 'a@x.com');
      final b = Account(id: 'b2', email: 'b@x.com');
      expect(a.id, isNot(b.id));
      a.balance = 10;
      b.balance = 20;
      expect(a.balance, isNot(b.balance));
    });

    test('daily counters roll over', () {
      final a = Account(id: 'x', email: 'x@x.com', dayKeyIn: '2000-01-01');
      a.claimsToday = 5;
      a.accelerationsToday = 3;
      a.rolloverDayIfNeeded();
      expect(a.claimsToday, 0);
      expect(a.accelerationsToday, 0);
    });

    test('account secrets round-trip', () {
      final s = AccountSecrets(
        password: 'pw',
        accessToken: 'at',
        refreshToken: 'rt',
        openedExtensions: {'e1', 'e2'},
      );
      final back = AccountSecrets.fromJson(s.toJson());
      expect(back.password, 'pw');
      expect(back.openedExtensions, containsAll(['e1', 'e2']));
    });
  });

  group('AccelerateTargets', () {
    test('maps percent to ad count', () {
      expect(AccelerateTargets.adsFor(20), 1);
      expect(AccelerateTargets.adsFor(40), 2);
      expect(AccelerateTargets.adsFor(60), 3);
      expect(AccelerateTargets.adsFor(999), 1);
    });
  });
}
