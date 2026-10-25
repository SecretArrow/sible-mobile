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

  static final Random _rng = Random.secure();

  static String randomPassword([int len = 16]) {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#\$';
    return List.generate(len, (_) => chars[_rng.nextInt(chars.length)]).join();
  }

  static String randomLocalPart([String prefix = 'sibler']) {
    final n = 1000 + _rng.nextInt(90000);
    return '$prefix$n';
  }

  Future<Map<String, dynamic>?> _request(
    String method,
    String path, {
    Object? body,
    String? bearer,
    int retries = 2,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        final req =
            await _http.openUrl(method, Uri.parse('${MailTm.baseUrl}$path'));
        req.headers.set(HttpHeaders.acceptHeader, 'application/json');
        if (body != null) {
          req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        }
        if (bearer != null) {
          req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
        }
        if (body != null) req.write(jsonEncode(body));
        final res = await req.close().timeout(const Duration(seconds: 20));
        final text = await res.transform(utf8.decoder).join();
        if (res.statusCode == 429 && attempt <= retries) {
          await Future<void>.delayed(Duration(
              seconds:
                  int.tryParse(res.headers.value('retry-after') ?? '') ?? 4));
          continue;
        }
        if (res.statusCode >= 400) {
          throw MailTmException('mail.tm error (HTTP ${res.statusCode}): $text',
              status: res.statusCode);
        }
        if (text.isEmpty) return null;
        return jsonDecode(text) as Map<String, dynamic>;
      } on TimeoutException {
        if (attempt > retries) rethrow;
      }
    }
  }

  /// Available active domains.
  Future<List<String>> domains() async {
    final data = await _request('GET', '/domains');
    final items = (data?['hydra:member'] ??
        data?['member'] ??
        data?['data'] ??
        []) as List;
    return items
        .whereType<Map>()
        .map((m) => m['domain'] as String?)
        .whereType<String>()
        .toList();
  }

  /// Create a mailbox and authenticate it.
  Future<MailTmAccount> createAccount(
      {String prefix = 'sibler', String? password}) async {
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
    final token = tokenData?['token'] as String?;
    if (token == null) {
      throw MailTmException('mail.tm token missing after login');
    }
    return MailTmAccount(
        address: '$local@$domain', password: pass, token: token);
  }

  Future<List<Map<String, dynamic>>> messages(String bearer) async {
    final data = await _request('GET', '/messages?page=1', bearer: bearer);
    final items =
        (data?['hydra:member'] ?? data?['member'] ?? const []) as List;
    return items.whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>> message(String bearer, String id) =>
      _request('GET', '/messages/$id', bearer: bearer)
          as Future<Map<String, dynamic>>;

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
  Future<String> waitForOtp(
    MailTmAccount box, {
    Duration timeout = const Duration(minutes: 3),
    Duration pollEvery = const Duration(seconds: 6),
    String senderFilter = 'sible',
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final msgs = await messages(box.token);
      for (final m in msgs) {
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
