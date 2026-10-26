/// Pure InferHub data models and LLM-output parsing helpers.
///
/// Deliberately framework- and plugin-free (only `dart:convert`): unit tests
/// import this file directly without any Flutter binding.
library;

import 'dart:convert';

/// Minimal AI surface the [InferHubBrain] facade consults.
///
/// Implemented by `InferHubService` (real HTTP gateway); unit tests plug in
/// fakes. Declared here so service and brain share the contract without
/// pulling platform plugins into tests.
abstract class InferHubGateway {
  /// Asks the model for this session's acceleration target.
  Future<AiAccelerationPlan> planAcceleration({
    required dynamic miningStatusRaw,
    required int adsWatchedThisSession,
    required String targetBias,
  });

  /// Asks the model to answer one reward task.
  Future<AiTaskAnswer> solveRewardTask({required Map<String, dynamic> task});

  /// Asks the model which explorer apps to open (at most 3 ids).
  Future<List<String>> pickExtensionIds({
    required List<Map<String, dynamic>> apps,
    required dynamic statusRaw,
  });
}

/// One model entry from GET /v1/models (defensively parsed).
class InferHubModel {
  /// Full addressable id, e.g. `z-ai/glm-4.6` or `free/meta/llama-3`.
  final String id;

  /// True when the model is addressable as `free/...` or has zero prices.
  final bool free;

  /// Advertised context window in tokens, when known.
  final int? contextLength;

  /// USD per million input tokens, when known.
  final double? inputPrice;

  /// USD per million output tokens, when known.
  final double? outputPrice;

  const InferHubModel({
    required this.id,
    this.free = false,
    this.contextLength,
    this.inputPrice,
    this.outputPrice,
  });

  /// Defensive parsing - missing or renamed fields simply fall back to
  /// defaults. Free detection: `free/` id prefix, an explicit `free` flag,
  /// or both prices known and exactly zero.
  static InferHubModel fromJson(dynamic raw) {
    if (raw is! Map) return const InferHubModel(id: '');
    final id = '${raw['id'] ?? raw['model'] ?? raw['name'] ?? ''}';
    final inputKeys = const [
      'inputPrice',
      'input_price',
      'promptPrice',
      'prompt_price',
    ];
    final outputKeys = const [
      'outputPrice',
      'output_price',
      'completionPrice',
      'completion_price',
    ];
    final ctxKeys = const [
      'contextLength',
      'context_length',
      'contextWindow',
      'context_window',
      'context',
      'maxContextLength',
    ];
    final inputPricing = const [
      'input',
      'prompt',
      'input_price',
      'prompt_price',
    ];
    final outputPricing = const [
      'output',
      'completion',
      'output_price',
      'completion_price',
    ];
    final input = _price(raw, inputKeys, inputPricing);
    final output = _price(raw, outputKeys, outputPricing);
    final ctx = _double(raw, ctxKeys);
    final free = id.startsWith('free/') ||
        raw['free'] == true ||
        (input != null && output != null && input == 0 && output == 0);
    return InferHubModel(
      id: id,
      free: free,
      contextLength: ctx?.toInt(),
      inputPrice: input,
      outputPrice: output,
    );
  }

  static double? _price(Map raw, List<String> keys, List<String> nested) {
    final direct = _double(raw, keys);
    if (direct != null) return direct;
    final pricing = raw['pricing'] ?? raw['prices'] ?? raw['cost'];
    if (pricing is Map) {
      for (final k in nested) {
        final v = pricing[k];
        if (v is num) return v.toDouble();
        if (v is String) {
          final d = double.tryParse(v.trim());
          if (d != null) return d;
        }
      }
    }
    return null;
  }

  static double? _double(Map raw, List<String> keys) {
    for (final k in keys) {
      final v = raw[k];
      if (v is num) return v.toDouble();
      if (v is String && v.trim().isNotEmpty) {
        final d = double.tryParse(v.trim());
        if (d != null) return d;
      }
    }
    return null;
  }
}

/// One page of the client-side model search (pure and unit-testable).
class ModelPage {
  /// Models belonging to [page].
  final List<InferHubModel> models;

  /// Requested page, clamped to `0 .. totalPages - 1`.
  final int page;

  /// Always >= 1 (an empty result still reports one empty page).
  final int totalPages;

  /// Number of models matching the query (across all pages).
  final int total;

  const ModelPage({
    required this.models,
    required this.page,
    required this.totalPages,
    required this.total,
  });

