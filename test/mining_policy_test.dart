import 'package:flutter_test/flutter_test.dart';
import 'package:sible_mobile/services/mining_policy.dart';

MiningStatusView _status({
  bool running = true,
  String? sessionId = 's1',
  DateTime? endsAt,
  DateTime? nextAdAt,
  bool canWatchAd = true,
}) {
  return MiningStatusView(
    sessionRunning: running,
    sessionId: sessionId,
    sessionEndsAt: endsAt,
    nextAdAt: nextAdAt,
    canWatchAd: canWatchAd,
  );
}

void main() {
  final now = DateTime.utc(2026, 10, 25, 12, 0, 0);

  group('decideNextMiningAction', () {
    test('starts session when none is running', () {
      final action = decideNextMiningAction(
        _status(running: false, sessionId: null),
        adsWatchedThisSession: 0,
        targetAds: 3,
        now: now,
      );
      expect(action, MiningAction.startSession);
    });

    test('claims when session finished and not yet claimed', () {
      final action = decideNextMiningAction(
        _status(
          running: false,
          sessionId: 's9',
          endsAt: now.subtract(const Duration(minutes: 1)),
        ),
        adsWatchedThisSession: 3,
        targetAds: 3,
        now: now,
      );
      expect(action, MiningAction.claim);
    });

    test('does not re-claim same session', () {
      final action = decideNextMiningAction(
        _status(
          running: false,
          sessionId: 's9',
          endsAt: now.subtract(const Duration(minutes: 1)),
        ),
        adsWatchedThisSession: 3,
        targetAds: 3,
        now: now,
        lastClaimedSessionId: 's9',
      );
      expect(action, isNot(MiningAction.claim));
    });

    test('watches ad when below target and ad available', () {
      final action = decideNextMiningAction(
        _status(canWatchAd: true),
        adsWatchedThisSession: 0,
        targetAds: 3,
        now: now,
      );
      expect(action, MiningAction.watchAd);
    });

    test('waits when next ad is in cooldown', () {
      final action = decideNextMiningAction(
        _status(
          canWatchAd: false,
          nextAdAt: now.add(const Duration(minutes: 2)),
        ),
        adsWatchedThisSession: 1,
        targetAds: 3,
        now: now,
      );
      expect(action, MiningAction.waitAdCooldown);
    });

    test('watches when cooldown expired', () {
      final action = decideNextMiningAction(
        _status(
          canWatchAd: false,
          nextAdAt: now.subtract(const Duration(seconds: 30)),
        ),
        adsWatchedThisSession: 1,
        targetAds: 3,
        now: now,
      );
      expect(action, MiningAction.watchAd);
    });

    test('returns none when target reached', () {
      final action = decideNextMiningAction(
        _status(canWatchAd: true),
        adsWatchedThisSession: 3,
        targetAds: 3,
        now: now,
      );
      expect(action, MiningAction.none);
    });
  });

  group('MiningStatusView.fromJson', () {
    test('parses full status', () {
      final v = MiningStatusView.fromJson({
        'canWatchAd': false,
        'slotEndsAt': '2026-10-25T13:00:00.000Z',
        'session': {
          'id': 'abc',
          'isRunning': true,
          'endsAt': '2026-10-25T13:00:00.000Z',
          'nextAdAt': '2026-10-25T12:05:00.000Z',
        },
        'boosts': [
          {'boostPct': 20},
          {'boostPct': 40},
        ],
      });
      expect(v.sessionRunning, isTrue);
      expect(v.sessionId, 'abc');
      expect(v.canWatchAd, isFalse);
      expect(v.nextAdAt, isNotNull);
    });

    test('defensive against unknown shape', () {
      final v = MiningStatusView.fromJson({'weird': 1});
      expect(v.sessionRunning, isFalse);
      expect(v.canWatchAd, isTrue);
    });
  });

  group('parseBalance', () {
    test('reads balance field', () {
      expect(parseBalance({'balance': 12.34}), 12.34);
      expect(parseBalance({'balance': '15.5'}), 15.5);
    });

    test('reads nested wallet', () {
      expect(
          parseBalance({
            'wallet': {'availableBalance': 7}
          }),
          7.0);
    });

    test('null when nothing matches', () {
      expect(parseBalance({'foo': 'bar'}), isNull);
      expect(parseBalance('nope'), isNull);
    });
  });

  group('TaskView', () {
    test('claimable filter', () {
      final tasks = TaskView.listFrom([
        {'id': 't1', 'action': 'mine', 'state': 'open', 'eligible': true},
        {'id': 't2', 'action': 'mine', 'state': 'done', 'eligible': true},
        {'id': 't3', 'action': 'referral', 'state': 'new', 'eligible': false},
        {
          'id': 't4',
          'action': 'open',
          'state': 'open',
          'eligible': true,
          'isBoost': true
        },
      ]);
      expect(tasks, hasLength(4));
      expect(
          tasks.where((t) => t.claimReady).map((t) => t.id).toList(), ['t1']);
    });
  });

  group('ExplorerAppView', () {
    test('parses list response', () {
      final apps = ExplorerAppView.listFrom({
        'apps': [
          {'id': 'a1', 'name': 'App One'},
          {'id': 'a2', 'name': 'App Two'},
        ]
      });
      expect(apps, hasLength(2));
      expect(apps.first.name, 'App One');
    });

    test('parses bare list', () {
      final apps = ExplorerAppView.listFrom([
        {'id': 'x'},
      ]);
      expect(apps, hasLength(1));
    });
  });
}
