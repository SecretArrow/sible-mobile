/// InferHub (https://inferhub.dev) client: OpenAI-compatible inference API
/// plus the management API, and the persisted settings (prefs + secure
/// storage) that drive the optional AI brain.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../models/inferhub_models.dart';

/// Error raised by every InferHub call, with a stable machine-readable
/// [code] (TIMEOUT, UNAUTHORIZED, CAPACITY_SATURATED,
/// NO_PROVIDER_UNDER_BID, NO_API_KEY, NO_MODEL, BAD_RESPONSE,
/// NETWORK_ERROR, HTTP_ERROR, HTTP_<status>).
class InferHubException implements Exception {
  /// Stable machine-readable error code (see the class doc for the list).
  final String code;

  /// Human-readable error message (may come from the gateway error body).
  final String message;

  /// HTTP status of the failing response (0 for non-HTTP failures).
  final int httpStatus;

  /// Milliseconds to wait before a retry (from `Retry-After`), if any.
  final int? retryAfterMs;

  const InferHubException(
    this.code,
    this.message, {
    this.httpStatus = 0,
    this.retryAfterMs,
  });

  @override
  String toString() => 'InferHubException($code, $httpStatus): $message';
}

/// Persisted InferHub settings.
///
/// The config lives in SharedPreferences under `inferhub.*` keys; the API
/// key lives in FlutterSecureStorage (`inferhub.apiKey`) and is never
/// written to plain prefs. A process-wide memo keeps per-cycle reloads cheap
/// (the settings only change through [save]).
class InferHubSettings {
  static const _configKey = 'inferhub.config';
  static const _apiKeyStoreKey = 'inferhub.apiKey';

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// User configuration (feature switches, sampling, caps).
  final InferHubConfig config;

  /// Bearer API key from secure storage (empty when not configured).
  final String apiKey;

  const InferHubSettings({required this.config, required this.apiKey});

  static InferHubSettings? _memo;

  /// Loads settings (memoized; pass `force: true` to bypass the memo).
  static Future<InferHubSettings> load({bool force = false}) async {
    if (!force) {
      final m = _memo;
      if (m != null) return m;
    }
    final prefs = await SharedPreferences.getInstance();
    final config =
        InferHubConfig.fromMap(_decodeMap(prefs.getString(_configKey)));
    final apiKey = await _secure.read(key: _apiKeyStoreKey) ?? '';
    return _memo = InferHubSettings(config: config, apiKey: apiKey);
  }

  /// Persists config + API key and refreshes the process-wide memo.
  static Future<InferHubSettings> save({
    required InferHubConfig config,
    required String apiKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(config.toMap()));
    if (apiKey.isEmpty) {
      await _secure.delete(key: _apiKeyStoreKey);
    } else {
      await _secure.write(key: _apiKeyStoreKey, value: apiKey);
    }
    return _memo = InferHubSettings(config: config, apiKey: apiKey);
  }

  static Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Corrupt config -> fall back to defaults.
    }
    return const {};
  }
}

/// Thin HTTP client for the InferHub gateway (one-shot HttpClient per
/// request, explicit content-length bodies, per-call timeout).
class InferHubService implements InferHubGateway {
  /// Snapshot of the user configuration (caps, timeout, defaults).
  final InferHubConfig config;

  /// Bearer API key (`sk-airo-...`); empty means "not configured".
  final String apiKey;

  InferHubService({required this.config, required this.apiKey});

  Duration get _timeout => Duration(seconds: config.timeoutSeconds);

  // ---------------------------------------------------------------------------
  // Model catalog
  // ---------------------------------------------------------------------------

  List<InferHubModel>? _modelsCache;
  DateTime? _modelsCacheAt;
  static const _modelsTtl = Duration(minutes: 5);

  /// GET /v1/models with a 5-minute in-memory cache and defensive parsing.
  Future<List<InferHubModel>> fetchModels({bool force = false}) async {
    final cached = _modelsCache;
    final at = _modelsCacheAt;
    if (!force &&
        cached != null &&
        at != null &&
        DateTime.now().difference(at) < _modelsTtl) {
      return cached;
    }
    final decoded =
        await _getJson(Uri.parse('${InferHub.inferenceBaseUrl}/models'));
    final List items = decoded is Map
        ? (decoded['data'] as List? ?? const [])
        : decoded is List
            ? decoded
            : const [];
    final models = items
        .whereType<Map>()
        .map(InferHubModel.fromJson)
        .where((m) => m.id.isNotEmpty)
        .toList(growable: false);
    _modelsCache = models;
    _modelsCacheAt = DateTime.now();
    return models;
  }

