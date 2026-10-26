/// Unit tests for the earnings statistics service (feature #1).
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sible_mobile/services/stats_service.dart';

EarningRecord rec(String id, double amount, DateTime at, {String? session}) =>
    EarningRecord(accountId: id, sessionId: session, amount: amount, at: at);

void main() {
  final now = DateTime.utc(2026, 10, 25, 12, 0, 0);

  group('EarningRecord json roundtrip', () {
    test('keeps all fields', () {
      final r = rec(
        'acc1',
        0.123456,
        DateTime.utc(2026, 10, 25, 8, 30),
        session: 's1',
      );
      final back = EarningRecord.fromJson(r.toJson());
      expect(back.accountId, 'acc1');
      expect(back.sessionId, 's1');
      expect(back.amount, 0.123456);
      expect(back.at, DateTime.utc(2026, 10, 25, 8, 30));
    });

    test('normalizes local times to UTC', () {
      final r = rec('a', 1, DateTime(2026, 10, 25, 10));
      final back = EarningRecord.fromJson(r.toJson());
      expect(back.at.isUtc, isTrue);
      expect(back.at, r.at.toUtc());
    });

    test('tolerates string amounts and missing fields', () {
      final back = EarningRecord.fromJson(<String, dynamic>{
        'accountId': 'a',
        'amount': '0.5',
        'at': '2026-10-25T00:00:00.000Z',
      });
      expect(back.amount, 0.5);
      expect(back.sessionId, isNull);
      expect(back.at, DateTime.utc(2026, 10, 25));
    });

    test('falls back to epoch for a broken timestamp', () {
      final back = EarningRecord.fromJson(
        <String, dynamic>{'accountId': 'a', 'amount': 1, 'at': 'nope'},
      );
      expect(back.at, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    });
  });

  group('aggregateDaily', () {
    test('splits records at UTC day boundaries', () {
      final lateNight = DateTime.utc(2026, 10, 24, 23, 59, 59);
      final early = DateTime.utc(2026, 10, 25, 0, 0, 0);
      final daily = aggregateDaily(
        [rec('a', 1, lateNight), rec('a', 2, early)],
        days: 2,
        now: now,
      );
      expect(daily.length, 2);
      expect(daily[0].day, DateTime.utc(2026, 10, 24));
      expect(daily[0].total, 1);
      expect(daily[0].count, 1);
      expect(daily[1].day, DateTime.utc(2026, 10, 25));
      expect(daily[1].total, 2);
      expect(daily[1].count, 1);
    });

    test('zero-fills missing days and orders oldest first', () {
      final daily = aggregateDaily(
        [rec('a', 5, DateTime.utc(2026, 10, 25, 1))],
        days: 4,
        now: now,
      );
      expect(daily.map((d) => d.day).toList(), [
        DateTime.utc(2026, 10, 22),
        DateTime.utc(2026, 10, 23),
        DateTime.utc(2026, 10, 24),
        DateTime.utc(2026, 10, 25),
      ]);
      expect(daily.take(3).map((d) => d.total), [0, 0, 0]);
      expect(daily.last.total, 5);
      expect(daily.last.count, 1);
    });

    test('ignores records older than the window', () {
      final old = rec('a', 99, DateTime.utc(2026, 10, 1));
      final daily = aggregateDaily([old], days: 3, now: now);
      expect(daily.every((d) => d.total == 0), isTrue);
      expect(daily.every((d) => d.count == 0), isTrue);
    });

    test('days <= 0 yields an empty list', () {
      expect(aggregateDaily(const [], days: 0, now: now), isEmpty);
      expect(aggregateDaily(const [], days: -3, now: now), isEmpty);
    });
  });

  group('aggregateByAccount', () {
    test('sums per account and sorts by total desc', () {
      final records = [
        rec('b', 1, now.subtract(const Duration(hours: 1))),
        rec('a', 2, now.subtract(const Duration(hours: 2))),
        rec('b', 2.5, now.subtract(const Duration(hours: 3))),
        rec('c', 0.5, now.subtract(const Duration(hours: 4))),
      ];
      final totals = aggregateByAccount(records);
      expect(totals.map((t) => t.accountId).toList(), ['b', 'a', 'c']);
      expect(totals.first.total, 3.5);
      expect(totals.first.claims, 2);
    });

    test('breaks ties by account id', () {
      final records = [rec('z', 1, now), rec('a', 1, now)];
      expect(
        aggregateByAccount(records).map((t) => t.accountId).toList(),
        ['a', 'z'],
      );
    });

    test('topN slices the ranking', () {
      final records = [rec('a', 1, now), rec('b', 2, now), rec('c', 3, now)];
      final tops = aggregateByAccount(records, topN: 2);
      expect(tops.map((t) => t.accountId).toList(), ['c', 'b']);
      expect(aggregateByAccount(records, topN: 0), isEmpty);
      expect(aggregateByAccount(records, topN: 99).length, 3);
    });
  });

  group('bestDay / averagePerDay / totals', () {
    test('bestDay returns the highest-earning day', () {
      final records = [
        rec('a', 1, DateTime.utc(2026, 10, 24, 10)),
        rec('a', 2, DateTime.utc(2026, 10, 24, 11)),
        rec('a', 5, DateTime.utc(2026, 10, 25, 9)),
      ];
      final best = bestDay(records)!;
      expect(best.day, DateTime.utc(2026, 10, 25));
      expect(best.total, 5);
      expect(best.count, 1);
    });

    test('bestDay resolves ties to the earliest day', () {
      final records = [
        rec('a', 3, DateTime.utc(2026, 10, 24, 10)),
        rec('a', 3, DateTime.utc(2026, 10, 25, 10)),
      ];
      expect(bestDay(records)!.day, DateTime.utc(2026, 10, 24));
    });

    test('bestDay is null without records', () {
      expect(bestDay(const []), isNull);
    });

    test('averagePerDay divides the window total by days', () {
      final realNow = DateTime.now().toUtc();
      final today = DateTime.utc(realNow.year, realNow.month, realNow.day);
      final records = [
        rec('a', 2, today),
        rec('a', 1, today.subtract(const Duration(days: 2))),
        rec('a', 50, today.subtract(const Duration(days: 30))),
      ];
      expect(averagePerDay(records, days: 7), closeTo(3 / 7, 1e-9));
      expect(averagePerDay(records, days: 0), 0);
    });

    test('earnedSince is inclusive, totalEarned sums everything', () {
      final t0 = DateTime.utc(2026, 10, 25, 0);
      final records = [
        rec('a', 4, t0.subtract(const Duration(milliseconds: 1))),
        rec('a', 1, t0),
        rec('a', 2, t0.add(const Duration(hours: 1))),
      ];
      expect(totalEarned(records), 7);
      expect(earnedSince(records, t0), 3);
    });
  });

  group('StatsStore', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('stats_test');
    });

    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    test('init creates dir/file; record + loadAll roundtrip', () async {
      final store = StatsStore(rootDir: tmp.path);
      await store.init();
      final f = File('${tmp.path}/stats/earnings.jsonl');
      expect(f.existsSync(), isTrue);

      await store.record(
        rec('a', 0.25, DateTime.utc(2026, 10, 25, 8), session: 's1'),
      );
      await store.record(rec('b', 1.5, DateTime.utc(2026, 10, 25, 9)));

      final all = await store.loadAll();
      expect(all.length, 2);
      expect(all[0].accountId, 'a');
      expect(all[0].sessionId, 's1');
      expect(all[0].amount, 0.25);
      expect(all[1].accountId, 'b');
    });

    test('skips corrupt and non-object lines', () async {
      final store = StatsStore(rootDir: tmp.path);
      await store.init();
      final f = File('${tmp.path}/stats/earnings.jsonl');
      await f.writeAsString(
        '{"accountId":"a","amount":1,"at":"2026-10-25T00:00:00.000Z"}\n'
        'not-json-at-all\n'
        '{"broken": \n'
        '[1,2,3]\n'
        '{"accountId":"b","amount":2,"at":"2026-10-25T01:00:00.000Z"}\n',
      );
      final all = await store.loadAll();
      expect(all.length, 2);
      expect(all[0].accountId, 'a');
      expect(all[1].accountId, 'b');
    });

    test('init trims to maxLines keeping the newest lines', () async {
      final store = StatsStore(rootDir: tmp.path, maxLines: 3);
      await store.init();
      final f = File('${tmp.path}/stats/earnings.jsonl');
      for (var i = 0; i < 5; i++) {
        await store.record(
          rec('a$i', i.toDouble(), DateTime.utc(2026, 10, 25, i)),
        );
      }
      expect(f.readAsStringSync().trim().split('\n').length, 5);
      await store.init();
      final all = await store.loadAll();
      expect(all.length, 3);
      expect(all.first.accountId, 'a2');
      expect(all.last.accountId, 'a4');
      expect(f.readAsStringSync().trim().split('\n').length, 3);
    });

    test('loadAll on a missing file returns an empty list', () async {
      final store = StatsStore(rootDir: '${tmp.path}/does-not-exist');
      expect(await store.loadAll(), isEmpty);
    });
  });

  group('StatsRecorder', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('stats_recorder_test');
    });

    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    test('recordClaim is a logged no-op when not attached', () async {
      final logs = <String>[];
      final original = debugPrint;
      addTearDown(() => debugPrint = original);
      debugPrint = (String? message, {int? wrapWidth}) {
        logs.add(message ?? '');
      };
      StatsRecorder.attach(null);
      await StatsRecorder.recordClaim(accountId: 'a', amount: 1);
      expect(logs, contains('[stats] store not attached'));
    });

    test('recordClaim writes through the attached store', () async {
      final store = StatsStore(rootDir: tmp.path);
      await store.init();
      StatsRecorder.attach(store);
      addTearDown(() => StatsRecorder.attach(null));
      await StatsRecorder.recordClaim(
        accountId: 'x',
        sessionId: 's7',
        amount: 0.75,
      );
      final all = await store.loadAll();
      expect(all.single.accountId, 'x');
      expect(all.single.sessionId, 's7');
      expect(all.single.amount, 0.75);
    });
  });
}
