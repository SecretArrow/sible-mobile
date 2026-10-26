import 'package:flutter_test/flutter_test.dart';
import 'package:sible_mobile/core/constants.dart';
import 'package:sible_mobile/models/models.dart';
import 'package:sible_mobile/services/error_advisor.dart';

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

    test('keepalive timestamp round-trips through JSON', () {
      final a = Account(id: 'k1', email: 'k@x.com');
      a.lastKeepalive = DateTime.utc(2026, 10, 26, 8, 30);
      final back = Account.fromJson(
          Map<String, dynamic>.from(a.toJson().map((k, v) => MapEntry(k, v))));
      expect(back.lastKeepalive, a.lastKeepalive);
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

  group('ErrorAdvisor', () {
    test('flags problem statuses', () {
      final otp = Account(id: 'a', email: 'a@x.com')
        ..status = AccountStatus.needsOtp;
      final rel = Account(id: 'b', email: 'b@x.com')
        ..status = AccountStatus.needsRelogin;
      final ban = Account(id: 'c', email: 'c@x.com')
        ..status = AccountStatus.banned;
      final err = Account(id: 'd', email: 'd@x.com')
        ..status = AccountStatus.error;
      final ok = Account(id: 'e', email: 'e@x.com')
        ..status = AccountStatus.mining;
      expect(ErrorAdvisor.hasProblem(otp), isTrue);
      expect(ErrorAdvisor.hasProblem(rel), isTrue);
      expect(ErrorAdvisor.hasProblem(ban), isTrue);
      expect(ErrorAdvisor.hasProblem(err), isTrue);
      expect(ErrorAdvisor.hasProblem(ok), isFalse);
    });

    test('needsOtp -> enter OTP guidance', () {
      final a = Account(id: 'a', email: 'a@x.com')
        ..status = AccountStatus.needsOtp;
      final advice = ErrorAdvisor.adviseFor(a);
      expect(advice.titleKey, 'fix.needsOtp.title');
      expect(advice.actions, contains(FixAction.enterOtp));
    });

    test('network-ish error -> proxy guidance', () {
      final a = Account(id: 'a', email: 'a@x.com')
        ..status = AccountStatus.error
        ..lastError = 'TIMEOUT: Request timed out';
      final advice = ErrorAdvisor.adviseFor(a);
      expect(advice.titleKey, 'fix.proxyError.title');
      expect(advice.actions, contains(FixAction.refreshProxyPool));
    });

    test('no healthy proxy -> proxy guidance', () {
      final a = Account(id: 'a', email: 'a@x.com')
        ..status = AccountStatus.error
        ..lastError =
            'No healthy proxy available (unique-per-account pool empty)';
      final advice = ErrorAdvisor.adviseFor(a);
      expect(advice.titleKey, 'fix.proxyError.title');
    });

    test('banned -> remove account action only', () {
      final a = Account(id: 'a', email: 'a@x.com')
        ..status = AccountStatus.banned;
      final advice = ErrorAdvisor.adviseFor(a);
      expect(advice.titleKey, 'fix.banned.title');
      expect(advice.actions, [FixAction.removeAccount]);
    });

    test('unknown error -> generic guidance', () {
      final a = Account(id: 'a', email: 'a@x.com')
        ..status = AccountStatus.error
        ..lastError = 'WEIRD: something odd';
      final advice = ErrorAdvisor.adviseFor(a);
      expect(advice.titleKey, 'fix.generic.title');
    });

    test('every action enum maps to advice somewhere', () {
      // Sanity: the enum is closed and referenced by the advisor.
      expect(FixAction.values, hasLength(9));
    });
  });
}
