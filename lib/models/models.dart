/// Data models: proxy entry, account, settings.
library;

import 'dart:convert';

// ---------------------------------------------------------------------------
// Proxy
// ---------------------------------------------------------------------------

enum ProxyProtocol { http, https, socks5 }

class ProxyEntry {
  final String host;
  final int port;
  final ProxyProtocol protocol;
  int latencyMs;
  bool alive;
  int failures;
  DateTime? lastChecked;

  /// Account id currently using this proxy. Null = free.
  String? assignedTo;

  ProxyEntry({
    required this.host,
    required this.port,
    this.protocol = ProxyProtocol.http,
    this.latencyMs = 0,
    this.alive = false,
    this.failures = 0,
    this.lastChecked,
    this.assignedTo,
  });

  String get key => '$host:$port';
  String get proxyUri => '${protocol.name}://$host:$port';

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'protocol': protocol.name,
        'latencyMs': latencyMs,
        'alive': alive,
        'failures': failures,
        'lastChecked': lastChecked?.toIso8601String(),
        'assignedTo': assignedTo,
      };

  factory ProxyEntry.fromJson(Map<String, dynamic> j) => ProxyEntry(
        host: j['host'] as String? ?? '',
        port: int.tryParse('${j['port']}') ?? 0,
        protocol: ProxyProtocol.values.firstWhere(
          (p) => p.name == j['protocol'],
          orElse: () => ProxyProtocol.http,
        ),
        latencyMs: int.tryParse('${j['latencyMs']}') ?? 0,
        alive: j['alive'] == true,
        failures: int.tryParse('${j['failures']}') ?? 0,
        lastChecked: DateTime.tryParse(j['lastChecked'] as String? ?? ''),
        assignedTo: j['assignedTo'] as String?,
      );

  /// Parse raw "host:port" text lists (proxyscrape / TheSpeedX / monosans).
  static List<ProxyEntry> parseRawList(String raw,
      {ProxyProtocol proto = ProxyProtocol.http}) {
    final pattern = RegExp(r'^(\d{1,3}(?:\.\d{1,3}){3}):(\d{2,5})$');
    final out = <ProxyEntry>[];
    for (final line in raw.split(RegExp(r'[\r\n]+'))) {
      final l = line.trim();
      if (l.isEmpty || l.startsWith('#')) continue;
      final m = pattern.firstMatch(l);
      if (m != null) {
        final port = int.tryParse(m.group(2)!);
        if (port != null && port > 0 && port < 65536) {
          out.add(ProxyEntry(host: m.group(1)!, port: port, protocol: proto));
        }
      }
    }
    return out;
  }

  /// Parse geonode JSON API response.
  static List<ProxyEntry> parseGeonode(String body) {
    final out = <ProxyEntry>[];
    try {
      final decoded = jsonDecode(body);
      final list = decoded is Map
          ? (decoded['data'] as List? ?? const [])
          : (decoded as List? ?? const []);
      for (final item in list) {
        if (item is! Map) continue;
        final host = item['ip'] as String?;
        final port = int.tryParse('${item['port']}');
        if (host == null || port == null) continue;
        final protos = (item['protocols'] as List?)?.cast<String>() ?? const [];
        final proto =
            protos.contains('https') ? ProxyProtocol.https : ProxyProtocol.http;
        out.add(ProxyEntry(host: host, port: port, protocol: proto));
      }
    } catch (_) {}
    return out;
  }
}

// ---------------------------------------------------------------------------
// Account
// ---------------------------------------------------------------------------

enum AccountStatus {
  newAccount, // created but never validated
  idle,
  mining,
  claiming,
  needsOtp,
  needsRelogin,
  error,
  banned,
  disabled,
}

AccountStatus accountStatusFromName(String? name) => AccountStatus.values
    .firstWhere((s) => s.name == name, orElse: () => AccountStatus.newAccount);

class Account {
  final String id;
  String email;
  String label;
  AccountStatus status;
  bool enabled;

  // Automation configuration (per account, isolated).
  bool autoAccelerate;
  int accelerateTargetPct; // 20 / 40 / 60
  bool autoExtension;
  bool autoClaimTasks;

  // Live stats.
  double balance;
  double ratePerHour;
  int boostPct;
  DateTime? sessionEndsAt;
  DateTime? lastCheck;
  DateTime? lastClaim;
  int claimsToday;
  int accelerationsToday;
  int extensionOpensToday;
  String? lastError;

  // Proxy binding.
  String? proxyKey; // "host:port" of currently assigned proxy
  String? proxyLabel; // e.g. "ID · 210ms"

  // mail.tm credential (kept for OTP re-verification when needed).
  bool isTempMailbox;
  String? mailPassword;
  String? mailToken;

  String dayKey; // yyyy-mm-dd for daily counters

