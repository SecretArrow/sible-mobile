/// KEEPALIVE: keeps every account's auth session alive.
///
/// Runs a bounded-concurrency pass over all enabled accounts every
/// 10 minutes (in the background service isolate, and in the UI isolate
/// when the service is off) so that JWT access tokens / refresh tokens /
/// any session state never reach their expiry while the app is installed.
///
/// Guarantees:
///  * never throws (per-account catch-all),
///  * never fights a running automation cycle (busy accounts are skipped),
///  * always persists rotated tokens to the per-account secure store,
///  * uses the same per-account proxy as cycles (isolation preserved).
library;

import 'package:flutter/foundation.dart';

import '../core/utils.dart' show LogLevel;
import '../models/models.dart';
import 'account_manager.dart';
import 'sible_api.dart';

class KeepaliveSummary {
  final int checked;
  final int refreshed;
  final int reloggedIn;
  final int failed;
  final int skipped;

  const KeepaliveSummary({
    required this.checked,
    required this.refreshed,
    required this.reloggedIn,
    required this.failed,
    required this.skipped,
  });

  @override
  String toString() => 'keepalive: $checked checked, $refreshed refreshed, '
      '$reloggedIn re-logged, $failed failed, $skipped skipped';
}

class TokenKeepalive {
  /// Fixed cadence requested by the product: every 10 minutes.
  static const Duration interval = Duration(minutes: 10);

  /// Bounded parallelism so 100 accounts do not burst the network stack.
  static const int _concurrency = 3;

  /// Runs one full keepalive pass over the manager's enabled accounts.
  ///
  /// Never throws: any error is turned into a [KeepaliveSummary] and a log
  /// event on the affected account.
  static Future<KeepaliveSummary> run(
    AccountManager mgr, {
    void Function(String message)? onLog,
  }) async {
    var checked = 0, refreshed = 0, reloggedIn = 0, failed = 0, skipped = 0;
    final targets = mgr.accounts
        .where((a) => a.enabled && a.status != AccountStatus.banned)
        .toList();
    if (targets.isEmpty) {
      return KeepaliveSummary(
        checked: 0,
        refreshed: 0,
        reloggedIn: 0,
        failed: 0,
        skipped: 0,
      );
    }

    onLog?.call('keepalive pass starting for ${targets.length} account(s)');

    int idx = 0;
    Future<void> worker() async {
      while (true) {
        final i = idx++;
        if (i >= targets.length) return;
        final a = targets[i];
        // Never touch an account whose automation cycle is running right
        // now - the cycle performs its own auth handling and persists the
        // freshest tokens itself.
        if (mgr.cycleRunning || mgr.isAccountBusy(a.id)) {
          skipped++;
          continue;
        }
        try {
          final result = await _keepAliveOne(mgr, a);
          checked++;
          switch (result) {
            case _KaOutcome.refreshed:
              refreshed++;
              break;
            case _KaOutcome.reloggedIn:
              reloggedIn++;
              break;
            case _KaOutcome.ok:
            case _KaOutcome.noCredentials:
              break;
            case _KaOutcome.failed:
              failed++;
              break;
          }
        } catch (e) {
          // Absolute last-resort guard - _keepAliveOne already swallows, but
          // a bug here must never take down the caller's loop.
          failed++;
          debugPrint('[keepalive] unexpected error for ${a.id}: $e');
        }
      }
    }

    await Future.wait(
      List.generate(_concurrency, (_) => worker()),
    );
    return KeepaliveSummary(
      checked: checked,
      refreshed: refreshed,
      reloggedIn: reloggedIn,
      failed: failed,
      skipped: skipped,
    );
  }