  /// Pure client-side search + pagination over already-fetched models
  /// (delegates to [ModelPage.search]).
  static ModelPage searchModels(
    List<InferHubModel> models, {
    String query = '',
    int page = 0,
    int pageSize = InferHub.modelPageSize,
  }) =>
      ModelPage.search(models, query: query, page: page, pageSize: pageSize);

  // ---------------------------------------------------------------------------
  // Chat completions
  // ---------------------------------------------------------------------------

  /// POST /v1/chat/completions (OpenAI shape). Sends the bid-cap headers
  /// only when the configured price caps are > 0, and retries exactly once
  /// on 429 when `Retry-After` is <= 5s. Throws [InferHubException].
  @override
  Future<String> chat({
    required List<Map<String, String>> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    final m = model ?? config.model;
    final temp = temperature ?? config.temperature;
    final tokens = maxTokens ?? config.maxTokens;
    try {
      return await _sendChat(
        messages: messages,
        model: m,
        temperature: temp,
        maxTokens: tokens,
      );
    } on InferHubException catch (e) {
      final wait = e.retryAfterMs;
      if (e.httpStatus == 429 && wait != null && wait > 0 && wait <= 5000) {
        await Future<void>.delayed(Duration(milliseconds: wait));
        return _sendChat(
          messages: messages,
          model: m,
          temperature: temp,
          maxTokens: tokens,
        );
      }
      rethrow;
    }
  }

  Future<String> _sendChat({
    required List<Map<String, String>> messages,
    required String model,
    required double temperature,
    required int maxTokens,
  }) async {
    _requireConfig();
    if (model.isEmpty) {
      throw const InferHubException('NO_MODEL', 'InferHub model not set');
    }
    final uri = Uri.parse('${InferHub.inferenceBaseUrl}/chat/completions');
    final payload = utf8.encode(jsonEncode({
      'model': model,
      'messages': messages,
      'temperature': temperature,
      'max_tokens': maxTokens,
      'stream': false,
    }));
    try {
      final http = HttpClient();
      try {
        final req = await http.openUrl('POST', uri).timeout(_timeout);
        req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        req.headers.set(HttpHeaders.acceptHeader, 'application/json');
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
        if (config.maxInputPrice > 0) {
          req.headers.set('x-max-input-price', '${config.maxInputPrice}');
        }
        if (config.maxOutputPrice > 0) {
          req.headers.set('x-max-output-price', '${config.maxOutputPrice}');
        }
        req.headers.contentLength = payload.length;
        req.add(payload);
        final res = await req.close().timeout(_timeout);
        final text = await res.transform(utf8.decoder).join().timeout(_timeout);
        if (res.statusCode >= 400) {
          throw _fromStatus(res.statusCode, text, res.headers);
        }
        return _extractContent(text);
      } finally {
        http.close(force: true);
      }
    } on InferHubException {
      rethrow;
    } on TimeoutException {
      throw const InferHubException('TIMEOUT', 'InferHub request timed out');
    } on SocketException catch (e) {
      throw InferHubException('NETWORK_ERROR', 'Network error: ${e.message}');
    } on HttpException catch (e) {
      throw InferHubException('HTTP_ERROR', 'HTTP error: ${e.message}');
    } on FormatException catch (e) {
      throw InferHubException('BAD_RESPONSE', 'Bad response: ${e.message}');
    }
  }

  // ---------------------------------------------------------------------------
  // Management API
  // ---------------------------------------------------------------------------

  /// GET /api/me -> account balance (USDC decimal string). Throws
  /// [InferHubException] on any failure.
  Future<String> testConnection() async {
    _requireConfig();
    final me = await _getJson(Uri.parse('${InferHub.managementBaseUrl}/me'));
    if (me is! Map) {
      throw const InferHubException('BAD_RESPONSE', '/me is not an object');
    }
    final account = me['account'];
    for (final k in const [
      'balance',
      'usdcBalance',
      'credits',
      'walletBalance',
    ]) {
      final v = me[k] ?? (account is Map ? account[k] : null);
      if (v is num) return '$v';
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '0';
  }

  // ---------------------------------------------------------------------------
  // AI jobs (InferHubGateway)
  // ---------------------------------------------------------------------------

  /// Asks the model for this session's acceleration target (20/40/60).
  @override
  Future<AiAccelerationPlan> planAcceleration({
    required dynamic miningStatusRaw,
    required int adsWatchedThisSession,
    required String targetBias,
  }) async {
    const system = 'You are the acceleration planner of an autonomous Sible '
        'Network mining bot. Each acceleration slot adds +20% hashrate and a '
        'session supports at most 3 slots. Pick the boost target percent for '
        'this session. Respond ONLY with compact JSON '
        '{"targetPercent": 20|40|60, "extendSession": true|false, '
        '"rationale": "max 140 chars"}. No prose, no markdown.';
    final user = jsonEncode({
      'today': DateTime.now().toUtc().toIso8601String(),
      'staticPolicyTargetPercent': targetBias,
      'adsWatchedThisSession': adsWatchedThisSession,
      'miningStatus': miningStatusRaw,
    });
    final text = await chat(messages: [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ]);
    return AiAccelerationPlan.fromLlmText(text);
  }

  /// Asks the model to answer one reward task.
  @override
  Future<AiTaskAnswer> solveRewardTask(
      {required Map<String, dynamic> task}) async {
    final now = DateTime.now().toUtc();
    final today = now.toIso8601String().split('T').first;
    final system = 'You solve Sible Network reward tasks autonomously. Today '
        'is $today. Decide whether a submission should be sent and craft it. '
        'Respond ONLY with compact JSON {"shouldSubmit": true|false, '
        '"submission": {...}, "rationale": "max 140 chars"}. '
        'No prose, no markdown.';
    final text = await chat(messages: [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': jsonEncode(task)},
    ]);
    return AiTaskAnswer.fromLlmText(text);
  }

  /// Asks the model which explorer apps to open (at most 3 ids).
  @override
  Future<List<String>> pickExtensionIds({
    required List<Map<String, dynamic>> apps,
    required dynamic statusRaw,
  }) async {
    const system = 'You pick explorer (extension) apps for a running Sible '
        'mining session; opening an app may extend the session. From the '
        'given apps, return ONLY a compact JSON array of at most 3 app ids '
        'most likely to extend the mining session. No prose, no markdown.';
    final text = await chat(messages: [
      {'role': 'system', 'content': system},
      {
        'role': 'user',
        'content': jsonEncode({'status': statusRaw, 'apps': apps}),
      },
    ]);
    return parseExtensionIdsFromLlm(text);
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _requireConfig() {
    if (apiKey.isEmpty) {
      throw const InferHubException('NO_API_KEY', 'InferHub API key not set');
    }
  }

  Future<dynamic> _getJson(Uri uri) async {
    _requireConfig();
    try {
      final http = HttpClient();
      try {
        final req = await http.openUrl('GET', uri).timeout(_timeout);
        req.headers.set(HttpHeaders.acceptHeader, 'application/json');
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
        final res = await req.close().timeout(_timeout);
        final text = await res.transform(utf8.decoder).join().timeout(_timeout);
        if (res.statusCode >= 400) {
          throw _fromStatus(res.statusCode, text, null);
        }
        return jsonDecode(text);
      } finally {
        http.close(force: true);
      }
    } on InferHubException {
      rethrow;
    } on TimeoutException {
      throw const InferHubException('TIMEOUT', 'InferHub request timed out');
    } on SocketException catch (e) {
      throw InferHubException('NETWORK_ERROR', 'Network error: ${e.message}');
    } on HttpException catch (e) {
      throw InferHubException('HTTP_ERROR', 'HTTP error: ${e.message}');
    } on FormatException catch (e) {
      throw InferHubException('BAD_RESPONSE', 'Bad response: ${e.message}');
    }
  }

  InferHubException _fromStatus(
      int status, String body, HttpHeaders? headers) {
    var code = 'HTTP_$status';
    var message = 'HTTP $status';
    int? retryAfterMs;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final err = decoded['error'];
        if (err is Map) {
          code = '${err['code'] ?? code}';
          message = '${err['message'] ?? message}';
        }
      }
    } catch (_) {
      // Non-JSON error body -> keep the HTTP fallback code.
    }
    if (status == 401) code = 'UNAUTHORIZED';
    if (status == 402) code = 'NO_PROVIDER_UNDER_BID';
    if (status == 429) {
      code = 'CAPACITY_SATURATED';
      final ra = headers?.value(HttpHeaders.retryAfterHeader);
      final seconds = ra == null ? null : int.tryParse(ra.trim());
      retryAfterMs = (seconds ?? 2) * 1000;
    }
    return InferHubException(
      code,
      message,
      httpStatus: status,
      retryAfterMs: retryAfterMs,
    );
  }

  String _extractContent(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('chat response is not an object');
    }
    final choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      final message = first is Map ? first['message'] : null;
      final content = message is Map ? message['content'] : null;
      if (content is String && content.isNotEmpty) return content;
    }
    throw const FormatException('choices[0].message.content missing');
  }
}
