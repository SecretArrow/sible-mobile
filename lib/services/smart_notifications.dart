/// Smart notification policy (#7): error-only mode, grouping and cooldown.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kinds of notification events the policy can judge:
/// `cycle_ok` / `cycle_error` (per-account mining cycle outcome), `claim`
/// (balance claim) and `alert` (ban / login failure / proxy exhaustion).
const Set<String> kNotifKinds = {'cycle_ok', 'cycle_error', 'claim', 'alert'};

/// Verdict returned by [decide].
class NotificationDecision {
  /// Whether the notification should be shown.
  final bool notify;

  /// Machine-readable verdict: `ok`, `claim`, `error`, `errorOnly`,
  /// `cooldown` or `unknownKind`.
  final String reason;

  const NotificationDecision(this.notify, this.reason);

  const NotificationDecision.allow(this.reason) : notify = true;

  const NotificationDecision.block(this.reason) : notify = false;

  @override
  String toString() => 'NotificationDecision($notify, $reason)';
}

/// Pure policy decision for one notification event.
///
/// Rules, evaluated in order:
/// 1. Claims ([isClaim] or `kind == 'claim'`) always pass — even when
///    [errorOnly] is on and inside a cooldown window.
/// 2. Errors ([isError] or `kind == 'cycle_error'`) always pass and are
///    *transparent to the cooldown map* (they never update it, so they can
///    never suppress later non-error notifications).
/// 3. `cycle_ok` is blocked when [errorOnly] is enabled.
/// 4. Every other non-error notification (`cycle_ok` with error-only off,
///    and `alert`) is subject to a per-key cooldown keyed
///    `'<kind>|<accountId>'`: a repeat inside [cooldownMinutes] is blocked.
///    [cooldownMinutes] <= 0 disables the cooldown.
///
/// When a notification is allowed, [lastNotifyMillis] is updated with
/// [nowMillis] for the event key so subsequent calls observe the cooldown.
NotificationDecision decide({
  required bool errorOnly,
  required int cooldownMinutes,
  required String kind,
  required String accountId,
  required bool isError,
  required bool isClaim,
  required Map<String, int> lastNotifyMillis,
  required int nowMillis,
}) {
  if (isClaim || kind == 'claim') {
    return const NotificationDecision.allow('claim');
  }
  if (isError || kind == 'cycle_error') {
    return const NotificationDecision.allow('error');
  }
  if (kind == 'cycle_ok' && errorOnly) {
    return const NotificationDecision.block('errorOnly');
  }
  if (!kNotifKinds.contains(kind)) {
    return NotificationDecision.block('unknownKind');
  }
  final windowMs = cooldownMinutes <= 0 ? 0 : cooldownMinutes * 60000;
  final key = '$kind|$accountId';
  final last = lastNotifyMillis[key];
  if (windowMs > 0 && last != null && nowMillis - last < windowMs) {
    return const NotificationDecision.block('cooldown');
  }
  lastNotifyMillis[key] = nowMillis;
  return const NotificationDecision.allow('ok');
}

/// SharedPreferences-backed notification policy (`notif.*` keys).
class NotifPolicy extends ChangeNotifier {
  /// Pref key: smart notifications master switch.
  static const String keySmart = 'notif.smart';

  /// Pref key: errors & claims only (suppresses cycle_ok).
  static const String keyErrorOnly = 'notif.errorOnly';

  /// Pref key: one aggregated daily summary instead of per-cycle pings.
  static const String keyDailySummary = 'notif.dailySummary';

  /// Pref key: repeat-alert cooldown in minutes.
  static const String keyCooldownMinutes = 'notif.cooldownMinutes';

  /// Default for [smartEnabled].
  static const bool defaultSmart = true;

  /// Default for [errorOnly].
  static const bool defaultErrorOnly = true;

  /// Default for [dailySummary].
  static const bool defaultDailySummary = false;

  /// Default for [cooldownMinutes].
  static const int defaultCooldownMinutes = 30;

  /// Backing preferences (same pattern as the app settings stores).
  final SharedPreferences prefs;

  /// Creates a policy reading from [prefs].
  NotifPolicy(this.prefs);

  /// Master switch for the smart policy.
  bool get smartEnabled => prefs.getBool(keySmart) ?? defaultSmart;

  /// Whether cycle_ok notifications are suppressed (errors & claims pass).
  bool get errorOnly => prefs.getBool(keyErrorOnly) ?? defaultErrorOnly;

  /// Whether a single daily summary replaces per-cycle notifications.
  bool get dailySummary =>
      prefs.getBool(keyDailySummary) ?? defaultDailySummary;

  /// Repeat-alert cooldown window in minutes.
  int get cooldownMinutes =>
      prefs.getInt(keyCooldownMinutes) ?? defaultCooldownMinutes;

  /// Sets [smartEnabled].
  Future<void> setSmartEnabled(bool v) async {
    await prefs.setBool(keySmart, v);
    notifyListeners();
  }

  /// Sets [errorOnly].
  Future<void> setErrorOnly(bool v) async {
    await prefs.setBool(keyErrorOnly, v);
    notifyListeners();
  }

  /// Sets [dailySummary].
  Future<void> setDailySummary(bool v) async {
    await prefs.setBool(keyDailySummary, v);
    notifyListeners();
  }

  /// Sets [cooldownMinutes].
  Future<void> setCooldownMinutes(int v) async {
    await prefs.setInt(keyCooldownMinutes, v);
    notifyListeners();
  }

  /// Renders the grouped "N accounts OK" body from [template] by replacing
  /// the `{n}` placeholder with [n]. Templates without `{n}` pass through.
  static String formatGroupedOk(String template, int n) =>
      template.replaceAll('{n}', '$n');
}
