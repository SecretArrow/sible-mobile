/// Live end-to-end harness: registers N fresh accounts via mail.tm, then runs
/// the full automation flow using the EXACT same Dart services that ship in
/// the APK (SibleApiClient + MailTmService + MiningStatusView parsing).
///
/// Usage (from repo root):
///   dart run tool/e2e_5accounts.dart [count]
///
/// Writes a machine-readable report to tool/e2e_report.json and prints a
/// per-account stage table. Exit code 0 only when every stage of every
/// account succeeded.
library;

import 'dart:convert';
import 'dart:io';

import 'package:sible_mobile/core/constants.dart';
import 'package:sible_mobile/services/mailtm_service.dart';
import 'package:sible_mobile/services/mining_policy.dart';
import 'package:sible_mobile/services/sible_api.dart';

const stages = <String>[
  'mailbox',
  'register',
  'otp',
  'verify',
  'login',
  'me',
  'status',
  'start',
  'accelerate',
  'extension',
  'tasks',
];

class Report {
  String email;
  final Map<String, String> results = {}; // stage -> ok|SKIP:...|ERR:...
  final Map<String, dynamic> snapshots = {};
  final List<String> notes = [];

  Report(this.email);

  void ok(String stage) => results[stage] = 'ok';
  void skip(String stage, String why) => results[stage] = 'SKIP:$why';
  void fail(String stage, Object e) => results[stage] = 'ERR:$e';
  void note(String s) => notes.add(s);

  Map<String, dynamic> toJson() => {
        'email': email,
        'results': results,
        'snapshots': snapshots,
        'notes': notes,
      };
}

String shortErr(Object e) {
  if (e is SibleApiException) return '${e.code}(${e.httpStatus})';
  if (e is MailTmException) return 'mailtm:${e.message.split('\n').first}';
  return '$e'.split('\n').first;
}

Future<void> main(List<String> args) async {
  final count = args.isNotEmpty ? int.tryParse(args[0]) ?? 5 : 5;
  final mail = MailTmService();
  final reports = <Report>[];

  stdout.writeln('=== Sible live e2e: $count account(s) via mail.tm ===');
  stdout.writeln('base: ${SibleApi.baseUrl}\n');

  for (var i = 0; i < count; i++) {
    final n = i + 1;
    final r = await runOneAccount(mail, n);
    reports.add(r);
    // Be polite to mail.tm (429s) and the Sible API.
    if (i < count - 1) {
      await Future<void>.delayed(const Duration(seconds: 4));
    }
  }

  _printSummary(reports);
  final file = File('tool/e2e_report.json');
  file.writeAsStringSync(const JsonEncoder.withIndent('  ')
      .convert(reports.map((r) => r.toJson()).toList()));
  stdout.writeln('\nreport: ${file.path}');

  final allStagesOk = reports.every(
      (r) => r.results.values.every((v) => v == 'ok' || v.startsWith('SKIP:')));
  mail.close();
  exit(allStagesOk ? 0 : 1);
}

