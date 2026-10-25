/// Global constants for the Sible Miner app.
library;

class SibleApi {
  /// Full REST base. The Expo app builds `${apiUrl}/api/v1` internally
  /// (see bundle: `s = \`${n.apiUrl}/api/v1\``), so all request paths below
  /// are appended to this base.
  static const String baseUrl = 'https://prod.sible.network/api/v1';
  static const String appVersion = '1.2.0';
  static const int appBuild = 20;
}

class MailTm {
  static const String baseUrl = 'https://api.mail.tm';
}

class Limits {
  static const int maxAccounts = 100;
  static const int defaultPoolTarget = 240;
  static const int maxPoolTarget = 500;
  static const int logRingSize = 300;
  static const int globalLogRingSize = 600;
}

/// Acceleration targets - Sible grants +20% per acceleration slot,
/// up to three slots per mining session (20 / 40 / 60%).
class AccelerateTargets {
  static const List<int> percentages = [20, 40, 60];

  /// Number of ads/accelerations needed to reach [percent].
  static int adsFor(int percent) {
    final idx = percentages.indexOf(percent);
    if (idx < 0) return 1;
    return idx + 1;
  }
}

class Channels {
  static const String service = 'sible_service';
  static const String events = 'sible_events';
  static const String alerts = 'sible_alerts';
}

class NotificationIds {
  static const int service = 112233;
  static const int cycleSummary = 2001;
  static const int alertsBase = 3000;
}
