/// Pure tests for the ops features (#6/#7/#8): log filter + CSV export,
/// notification policy matrix and proxy URI parsing. Only pure logic is
/// exercised — no plugin platform channels are touched.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sible_mobile/services/log_filter.dart';
import 'package:sible_mobile/services/proxy_tester.dart';
import 'package:sible_mobile/services/smart_notifications.dart';

// ---------------------------------------------------------------------------
// #6 Log filter + CSV
// ---------------------------------------------------------------------------

const List<LogRow> _rows = [
  LogRow(
      at: 't1',
      account: 'Miner 1',
      level: 'info',
      message: 'Mining session started'),
  LogRow(
      at: 't2',
      account: 'Miner 1',
      level: 'success',
      message: 'Balance 1.00 -> 2.00'),
  LogRow(
      at: 't3',
      account: 'Miner 2',
      level: 'warn',
      message: 'start: SLOT_ALREADY_USED'),
  LogRow(
      at: 't4', account: 'Miner 2', level: 'error', message: 'ACCOUNT BANNED'),
];

LogsFilterState _state({
  String? account,
  LogLevelFilter level = LogLevelFilter.all,
  String text = '',
}) {
  final s = LogsFilterState()
    ..setAccountFilter(account)
    ..setLevel(level)
    ..setTextQuery(text);
  return s;
}

List<LogRow> _apply(LogsFilterState s) => applyLogFilter(
      _rows,
      s,
      account: (r) => r.account,
      level: (r) => r.level,
      message: (r) => r.message,
    );

