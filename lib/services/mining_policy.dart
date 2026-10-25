/// Pure mining-cycle decision logic. Kept framework-free for easy unit tests.
library;

/// Parsed view of GET /mining/status.
class MiningStatusView {
  final bool sessionRunning;
  final String? sessionId;
  final DateTime? sessionEndsAt;
  final DateTime? nextAdAt;
  final bool canWatchAd;
  final DateTime? slotEndsAt;
  final double ratePerHour;
  final DateTime? serverClock;

  const MiningStatusView({
    required this.sessionRunning,
    this.sessionId,
    this.sessionEndsAt,
    this.nextAdAt,
    required this.canWatchAd,
    this.slotEndsAt,
    this.ratePerHour = 0,
    this.serverClock,
  });

  /// Defensive parsing - unknown/renamed fields simply fall back to defaults.
  static MiningStatusView fromJson(dynamic raw) {
    if (raw is! Map) {
      return const MiningStatusView(sessionRunning: false, canWatchAd: true);
    }
    final session = raw['session'];
    final s = session is Map ? session : null;
    final boostList = _firstList(
        raw, ['boosts', 'accelerations', 'accelerationSlots', 'adBoosts']);
    final boostCount = boostList.where((e) => e is Map && _pctOf(e) > 0).length;
    final canWatch = raw['canWatchAd'] == true ||
        (raw['canWatchAd'] == null && boostCount < 3);
    DateTime? dt(dynamic v) =>
        v is String ? DateTime.tryParse(v)?.toUtc() : null;
    double? asDouble(dynamic v) =>
        v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
    return MiningStatusView(
      sessionRunning: s?['isRunning'] == true || s?['running'] == true,
      sessionId: s?['id'] as String?,
      sessionEndsAt: dt(s?['endsAt']),
      nextAdAt: dt(s?['nextAdAt']),
      canWatchAd: canWatch,
      slotEndsAt: dt(raw['slotEndsAt']),
      ratePerHour: asDouble(raw['rate']) ?? asDouble(raw['ratePerHour']) ?? 0,
      serverClock: dt(raw['clock']?['now'] ?? raw['clock']),
    );
  }

  static List _firstList(Map raw, List<String> keys) {
    for (final k in keys) {
      final v = raw[k];
      if (v is List) {
        return v;
      }
    }
    return const [];
  }

  static double _pctOf(Map item) {
    final v =
        item['boostPct'] ?? item['pct'] ?? item['percent'] ?? item['value'];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

/// Single decision produced for one mining cycle step.
enum MiningAction { startSession, watchAd, waitAdCooldown, claim, none }

/// Decide the next action for a mining session.
///
/// [adsWatchedThisSession] is how many accelerations have already been applied
/// (each worth +20%). [targetAds] is derived from the configured 20/40/60%
/// target. [now] is injectable for tests.
MiningAction decideNextMiningAction(
  MiningStatusView status, {
  required int adsWatchedThisSession,
  required int targetAds,
  DateTime? now,
  String? lastClaimedSessionId,
}) {
  final t = now ?? DateTime.now().toUtc();

  // Session over -> claim before anything else.
  final sessionEnded = status.sessionId != null &&
      !status.sessionRunning &&
      status.sessionEndsAt != null;
  if (sessionEnded &&
      status.sessionEndsAt!.isBefore(t) &&
      lastClaimedSessionId != status.sessionId) {
    return MiningAction.claim;
  }

  if (!status.sessionRunning) return MiningAction.startSession;

  // Session running -> accelerate while below target.
  if (adsWatchedThisSession < targetAds) {
    if (status.canWatchAd) return MiningAction.watchAd;
    final next = status.nextAdAt;
    if (next == null) return MiningAction.none;
    if (next.isBefore(t)) return MiningAction.watchAd;
    return MiningAction.waitAdCooldown;
  }
  return MiningAction.none;
}

/// Outcome of POST /mining/claim plus its polling.
class ClaimOutcome {
  final String outcome; // completed | pending | failed
  final String? sessionId;
  final double? claimedAmount;

  const ClaimOutcome(
      {required this.outcome, this.sessionId, this.claimedAmount});

  static ClaimOutcome fromData(dynamic data) {
    if (data is! Map) return const ClaimOutcome(outcome: 'completed');
    final dynamic amountRaw = data['amount'];
    final double? amount =
        amountRaw is num ? amountRaw.toDouble() : double.tryParse('$amountRaw');
    return ClaimOutcome(
      outcome: '${data['outcome'] ?? data['status'] ?? 'completed'}',
      sessionId: data['sessionId'] as String? ?? data['id'] as String?,
      claimedAmount: amount,
    );
  }
}

/// Defensive balance extraction from GET /users/me.
double? parseBalance(dynamic me) {
  if (me is! Map) return null;
  final candidates = [
    'balance',
    'availableBalance',
    'totalBalance',
    'miningBalance',
    'wallet',
  ];
  for (final k in candidates) {
    final v = me[k];
    if (v is num) return v.toDouble();
    if (v is String && double.tryParse(v) != null) return double.tryParse(v);
    if (v is Map) {
      for (final k2 in candidates) {
        final v2 = v[k2];
        if (v2 is num) return v2.toDouble();
        if (v2 is String && double.tryParse(v2) != null) {
          return double.tryParse(v2);
        }
      }
    }
  }
  return null;
}

/// Parsed reward task.
class TaskView {
  final String id;
  final String action; // mine | referral | open | url...
  final String state; // new | open | done | in_review...
  final bool enabled;
  final bool eligible;
  final bool isBoostTask;

  const TaskView({
    required this.id,
    required this.action,
    required this.state,
    this.enabled = true,
    this.eligible = false,
    this.isBoostTask = false,
  });

  bool get claimReady =>
      enabled &&
      eligible &&
      (state == 'open' || state == 'new') &&
      !isBoostTask;

  static List<TaskView> listFrom(dynamic data) {
    final List items = data is List
        ? data
        : data is Map
            ? (data['tasks'] as List? ?? data['items'] as List? ?? const [])
            : const [];
    return items
        .whereType<Map>()
        .map((m) => TaskView(
              id: '${m['id'] ?? m['_id'] ?? ''}',
              action: '${m['action'] ?? ''}',
              state: '${m['state'] ?? ''}',
              enabled: m['enabled'] != false,
              eligible: m['eligible'] == true,
              isBoostTask: m['isBoost'] == true ||
                  '${m['type'] ?? ''}'.contains('boost'),
            ))
        .where((t) => t.id.isNotEmpty)
        .toList();
  }
}

/// Parsed explorer/extension app.
class ExplorerAppView {
  final String id;
  final String name;
  final String? description;

  const ExplorerAppView(
      {required this.id, required this.name, this.description});

  static List<ExplorerAppView> listFrom(dynamic data) {
    final List items = data is List
        ? data
        : data is Map
            ? (data['apps'] as List? ?? data['items'] as List? ?? const [])
            : const [];
    return items
        .whereType<Map>()
        .map((m) {
          final id = '${m['id'] ?? m['_id'] ?? m['slug'] ?? ''}';
          return ExplorerAppView(
            id: id,
            name: '${m['name'] ?? m['title'] ?? id}',
            description: m['description'] as String?,
          );
        })
        .where((a) => a.id.isNotEmpty)
        .toList();
  }
}