  static Future<_KaOutcome> _keepAliveOne(
    AccountManager mgr,
    Account a,
  ) async {
    try {
      final secrets = await mgr.store.readSecrets(a.id);
      if (secrets == null || (secrets.password.isEmpty)) {
        // Nothing to keep alive yet (account added but never verified).
        return _KaOutcome.noCredentials;
      }

      // Same proxy strategy as automation cycles (manual override -> pool).
      ProxyEntry? proxy;
      if (mgr.useProxies) {
        proxy = await mgr.ensureProxyFor(a);
      }
      if (proxy != null) a.proxyKey = proxy.key;
      final client = mgr.clientFor(a, proxy?.proxyUri);

      // Seed tokens from secure storage on first use in this isolate.
      client.tokens ??= AuthTokens(
        accessToken: secrets.accessToken ?? '',
        refreshToken: secrets.refreshToken ?? '',
      );

      final hasAnyToken = (client.tokens?.accessToken ?? '').isNotEmpty ||
          (client.tokens?.refreshToken ?? '').isNotEmpty;

      if (!hasAnyToken) {
        // Fresh-ish account: a single login re-establishes the session.
        if (a.status == AccountStatus.needsOtp) {
          return _KaOutcome.noCredentials; // wait for the user's OTP
        }
        try {
          final t = await client.login(a.email, secrets.password);
          secrets
            ..accessToken = t.accessToken
            ..refreshToken = t.refreshToken;
          await mgr.store.writeSecrets(a.id, secrets);
          await _touch(mgr, a);
          return _KaOutcome.reloggedIn;
        } on SibleApiException catch (e) {
          await _recordAuthFailure(mgr, a, e);
          return _KaOutcome.failed;
        }
      }

      // Light authenticated ping. `me()` is the cheapest stable endpoint.
      try {
        await client.me();
        // 200 => token still valid. Persist any rotation the request layer
        // may have done opportunistically.
        await _persistTokens(mgr, a, client, secrets);
        await _touch(mgr, a);
        return _KaOutcome.ok;
      } on SibleApiException catch (e) {
        if (!e.isAuthError) {
          // Non-auth problem (network/proxy/server): token itself is fine.
          // Treat as alive - do NOT force re-login on flaky networks.
          await _touch(mgr, a);
          return _KaOutcome.ok;
        }
        // Auth error -> rotate via refresh token.
        final ok = await client.refresh();
        if (ok) {
          await _persistTokens(mgr, a, client, secrets);
          await _touch(mgr, a);
          return _KaOutcome.refreshed;
        }
        // Refresh failed -> final fallback: full re-login.
        if (a.status == AccountStatus.needsOtp) {
          await _recordAuthFailure(mgr, a, e);
          return _KaOutcome.failed;
        }
        try {
          final t = await client.login(a.email, secrets.password);
          secrets
            ..accessToken = t.accessToken
            ..refreshToken = t.refreshToken;
          await mgr.store.writeSecrets(a.id, secrets);
          await _touch(mgr, a);
          return _KaOutcome.reloggedIn;
        } on SibleApiException catch (e2) {
          await _recordAuthFailure(mgr, a, e2);
          return _KaOutcome.failed;
        }
      }
    } catch (e) {
      debugPrint('[keepalive] account ${a.id} failed: $e');
      return _KaOutcome.failed;
    }
  }

  static Future<void> _touch(AccountManager mgr, Account a) async {
    try {
      a.lastKeepalive = DateTime.now();
      await mgr.saveAccount(a);
    } catch (_) {
      // Timestamp is cosmetic - never let its write failure fail the pass.
    }
  }

  static Future<void> _persistTokens(
    AccountManager mgr,
    Account a,
    SibleApiClient client,
    AccountSecrets secrets,
  ) async {
    try {
      final acc = client.tokens;
      if (acc == null) return;
      if (acc.accessToken == secrets.accessToken &&
          acc.refreshToken == secrets.refreshToken) {
        return; // nothing rotated - skip the secure-store write
      }
      secrets
        ..accessToken = acc.accessToken
        ..refreshToken = acc.refreshToken;
      await mgr.store.writeSecrets(a.id, secrets);
    } catch (e) {
      debugPrint('[keepalive] persist tokens failed for ${a.id}: $e');
    }
  }

  static Future<void> _recordAuthFailure(
    AccountManager mgr,
    Account a,
    SibleApiException e,
  ) async {
    try {
      if (e.isBanned) {
        a
          ..status = AccountStatus.banned
          ..lastError = 'Account banned';
      } else if (e.code == 'OTP_REQUIRED' || e.code == 'OTP_INVALID') {
        a
          ..status = AccountStatus.needsOtp
          ..lastError = 'OTP verification required';
      } else {
        a
          ..status = AccountStatus.needsRelogin
          ..lastError = '${e.code}: ${e.message}';
      }
      mgr.logEvent(
        level: LogLevel.warn,
        category: 'auth',
        accountId: a.id,
        accountLabel: a.displayName,
        message: 'keepalive: ${e.code} ${e.message}',
      );
      await mgr.saveAccount(a);
    } catch (_) {}
  }
}

enum _KaOutcome { ok, refreshed, reloggedIn, noCredentials, failed }