  Account({
    required this.id,
    required this.email,
    String? passwordInSecureStore,
    this.label = '',
    this.status = AccountStatus.newAccount,
    this.enabled = true,
    this.autoAccelerate = true,
    this.accelerateTargetPct = 60,
    this.autoExtension = true,
    this.autoClaimTasks = true,
    this.balance = 0,
    this.ratePerHour = 0,
    this.boostPct = 0,
    this.sessionEndsAt,
    this.lastCheck,
    this.lastClaim,
    this.claimsToday = 0,
    this.accelerationsToday = 0,
    this.extensionOpensToday = 0,
    this.lastError,
    this.proxyKey,
    this.proxyLabel,
    this.isTempMailbox = false,
    this.mailPassword,
    this.mailToken,
    String? dayKeyIn,
  }) : dayKey = dayKeyIn ?? _todayKey();

  String get displayName => label.isNotEmpty ? label : email;

  static String _todayKey() {
    final n = DateTime.now().toUtc();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  void rolloverDayIfNeeded() {
    final today = _todayKey();
    if (dayKey != today) {
      dayKey = today;
      claimsToday = 0;
      accelerationsToday = 0;
      extensionOpensToday = 0;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'label': label,
        'status': status.name,
        'enabled': enabled,
        'autoAccelerate': autoAccelerate,
        'accelerateTargetPct': accelerateTargetPct,
        'autoExtension': autoExtension,
        'autoClaimTasks': autoClaimTasks,
        'balance': balance,
        'ratePerHour': ratePerHour,
        'boostPct': boostPct,
        'sessionEndsAt': sessionEndsAt?.toIso8601String(),
        'lastCheck': lastCheck?.toIso8601String(),
        'lastClaim': lastClaim?.toIso8601String(),
        'claimsToday': claimsToday,
        'accelerationsToday': accelerationsToday,
        'extensionOpensToday': extensionOpensToday,
        'lastError': lastError,
        'proxyKey': proxyKey,
        'proxyLabel': proxyLabel,
        'isTempMailbox': isTempMailbox,
        'dayKey': dayKey,
      };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] as String,
        email: j['email'] as String? ?? '',
        label: j['label'] as String? ?? '',
        status: accountStatusFromName(j['status'] as String?),
        enabled: j['enabled'] != false,
        autoAccelerate: j['autoAccelerate'] != false,
        accelerateTargetPct: int.tryParse('${j['accelerateTargetPct']}') ?? 60,
        autoExtension: j['autoExtension'] != false,
        autoClaimTasks: j['autoClaimTasks'] != false,
        balance: double.tryParse('${j['balance']}') ?? 0,
        ratePerHour: double.tryParse('${j['ratePerHour']}') ?? 0,
        boostPct: int.tryParse('${j['boostPct']}') ?? 0,
        sessionEndsAt: DateTime.tryParse(j['sessionEndsAt'] as String? ?? ''),
        lastCheck: DateTime.tryParse(j['lastCheck'] as String? ?? ''),
        lastClaim: DateTime.tryParse(j['lastClaim'] as String? ?? ''),
        claimsToday: int.tryParse('${j['claimsToday']}') ?? 0,
        accelerationsToday: int.tryParse('${j['accelerationsToday']}') ?? 0,
        extensionOpensToday: int.tryParse('${j['extensionOpensToday']}') ?? 0,
        lastError: j['lastError'] as String?,
        proxyKey: j['proxyKey'] as String?,
        proxyLabel: j['proxyLabel'] as String?,
        isTempMailbox: j['isTempMailbox'] == true,
        dayKeyIn: j['dayKey'] as String?,
      );
}

/// Secrets kept in secure storage, one key per account (never in profile file).
class AccountSecrets {
  String password;
  String? accessToken;
  String? refreshToken;
  final Set<String> openedExtensions; // app ids already opened

  AccountSecrets({
    required this.password,
    this.accessToken,
    this.refreshToken,
    Set<String>? openedExtensions,
  }) : openedExtensions = openedExtensions ?? <String>{};

  Map<String, dynamic> toJson() => {
        'password': password,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'openedExtensions': openedExtensions.toList(),
      };

  factory AccountSecrets.fromJson(Map<String, dynamic> j) => AccountSecrets(
        password: j['password'] as String? ?? '',
        accessToken: j['accessToken'] as String?,
        refreshToken: j['refreshToken'] as String?,
        openedExtensions: ((j['openedExtensions'] as List?) ?? const [])
            .cast<String>()
            .toSet(),
      );
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

class AppSettings {
  bool serviceEnabled;
  int intervalMinutes; // 5 default
  bool notifyCycleSummary;
  bool notifyAlerts;
  bool proxyEnabled;
  bool allowDirectFallback;
  int poolTarget;
  int cycleConcurrency;
  String referralCode;

  AppSettings({
    this.serviceEnabled = true,
    this.intervalMinutes = 5,
    this.notifyCycleSummary = true,
    this.notifyAlerts = true,
    this.proxyEnabled = true,
    this.allowDirectFallback = false,
    this.poolTarget = 240,
    this.cycleConcurrency = 6,
    this.referralCode = '',
  });
}
