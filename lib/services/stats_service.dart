/// Earnings statistics: persistent claim history + pure aggregations.
///
/// The store appends one JSON object per successful claim to
/// `<rootDir>/stats/earnings.jsonl`. Aggregation helpers are pure functions
/// (no IO) so they can be unit-tested without touching the filesystem.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// One successful claim (earning event) of a mining session.
class EarningRecord {
  /// Account that performed the claim.
  final String accountId;

  /// Mining session the claim belongs to (optional).
  final String? sessionId;

  /// Claimed token amount.
  final double amount;

  /// When the claim completed (normalized to UTC).
  final DateTime at;

  const EarningRecord({
    required this.accountId,
    this.sessionId,
    required this.amount,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'accountId': accountId,
        'sessionId': sessionId,
        'amount': amount,
        'at': at.toUtc().toIso8601String(),
      };

  /// Defensive parse: bad/missing fields fall back to defaults instead of
  /// throwing, so a partially corrupt line never kills a whole load.
  factory EarningRecord.fromJson(Map<String, dynamic> j) {
    final dynamic amountRaw = j['amount'];
    final double amount = amountRaw is num
        ? amountRaw.toDouble()
        : double.tryParse('$amountRaw') ?? 0;
    final dynamic atRaw = j['at'];
    final at = atRaw is String ? DateTime.tryParse(atRaw)?.toUtc() : null;
    return EarningRecord(
      accountId: '${j['accountId'] ?? ''}',
      sessionId: j['sessionId'] is String ? j['sessionId'] as String : null,
      amount: amount,
      at: at ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

/// Aggregated earnings for a single UTC calendar day.
class DailyTotal {
  /// Start of the UTC day bucket.
  final DateTime day;

  /// Sum of claimed amounts that day.
  final double total;

  /// Number of claims that day.
  final int count;

  const DailyTotal({
    required this.day,
    required this.total,
    required this.count,
  });
}

/// Aggregated earnings for a single account.
class AccountTotal {
  /// Account id (matches [EarningRecord.accountId]).
  final String accountId;

  /// Sum of claimed amounts for the account.
  final double total;

  /// Number of claims recorded for the account.
  final int claims;

  const AccountTotal({
    required this.accountId,
    required this.total,
    required this.claims,
  });
}

String _dayKey(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

/// Buckets [records] per UTC day over the last [days] days (today included).
///
/// Returns exactly [days] entries ordered oldest -> newest; days without
/// claims are zero-filled. Records outside the window are ignored. [now] is
/// injectable for tests.
List<DailyTotal> aggregateDaily(
  List<EarningRecord> records, {
  required int days,
  DateTime? now,
}) {
  if (days <= 0) return const [];
  final ref = (now ?? DateTime.now()).toUtc();
  final today = DateTime.utc(ref.year, ref.month, ref.day);
  final totals = <String, double>{};
  final counts = <String, int>{};
  for (final r in records) {
    final d = r.at.toUtc();
    final key = _dayKey(DateTime.utc(d.year, d.month, d.day));
    totals[key] = (totals[key] ?? 0) + r.amount;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final out = <DailyTotal>[];
  for (var i = days - 1; i >= 0; i--) {
    final day = today.subtract(Duration(days: i));
    final key = _dayKey(day);
    out.add(DailyTotal(
      day: day,
      total: totals[key] ?? 0,
      count: counts[key] ?? 0,
    ));
  }
  return out;
}

/// Totals per account, sorted by [AccountTotal.total] descending (ties break
/// by account id). When [topN] is provided only the first [topN] are kept.
List<AccountTotal> aggregateByAccount(
  List<EarningRecord> records, {
  int? topN,
}) {
  final totals = <String, double>{};
  final counts = <String, int>{};
  for (final r in records) {
    totals[r.accountId] = (totals[r.accountId] ?? 0) + r.amount;
    counts[r.accountId] = (counts[r.accountId] ?? 0) + 1;
  }
  final out = totals.entries
      .map((e) => AccountTotal(
            accountId: e.key,
            total: e.value,
            claims: counts[e.key] ?? 0,
          ))
      .toList()
    ..sort((a, b) {
      final byTotal = b.total.compareTo(a.total);
      if (byTotal != 0) return byTotal;
      return a.accountId.compareTo(b.accountId);
    });
  if (topN != null && topN >= 0 && out.length > topN) {
    return out.sublist(0, topN);
  }
  return out;
}

/// Sum of all claimed amounts.
double totalEarned(List<EarningRecord> records) =>
    records.fold(0.0, (sum, r) => sum + r.amount);

/// Sum of claimed amounts at or after [since] (inclusive).
double earnedSince(List<EarningRecord> records, DateTime since) => records
    .where((r) => !r.at.isBefore(since))
    .fold(0.0, (sum, r) => sum + r.amount);

/// The single highest-earning UTC day, or null when [records] is empty.
/// Ties resolve to the earliest day.
DailyTotal? bestDay(List<EarningRecord> records) {
  final buckets = <String, DailyTotal>{};
  for (final r in records) {
    final d = r.at.toUtc();
    final day = DateTime.utc(d.year, d.month, d.day);
    final key = _dayKey(day);
    final cur = buckets[key];
    buckets[key] = DailyTotal(
      day: day,
      total: (cur?.total ?? 0) + r.amount,
      count: (cur?.count ?? 0) + 1,
    );
  }
  if (buckets.isEmpty) return null;
  DailyTotal best = buckets.values.first;
  for (final v in buckets.values) {
    final better = v.total > best.total ||
        (v.total == best.total && v.day.isBefore(best.day));
    if (better) best = v;
  }
  return best;
}

/// Mean earnings per day over the last [days] days (today included).
double averagePerDay(List<EarningRecord> records, {required int days}) {
  if (days <= 0) return 0;
  final total = aggregateDaily(records, days: days)
      .fold(0.0, (sum, d) => sum + d.total);
  return total / days;
}

/// Append-only JSONL store for claim history.
///
/// Layout: one [EarningRecord] JSON object per line inside
/// `<rootDir>/stats/earnings.jsonl`. Designed to be callable from both the
/// UI isolate and the background service isolate: each [record] opens the
/// file in append mode, writes a single line, flushes and closes. Writes are
/// serialized per isolate; rare cross-isolate interleaving self-heals because
/// [loadAll] skips lines it cannot parse. History is capped at [maxLines]
/// lines (oldest trimmed) on [init].
class StatsStore {
  /// Root data dir (same pattern as `resolveRootDir()`, e.g. `<docs>/sible`).
  final String rootDir;

  /// Maximum number of lines kept in the file (trimmed oldest-first on init).
  final int maxLines;

  /// Default value for [maxLines].
  static const int defaultMaxLines = 20000;

  StatsStore({required this.rootDir, this.maxLines = defaultMaxLines});

  /// The JSONL earnings file.
  File get earningsFile => File('$rootDir/stats/earnings.jsonl');

  Future<void>? _pending;

  /// Creates the stats directory/file and trims history beyond [maxLines].
  Future<void> init() async {
    try {
      final f = earningsFile;
      await f.parent.create(recursive: true);
      if (!await f.exists()) {
        await f.writeAsString('');
        return;
      }
      final lines = (await f.readAsString())
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (lines.length <= maxLines) return;
      final kept = lines.sublist(lines.length - maxLines);
      await f.writeAsString('${kept.join('\n')}\n', flush: true);
    } catch (e) {
      debugPrint('[stats] init failed: $e');
    }
  }

  /// Appends [record] as a single JSONL line (serialized per isolate).
  Future<void> record(EarningRecord record) {
    final result = _enqueue('${jsonEncode(record.toJson())}\n');
    // Keep the write queue alive even when a single append fails.
    _pending = result.then(
      (_) {},
      onError: (Object e) {
        debugPrint('[stats] append failed: $e');
      },
    );
    return result;
  }

  Future<void> _enqueue(String line) {
    final prev = _pending ?? Future<void>.value();
    return prev.then((_) async {
      final f = earningsFile;
      await f.parent.create(recursive: true);
      await f.writeAsString(line, mode: FileMode.append, flush: true);
    });
  }

  /// Loads all records oldest -> newest; corrupt lines are skipped.
  Future<List<EarningRecord>> loadAll() async {
    try {
      final f = earningsFile;
      if (!await f.exists()) return const [];
      final content = await f.readAsString();
      final out = <EarningRecord>[];
      for (final line in content.split('\n')) {
        final l = line.trim();
        if (l.isEmpty) continue;
        try {
          final decoded = jsonDecode(l);
          if (decoded is Map) {
            out.add(
              EarningRecord.fromJson(Map<String, dynamic>.from(decoded)),
            );
          }
        } catch (_) {
          // Corrupt or incompatible line - skip it (never fail the load).
        }
      }
      return out;
    } catch (e) {
      debugPrint('[stats] load failed: $e');
      return const [];
    }
  }
}

/// Process-wide facade for recording claims.
///
/// The UI isolate and the background service isolate each run their own copy
/// of Dart statics, so both must call [attach] with a store built from the
/// same root dir. Recommended wiring for the integrator:
///
/// * `AppDependencies.build` (UI isolate) and `onServiceStart > buildManager`
///   (background isolate): `StatsRecorder.attach(StatsStore(rootDir: root));`
/// * In `AccountManager._claimFlow`, right after a claim is confirmed done:
///
/// ```dart
/// await StatsRecorder.recordClaim(
///   accountId: a.id,
///   sessionId: outcome.sessionId,
///   amount: amount ?? 0,
/// );
/// ```
class StatsRecorder {
  StatsRecorder._();

  /// Singleton instance.
  static final StatsRecorder instance = StatsRecorder._();

  static StatsStore? _store;

  /// Whether a store is attached.
  static bool get isAttached => _store != null;

  /// Registers the backing store (pass null to detach).
  static void attach(StatsStore? store) => _store = store;

  /// Records one successful claim. Safe no-op (logs a hint) when no store
  /// is attached; never throws into the mining cycle on IO failures.
  static Future<void> recordClaim({
    required String accountId,
    String? sessionId,
    required double amount,
  }) async {
    final store = _store;
    if (store == null) {
      debugPrint('[stats] store not attached');
      return;
    }
    try {
      await store.record(
        EarningRecord(
          accountId: accountId,
          sessionId: sessionId,
          amount: amount,
          at: DateTime.now().toUtc(),
        ),
      );
    } catch (e) {
      debugPrint('[stats] record failed: $e');
    }
  }
}