  /// Filters [all] by case-insensitive substring on the model id and returns
  /// the requested page, clamped to the valid range. [pageSize] <= 0 falls
  /// back to 20.
  static ModelPage search(
    List<InferHubModel> all, {
    String query = '',
    int page = 0,
    int pageSize = 20,
  }) {
    final size = pageSize <= 0 ? 20 : pageSize;
    final q = query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? all
        : all.where((m) => m.id.toLowerCase().contains(q)).toList();
    final totalPages =
        filtered.isEmpty ? 1 : (filtered.length + size - 1) ~/ size;
    var p = page < 0 ? 0 : page;
    if (p >= totalPages) p = totalPages - 1;
    final models = filtered.skip(p * size).take(size).toList(growable: false);
    return ModelPage(
      models: models,
      page: p,
      totalPages: totalPages,
      total: filtered.length,
    );
  }
}

/// User configuration for the InferHub AI brain.
///
/// [apiKey] is intentionally NOT serialized by [toMap]: the key lives in
/// secure storage (see `InferHubSettings`) and must never reach plain prefs.
class InferHubConfig {
  /// Master switch; when false [InferHubBrain.maybeCreate] returns null.
  final bool enabled;

  /// Bearer API key; in-memory only; never persisted by [toMap].
  final String apiKey;

  /// Default model id used for every AI job (e.g. `z-ai/glm-4.6`).
  final String model;

  /// When true the model picker only lists free models.
  final bool freeOnly;

  /// Per-feature switches (each independent of the master [enabled] toggle).
  final bool taskSolver;
  final bool planner;
  final bool extensionPicker;

  final double temperature;
  final int maxTokens;

  /// Bid caps in USD per Mtok; 0 means "send no cap header".
  final double maxInputPrice;
  final double maxOutputPrice;

  /// Per-request timeout in seconds (clamped to 5..300 when deserialized).
  final int timeoutSeconds;

  const InferHubConfig({
    this.enabled = false,
    this.apiKey = '',
    this.model = '',
    this.freeOnly = false,
    this.taskSolver = true,
    this.planner = true,
    this.extensionPicker = true,
    this.temperature = 0.2,
    this.maxTokens = 512,
    this.maxInputPrice = 0,
    this.maxOutputPrice = 0,
    this.timeoutSeconds = 60,
  });

  /// Copies this config with the given fields replaced.
  InferHubConfig copyWith({
    bool? enabled,
    String? apiKey,
    String? model,
    bool? freeOnly,
    bool? taskSolver,
    bool? planner,
    bool? extensionPicker,
    double? temperature,
    int? maxTokens,
    double? maxInputPrice,
    double? maxOutputPrice,
    int? timeoutSeconds,
  }) {
    return InferHubConfig(
      enabled: enabled ?? this.enabled,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      freeOnly: freeOnly ?? this.freeOnly,
      taskSolver: taskSolver ?? this.taskSolver,
      planner: planner ?? this.planner,
      extensionPicker: extensionPicker ?? this.extensionPicker,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      maxInputPrice: maxInputPrice ?? this.maxInputPrice,
      maxOutputPrice: maxOutputPrice ?? this.maxOutputPrice,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    );
  }

  /// Persisted fields only - the API key is deliberately omitted.
  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'model': model,
        'freeOnly': freeOnly,
        'taskSolver': taskSolver,
        'planner': planner,
        'extensionPicker': extensionPicker,
        'temperature': temperature,
        'maxTokens': maxTokens,
        'maxInputPrice': maxInputPrice,
        'maxOutputPrice': maxOutputPrice,
        'timeoutSeconds': timeoutSeconds,
      };

  /// Defensive deserialization - unknown shapes fall back to defaults.
  /// Note: `apiKey` is never restored from maps (secure-storage only).
  static InferHubConfig fromMap(dynamic raw) {
    if (raw is! Map) return const InferHubConfig();
    bool asBool(Object? v) => v == true || v == 'true';
    double asDouble(Object? v, double fallback) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.trim()) ?? fallback;
      return fallback;
    }

    int asInt(Object? v, int fallback) {
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim()) ?? fallback;
      return fallback;
    }

    final temperature = asDouble(raw['temperature'], 0.2).clamp(0, 2);
    final timeout = asInt(raw['timeoutSeconds'], 60).clamp(5, 300).toInt();
    return InferHubConfig(
      enabled: asBool(raw['enabled']),
      apiKey: '',
      model: '${raw['model'] ?? ''}',
      freeOnly: asBool(raw['freeOnly']),
      taskSolver: raw['taskSolver'] != false && raw['taskSolver'] != 'false',
      planner: raw['planner'] != false && raw['planner'] != 'false',
      extensionPicker:
          raw['extensionPicker'] != false && raw['extensionPicker'] != 'false',
      temperature: temperature.toDouble(),
      maxTokens: asInt(raw['maxTokens'], 512).clamp(1, 100000).toInt(),
      maxInputPrice: asDouble(raw['maxInputPrice'], 0),
      maxOutputPrice: asDouble(raw['maxOutputPrice'], 0),
      timeoutSeconds: timeout,
    );
  }
}

