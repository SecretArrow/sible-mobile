/// Dashboard: fleet overview + one-tap controls.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../services/account_manager.dart';
import '../../services/background_service.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  StreamSubscription<Map<String, dynamic>>? _cycleDoneSub;

  @override
  void initState() {
    super.initState();
    // Mirror background-service cycles into the UI: without this listener
    // the dashboard countdown / "last cycle" never reflect the service.
    final deps = context.read<AppDependencies>();
    final service = FlutterBackgroundService();
    _cycleDoneSub = service.on(serviceCycleDoneEvent).listen((data) {
      final mgr = deps.accountManager;
      final nextRaw = data['nextCycleAt'];
      final next = nextRaw is String ? DateTime.tryParse(nextRaw) : null;
      final error = data['error'];
      final hasError = error != null && '$error'.isNotEmpty;
      if (next != null) {
        mgr.nextCycleAt = next;
      }
      if (data['accountsRun'] is num) {
        // Synthetic event so background activity is visible on the dashboard.
        mgr.log(LogEvent(
          ts: DateTime.now(),
          level: hasError ? LogLevel.error : LogLevel.success,
          category: 'cycle',
          message: hasError
              ? 'Background cycle error: $error'
              : 'Background cycle done: ${data['success'] ?? 0} ok · '
                  '${data['failed'] ?? 0} failed · '
                  '${data['claims'] ?? 0} claims · '
                  '+${data['accelerations'] ?? 0} accel · '
                  '${data['extensionOpens'] ?? 0} ext',
        ));
        mgr.lastCycleAt = DateTime.now();
      }
      mgr.notifyListeners();
    });
  }

  @override
  void dispose() {
    _cycleDoneSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mgr = context.watch<AccountManager>();
    final settings = context.watch<SettingsStore>();
    final deps = context.read<AppDependencies>();

    final next = mgr.nextCycleAt;
    final countdown = next != null && next.isAfter(DateTime.now())
        ? hhmmss(next.difference(DateTime.now()))
        : null;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: SibleTheme.brandGradient,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.bolt, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sible Miner',
                        style: TextStyle(
                          color: SibleTheme.textPrimary,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        'Fleet automation console',
                        style: TextStyle(
                          color: SibleTheme.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                ServicePill(settings: settings, deps: deps),
              ],
            ),
          ),
          const SizedBox(height: 10),
          HeroStat(
            label: 'Total balance',
            value: mgr.totalBalance.toStringAsFixed(3),
            suffix: 'SIBLE',
            icon: Icons.diamond_outlined,
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Accounts',
                    value: '${mgr.accounts.length}',
                    icon: Icons.group_outlined,
                    color: SibleTheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    label: 'Mining now',
                    value: '${mgr.miningCount}',
                    icon: Icons.play_circle_outline,
                    color: SibleTheme.success,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    label: 'Issues',
                    value: '${mgr.problemCount}',
                    icon: Icons.warning_amber_outlined,
                    color: SibleTheme.warning,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GradientButton(
              label: mgr.cycleRunning ? 'Running cycle...' : 'Run cycle now',
              icon: Icons.rocket_launch_outlined,
              busy: mgr.cycleRunning,
              onPressed: () => _runNow(context, deps),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.schedule, size: 13, color: SibleTheme.textSecondary),
                const SizedBox(width: 6),
                Text(
                  countdown != null
                      ? 'Next auto-check in $countdown'
                      : 'Auto-check every ${settings.intervalMinutes} min',
                  style: const TextStyle(
                    color: SibleTheme.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          SectionHeader(
            'Live activity',
            trailing: Text(
              mgr.lastCycleAt != null
                  ? 'last cycle ${timeAgo(mgr.lastCycleAt)}'
                  : 'waiting for first cycle',
              style: const TextStyle(
                  color: SibleTheme.textSecondary, fontSize: 11),
            ),
          ),
          if (mgr.liveLog.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: EmptyState(
                icon: Icons.bolt,
                title: 'No activity yet',
                subtitle:
                    'Add accounts, start the background service, and cycles will stream here every 5 minutes.',
              ),
            )
          else
            ...mgr.liveLog.reversed.take(8).map((e) => LogTile(event: e)),
        ],
      ),
    );
  }

  Future<void> _runNow(BuildContext context, AppDependencies deps) async {
    final service = FlutterBackgroundService();
    final mgr = deps.accountManager;
    if (mgr.cycleRunning) return; // double-tap guard (inline path)
    try {
      if (await service.isRunning()) {
        requestRunNow(service);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Background cycle triggered')),
          );
        }
      } else if (deps.settings.serviceEnabled) {
        // Service SHOULD be running (auto mode) - restart it; the service
        // runs its own cycle immediately. Avoids the cross-isolate
        // double-cycle race of an inline run.
        try {
          await service.startService();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Background worker started - cycle running')),
            );
          }
        } catch (e) {
          // Fallback: run inline in the UI isolate.
          final summary = await mgr.runAllCycles(notifySummary: true);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Cycle done: ${summary.headline}')),
            );
          }
        }
      } else {
        // Auto mode is off - run inline on demand.
        final summary = await mgr.runAllCycles(notifySummary: true);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(summary.accountsRun == 0
                    ? 'No enabled accounts to cycle'
                    : 'Cycle done: ${summary.headline}')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cycle failed: $e')),
        );
      }
    }
  }
}

/// Start/stop pill for the background worker.
class ServicePill extends StatelessWidget {
  final SettingsStore settings;
  final AppDependencies deps;

  const ServicePill({super.key, required this.settings, required this.deps});

  @override
  Widget build(BuildContext context) {
    final on = settings.serviceEnabled;
    return GestureDetector(
      onTap: () async {
        final service = FlutterBackgroundService();
        final newValue = !on;
        try {
          if (newValue) {
            // Start FIRST, persist only on success - otherwise the pill
            // shows "AUTO ON" while nothing is actually running.
            final started = await service.startService();
            await settings.setServiceEnabled(started != false);
          } else {
            await settings.setServiceEnabled(false);
            await stopBackgroundService(service);
          }
        } catch (e) {
          await settings.setServiceEnabled(!newValue); // revert UI state
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(
                  'Gagal ${newValue ? 'menyalakan' : 'mematikan'} service: $e')),
            );
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: (on ? SibleTheme.success : SibleTheme.textSecondary)
              .withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: (on ? SibleTheme.success : SibleTheme.textSecondary)
                .withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? SibleTheme.success : SibleTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              on ? 'AUTO ON' : 'AUTO OFF',
              style: TextStyle(
                color: on ? SibleTheme.success : SibleTheme.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
