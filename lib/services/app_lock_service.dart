/// Biometric / device-credential app lock built on `local_auth`.
///
/// [shouldLock] is pure (no plugin calls) so the lock decision can be unit
/// tested without platform channels; [AppLockService] and [LockSession] are
/// the thin runtime wrappers around it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Grace period after a successful unlock during which the app stays open.
///
/// Locking immediately on every app pause is hostile (push notifications,
/// quick app switches, screenshot to another app...), so the gate only
/// engages again after this window has elapsed.
const Duration kLockGracePeriod = Duration(minutes: 1);

/// Pure decision: should the lock gate be shown right now?
///
/// * [enabled] false -> never lock.
/// * [lastUnlockAt] null -> lock (never unlocked / explicitly cleared).
/// * unlocked within [gracePeriod] -> stay open.
/// * unlocked after [gracePeriod] elapsed -> lock again.
/// * a "future" timestamp (clock skew) is treated as within grace.
bool shouldLock(
  bool enabled,
  DateTime? lastUnlockAt, {
  Duration gracePeriod = kLockGracePeriod,
  DateTime? now,
}) {
  if (!enabled) return false;
  if (lastUnlockAt == null) return true;
  final at = now ?? DateTime.now();
  final elapsed = at.difference(lastUnlockAt);
  if (elapsed < Duration.zero) return false;
  return elapsed >= gracePeriod;
}

/// Outcome of a single authentication attempt.
class LockResult {
  /// Whether the user is now authenticated.
  final bool ok;

  /// Plugin error code when [ok] is false, e.g. `not_enrolled`, `locked_out`.
  final String? errorCode;

  const LockResult({required this.ok, this.errorCode});
}

/// Thin, testable wrapper around the `local_auth` plugin.
class AppLockService {
  final LocalAuthentication _auth;

  AppLockService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  /// True when the device supports authentication and biometrics can be
  /// checked (falls back to device credential inside [authenticate]).
  Future<bool> canAuthenticate() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return supported && canCheck;
    } on PlatformException catch (e) {
      debugPrint('[lock] canAuthenticate error: ${e.code}');
      return false;
    } catch (e) {
      debugPrint('[lock] canAuthenticate failed: $e');
      return false;
    }
  }

  /// Runs the system authentication sheet (biometric first, device PIN as
  /// fallback). Never throws: failures are mapped into [LockResult].
  Future<LockResult> authenticate({required String localizedReason}) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: localizedReason,
      );
      return LockResult(ok: ok, errorCode: ok ? null : 'failed');
    } on PlatformException catch (e) {
      debugPrint('[lock] authenticate error: ${e.code}');
      return LockResult(ok: false, errorCode: e.code);
    } catch (e) {
      debugPrint('[lock] authenticate failed: $e');
      return const LockResult(ok: false, errorCode: 'unknown');
    }
  }
}

/// In-memory + persisted "last successful unlock" timestamp.
///
/// The timestamp survives process death via the `security.lastUnlock`
/// preference so a cold start right after unlocking does not re-lock.
class LockSession {
  LockSession._();

  /// Process-wide singleton.
  static final LockSession instance = LockSession._();

  /// Preference key holding the epoch-milliseconds of the last unlock.
  static const String prefKey = 'security.lastUnlock';

  SharedPreferences? _prefs;

  /// Last successful unlock; null means locked / unknown.
  DateTime? lastUnlock;

  Future<SharedPreferences> _store() async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Restores the persisted timestamp (call once at startup).
  Future<void> restore() async {
    final prefs = await _store();
    final ms = prefs.getInt(prefKey);
    lastUnlock = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Pure check against the current timestamp.
  bool needsLock(bool enabled, {Duration gracePeriod = kLockGracePeriod}) {
    return shouldLock(enabled, lastUnlock, gracePeriod: gracePeriod);
  }

  /// Records a successful unlock (memory + preference).
  Future<void> markUnlocked() async {
    lastUnlock = DateTime.now();
    final prefs = await _store();
    await prefs.setInt(prefKey, lastUnlock!.millisecondsSinceEpoch);
  }

  /// Clears the timestamp (used by the "Lock now" action).
  Future<void> clear() async {
    lastUnlock = null;
    final prefs = await _store();
    await prefs.remove(prefKey);
  }
}
