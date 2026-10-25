/// Isolated Sible Network API client.
///
/// Every account owns its own [SibleApiClient] instance with its own
/// [HttpClient] (own connection pool, own cookie/token state, optional own
/// proxy) so that no request state is ever shared between accounts.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/constants.dart';

class SibleApiException implements Exception {
  final String code;
  final String message;
  final int httpStatus;

  SibleApiException(this.code, this.message, {this.httpStatus = 0});

  bool get isBanned => code == 'ACCOUNT_BANNED';
  bool get isAuthError =>
      code == 'TOKEN_INVALID' || code == 'UNAUTHORIZED' || httpStatus == 401;

  @override
  String toString() => 'SibleApiException($code, $httpStatus): $message';
}

/// Envelope: {"success": bool, "data": ..., "error": {code, message}, "requestId"}
class Envelope {
  final bool success;
  final dynamic data;
  final String? errorCode;
  final String? errorMessage;

  const Envelope({
    required this.success,
    this.data,
    this.errorCode,
    this.errorMessage,
  });

  static Envelope parse(String body, int status) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw SibleApiException(
        'BAD_RESPONSE',
        'Response body is not valid JSON (HTTP $status)',
        httpStatus: status,
      );
    }
    if (decoded is! Map || decoded['success'] is! bool) {
      throw SibleApiException(
        'BAD_ENVELOPE',
        "Response is missing the envelope's `success` field (HTTP $status)",
        httpStatus: status,
      );
    }
    final ok = decoded['success'] as bool;
    if (!ok) {
      final err = decoded['error'];
      final code = err is Map ? '${err['code'] ?? 'UNKNOWN'}' : 'UNKNOWN';
      final msg =
          err is Map ? '${err['message'] ?? 'Unknown error'}' : 'Unknown error';
      return Envelope(success: false, errorCode: code, errorMessage: msg);
    }
    return Envelope(success: true, data: decoded['data']);
  }
}

class AuthTokens {
  final String accessToken;
  final String refreshToken;

  const AuthTokens({required this.accessToken, required this.refreshToken});

  static AuthTokens? fromData(dynamic data) {
    if (data is! Map) return null;
    final tokens = data['tokens'];
    final access =
        (tokens is Map ? tokens['accessToken'] : null) ?? data['accessToken'];
    final refresh =
        (tokens is Map ? tokens['refreshToken'] : null) ?? data['refreshToken'];
    if (access is String && access.isNotEmpty) {
      return AuthTokens(
        accessToken: access,
        refreshToken: refresh is String ? refresh : '',
      );
    }
    return null;
  }
}

class SibleApiClient {
  final HttpClient _http;
  final String? proxyUri;
  AuthTokens? tokens;
  int _refreshInFlight = 0;

  SibleApiClient({this.proxyUri, this.tokens}) : _http = HttpClient();

  /// Whether this client routes through a proxy (isolation guarantee).
  bool get isProxied => proxyUri != null && proxyUri!.isNotEmpty;

  static SibleApiClient create({String? proxyUri, AuthTokens? tokens}) {
    final api = SibleApiClient(proxyUri: proxyUri, tokens: tokens);
    api._http.connectionTimeout = const Duration(seconds: 12);
    if (proxyUri != null && proxyUri.isNotEmpty) {
      // Dart HttpClient supports HTTP(S) proxies via findProxy.
      api._http.findProxy = (uri) => 'PROXY $proxyUri';
    }
    return api;
  }

  Map<String, String> _baseHeaders() => {
        'X-Client-Type': 'mobile',
        'X-App-Platform': 'android',
        'X-App-Version': SibleApi.appVersion,
        'X-App-Build': '${SibleApi.appBuild}',
        'X-App-Distribution': 'apk',
        'Accept': 'application/json',
      };

  /// Executes a request against the Sible API and unwraps the envelope.
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
    bool auth = true,
    bool retryOnAuthFailure = true,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      final status = await _rawRequest(path,
          method: method, body: body, auth: auth, timeout: timeout);
      if (status.ok) return status.envelope!.data;

