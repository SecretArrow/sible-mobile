/// Facade the automation cycle consults for AI decisions.
///
/// Guarantees: every method is failure-proof - on any error/timeout it
/// returns the caller's fallback (or an empty result) instead of throwing,
/// so the mining automation always degrades gracefully to the static policy.
library;

import 'package:flutter/foundation.dart';

import '../models/inferhub_models.dart';
import 'inferhub_service.dart';

/// Failure-proof bridge between the mining cycle and InferHub.
class InferHubBrain {
  /// Active configuration (feature switches, sampling, caps).
  final InferHubConfig config;

  /// Gateway used for the actual model calls (real service or a fake).
  final InferHubGateway gateway;

  /// Creates a brain from an explicit config + gateway (DI-friendly: unit
  /// tests plug in fakes here instead of touching platform channels).
  InferHubBrain({required this.config, required this.gateway});

  /// Builds the brain from persisted settings, or returns null when the
  /// InferHub integration is disabled, lacks an API key or lacks a model.
  static Future<InferHubBrain?> maybeCreate() async {
    try {
      final settings = await InferHubSettings.load();
      final cfg = settings.config;
      if (!cfg.enabled || settings.apiKey.isEmpty || cfg.model.isEmpty) {
        return null;
      }
      return InferHubBrain(
        config: cfg,
        gateway: InferHubService(config: cfg, apiKey: settings.apiKey),
      );
    } catch (e) {
      debugPrint('[inferhub] brain unavailable: $e');
      return null;
    }
  }

  /// AI acceleration target percent for this session.
  ///
  /// Returns [fallbackPercent] on ANY failure/timeout or when the planner
  /// feature is off - NEVER throws. Success values are already clamped to
  /// 20 / 40 / 60 by [AiAccelerationPlan].
  Future<int> accelerationTargetPercent({
    required int fallbackPercent,
    Map<String, dynamic>? statusRaw,
    int adsWatchedThisSession = 0,
  }) async {
    if (!config.planner) return fallbackPercent;
    try {
      final plan = await gateway.planAcceleration(
        miningStatusRaw: statusRaw ?? const <String, dynamic>{},
        adsWatchedThisSession: adsWatchedThisSession,
        targetBias: '$fallbackPercent',
      );
      debugPrint('[inferhub] acceleration plan: $plan');
      return plan.targetPercent;
    } catch (e) {
      debugPrint(
          '[inferhub] planner failed, static $fallbackPercent% kept: $e');
      return fallbackPercent;
    }
  }

  /// AI submission payload for one reward task.
  ///
  /// Returns null when the solver is disabled, the model declines the task
  /// or anything fails - NEVER throws. On success the map carries
  /// `shouldSubmit`, `submission` and `rationale`.
  Future<Map<String, dynamic>?> taskSubmissionPayload(
      Map<String, dynamic> task) async {
    if (!config.taskSolver) return null;
    try {
      final answer = await gateway.solveRewardTask(task: task);
      debugPrint('[inferhub] task ${task['id']}: $answer');
      if (!answer.shouldSubmit) return null;
      return <String, dynamic>{
        'shouldSubmit': true,
        'submission': answer.submission,
        'rationale': answer.rationale,
      };
    } catch (e) {
      debugPrint('[inferhub] task solver failed: $e');
      return null;
    }
  }

  /// AI-picked explorer app ids (at most 3).
  ///
  /// Returns an empty list on ANY failure or when the picker feature is off
  /// (caller falls back to the static policy) - NEVER throws.
  Future<List<String>> extensionAppIds({
    required List<Map<String, dynamic>> apps,
    required dynamic statusRaw,
  }) async {
    if (!config.extensionPicker) return const [];
    try {
      final ids = await gateway.pickExtensionIds(
        apps: apps,
        statusRaw: statusRaw,
      );
      debugPrint('[inferhub] extension picks: $ids');
      return ids;
    } catch (e) {
      debugPrint('[inferhub] extension picker failed: $e');
      return const [];
    }
  }
}
