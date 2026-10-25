/// Small shared helpers: time formatting, jitter, logging events.
library;

import 'dart:math';

String hhmmss(Duration d) {
  final h = d.inHours,
      m = d.inMinutes.remainder(60),
      s = d.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m}m ${s}s';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

String clockHHmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String timeAgo(DateTime? t) {
  if (t == null) return 'never';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

String compactNumber(num n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(2)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(2)}K';
  return n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 2);
}

final Random rng = Random.secure();

Duration jitter({int baseMs = 800, int spreadMs = 1600}) =>
    Duration(milliseconds: baseMs + rng.nextInt(spreadMs));

String randomToken({int length = 12}) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(length, (_) => chars[rng.nextInt(chars.length)]).join();
}

/// Log levels used across the app.
enum LogLevel { info, success, warn, error }

/// A single activity event (per-account or global).
class LogEvent {
  final DateTime ts;
  final LogLevel level;
  final String category; // auth|mining|accel|extension|task|proxy|system
  final String accountId;
  final String accountLabel;
  final String message;

  const LogEvent({
    required this.ts,
    required this.level,
    required this.category,
    this.accountId = '',
    this.accountLabel = '',
    required this.message,
  });

  Map<String, dynamic> toJson() => {
        'ts': ts.toIso8601String(),
        'level': level.name,
        'category': category,
        'accountId': accountId,
        'accountLabel': accountLabel,
        'message': message,
      };

  factory LogEvent.fromJson(Map<String, dynamic> j) => LogEvent(
        ts: DateTime.tryParse(j['ts'] as String? ?? '') ?? DateTime.now(),
        level: LogLevel.values.firstWhere(
          (l) => l.name == j['level'],
          orElse: () => LogLevel.info,
        ),
        category: j['category'] as String? ?? 'system',
        accountId: j['accountId'] as String? ?? '',
        accountLabel: j['accountLabel'] as String? ?? '',
        message: j['message'] as String? ?? '',
      );
}
