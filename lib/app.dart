/// App root: MaterialApp + theme + navigation shell with 5 tabs.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'services/account_manager.dart';
import 'state/providers.dart';
import 'ui/screens/accounts_screen.dart';
import 'ui/screens/dashboard_screen.dart';
import 'ui/screens/logs_screen.dart';
import 'ui/screens/proxies_screen.dart';
import 'ui/screens/settings_screen.dart';

class SibleMinerApp extends StatelessWidget {
  final AppDependencies deps;

  const SibleMinerApp({super.key, required this.deps});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppDependencies>.value(value: deps),
        ChangeNotifierProvider<SettingsStore>.value(value: deps.settings),
        ChangeNotifierProvider<AccountManager>.value(
            value: deps.accountManager),
      ],
      child: MaterialApp(
        title: 'Sible Miner',
        debugShowCheckedModeBanner: false,
        theme: SibleTheme.dark(),
        home: const HomeShell(),
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
    final pages = const [
      DashboardScreen(),
      AccountsScreen(),
      ProxiesScreen(),
      LogsScreen(),
      SettingsScreen(),
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
          const NavigationDestination(
            icon: Icon(Icons.shield_moon_outlined),
            selectedIcon: Icon(Icons.shield_moon),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: mgr.problemCount > 0,
              label: Text('${mgr.problemCount}'),
              backgroundColor: SibleTheme.danger,
              child: const Icon(Icons.group_outlined),
            ),
            selectedIcon: const Icon(Icons.group),
            label: 'Accounts',
          ),
          const NavigationDestination(
            icon: Icon(Icons.lan_outlined),
            selectedIcon: Icon(Icons.lan),
            label: 'Proxy',
          ),
          const NavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            selectedIcon: Icon(Icons.bolt),
            label: 'Activity',
          ),
          const NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
