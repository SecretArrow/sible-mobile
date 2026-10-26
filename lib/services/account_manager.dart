/// Account manager: owns all accounts, runs automation cycles, guarantees
/// per-account isolation (own API client, own proxy, own storage).
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/utils.dart';
import '../models/models.dart';
import 'account_store.dart';
// INFERHUB: optional AI brain (reward-task solver + acceleration planner).
import 'inferhub_brain.dart';
import 'mailtm_service.dart';
import 'mining_policy.dart';
import 'notification_service.dart';
import 'proxy_engine.dart';
import 'sible_api.dart';

class CycleSummary {
  final int accountsRun;
  final int success;
  final int failed;
  final int claims;
  final int accelerations;
  final int extensionOpens;
  final DateTime at;

  const CycleSummary({
    required this.accountsRun,
    required this.success,
    required this.failed,
    required this.claims,
    required this.accelerations,
    required this.extensionOpens,
    required this.at,
  });

  String get headline =>
      '$success ok · $failed failed · $claims claims · +$accelerations accel · $extensionOpens ext';
}

class AccountManager extends ChangeNotifier {
  final AccountStore store;
  final ProxyEngine proxyEngine;
  final NotificationService notifications;

  final List<Account> accounts = [];
  final List<LogEvent> _liveLog = [];
  bool cycleRunning = false;
  DateTime? lastCycleAt;
  DateTime? nextCycleAt;

  final Map<String, SibleApiClient> _clients = {};

  AccountManager({
    required this.store,
    required this.proxyEngine,
    required this.notifications,
  });

  List<LogEvent> get liveLog => List.unmodifiable(_liveLog);

  List<Account> get activeAccounts => accounts
      .where((a) => a.enabled && a.status != AccountStatus.banned)
      .toList();

  double get totalBalance => accounts.fold(0, (s, a) => s + a.balance);
  int get miningCount =>
      accounts.where((a) => a.status == AccountStatus.mining).length;
  int get problemCount => accounts
      .where((a) =>
          a.status == AccountStatus.error ||
          a.status == AccountStatus.banned ||
          a.status == AccountStatus.needsOtp ||
          a.status == AccountStatus.needsRelogin)
      .length;

  // ---------------------------------------------------------------------------
  // Logging
  // ---------------------------------------------------------------------------

  void log(LogEvent ev) {
    _liveLog.add(ev);
    while (_liveLog.length > 120) {
      _liveLog.removeAt(0);
    }
    store.appendGlobalLog(ev);
    if (ev.accountId.isNotEmpty) store.appendAccountLog(ev.accountId, ev);
    notifyListeners();
  }

  void _logFor(Account a, LogLevel level, String category, String message) =>
      log(LogEvent(
        ts: DateTime.now(),
        level: level,
        category: category,
        accountId: a.id,
        accountLabel: a.displayName,
        message: message,
      ));

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  Future<void> loadAll() async {
    final ids = await store.listAccountIds();
    final loaded = <Account>[];
    for (final id in ids) {
      final p = await store.readProfile(id);
      if (p != null) {
        p.rolloverDayIfNeeded();
        loaded.add(p);
      }
    }
    accounts
      ..clear()
      ..addAll(loaded);
    notifyListeners();
  }