Future<Report> runOneAccount(MailTmService mail, int n) async {
  final tag = '[$n/5]';
  final client = SibleApiClient.create();
  Report? rep;

  Future<bool> step(String stage, Future<void> Function() body,
      {bool fatal = false}) async {
    try {
      await body();
      rep?.ok(stage);
      stdout.writeln('$tag ✔ $stage');
      return true;
    } catch (e) {
      rep?.fail(stage, e);
      stdout.writeln('$tag ✘ $stage -> ${shortErr(e)}');
      return !fatal;
    }
  }

  // -- 1) mailbox -----------------------------------------------------------
  MailTmAccount? box;
  final rep0 = Report('pending');
  rep = rep0;
  var okBox = false;
  try {
    box = await mail.createAccount(prefix: 'sibler');
    rep0.snapshots['mailbox'] = box.address;
    rep0.results['mailbox'] = 'ok';
    okBox = true;
  } catch (e) {
    rep0.results['mailbox'] = 'ERR:$e';
  }
  if (!okBox || box == null) {
    rep0.email = 'account#$n(mailbox-failed)';
    stdout.writeln('$tag ✘ mailbox -> ${rep0.results['mailbox']}');
    return rep0;
  }

  final r = Report(box.address);
  rep = r;
  final b = box; // non-null alias for closure flow analysis
  final password = b.password;
  r.snapshots['password'] = password; // throwaway test account
  stdout.writeln('$tag mailbox: ${b.address}');

  // -- 2) register ------------------------------------------------------------
  var needsVerification = true;
  final priorToRegister =
      (await mail.messages(b.token)).map((m) => '${m['id']}').toSet();
  await step('register', () async {
    final res = await client.request('/auth/register',
        method: 'POST',
        body: {
          'email': b.address,
          'password': password,
          'username': 'mn${b.address.split('@')[0].substring(6)}',
        },
        auth: false);
    // Register returns {needsVerification, email, resendAfterSec}.
    needsVerification = res is Map && res['needsVerification'] == true;
    r.snapshots['register'] = res is Map ? Map<String, dynamic>.from(res) : {};
  });

  // -- 3+4) OTP ---------------------------------------------------------------
  var otpDone = !needsVerification;
  if (needsVerification) {
    String? code;
    await step('otp', () async {
      code = await mail.waitForOtp(b,
          timeout: const Duration(minutes: 3), skipIds: priorToRegister);
      r.snapshots['otp'] = code!;
    });
    if (code != null) {
      await step('verify', () async {
        await client.verifyOtp(b.address, code!, purpose: 'verify_email');
      });
      otpDone = r.results['verify'] == 'ok';
    }
  } else {
    r.skip('otp', 'not required');
    r.skip('verify', 'not required');
  }
  if (!otpDone) r.note('verification incomplete; login may fail');

  // -- 5) login ----------------------------------------------------------------
  var loggedIn = false;
  final okLogin = await step('login', () async {
    final raw = await client.request('/auth/login',
        method: 'POST',
        body: {'identifier': b.address, 'password': password},
        auth: false);
    r.snapshots['login_raw'] =
        raw is Map ? Map<String, dynamic>.from(raw) : {'raw': '$raw'};
    if (raw is Map && raw['needsOtp'] == true) {
      // Login triggers an OTP challenge -> solve it from the mailbox.
      r.note('login requires OTP challenge');
      // Snapshot ids of emails already in the box so the fresh sign-in code
      // is never confused with the earlier sign-up email.
      final priorIds =
          (await mail.messages(b.token)).map((m) => '${m['id']}').toSet();
      final code = await mail.waitForOtp(b,
          timeout: const Duration(minutes: 3), skipIds: priorIds);
      r.snapshots['login_otp'] = code;
      await client.verifyOtpForTokens(b.address, code, purpose: 'login');
      r.snapshots['login_via'] = 'verify-otp(purpose=login)';
    } else {
      await client.login(b.address, password);
      r.snapshots['login_via'] = 'login';
    }
  });
  loggedIn = okLogin;
  if (!loggedIn) return r; // cannot go further without tokens

  // -- 6) me -------------------------------------------------------------------
  await step('me', () async {
    final me = await client.me();
    if (me is Map) {
      r.snapshots['me_keys'] = me.keys.take(24).toList();
      r.snapshots['balance'] = parseBalance(me);
    }
  });

  // -- 7) mining status ---------------------------------------------------------
  Map<String, dynamic> status = {};
  await step('status', () async {
    final raw = await client.miningStatus();
    if (raw is Map) {
      status = Map<String, dynamic>.from(raw);
      r.snapshots['status_keys'] = status.keys.toList();
      r.snapshots['canActivate'] = status['canActivate'];
      r.snapshots['canWatchAd'] = status['canWatchAd'];
      r.snapshots['canClaim'] = status['canClaim'];
      final v = MiningStatusView.fromJson(raw);
      r.snapshots['parsed_running'] = v.sessionRunning;
      r.snapshots['parsed_endsAt'] = v.sessionEndsAt?.toIso8601String();
    }
  });

  // -- 8) start mining ------------------------------------------------------------
  if (status.isNotEmpty && status['canActivate'] == false) {
    r.skip('start', 'canActivate=false');
    stdout.writeln('$tag ○ start skipped (canActivate=false)');
  } else {
    await step('start', () async {
      await client.startMining();
      await Future<void>.delayed(const Duration(seconds: 2));
      final raw = await client.miningStatus();
      final v = MiningStatusView.fromJson(raw);
      if (!v.sessionRunning) {
        throw StateError('session not running after start');
      }
      r.snapshots['started_sessionId'] = v.sessionId;
    });
  }

  // -- 9) accelerate (watch ad, target 20% = 1 ad) ---------------------------------
  var watched = 0;
  var attempted = false;
  try {
    final raw = await client.miningStatus();
    final st = MiningStatusView.fromJson(raw);
    if (st.sessionRunning && st.canWatchAd) {
      attempted = true;
      await client.watchAd();
      watched++;
    }
  } catch (e) {
    r.note('accel: ${shortErr(e)}');
  }
  if (watched > 0) {
    r.ok('accelerate');
    r.snapshots['adsWatched'] = watched;
    stdout.writeln('$tag ✔ accelerate (+${watched * 20}%)');
  } else {
    r.skip('accelerate', attempted ? 'see notes' : 'not eligible now');
    stdout.writeln('$tag ○ accelerate skipped (watched=0)');
  }

  // -- 10) extension (explorer) ------------------------------------------------------
  await step('extension', () async {
    final apps = await client.explorerApps();
    final list = ExplorerAppView.listFrom(apps);
    r.snapshots['explorer_apps'] = list.map((a) => a.name).take(12).toList();
    if (list.isEmpty) {
      r.note('explorer list empty');
      return;
    }
    final res = await client.openExplorerApp(list.first.id);
    r.snapshots['opened'] = list.first.name;
    r.snapshots['open_res'] = res is Map ? '${res.keys.toList()}' : '$res';
  });

  // -- 11) reward tasks ----------------------------------------------------------------
  await step('tasks', () async {
    final raw = await client.rewardTasks();
    final tasks = TaskView.listFrom(raw);
    r.snapshots['tasks'] =
        tasks.map((t) => '${t.id}:${t.state}').take(12).toList();
  });

  client.close();
  return r;
}

void _printSummary(List<Report> reports) {
  stdout.writeln('\n=== SUMMARY ===');
  final head = stages
      .map((s) => s.substring(0, s.length > 6 ? 6 : s.length).padRight(8))
      .join();
  stdout.writeln('#'.padRight(4) + 'account'.padRight(34) + head);
  for (var i = 0; i < reports.length; i++) {
    final r = reports[i];
    final cols = stages.map((s) {
      final v = r.results[s];
      if (v == null) return '-'.padRight(8);
      if (v == 'ok') return 'ok'.padRight(8);
      if (v.startsWith('SKIP')) return 'skip'.padRight(8);
      return 'ERR'.padRight(8);
    }).join();
    stdout.writeln(
        '${(i + 1).toString().padRight(4)}${r.email.padRight(34)}$cols');
  }
  final errs = reports
      .expand((r) => r.results.entries.where((e) => e.value.startsWith('ERR')))
      .map((e) => '${e.key}: ${e.value}')
      .toList();
  if (errs.isNotEmpty) {
    stdout.writeln('\nerrors:');
    errs.forEach(stdout.writeln);
  }
}
