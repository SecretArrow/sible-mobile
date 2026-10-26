/// Dependency wiring + UI-facing state notifiers.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/account_manager.dart';
import '../services/account_store.dart';
import '../services/notification_service.dart';
import '../services/proxy_engine.dart';
// STATS: earnings recorder for the statistics screen.
import '../services/stats_service.dart';

/// SharedPreferences-backed settings with change notifications for the UI.
class SettingsStore extends ChangeNotifier {
  final SharedPreferences prefs;

  SettingsStore(this.prefs);

  bool get serviceEnabled => prefs.getBool('settings.serviceEnabled') ?? true;
  int get intervalMinutes => prefs.getInt('settings.intervalMinutes') ?? 5;
  bool get notifyCycleSummary =>
      prefs.getBool('settings.notifyCycleSummary') ?? true;
  bool get notifyAlerts => prefs.getBool('settings.notifyAlerts') ?? true;
  bool get proxyEnabled => prefs.getBool('settings.proxyEnabled') ?? true;
  bool get allowDirectFallback =>
      prefs.getBool('settings.allowDirectFallback') ?? false;
  int get poolTarget => prefs.getInt('settings.poolTarget') ?? 240;
  int get cycleConcurrency => prefs.getInt('settings.cycleConcurrency') ?? 6;
  String get referralCode => prefs.getString('settings.referralCode') ?? '';

  /// KEEPALIVE: refresh auth tokens every 10 minutes so sessions never expire.
  bool get keepaliveEnabled =>
      prefs.getBool('settings.keepaliveEnabled') ?? true;

  Future<void> setServiceEnabled(bool v) async {
    await prefs.setBool('settings.serviceEnabled', v);
    notifyListeners();
  }

  Future<void> setIntervalMinutes(int v) async {
    await prefs.setInt('settings.intervalMinutes', v);
    notifyListeners();
  }

  Future<void> setNotifyCycleSummary(bool v) async {
    await prefs.setBool('settings.notifyCycleSummary', v);
    notifyListeners();
  }

  Future<void> setNotifyAlerts(bool v) async {
    await prefs.setBool('settings.notifyAlerts', v);
    notifyListeners();
  }

  Future<void> setProxyEnabled(bool v) async {
    await prefs.setBool('settings.proxyEnabled', v);
    notifyListeners();
  }

  Future<void> setAllowDirectFallback(bool v) async {
    await prefs.setBool('settings.allowDirectFallback', v);
    notifyListeners();
  }

  Future<void> setPoolTarget(int v) async {
    await prefs.setInt('settings.poolTarget', v);
    notifyListeners();
  }

  Future<void> setCycleConcurrency(int v) async {
    await prefs.setInt('settings.cycleConcurrency', v);
    notifyListeners();
  }

  Future<void> setReferralCode(String v) async {
    await prefs.setString('settings.referralCode', v);
    notifyListeners();
  }

  Future<void> setKeepaliveEnabled(bool v) async {
    await prefs.setBool('settings.keepaliveEnabled', v);
    notifyListeners();
  }
}

/// Convenience bundle passed through providers.
class AppDependencies {
  final SharedPreferences prefs;
  final SettingsStore settings;
  final AccountStore store;
  final ProxyEngine proxyEngine;
  final AccountManager accountManager;

  AppDependencies._({
    required this.prefs,
    required this.settings,
    required this.store,
    required this.proxyEngine,
    required this.accountManager,
  });

  static Future<AppDependencies> build({required String rootDir}) async {
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsStore(prefs);
    final store = AccountStore(rootDir: rootDir);
    final engine = ProxyEngine(
      storePathResolver: () => '$rootDir/proxy_pool.json',
      onLog: (m) => debugPrint('[proxy-ui] $m'),
    );
    await engine.load();
    final manager = AccountManager(
      store: store,
      proxyEngine: engine,
      notifications: NotificationService.instance,
    );
    // Mirror automation-relevant settings so inline UI cycles behave exactly
    // like service cycles.
    manager
      ..useProxies = settings.proxyEnabled
      ..allowDirectFallback = settings.allowDirectFallback;
    // STATS: attach the earnings recorder (UI isolate).
    try {
      final stats = StatsStore(rootDir: rootDir);
      await stats.init();
      StatsRecorder.attach(stats);
    } catch (_) {}
    return AppDependencies._(
      prefs: prefs,
      settings: settings,
      store: store,
      proxyEngine: engine,
      accountManager: manager,
    );
  }
}
