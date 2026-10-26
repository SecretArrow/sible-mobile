/// App root: MaterialApp + theme + navigation shell with 6 tabs.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/i18n.dart';
import 'core/theme.dart';
import 'services/account_manager.dart';
// KEEPALIVE: 10-minute token refresher for the UI isolate.
import 'services/token_keepalive.dart';
import 'state/providers.dart';
import 'ui/screens/accounts_screen.dart';
import 'ui/screens/dashboard_screen.dart';
import 'ui/screens/lock_screen.dart';
import 'ui/screens/logs_screen.dart';
import 'ui/screens/proxies_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/stats_screen.dart';

class SibleMinerApp extends StatefulWidget {
  final AppDependencies deps;

  const SibleMinerApp({super.key, required this.deps});

  @override
  State<SibleMinerApp> createState() => _SibleMinerAppState();
}

class _SibleMinerAppState extends State<SibleMinerApp>
    with WidgetsBindingObserver {
  Timer? _uiKeepaliveTimer;
  bool _keepaliveInFlight = false;
  DateTime _lastKeepalive = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // I18N: restore the persisted app language before first frame.
    SharedPreferences.getInstance()
        .then((p) => LocaleController.instance.loadFrom(
              p.getString('settings.lang'),
            ))
        .catchError((_) {});
    _startUiKeepalive();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _uiKeepaliveTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the foreground: tokens may have aged while backgrounded
    // (UI timers pause in background) - refresh immediately, then resume the
    // 10-minute cadence.
    if (state == AppLifecycleState.resumed) {
      _runUiKeepalive(force: true);
    }
  }

  void _startUiKeepalive() {
    _uiKeepaliveTimer?.cancel();
    _uiKeepaliveTimer = Timer.periodic(TokenKeepalive.interval, (_) {
      _runUiKeepalive();
    });
    // First pass after a short settle delay.
    Future<void>.delayed(const Duration(seconds: 30), () {
      if (mounted) _runUiKeepalive();
    });
  }

  /// UI-isolate keepalive pass. The background service runs the same pass in
  /// its own isolate; when the automation service is ON we skip here to avoid
  /// double refresh races on refresh-token rotation. Fully guarded.
  Future<void> _runUiKeepalive({bool force = false}) async {
    if (_keepaliveInFlight || !mounted) return;
    // Respect the minimum cadence unless forced (app resumed).
    if (!force &&
        DateTime.now().difference(_lastKeepalive) < TokenKeepalive.interval) {
      return;
    }
    _keepaliveInFlight = true;
    _lastKeepalive = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('settings.keepaliveEnabled') ?? true;
      final serviceOn = prefs.getBool('settings.serviceEnabled') ?? true;
      if (!enabled || serviceOn) return;
      await TokenKeepalive.run(widget.deps.accountManager);
    } catch (e) {
      // Never crash the shell over a keepalive hiccup.
      debugPrint('[keepalive-ui] $e');
    } finally {
      _keepaliveInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppDependencies>.value(value: widget.deps),
        ChangeNotifierProvider<SettingsStore>.value(
            value: widget.deps.settings),
        ChangeNotifierProvider<AccountManager>.value(
            value: widget.deps.accountManager),
      ],
      // I18N: rebuild MaterialApp when the user switches language.
      child: ListenableBuilder(
        listenable: LocaleController.instance,
        builder: (context, _) => I18nScope(
          lang: LocaleController.instance.lang,
          child: MaterialApp(
            title: 'Sible Miner',
            debugShowCheckedModeBanner: false,
            theme: SibleTheme.dark(),
            // SECURITY: biometric lock gate wraps every route.
            builder: (context, child) => LockGate(
              child: child ?? const SizedBox.shrink(),
            ),
            home: const HomeShell(),
          ),
        ),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final mgr = context.watch<AccountManager>();
    final pages = <Widget>[
      const DashboardScreen(),
      const AccountsScreen(),
      const StatsScreen(),
      const ProxiesScreen(),
      const LogsScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: KeyedSubtree(
          key: ValueKey(_index),
          child: pages[_index],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        height: 68,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.shield_moon_outlined),
            selectedIcon: const Icon(Icons.shield_moon),
            label: t(context, 'nav.dashboard'),
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: mgr.problemCount > 0,
              label: Text('${mgr.problemCount}'),
              backgroundColor: SibleTheme.danger,
              child: const Icon(Icons.group_outlined),
            ),
            selectedIcon: const Icon(Icons.group),
            label: t(context, 'nav.accounts'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.insights_outlined),
            selectedIcon: const Icon(Icons.insights),
            label: t(context, 'nav.stats'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.lan_outlined),
            selectedIcon: const Icon(Icons.lan),
            label: t(context, 'nav.proxies'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.bolt_outlined),
            selectedIcon: const Icon(Icons.bolt),
            label: t(context, 'nav.logs'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.tune_outlined),
            selectedIcon: const Icon(Icons.tune),
            label: t(context, 'nav.settings'),
          ),
        ],
      ),
    );
  }
}