  Future<void> saveAccount(Account a) async {
    await store.writeProfile(a);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Account CRUD
  // ---------------------------------------------------------------------------

  Future<Account?> addManualAccount({
    required String email,
    required String password,
    String label = '',
  }) async {
    if (accounts.length >= Limits.maxAccounts) {
      throw StateError('Maximum of ${Limits.maxAccounts} accounts reached');
    }
    final acc = Account(
      id: randomToken(length: 10),
      email: email.trim(),
      label: label.trim(),
    );
    await store.writeSecrets(acc.id, AccountSecrets(password: password));
    accounts.add(acc);
    await saveAccount(acc);
    _logFor(acc, LogLevel.info, 'auth', 'Account added (manual)');
    return acc;
  }

  Future<void> removeAccount(String id) async {
    _clients.remove(id)?.close();
    await proxyEngine.release(id);
    accounts.removeWhere((a) => a.id == id);
    await store.deleteAccount(id);
    notifyListeners();
  }

  Future<bool> testLogin(Account a) async {
    final secrets = await store.readSecrets(a.id);
    if (secrets == null || secrets.password.isEmpty) return false;
    final client = clientFor(a, null);
    try {
      final tokens = await client.login(a.email, secrets.password);
      secrets
        ..accessToken = tokens.accessToken
        ..refreshToken = tokens.refreshToken;
      await store.writeSecrets(a.id, secrets);
      a.status = AccountStatus.idle;
      a.lastError = null;
      await saveAccount(a);
      return true;
    } on SibleApiException catch (e) {
      if (e.isBanned) {
        a.status = AccountStatus.banned;
      } else {
        a.status = AccountStatus.error;
        a.lastError = e.message;
      }
      await saveAccount(a);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Client management (one isolated client per account + proxy)
  // ---------------------------------------------------------------------------

  SibleApiClient clientFor(Account a, String? proxyUri) {
    final key = '${a.id}|${proxyUri ?? 'direct'}';
    final existing = _clients[key];
    if (existing != null) return existing;
    final client = SibleApiClient.create(proxyUri: proxyUri);
    _clients[key] = client;
    return client;
  }

  void invalidateClient(Account a) {
    _clients.removeWhere((k, v) => k.startsWith('${a.id}|'));
  }

  // ---------------------------------------------------------------------------
  // Account creation via mail.tm (auto account factory)
  // ---------------------------------------------------------------------------

  /// Creates [count] accounts using disposable mail.tm mailboxes, verifies
  /// OTP, logs in and persists them. [onProgress] reports per-slot status.
  Future<int> createMailTmAccounts({
    required int count,
    String? referralCode,
    required int startIndex,
    void Function(int index, String stage, {bool ok})? onProgress,
  }) async {
    final mail = _mailTm();
    var created = 0;
    for (var i = 0; i < count; i++) {
      final slot = startIndex + i;
      if (accounts.length >= Limits.maxAccounts) {
        onProgress?.call(slot, 'limit reached', ok: false);
        break;
      }
      try {
        onProgress?.call(slot, 'creating mailbox', ok: true);
        final box = await mail.createAccount(prefix: 'sibler');
        final acc = Account(
          id: randomToken(length: 10),
          email: box.address,
          label: 'Miner ${slot + 1}',
          isTempMailbox: true,
          mailPassword: box.password,
          mailToken: box.token,
        );
        await store.writeSecrets(
            acc.id, AccountSecrets(password: box.password));
        accounts.add(acc);
        await saveAccount(acc);

        onProgress?.call(slot, 'registering', ok: true);
        final client = clientFor(acc, null);
        final username = 'mn${randomToken(length: 8)}';
        // Snapshot mailbox state before triggering actions so we never pick
        // up a stale code (mail.tm deliveries can race within seconds).
        var knownMailIds = <String>{};
        try {
          knownMailIds =
              (await mail.messages(box.token)).map((m) => '${m['id']}').toSet();
        } catch (_) {}
        try {
          await client.register(
            email: box.address,
            password: box.password,
            username: username,
            referralCode: referralCode,
          );
        } on SibleApiException catch (e) {
          // Registration may still require e-mail verification first.
          _logFor(
              acc, LogLevel.warn, 'auth', 'register: ${e.code} ${e.message}');
        }

        onProgress?.call(slot, 'waiting OTP', ok: true);
        String code;
        try {
          code = await mail.waitForOtp(box, skipIds: knownMailIds);
        } on MailTmException {
          await client.resendOtp(box.address);
          code = await mail.waitForOtp(box, skipIds: knownMailIds);
        }
        onProgress?.call(slot, 'verifying OTP', ok: true);
        var verifiedWithTokens = false;
        try {
          // /auth/verify-otp returns the session tokens directly - capture
          // them instead of calling /auth/login (which would trigger a
          // fresh needsOtp challenge for every fresh account).
          await client.verifyOtpForTokens(box.address, code,
              purpose: 'verify_email');
          verifiedWithTokens = true;
          final secretsNow = await store.readSecrets(acc.id);
          if (secretsNow != null) {
            secretsNow
              ..accessToken = client.tokens?.accessToken
              ..refreshToken = client.tokens?.refreshToken;
            await store.writeSecrets(acc.id, secretsNow);
          }
          acc
            ..status = AccountStatus.idle
            ..lastError = null;
          await saveAccount(acc);
        } on SibleApiException catch (e) {
          _logFor(acc, LogLevel.warn, 'auth', 'verify: ${e.code} ${e.message}');
        }

        if (verifiedWithTokens) {
          _logFor(acc, LogLevel.success, 'auth', 'mail.tm account ready');
          created++;
          await Future<void>.delayed(jitter(baseMs: 1200, spreadMs: 1800));
          continue;
        }

        onProgress?.call(slot, 'logging in', ok: true);
        final okLogin = await testLogin(acc);
        _logFor(
            acc,
            okLogin ? LogLevel.success : LogLevel.error,
            'auth',
            okLogin
                ? 'mail.tm account ready'
                : 'login after verification failed');
        created++;
      } catch (e) {
        onProgress?.call(slot, 'failed: $e', ok: false);
        log(LogEvent(
          ts: DateTime.now(),
          level: LogLevel.error,
          category: 'auth',
          message: 'mail.tm account #$slot failed: $e',
        ));
      }
      await Future<void>.delayed(jitter(baseMs: 1200, spreadMs: 1800));
    }
    notifyListeners();
    return created;
  }

  MailTmService? _mailTmInstance;
  MailTmService _mailTm() => _mailTmInstance ??= MailTmService();

  // INFERHUB: per-cycle AI brain cache. Null = disabled/unavailable; every
  // consumer must treat it as optional and fall back to the static policy.
  InferHubBrain? _inferhubBrain;
  bool _inferhubBrainLoaded = false;

  /// INFERHUB: returns the cached AI brain, creating it once per cycle run.
  /// Never throws; null when InferHub is disabled or fails to initialize.
  Future<InferHubBrain?> _inferhubBrainForCycle() async {
    if (!_inferhubBrainLoaded) {
      _inferhubBrainLoaded = true;
      try {
        _inferhubBrain = await InferHubBrain.maybeCreate();
      } catch (e) {
        debugPrint('[inferhub] brain init failed, static policy kept: $e');
        _inferhubBrain = null;
      }
    }
    return _inferhubBrain;
  }

  // ---------------------------------------------------------------------------
  // Cycles
  // ---------------------------------------------------------------------------

  /// Run one full automation pass for a single account.
  Future<bool> runCycle(Account a, {bool notifyAlerts = true}) async {
    a.rolloverDayIfNeeded();
    a.lastCheck = DateTime.now();
    var ok = true;

    // 1) Proxy - unique per account, rotate on failure.
    var proxy = await _ensureProxy(a);
    if (proxy == null) {
      a.status = AccountStatus.error;
      a.lastError =
          'No healthy proxy available (unique-per-account pool empty)';
      _logFor(a, LogLevel.error, 'proxy', a.lastError!);
      await saveAccount(a);
      return false;
    }
    a.proxyKey = proxy.key;
    a.proxyLabel = '${proxy.latencyMs}ms';

    var client = clientFor(a, proxy.proxyUri);

    // 2) Auth.
    final secrets = await store.readSecrets(a.id);
    if (secrets == null) {
      a.status = AccountStatus.needsRelogin;
      a.lastError = 'No stored credentials';
      await saveAccount(a);
      return false;
    }
    client.tokens ??= AuthTokens(
        accessToken: secrets.accessToken ?? '',
        refreshToken: secrets.refreshToken ?? '');
    if ((client.tokens?.accessToken ?? '').isEmpty) {
      try {
        final t = await client.login(a.email, secrets.password);
        secrets
          ..accessToken = t.accessToken
          ..refreshToken = t.refreshToken;
        await store.writeSecrets(a.id, secrets);
        _logFor(a, LogLevel.success, 'auth', 'Logged in');
      } on SibleApiException catch (e) {
        ok = false;
        await _handleAuthError(a, e, notifyAlerts: notifyAlerts);
        await saveAccount(a);
        return false;
      }
    }

    try {
      // 3) Mining session.
      var status = MiningStatusView.fromJson(await client.miningStatus());
      if (!status.sessionRunning) {
        final claimable = status.sessionId != null &&
            !status.sessionRunning &&
            (a.lastClaim == null ||
                status.sessionEndsAt == null ||
                status.sessionEndsAt!.isAfter(a.lastClaim!));
        if (claimable) {
          a.status = AccountStatus.claiming;
          await _claimFlow(a, client, status, secrets);
        }
        try {
          await client.startMining();
          _logFor(a, LogLevel.info, 'mining', 'Mining session started');
          await Future<void>.delayed(const Duration(seconds: 2));
          status = MiningStatusView.fromJson(await client.miningStatus());
        } on SibleApiException catch (e) {
          if (e.code != 'SESSION_ALREADY_ACTIVE' &&
              e.code != 'slotAlreadyUsed') {
            _logFor(
                a, LogLevel.warn, 'mining', 'start: ${e.code} ${e.message}');
          }
        }
      }
      a.sessionEndsAt = status.sessionEndsAt;

      // 4) Auto accelerate 20/40/60%.
      if (a.autoAccelerate) {
        await _accelerateFlow(a, client, status);
      }

      // 5) Extension (explorer apps) auto-work.
      if (a.autoExtension) {
        await _extensionFlow(a, client, secrets);
      }

      // 6) Reward tasks (non-boost, claimable only).
      if (a.autoClaimTasks) {
        await _tasksFlow(a, client);
      }

      // 7) Balance refresh.
      try {
        final me = await client.me();
        final bal = parseBalance(me);
        if (bal != null) {
          if (bal > a.balance) {
            _logFor(a, LogLevel.success, 'mining',
                'Balance ${a.balance.toStringAsFixed(2)} -> ${bal.toStringAsFixed(2)}');
          }
          a.balance = bal;
        }
      } on SibleApiException catch (e) {
        _logFor(a, LogLevel.warn, 'mining', 'balance: ${e.code}');
      }

      a.status = AccountStatus.mining;
      a.lastError = null;
    } on SibleApiException catch (e) {
      ok = false;
      if (e.isAuthError) {
        await _handleAuthError(a, e, notifyAlerts: notifyAlerts);
      } else if (e.code == 'TIMEOUT' ||
          e.code == 'NETWORK_ERROR' ||
          e.code == 'PROXY_ERROR') {
        // Proxy likely dead -> blacklist for this account, will rotate next run.
        if (a.proxyKey != null) {
          proxyEngine.blacklistFor(a.id, a.proxyKey!);
          proxyEngine.release(a.id);
          invalidateClient(a);
          _logFor(a, LogLevel.warn, 'proxy',
              'Proxy failed (${e.code}) -> rotating');
        }
        a.status = AccountStatus.error;
        a.lastError = e.message;
      } else if (e.isBanned) {
        a.status = AccountStatus.banned;
        a.lastError = 'Account banned';
        _logFor(a, LogLevel.error, 'auth', 'ACCOUNT BANNED');
        if (notifyAlerts) {
          await notifications.notifyAlert(
              title: 'Sible Miner - banned',
              body: '${a.displayName} has been banned.');
        }
      } else {
        a.status = AccountStatus.error;
        a.lastError = '${e.code}: ${e.message}';
        _logFor(a, LogLevel.error, 'system', a.lastError!);
      }
    } catch (e) {
      ok = false;
      a.status = AccountStatus.error;
      a.lastError = '$e';
      _logFor(a, LogLevel.error, 'system', 'unexpected: $e');
    }

    await saveAccount(a);
    return ok;
  }

  Future<ProxyEntry?> _ensureProxy(Account a) async {
    if (proxyEngine.all.isNotEmpty && proxyEngine.aliveCount == 0) {
      await proxyEngine.refreshPool();
    }
    var proxy = await proxyEngine.acquireFor(a.id);
    if (proxy == null) {
      // Try refilling once before giving up.
      await proxyEngine.refreshPool();
      proxy = await proxyEngine.acquireFor(a.id);
    }
    return proxy;
  }

  Future<void> _handleAuthError(Account a, SibleApiException e,
      {required bool notifyAlerts}) async {
    if (e.isBanned) {
      a.status = AccountStatus.banned;
      a.lastError = 'Account banned';
      _logFor(a, LogLevel.error, 'auth', 'ACCOUNT BANNED');
      if (notifyAlerts) {
        await notifications.notifyAlert(
            title: 'Sible Miner - banned',
            body: '${a.displayName} has been banned.');
      }
      return;
    }
    if (e.code == 'OTP_REQUIRED' || e.code == 'OTP_INVALID') {
      a.status = AccountStatus.needsOtp;
      a.lastError = 'OTP verification required';
      if (a.isTempMailbox && a.mailToken != null) {
        try {
          final mail = _mailTm();
          final box = MailTmAccount(
              address: a.email,
              password: a.mailPassword ?? '',
              token: a.mailToken!);
          // Only accept a code from an email that arrived from now on -
          // the mailbox may still hold the older sign-up code.
          final knownMailIds =
              (await mail.messages(box.token)).map((m) => '${m['id']}').toSet();
          final code = await mail.waitForOtp(box,
              timeout: const Duration(seconds: 70), skipIds: knownMailIds);
          final client = _clients['${a.id}|${a.proxyKey ?? 'direct'}'];
          if (client != null) {
            final t = await client.verifyOtpForTokens(a.email, code,
                purpose: 'login');
            final secretsNow = await store.readSecrets(a.id);
            if (secretsNow != null) {
              secretsNow
                ..accessToken = t.accessToken
                ..refreshToken = t.refreshToken;
              await store.writeSecrets(a.id, secretsNow);
            }
            a.status = AccountStatus.idle;
            _logFor(a, LogLevel.success, 'auth', 'OTP auto-verified');
          }
        } catch (err) {
          _logFor(a, LogLevel.warn, 'auth', 'auto OTP failed: $err');
        }
      }
      return;
    }
    a.status = AccountStatus.needsRelogin;
    a.lastError = '${e.code}: ${e.message}';
    _logFor(a, LogLevel.error, 'auth', a.lastError!);
    if (notifyAlerts) {
      await notifications.notifyAlert(
          title: 'Sible Miner - login issue',
          body: '${a.displayName}: ${e.message}');
    }
  }

  Future<void> _accelerateFlow(
      Account a, SibleApiClient client, MiningStatusView status) async {
    var watched = 0;
    // INFERHUB: the AI planner may override the static 20/40/60% target for
    // this session; any failure keeps the account's static target.
    var targetPct = a.accelerateTargetPct;
    final brain = await _inferhubBrainForCycle();
    if (brain != null) {
      try {
        final aiPct = await brain.accelerationTargetPercent(
          fallbackPercent: a.accelerateTargetPct,
          adsWatchedThisSession: 0,
        );
        if (aiPct != a.accelerateTargetPct) {
          _logFor(a, LogLevel.info, 'accel',
              'AI target $aiPct% (static ${a.accelerateTargetPct}%)');
        }
        targetPct = aiPct;
      } catch (e) {
        _logFor(a, LogLevel.warn, 'accel', 'AI planner failed: $e');
      }
    }
    final target = AccelerateTargets.adsFor(targetPct);
    final beforeBoost = a.boostPct;
    for (var i = 0; i < target; i++) {
      MiningStatusView st = status;
      if (i > 0) {
        await Future<void>.delayed(const Duration(seconds: 2));
        st = MiningStatusView.fromJson(await client.miningStatus());
      }
      final action = decideNextMiningAction(
        st,
        adsWatchedThisSession: watched,
        targetAds: target,
      );
      if (action != MiningAction.watchAd) {
        if (action == MiningAction.waitAdCooldown && watched == 0) {
          _logFor(a, LogLevel.info, 'accel',
              'Next acceleration at ${st.nextAdAt?.toLocal() ?? 'later'}');
        }
        break;
      }
      try {
        final res = await client.watchAd();
        watched++;
        a.accelerationsToday++;
        final data = res is Map ? res['boost'] ?? res : res;
        final pct = data is Map
            ? (data['boostPct'] ?? data['pct'] ?? (watched * 20))
            : watched * 20;
        a.boostPct = pct is num ? pct.toInt() : watched * 20;
        _logFor(a, LogLevel.success, 'accel',
            'Acceleration +${a.boostPct}% applied ($watched/$target)');
      } on SibleApiException catch (e) {
        final terminal = [
          'adLimitReached',
          'adBoostDisabled',
          'notActive',
          'adTooSoon',
          'busy',
          'slotAlreadyUsed'
        ];
        _logFor(a, LogLevel.warn, 'accel', '${e.code}: ${e.message}');
        if (terminal.contains(e.code) || e.code == 'TIMEOUT') break;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }
    if (watched > 0 && beforeBoost != a.boostPct) {
      await saveAccount(a);
    }
  }

  Future<void> _claimFlow(Account a, SibleApiClient client,
      MiningStatusView status, AccountSecrets secrets) async {
    try {
      final res = await client.claim();
      final outcome = ClaimOutcome.fromData(res);
      var done = outcome.outcome == 'completed';
      var amount = outcome.claimedAmount;
      if (!done && outcome.sessionId != null) {
        for (final delayMs in const [500, 1000, 2000, 4000]) {
          await Future<void>.delayed(Duration(milliseconds: delayMs));
          try {
            final poll = await client.claimById(outcome.sessionId!);
            if (poll is Map) {
              final st = '${poll['status'] ?? poll['outcome'] ?? ''}';
              if (st == 'completed' || poll['amount'] != null) {
                done = true;
                amount ??= poll['amount'] is num
                    ? (poll['amount'] as num).toDouble()
                    : double.tryParse('${poll['amount']}');
                break;
              }
              if (st == 'failed') break;
            }
          } on SibleApiException catch (e) {
            _logFor(a, LogLevel.warn, 'mining', 'claim poll: ${e.code}');
            break;
          }
        }
      }
      if (done) {
        a.lastClaim = DateTime.now();
        a.claimsToday++;
        _logFor(a, LogLevel.success, 'mining',
            'Claimed ${amount?.toStringAsFixed(4) ?? ''} SIBLE'.trim());
      } else {
        _logFor(a, LogLevel.info, 'mining', 'Claim still pending');
      }
    } on SibleApiException catch (e) {
      if (e.code != 'nothingToClaim' && e.code != 'notReady') {
        _logFor(a, LogLevel.warn, 'mining', 'claim: ${e.code} ${e.message}');
      }
    }
  }

  Future<void> _extensionFlow(
      Account a, SibleApiClient client, AccountSecrets secrets) async {
    try {
      final apps = ExplorerAppView.listFrom(await client.explorerApps());
      if (apps.isEmpty) return;
      var opened = 0;
      const perCycleCap = 10;
      for (final app in apps) {
        if (opened >= perCycleCap) break;
        if (secrets.openedExtensions.contains(app.id)) continue;
        try {
          await client.openExplorerApp(app.id);
          secrets.openedExtensions.add(app.id);
          a.extensionOpensToday++;
          opened++;
          _logFor(a, LogLevel.info, 'extension', 'Opened "${app.name}"');
        } on SibleApiException catch (e) {
          _logFor(a, LogLevel.warn, 'extension', '${app.name}: ${e.code}');
          if (e.code == 'TIMEOUT' || e.code == 'NETWORK_ERROR') break;
        }
        await Future<void>.delayed(jitter(baseMs: 1500, spreadMs: 1500));
      }
      if (opened > 0) {
        await store.writeSecrets(a.id, secrets);
        _logFor(a, LogLevel.success, 'extension',
            '$opened extension app(s) processed');
      }
    } on SibleApiException catch (e) {
      _logFor(a, LogLevel.warn, 'extension', 'list: ${e.code} ${e.message}');
    }
  }

  Future<void> _tasksFlow(Account a, SibleApiClient client) async {
    try {
      final tasks = TaskView.listFrom(await client.rewardTasks());
      // INFERHUB: task solver hook - when enabled, the AI crafts a submission
      // payload per eligible task before the existing claim call path.
      final brain = await _inferhubBrainForCycle();
      var claimed = 0;
      for (final t in tasks) {
        if (!t.claimReady || claimed >= 3) continue;
        try {
          // INFERHUB: ask the AI for a submission payload; null (solver off,
          // declined, failed) keeps the plain claim path untouched.
          if (brain != null) {
            try {
              final payload =
                  await brain.taskSubmissionPayload(<String, dynamic>{
                'id': t.id,
                'action': t.action,
                'state': t.state,
                'enabled': t.enabled,
                'eligible': t.eligible,
              });
              final submission = payload?['submission'];
              if (payload != null &&
                  submission is Map &&
                  submission.isNotEmpty) {
                await client.submitTask(t.id,
                    body: Map<String, dynamic>.from(submission));
                _logFor(a, LogLevel.info, 'task', 'AI submission: ${t.id}');
              }
            } catch (e) {
              _logFor(a, LogLevel.warn, 'task', 'AI solver: $e');
            }
          }
          await client.claimTask(t.id);
          claimed++;
          a.claimsToday++;
          _logFor(a, LogLevel.success, 'task', 'Reward task ${t.id} claimed');
        } on SibleApiException catch (e) {
          if (e.code != 'TASK_NOT_CLAIMABLE') {
            _logFor(a, LogLevel.warn, 'task', '${t.id}: ${e.code}');
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    } on SibleApiException catch (e) {
      _logFor(a, LogLevel.warn, 'task', 'list: ${e.code}');
    }
  }

  // ---------------------------------------------------------------------------
  // All-accounts cycle with bounded concurrency
  // ---------------------------------------------------------------------------

  Future<CycleSummary> runAllCycles({
    int concurrency = 6,
    bool notifyAlerts = true,
    bool notifySummary = false,
  }) async {
    if (cycleRunning) {
      return CycleSummary(
        accountsRun: 0,
        success: 0,
        failed: 0,
        claims: 0,
        accelerations: 0,
        extensionOpens: 0,
        at: DateTime.now(),
      );
    }
    cycleRunning = true;
    notifyListeners();
    // INFERHUB: load the AI brain once for this whole cycle run (settings
    // changes are picked up again on the next run).
    _inferhubBrain = null;
    _inferhubBrainLoaded = false;
    await _inferhubBrainForCycle();
    await loadAll();
    final targets = activeAccounts;
    var success = 0, failed = 0, claims = 0, accelerations = 0, ext = 0;

    final results = <bool>[];
    final lock = <int>[];
    int idx = 0;
    Future<void> worker(int workerId) async {
      while (true) {
        if (idx >= targets.length) break;
        final i = idx++;
        lock.add(workerId);
        final a = targets[i];
        try {
          await Future<void>.delayed(Duration(
              milliseconds: 150 * i % 1200 + Random(workerId).nextInt(300)));
          final ok = await runCycle(a, notifyAlerts: notifyAlerts);
          results.add(ok);
          if (ok) {
            success++;
          } else {
            failed++;
          }
          claims += a.claimsToday;
          accelerations += a.accelerationsToday;
          ext += a.extensionOpensToday;
        } catch (e) {
          failed++;
          _logFor(a, LogLevel.error, 'system', 'cycle crash: $e');
        } finally {
          lock.remove(workerId);
        }
      }
    }

    final workers = List.generate(
        max(1, min(concurrency, targets.isEmpty ? 1 : targets.length)), worker);
    await Future.wait(workers);

    cycleRunning = false;
    final finishedAt = DateTime.now();
    lastCycleAt = finishedAt;
    final summary = CycleSummary(
      accountsRun: targets.length,
      success: success,
      failed: failed,
      claims: claims,
      accelerations: accelerations,
      extensionOpens: ext,
      at: finishedAt,
    );
    notifyListeners();

    if (notifySummary && summary.accountsRun > 0) {
      await notifications.notify(
        title: 'Sible Miner - cycle done',
        body: '${summary.headline} · ${summary.accountsRun} accounts',
        channel: Channels.events,
        silent: true,
      );
    }
    return summary;
  }
}
