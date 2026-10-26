/// Global constants for the Sible Miner app.
library;

class SibleApi {
  /// Full REST base. The Expo app builds `${apiUrl}/api/v1` internally
  /// (see bundle: `s = \`${n.apiUrl}/api/v1\``), so all request paths below
  /// are appended to this base.
  static const String baseUrl = 'https://prod.sible.network/api/v1';
  static const String appVersion = '2.2.0';
  static const int appBuild = 23;
}

/// InferHub LLM inference gateway (https://inferhub.dev/docs).
///
/// OpenAI-compatible surface used as the optional "AI brain" of the
/// automation: reward-task solving, acceleration planning (20/40/60%)
/// and extension (explorer app) picking.
class InferHub {
  /// OpenAI-compatible inference base (append `/chat/completions` etc).
  static const String inferenceBaseUrl = 'https://api.inferhub.dev/v1';

  /// Management API base (model catalog, account info).
  static const String managementBaseUrl = 'https://inferhub.dev/api';

  static const String docsUrl = 'https://inferhub.dev/docs';
  static const Duration defaultTimeout = Duration(seconds: 60);

  /// Models list page size used by the in-app picker.
  static const int modelPageSize = 20;
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