      final env = status.envelope!;
      if (!env.success) {
        final authProblem = status.httpStatus == 401 ||
            status.httpStatus == 403 ||
            env.errorCode == 'TOKEN_INVALID';
        if (auth &&
            retryOnAuthFailure &&
            authProblem &&
            tokens?.refreshToken != null &&
            (tokens?.refreshToken ?? '').isNotEmpty &&
            attempt == 1 &&
            _refreshInFlight == 0) {
          final refreshed = await refresh();
          if (refreshed) continue;
        }
        throw SibleApiException(
          env.errorCode ?? 'UNKNOWN',
          env.errorMessage ?? 'Unknown error',
          httpStatus: status.httpStatus,
        );
      }
      throw SibleApiException(
        'BAD_RESPONSE',
        'Unexpected response shape (HTTP ${status.httpStatus})',
        httpStatus: status.httpStatus,
      );
    }
  }

  Future<_RawResult> _rawRequest(
    String path, {
    required String method,
    Object? body,
    required bool auth,
    required Duration timeout,
  }) async {
    final uri = Uri.parse('${SibleApi.baseUrl}$path');
    final req = await _http.openUrl(method, uri);
    _baseHeaders().forEach(req.headers.set);
    // Auth header must be set BEFORE the body is added - once req.add() is
    // called the header block freezes ("HTTP headers are not mutable").
    if (auth && tokens?.accessToken != null) {
      req.headers.set(
          HttpHeaders.authorizationHeader, 'Bearer ${tokens!.accessToken}');
    }
    // IMPORTANT: send the body with an explicit Content-Length instead of
    // req.write() (chunked transfer-encoding). Some backends (mail.tm in
    // particular) fail with 504 on chunked request bodies.
    if (body != null) {
      final payload = utf8.encode(jsonEncode(body));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.headers.contentLength = payload.length;
      req.add(payload);
    }
    try {
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join();
      Envelope env;
      try {
        env = Envelope.parse(text, res.statusCode);
      } on SibleApiException catch (e) {
        return _RawResult(
            res.statusCode,
            Envelope(
                success: false, errorCode: e.code, errorMessage: e.message));
      }
      return _RawResult(res.statusCode, env);
    } on TimeoutException {
      throw SibleApiException('TIMEOUT', 'Request timed out: $path');
    } on SocketException catch (e) {
      throw SibleApiException('NETWORK_ERROR', 'Network error: ${e.message}');
    } on HttpException catch (e) {
      throw SibleApiException(
          'PROXY_ERROR', 'Proxy/connection error: ${e.message}');
    }
  }

  /// POST /auth/refresh - returns true when tokens were rotated.
  Future<bool> refresh() async {
    final refreshTok = tokens?.refreshToken;
    if (refreshTok == null || refreshTok.isEmpty) return false;
    _refreshInFlight++;
    try {
      final data = await request('/auth/refresh',
          method: 'POST', body: {'refreshToken': refreshTok}, auth: false);
      final t = AuthTokens.fromData(data);
      if (t == null) return false;
      tokens = t;
      return true;
    } finally {
      _refreshInFlight--;
    }
  }

  // -- Auth -----------------------------------------------------------------

  Future<AuthTokens> login(String email, String password) async {
    // The API expects `identifier` (email OR username), not `email`.
    final data = await request('/auth/login',
        method: 'POST',
        body: {'identifier': email, 'password': password},
        auth: false);
    final t = AuthTokens.fromData(data);
    if (t == null) {
      throw SibleApiException(
          'NO_TOKENS', 'Login succeeded but no tokens returned');
    }
    tokens = t;
    return t;
  }

  Future<void> register({
    required String email,
    required String password,
    String? username,
    String? referralCode,
  }) async {
    await request('/auth/register',
        method: 'POST',
        body: {
          'email': email,
          'password': password,
          if (username != null) 'username': username,
          if (referralCode != null && referralCode.isNotEmpty)
            'referralCode': referralCode,
        },
        auth: false);
  }

  Future<dynamic> verifyOtp(String email, String code,
          {String purpose = 'verify_email'}) =>
      request('/auth/verify-otp',
          method: 'POST',
          body: {'email': email, 'code': code, 'purpose': purpose},
          auth: false);

  /// Verifies an OTP and captures the returned session tokens.
  ///
  /// The API returns `{accessToken, refreshToken, user}` directly from
  /// /auth/verify-otp (both for purpose 'verify_email' and 'login'), so no
  /// separate /auth/login call is needed after verification.
  Future<AuthTokens> verifyOtpForTokens(String email, String code,
      {String purpose = 'verify_email'}) async {
    final data = await verifyOtp(email, code, purpose: purpose);
    final t = AuthTokens.fromData(data);
    if (t == null) {
      throw SibleApiException(
          'NO_TOKENS', 'OTP verified but no tokens returned');
    }
    tokens = t;
    return t;
  }

  Future<void> resendOtp(String email, {String purpose = 'verify_email'}) =>
      request('/auth/resend-otp',
          method: 'POST',
          body: {'email': email, 'purpose': purpose},
          auth: false);

  Future<void> logout() async {
    try {
      await request('/auth/logout', method: 'POST', body: {});
    } finally {
      tokens = null;
    }
  }

  // -- Users ----------------------------------------------------------------

  Future<dynamic> me() => request('/users/me');

  // -- Mining ---------------------------------------------------------------

  Future<dynamic> miningStatus() => request('/mining/status');

  Future<dynamic> startMining() =>
      request('/mining/start', method: 'POST', body: {});

  Future<dynamic> watchAd() => request('/mining/ad', method: 'POST', body: {});

  Future<dynamic> claim() => request('/mining/claim', method: 'POST', body: {});

  Future<dynamic> claimById(String id) => request('/mining/claim/$id');

  // -- Reward tasks ---------------------------------------------------------

  Future<dynamic> rewardTasks() => request('/reward-tasks');

  Future<dynamic> claimTask(String id) =>
      request('/reward-tasks/$id/claim', method: 'POST', body: {});

  Future<dynamic> submitTask(String id, {Object? body}) =>
      request('/reward-tasks/$id/submissions',
          method: 'POST', body: body ?? {});

  // -- Explorer (extension tab) ---------------------------------------------

  Future<dynamic> explorerApps() => request('/explorer');

  Future<dynamic> openExplorerApp(String id) =>
      request('/explorer/${Uri.encodeComponent(id)}/open',
          method: 'POST', body: {});

  // -- Referral (optional stats) --------------------------------------------

  Future<dynamic> referralOverview() => request('/referral/overview');

  void close() {
    _http.close(force: true);
  }
}

class _RawResult {
  final int httpStatus;
  final Envelope? envelope;

  const _RawResult(this.httpStatus, this.envelope);

  bool get ok => envelope != null && envelope!.success;
}
