/// mail.tm disposable mailbox service - used for creating & verifying
/// throwaway test accounts (see https://docs.mail.tm).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../core/constants.dart';

class MailTmAccount {
  final String address;
  final String password;
  final String token; // bearer token for mailbox APIs

  const MailTmAccount({
    required this.address,
    required this.password,
    required this.token,
  });
}

class MailTmException implements Exception {
  final String message;
  final int? status;
  MailTmException(this.message, {this.status});

  @override
  String toString() => 'MailTmException($status): $message';
}

class MailTmService {
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);

  /// mail.tm allows 30 requests / 60s per IP (ratelimit-policy header).
  /// Stay comfortably below by spacing requests out client-side.
  static const Duration _minInterval = Duration(milliseconds: 2600);

  /// POST /accounts has its own stricter policy: 1 creation / 60s.
  static const Duration _createInterval = Duration(seconds: 62);
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastCreateAt = DateTime.fromMillisecondsSinceEpoch(0);

  static final Random _rng = Random.secure();

  static String randomPassword([int len = 16]) {
    const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz';
    const digits = '23456789';
    const symbols = '!@#\$';
    const all = letters + digits + symbols;
    // The API enforces "must contain a letter and a number" - guarantee both
    // by seeding one of each, then filling the rest randomly.
    final rng = Random.secure();
    final sb = StringBuffer()
      ..write(letters[rng.nextInt(letters.length)])
      ..write(digits[rng.nextInt(digits.length)]);
    for (var i = 2; i < (len < 3 ? 3 : len); i++) {
      sb.write(all[rng.nextInt(all.length)]);
    }
    final chars = sb.toString().split('')..shuffle(rng);
    return chars.join();
  }

  static String randomLocalPart([String prefix = 'sibler']) {
    final n = 1000 + _rng.nextInt(90000);
    return '$prefix$n';
  }

  /// Returns the decoded JSON body: a Map for object endpoints, or a List
  /// for collection endpoints (mail.tm now returns plain arrays for
  /// /domains and /messages in addition to legacy hydra envelopes).
  Future<Object?> _request(
    String method,
    String path, {
    Object? body,
    String? bearer,
    int retries = 4,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      // Client-side pacing to avoid the 30 req/min server limit.
      final since = DateTime.now().difference(_lastAt);
      if (since < _minInterval) {
        await Future<void>.delayed(_minInterval - since);
      }
      _lastAt = DateTime.now();
      try {
        final req =
            await _http.openUrl(method, Uri.parse('${MailTm.baseUrl}$path'));
        req.headers.set(HttpHeaders.acceptHeader, 'application/json');
        if (bearer != null) {
          req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
        }
        // IMPORTANT: send the body with an explicit Content-Length.
        // req.write() would use chunked transfer-encoding, which the mail.tm
        // backend cannot handle (upstream 504 after ~10s every time).
        if (body != null) {
          final payload = utf8.encode(jsonEncode(body));
          req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
          req.headers.contentLength = payload.length;
          req.add(payload);
        }
        final res = await req.close().timeout(const Duration(seconds: 30));
        final text = await res.transform(utf8.decoder).join();
        if (res.statusCode == 429 && attempt <= retries) {
          final ra = int.tryParse(res.headers.value('retry-after') ?? '');
          await Future<void>.delayed(
              Duration(seconds: ra ?? (8 + 4 * attempt)));
          continue;
        }
        // Transient gateway errors: retry with short backoff.
        if (res.statusCode >= 500 && attempt <= retries) {
          await Future<void>.delayed(Duration(seconds: 2 * attempt));
          continue;
        }
        if (res.statusCode >= 400) {
          throw MailTmException('mail.tm error (HTTP ${res.statusCode}): $text',
              status: res.statusCode);
        }
        if (text.isEmpty) return null;
        return jsonDecode(text);
      } on TimeoutException {
        if (attempt > retries) rethrow;
      }
    }
  }

  /// Extracts collection items from either a plain JSON array or a
  /// legacy hydra/mercure envelope ({"hydra:member": [...]}).
  static List<dynamic> _itemsOf(Object? data) {
    if (data is List) return data;
    if (data is Map) {
      final v = data['hydra:member'] ??
          data['member'] ??
          data['data'] ??
          data['items'] ??
          const [];
      return v is List ? v : const [];
    }
    return const [];
  }

  /// Available active domains.
  Future<List<String>> domains() async {
    final data = await _request('GET', '/domains');
    return _itemsOf(data)
        .whereType<Map>()
        .map((m) => m['domain'] as String?)
        .whereType<String>()
        .toList();
  }

  /// Create a mailbox and authenticate it.
  ///
  /// Retries the whole flow with a FRESH random address on transient errors
  /// (5xx blips) or "already used" collisions — the server may have actually
  /// provisioned a mailbox even when it answered 504.
  Future<MailTmAccount> createAccount(
      {String prefix = 'sibler', String? password}) async {
    MailTmException? lastErr;
    for (var outer = 1; outer <= 3; outer++) {
      // Respect the 1-per-minute creation policy.
      final sinceCreate = DateTime.now().difference(_lastCreateAt);
      if (sinceCreate < _createInterval) {
        await Future<void>.delayed(_createInterval - sinceCreate);
      }
      _lastCreateAt = DateTime.now();
      try {
        final domainsList = await domains();
        if (domainsList.isEmpty) {
          throw MailTmException('No mail.tm domains available');
        }
        final domain = domainsList.first;
        final local = randomLocalPart(prefix);
        final pass = password ?? randomPassword();

        await _request('POST', '/accounts',
            body: {'address': '$local@$domain', 'password': pass});
        final tokenData = await _request('POST', '/token',
            body: {'address': '$local@$domain', 'password': pass});
        final token = tokenData is Map ? tokenData['token'] as String? : null;
        if (token == null) {
          throw MailTmException('mail.tm token missing after login');
        }
        return MailTmAccount(
            address: '$local@$domain', password: pass, token: token);
      } on MailTmException catch (e) {
        lastErr = e;
        final transient =
            (e.status ?? 0) >= 500 || e.message.contains('already used');
        if (!transient || outer == 3) rethrow;
        await Future<void>.delayed(Duration(seconds: 5 * outer));
      }
    }
    throw lastErr ?? MailTmException('createAccount failed');
  }

  Future<List<Map<String, dynamic>>> messages(String bearer) async {
    final data = await _request('GET', '/messages?page=1', bearer: bearer);
    return _itemsOf(data).whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>> message(String bearer, String id) async {
    final data = await _request('GET', '/messages/$id', bearer: bearer);
    if (data is! Map) {
      throw MailTmException('unexpected message payload for $id');
    }
    return Map<String, dynamic>.from(data);
  }

  /// Extract a 6-digit OTP from an email body (plain or HTML).
  static String? extractOtp(String body) {
    final cleaned = body.replaceAll(RegExp(r'<[^>]+>'), ' ');
    final patterns = [
      RegExp(r'\b(\d{6})\b'),
      RegExp(r'otp[^0-9]{0,24}(\d{6})', caseSensitive: false),
      RegExp(r'code[^0-9]{0,24}(\d{6})', caseSensitive: false),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(cleaned);
      if (m != null) return m.group(1);
    }
    return null;
  }

  /// Poll the mailbox until an OTP for [email] arrives or [timeout] elapses.
  ///
  /// [after] skips messages created before this timestamp, [skipIds] ignores
  /// specific message ids (e.g. emails already present before we triggered a
  /// fresh OTP challenge). Messages are processed newest-first so the most
  /// recent code always wins.
  Future<String> waitForOtp(
    MailTmAccount box, {
    Duration timeout = const Duration(minutes: 3),
    Duration pollEvery = const Duration(seconds: 6),
    String senderFilter = 'sible',
    DateTime? after,
    Set<String> skipIds = const {},
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final msgs = await messages(box.token);
      // Newest first so that, with several matching emails, the latest code
      // is tried before older (already-used) ones.
      msgs.sort((x, y) {
        final tx = DateTime.tryParse('${x['createdAt'] ?? ''}');
        final ty = DateTime.tryParse('${y['createdAt'] ?? ''}');
        return (ty ?? DateTime.now()).compareTo(tx ?? DateTime.now());
      });
      for (final m in msgs) {
        final id = '${m['id'] ?? ''}';
        if (id.isNotEmpty && skipIds.contains(id)) continue;
        if (after != null) {
          final createdAt = DateTime.tryParse('${m['createdAt'] ?? ''}');
          if (createdAt != null && createdAt.isBefore(after)) continue;
        }
        final from =
            (m['from'] is Map ? m['from']['address'] : '${m['from']}') ?? '';
        final subject = '${m['subject'] ?? ''}'.toLowerCase();
        final matchesFilter = senderFilter.isEmpty ||
            from.toLowerCase().contains(senderFilter) ||
            subject.contains(senderFilter);
        if (!matchesFilter) continue;
        try {
          final full = await message(box.token, '${m['id']}');
          final text = [
            '${full['intro'] ?? ''}',
            '${full['text'] ?? ''}',
            (full['html'] is List
                ? (full['html'] as List).join(' ')
                : '${full['html'] ?? ''}'),
          ].join('\n');
          final otp = extractOtp(text);
          if (otp != null) return otp;
        } catch (_) {}
      }
      await Future<void>.delayed(pollEvery);
    }
    throw MailTmException('OTP not received in time for ${box.address}');
  }

  void close() => _http.close(force: true);
}
