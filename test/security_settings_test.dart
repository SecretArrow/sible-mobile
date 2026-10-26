/// Pure unit tests for the biometric-lock decision logic.
///
/// Only the plugin-free `shouldLock` function (and the grace-period
/// constant) are exercised — no platform channels are touched.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sible_mobile/services/app_lock_service.dart';

void main() {
  final base = DateTime(2025, 6, 1, 12, 0, 0);
  const grace = Duration(minutes: 1);

  group('shouldLock', () {
    test('disabled never locks', () {
      final longAgo = base.subtract(grace * 10);
      expect(shouldLock(false, longAgo, now: base), isFalse);
      expect(shouldLock(false, null, now: base), isFalse);
    });

    test('null lastUnlock locks (cold start / cleared session)', () {
      expect(shouldLock(true, null, now: base), isTrue);
    });

    test('within the grace period stays open', () {
      final justNow = base.subtract(const Duration(seconds: 1));
      final lateInGrace = base.subtract(const Duration(seconds: 59));
      expect(shouldLock(true, justNow, now: base), isFalse);
      expect(shouldLock(true, lateInGrace, now: base), isFalse);
    });

    test('exactly at the grace boundary locks again', () {
      final boundary = base.subtract(grace);
      expect(shouldLock(true, boundary, now: base), isTrue);
    });

    test('after the grace period locks again', () {
      final aBitLate = base.subtract(grace + const Duration(seconds: 1));
      final hoursLater = base.subtract(const Duration(hours: 8));
      expect(shouldLock(true, aBitLate, now: base), isTrue);
      expect(shouldLock(true, hoursLater, now: base), isTrue);
    });

    test('future timestamp (clock skew) counts as within grace', () {
      final future = base.add(const Duration(minutes: 5));
      expect(shouldLock(true, future, now: base), isFalse);
    });

    test('custom grace period is respected', () {
      final twoMinutesAgo = base.subtract(const Duration(minutes: 2));
      expect(
        shouldLock(true, twoMinutesAgo, now: base, gracePeriod: grace * 5),
        isFalse,
      );
      expect(
        shouldLock(true, twoMinutesAgo, now: base, gracePeriod: grace),
        isTrue,
      );
    });

    test('default grace period is 60 seconds', () {
      expect(kLockGracePeriod, const Duration(minutes: 1));
    });

    test('omitted now defaults to DateTime.now()', () {
      final recent = DateTime.now().subtract(const Duration(seconds: 5));
      expect(shouldLock(true, recent), isFalse);
    });
  });
}