void main() {
  group('LogsFilterState', () {
    test('defaults are all / null / empty', () {
      final s = LogsFilterState();
      expect(s.accountFilter, isNull);
      expect(s.level, LogLevelFilter.all);
      expect(s.textQuery, '');
      s.dispose();
    });

    test('setters update state and notify; no-ops do not notify', () {
      final s = LogsFilterState();
      var n = 0;
      s.addListener(() => n++);
      s.setAccountFilter('Miner 1');
      s.setLevel(LogLevelFilter.warn);
      s.setTextQuery('  balance  ');
      s.setAccountFilter('Miner 1'); // no-op
      s.setLevel(LogLevelFilter.warn); // no-op
      expect(n, 3);
      expect(s.accountFilter, 'Miner 1');
      expect(s.level, LogLevelFilter.warn);
      expect(s.textQuery, 'balance');
      s.reset();
      expect(n, 4);
      expect(s.accountFilter, isNull);
      expect(s.level, LogLevelFilter.all);
      expect(s.textQuery, '');
      s.dispose();
    });
  });

  group('applyLogFilter', () {
    test('passes everything by default', () {
      expect(_apply(_state()), hasLength(4));
    });

    test('empty account filter means all accounts', () {
      expect(_apply(_state(account: '')), hasLength(4));
    });

    test('info bucket matches info AND success rows', () {
      final out = _apply(_state(level: LogLevelFilter.info));
      expect(out.map((r) => r.at), ['t1', 't2']);
    });

    test('warn and error buckets match exactly', () {
      expect(
          _apply(_state(level: LogLevelFilter.warn)).map((r) => r.at), ['t3']);
      expect(
          _apply(_state(level: LogLevelFilter.error)).map((r) => r.at), ['t4']);
    });

    test('account filter narrows to one account', () {
      expect(_apply(_state(account: 'Miner 1')).map((r) => r.at), ['t1', 't2']);
    });

    test('text query is case-insensitive on the message', () {
      expect(_apply(_state(text: 'BALANCE')).map((r) => r.at), ['t2']);
    });

    test('combined filters intersect', () {
      final out = _apply(
        _state(account: 'Miner 2', level: LogLevelFilter.error),
      );
      expect(out.map((r) => r.at), ['t4']);
    });

    test('no matches yields an empty list', () {
      expect(_apply(_state(text: 'nope')), isEmpty);
    });

    test('is pure: does not mutate the input or state', () {
      final s = _state(level: LogLevelFilter.error);
      _apply(s);
      expect(_rows, hasLength(4));
      expect(s.level, LogLevelFilter.error);
    });
  });

  group('csvEscapeField', () {
    test('leaves plain fields untouched', () {
      expect(csvEscapeField('plain'), 'plain');
      expect(csvEscapeField(''), '');
      expect(csvEscapeField('a b'), 'a b');
    });

    test('quotes commas', () {
      expect(csvEscapeField('a,b'), '"a,b"');
    });

    test('doubles internal quotes', () {
      expect(csvEscapeField('say "hi"'), '"say ""hi"""');
    });

    test('quotes newlines and carriage returns', () {
      expect(csvEscapeField('l1\nl2'), '"l1\nl2"');
      expect(csvEscapeField('l1\r\nl2'), '"l1\r\nl2"');
    });

    test('handles combined offenders', () {
      expect(csvEscapeField('no,"mix"\nx'), '"no,""mix""\nx"');
    });
  });

  group('logsToCsv', () {
    test('emits only the header for an empty list', () {
      expect(logsToCsv(const []), 'at,account,level,message');
    });

    test('joins rows with newlines', () {
      final csv = logsToCsv(const [
        LogRow(at: 't1', account: 'Miner 1', level: 'info', message: 'ok'),
        LogRow(
            at: 't2', account: 'Miner 2', level: 'error', message: 'a,"b"\nc'),
      ]);
      // The embedded newline lives inside a quoted field, so splitting the
      // raw document still yields 4 physical lines.
      final lines = csv.split('\n');
      expect(lines, hasLength(4));
      expect(lines[0], 'at,account,level,message');
      expect(lines[1], 't1,Miner 1,info,ok');
      expect(lines[2], 't2,Miner 2,error,"a,""b"');
      expect(lines[3], 'c"');
      expect(csv.endsWith('c"'), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // #7 Smart notification policy
  // -------------------------------------------------------------------------

  const min = 60000;

  NotificationDecision _decide({
    bool errorOnly = false,
    int cooldownMinutes = 30,
    required String kind,
    String accountId = 'a1',
    bool isError = false,
    bool isClaim = false,
    Map<String, int>? last,
    required int nowMillis,
  }) =>
      decide(
        errorOnly: errorOnly,
        cooldownMinutes: cooldownMinutes,
        kind: kind,
        accountId: accountId,
        isError: isError,
        isClaim: isClaim,
        lastNotifyMillis: last ?? <String, int>{},
        nowMillis: nowMillis,
      );

  group('decide (error-only)', () {
    test('blocks cycle_ok when errorOnly is on', () {
      final d = _decide(errorOnly: true, kind: 'cycle_ok', nowMillis: 1000);
      expect(d.notify, isFalse);
      expect(d.reason, 'errorOnly');
    });

    test('allows cycle_ok when errorOnly is off and records the key', () {
      final last = <String, int>{};
      final d = decide(
        errorOnly: false,
        cooldownMinutes: 30,
        kind: 'cycle_ok',
        accountId: 'a1',
        isError: false,
        isClaim: false,
        lastNotifyMillis: last,
        nowMillis: 1000,
      );
      expect(d.notify, isTrue);
      expect(d.reason, 'ok');
      expect(last['cycle_ok|a1'], 1000);
    });

    test('claims pass even with errorOnly on', () {
      final d1 = _decide(
          errorOnly: true,
          kind: 'claim',
          last: {'claim|a1': 1000},
          nowMillis: 1000 + 5 * min);
      expect(d1.notify, isTrue);
      expect(d1.reason, 'claim');
      final d2 = _decide(
          errorOnly: true, kind: 'cycle_ok', isClaim: true, nowMillis: 1000);
      expect(d2.notify, isTrue);
      expect(d2.reason, 'claim');
    });

    test('errors always pass (bypass errorOnly too)', () {
      final d = _decide(errorOnly: true, kind: 'cycle_error', nowMillis: 1000);
      expect(d.notify, isTrue);
      expect(d.reason, 'error');
    });
  });

  group('decide (cooldown)', () {
    test('blocks a repeat cycle_ok inside the window, keeps the map', () {
      final last = {'cycle_ok|a1': 1000};
      final d = decide(
        errorOnly: false,
        cooldownMinutes: 30,
        kind: 'cycle_ok',
        accountId: 'a1',
        isError: false,
        isClaim: false,
        lastNotifyMillis: last,
        nowMillis: 1000 + 30 * min - 1,
      );
      expect(d.notify, isFalse);
      expect(d.reason, 'cooldown');
      expect(last['cycle_ok|a1'], 1000);
    });

    test('releases cycle_ok exactly at the window edge', () {
      final last = {'cycle_ok|a1': 1000};
      final d = decide(
        errorOnly: false,
        cooldownMinutes: 30,
        kind: 'cycle_ok',
        accountId: 'a1',
        isError: false,
        isClaim: false,
        lastNotifyMillis: last,
        nowMillis: 1000 + 30 * min,
      );
      expect(d.notify, isTrue);
      expect(last['cycle_ok|a1'], 1000 + 30 * min);
    });

    test('errors bypass the cooldown and never touch the map', () {
      final last = {'cycle_error|a1': 1000};
      final d1 = decide(
        errorOnly: false,
        cooldownMinutes: 30,
        kind: 'cycle_error',
        accountId: 'a1',
        isError: true,
        isClaim: false,
        lastNotifyMillis: last,
        nowMillis: 1000 + min,
      );
      final d2 = decide(
        errorOnly: false,
        cooldownMinutes: 30,
        kind: 'cycle_error',
        accountId: 'a1',
        isError: true,
        isClaim: false,
        lastNotifyMillis: last,
        nowMillis: 1000 + 2 * min,
      );
      expect(d1.notify, isTrue);
      expect(d2.notify, isTrue);
      expect(last['cycle_error|a1'], 1000);
    });

    test('claims ignore the cooldown window', () {
      final last = {'claim|a1': 1000};
      final d = decide(
        errorOnly: false,
        cooldownMinutes: 30,
        kind: 'claim',
        accountId: 'a1',
        isError: false,
        isClaim: false,
        lastNotifyMillis: last,
        nowMillis: 1000 + min,
      );
      expect(d.notify, isTrue);
      expect(d.reason, 'claim');
    });

    test('alerts respect the per-key cooldown', () {
      final last = <String, int>{};
      final a1 = _decide(kind: 'alert', last: last, nowMillis: 0);
      final a2 = _decide(kind: 'alert', last: last, nowMillis: 10 * min);
      final a3 = _decide(kind: 'alert', last: last, nowMillis: 31 * min);
      expect(a1.notify, isTrue);
      expect(a2.notify, isFalse);
      expect(a2.reason, 'cooldown');
      expect(a3.notify, isTrue);
    });

    test('cooldown keys are per kind + account', () {
      final last = {'alert|a1': 0};
      final d =
          _decide(kind: 'alert', accountId: 'a2', last: last, nowMillis: 1000);
      expect(d.notify, isTrue);
    });

    test('cooldownMinutes <= 0 disables the cooldown', () {
      final last = {'cycle_ok|a1': 0};
      final d = decide(
        errorOnly: false,
        cooldownMinutes: 0,
        kind: 'cycle_ok',
        accountId: 'a1',
        isError: false,
        isClaim: false,
        lastNotifyMillis: last,
        nowMillis: 5,
      );
      expect(d.notify, isTrue);
      expect(last['cycle_ok|a1'], 5);
    });

    test('unknown kinds are blocked', () {
      final d = _decide(kind: 'weird', nowMillis: 0);
      expect(d.notify, isFalse);
      expect(d.reason, 'unknownKind');
    });
  });

  group('NotifPolicy.formatGroupedOk', () {
    test('replaces the {n} placeholder', () {
      expect(
        NotifPolicy.formatGroupedOk('{n} accounts OK (grouped)', 7),
        '7 accounts OK (grouped)',
      );
    });

    test('leaves templates without a placeholder untouched', () {
      expect(NotifPolicy.formatGroupedOk('all good', 3), 'all good');
    });

    test('replaces every occurrence', () {
      expect(NotifPolicy.formatGroupedOk('{n}+{n}', 2), '2+2');
    });
  });

  // -------------------------------------------------------------------------
  // #8 Proxy URI parsing
  // -------------------------------------------------------------------------

  group('isValidProxyUri (accept)', () {
    const uris = [
      '1.2.3.4:8080',
      'user:pass@1.2.3.4:8080',
      'http://1.2.3.4:8080',
      'http://user:pass@proxy.example.com:3128',
      'socks5://10.0.0.1:1080',
      'https://u:p@h.io:443',
      'host:1',
      'host:65535',
      '1.2.3.4:0080', // leading zeros -> port 80
    ];
    for (final uri in uris) {
      test('accepts "$uri"', () => expect(isValidProxyUri(uri), isTrue));
    }
  });

  group('isValidProxyUri (reject)', () {
    const uris = [
      '',
      '   ',
      '1.2.3.4', // no port
      '1.2.3.4:', // empty port
      ':8080', // empty host
      '1.2.3.4:0', // port below 1
      '1.2.3.4:65536', // port above 65535
      '1.2.3.4:80x', // non-numeric port
      '1.2.3.4:+80', // signed port
      '1.2.3.4:-1', // negative port
      '1.2.3.4:80 80', // whitespace
      '1.2.3.4:8080/path', // trailing path
      '@host:8080', // empty userinfo
      'a@b@host:8080', // double userinfo
      'http://', // scheme only
    ];
    for (final uri in uris) {
      test('rejects "$uri"', () => expect(isValidProxyUri(uri), isFalse));
    }
  });

  group('normalizeProxyUri', () {
    test('strips the scheme and keeps credentials', () {
      expect(
        normalizeProxyUri('http://user:pass@1.2.3.4:8080'),
        'user:pass@1.2.3.4:8080',
      );
    });

    test('trims whitespace and passes plain host:port through', () {
      expect(normalizeProxyUri('  1.2.3.4:8080 '), '1.2.3.4:8080');
      expect(normalizeProxyUri('socks5://h.io:1080'), 'h.io:1080');
    });

    test('returns null for invalid input', () {
      expect(normalizeProxyUri('nope'), isNull);
      expect(normalizeProxyUri('1.2.3.4:0'), isNull);
    });
  });
}