/// AI decision for one session's acceleration target.
class AiAccelerationPlan {
  /// Always one of 20 / 40 / 60 (snapped to the nearest allowed slot).
  final int targetPercent;

  /// Model suggestion to also open an extension app to stretch the session.
  final bool extendSession;

  /// Short (<=140 chars) model explanation, for logs only.
  final String rationale;

  /// Allowed acceleration slots, mirroring `AccelerateTargets.percentages`.
  static const List<int> allowed = [20, 40, 60];

  AiAccelerationPlan({
    required int targetPercent,
    this.extendSession = false,
    this.rationale = '',
  }) : targetPercent = _clampPercent(targetPercent);

  /// Snaps [v] to the nearest allowed slot (below 20 -> 20, above 60 -> 60).
  static int _clampPercent(int v) {
    if (v <= allowed.first) return allowed.first;
    if (v >= allowed.last) return allowed.last;
    var best = allowed.first;
    var bestDist = (v - best).abs();
    for (final a in allowed) {
      final dist = (v - a).abs();
      if (dist < bestDist) {
        best = a;
        bestDist = dist;
      }
    }
    return best;
  }

  /// Parses raw model text ("prose {json} prose" is tolerated).
  ///
  /// Missing fields fall back to defaults; garbage input (no JSON object)
  /// throws [FormatException].
  static AiAccelerationPlan fromLlmText(String text) {
    final decoded = _firstJsonObject(text);
    final pctRaw = decoded['targetPercent'] ??
        decoded['target_percent'] ??
        decoded['percent'];
    final pct =
        pctRaw is num ? pctRaw.toInt() : int.tryParse('${pctRaw ?? ''}') ?? 60;
    final extend =
        decoded['extendSession'] == true || decoded['extend_session'] == true;
    return AiAccelerationPlan(
      targetPercent: pct,
      extendSession: extend,
      rationale: '${decoded['rationale'] ?? decoded['reason'] ?? ''}',
    );
  }

  @override
  String toString() =>
      'AiAccelerationPlan($targetPercent%, extend: $extendSession)';
}

/// AI answer for one reward task.
class AiTaskAnswer {
  /// True when the model says a submission should be sent.
  final bool shouldSubmit;

  /// Arbitrary JSON payload to send to the submission endpoint.
  final Map<String, dynamic> submission;

  /// Short (<=140 chars) model explanation, for logs only.
  final String rationale;

  const AiTaskAnswer({
    this.shouldSubmit = false,
    this.submission = const {},
    this.rationale = '',
  });

  /// Parses raw model text ("prose {json} prose" is tolerated).
  ///
  /// A missing/non-map `submission` falls back to an empty map; garbage
  /// input (no JSON object) throws [FormatException].
  static AiTaskAnswer fromLlmText(String text) {
    final decoded = _firstJsonObject(text);
    final sub = decoded['submission'];
    return AiTaskAnswer(
      shouldSubmit:
          decoded['shouldSubmit'] == true || decoded['should_submit'] == true,
      submission: sub is Map ? Map<String, dynamic>.from(sub) : const {},
      rationale: '${decoded['rationale'] ?? ''}',
    );
  }

  @override
  String toString() => 'AiTaskAnswer(submit: $shouldSubmit, $rationale)';
}

/// Extracts at most [max] unique string ids from a model reply that may wrap
/// a JSON array in prose. Garbage input (no JSON array) throws
/// [FormatException].
List<String> parseExtensionIdsFromLlm(String text, {int max = 3}) {
  final match = RegExp(r'\[[\s\S]*\]').firstMatch(text);
  if (match == null) {
    throw const FormatException('InferHub: no JSON array in model output');
  }
  final decoded = jsonDecode(match.group(0)!);
  if (decoded is! List) {
    throw const FormatException('InferHub: JSON is not an array');
  }
  final out = <String>[];
  for (final e in decoded) {
    if (e is! String) continue;
    final s = e.trim();
    if (s.isEmpty) continue;
    if (!out.contains(s)) out.add(s);
    if (out.length >= max) break;
  }
  return out;
}

Map<String, dynamic> _firstJsonObject(String text) {
  final match = RegExp(r'\{[\s\S]*\}').firstMatch(text);
  if (match == null) {
    throw const FormatException('InferHub: no JSON object in model output');
  }
  final decoded = jsonDecode(match.group(0)!);
  if (decoded is! Map) {
    throw const FormatException('InferHub: JSON is not an object');
  }
  return Map<String, dynamic>.from(decoded);
}
