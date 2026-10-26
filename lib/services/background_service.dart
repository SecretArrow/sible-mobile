/// Background foreground-service wiring (flutter_background_service).
/// The service isolate runs a self-repairing loop: every cycle it reloads
/// settings & accounts from disk, runs all account cycles, updates the
/// persistent notification, and informs the UI isolate.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../core/utils.dart';
import 'account_manager.dart';
import 'account_store.dart';
import 'notification_service.dart';
import 'proxy_engine.dart';
// STATS: earnings recorder in the service isolate.
import 'stats_service.dart';

const String serviceRunNowEvent = 'run_now';
const String serviceStopEvent = 'stop_service';
const String serviceCycleDoneEvent = 'cycle_done';

/// Configure (and start, depending on [enabled]) the background service.
Future<FlutterBackgroundService> configureBackgroundService({
  required bool enabled,
}) async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onServiceStart,
      autoStart: enabled,
      autoStartOnBoot: enabled,
      isForegroundMode: true,
      notificationChannelId: Channels.service,
      initialNotificationTitle: 'Sible Miner',
      initialNotificationContent: 'Background worker starting...',
      foregroundServiceNotificationId: NotificationIds.service,
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(
      onForeground: onServiceStart,
      onBackground: onIosBackground,
    ),
  );
  return service;
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

/// Root directory for all persisted data (works in any isolate).
Future<String> resolveRootDir() async {
  final docs = (await getApplicationDocumentsDirectory()).path;
  return '$docs/sible';
}

@pragma('vm:entry-point')
Future<void> onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  await NotificationService.instance.init();
  final notifications = NotificationService.instance;
  final android = service is AndroidServiceInstance ? service : null;

  bool stopping = false;
  bool cycleInFlight = false;
  int cycleCount = 0;

  Future<AccountManager> buildManager() async {
    final root = await resolveRootDir();
    final store = AccountStore(rootDir: root);
    final engine = ProxyEngine(
      storePathResolver: () => '$root/proxy_pool.json',
      onLog: (m) => debugPrint('[proxy] $m'),
    );
    await engine.load();
    return AccountManager(
      store: store,
      proxyEngine: engine,
      notifications: notifications,
    );
  }

  Future<int> intervalMinutes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt('settings.intervalMinutes') ?? 5;
      return v < 1 ? 5 : v;
    } catch (_) {
      return 5; // corrupted/mismatched prefs must never kill the loop
    }
  }

  Future<void> updateServiceNotification(String text) async {
    try {
      await android?.setForegroundNotificationInfo(
        title: 'Sible Miner',
        content: text,
      );
    } catch (_) {}
  }

  Future<void> runCycleNow() async {
    if (cycleInFlight || stopping) return;
    cycleInFlight = true;
    cycleCount++;
    AccountManager? manager;
    try {
      // buildManager() is INSIDE the try: a plugin/path_provider hiccup must
      // never leave cycleInFlight latched true (permanent silent deadlock).
      manager = await buildManager();
      final prefs = await SharedPreferences.getInstance();
      final concurrency = prefs.getInt('settings.cycleConcurrency') ?? 6;
      final notifySummary =
          prefs.getBool('settings.notifyCycleSummary') ?? true;
      // Mirror automation-relevant settings into the manager (previously
      // these toggles existed in the UI but were silently ignored).
      manager.useProxies = prefs.getBool('settings.proxyEnabled') ?? true;
      manager.allowDirectFallback =
          prefs.getBool('settings.allowDirectFallback') ?? false;
      final notifyAlerts = prefs.getBool('settings.notifyAlerts') ?? true;

      await manager.loadAll();
      await updateServiceNotification(
          'Running cycle #$cycleCount - ${manager.activeAccounts.length} accounts...');
      final summary = await manager.runAllCycles(
        concurrency: concurrency,
        notifyAlerts: notifyAlerts,
        notifySummary: notifySummary,
      );
      final nextMin = await intervalMinutes();
      final nextAt = DateTime.now().add(Duration(minutes: nextMin));
      await updateServiceNotification(
          '${manager.miningCount}/${manager.accounts.length} mining - next check ${clockHHmm(nextAt)}');
      service.invoke(serviceCycleDoneEvent, {
        'accountsRun': summary.accountsRun,
        'success': summary.success,
        'failed': summary.failed,
        'claims': summary.claims,
        'accelerations': summary.accelerations,
        'extensionOpens': summary.extensionOpens,
        'nextCycleAt': nextAt.toIso8601String(),
        'cycleCount': cycleCount,
      });
    } catch (e) {
      debugPrint('[service] cycle error: $e');
      try {
        await updateServiceNotification('Cycle error: $e');
      } catch (_) {}
      service.invoke(serviceCycleDoneEvent, {
        'error': '$e',
        'nextCycleAt':
            DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
      });
    } finally {
      // Release every HttpClient the manager owned (prevents fd exhaustion
      // across hours of background cycles).
      try {
        await manager?.dispose();
      } catch (_) {}
      cycleInFlight = false; // ALWAYS reset - deadlock-proof
    }
  }

  service.on(serviceRunNowEvent).listen((_) {
    // Bulletproof: runCycleNow is fully try/finally guarded internally.
    runCycleNow().catchError((e, st) {
      debugPrint('[service] run-now event error: $e');
      cycleInFlight = false;
    });
  });
  service.on(serviceStopEvent).listen((_) {
    stopping = true;
    service.stopSelf();
  });

  await updateServiceNotification('Worker ready - first check starting...');
  // STATS: attach the earnings recorder in the service isolate.
  try {
    final statsRoot = await resolveRootDir();
    final stats = StatsStore(rootDir: statsRoot);
    await stats.init();
    StatsRecorder.attach(stats);
  } catch (e) {
    debugPrint('[service] stats attach failed: $e');
  }
  // Main loop: sequential non-overlapping cycles. The WHOLE body is guarded
  // so that no exception - from any source - can kill the cron silently
  // while the foreground notification keeps showing "running".
  while (!stopping) {
    try {
      await runCycleNow();
    } catch (e, st) {
      debugPrint('[service] loop cycle error: $e\n$st');
      cycleInFlight = false;
      try {
        await updateServiceNotification('Worker error - retrying soon');
      } catch (_) {}
    }
    try {
      final minutes = await intervalMinutes();
      final deadline = DateTime.now().add(Duration(minutes: minutes));
      while (DateTime.now().isBefore(deadline) && !stopping) {
        await Future<void>.delayed(const Duration(seconds: 20));
      }
    } catch (e) {
      debugPrint('[service] wait error: $e');
      // Fallback sleep so we never spin-hot on repeated failures.
      try {
        await Future<void>.delayed(const Duration(minutes: 1));
      } catch (_) {}
    }
  }
}

/// Ask the running service to execute a cycle immediately (UI "Run now").
void requestRunNow(FlutterBackgroundService service) {
  service.invoke(serviceRunNowEvent);
}

/// Ask the service to stop (user turns the automation off).
Future<void> stopBackgroundService(FlutterBackgroundService service) async {
  service.invoke(serviceStopEvent);
  service.invoke('stopService');
}

/// Ensures data dir exists at first launch.
Future<void> ensureRootDir() async {
  final root = await resolveRootDir();
  await Directory(root).create(recursive: true);
}
