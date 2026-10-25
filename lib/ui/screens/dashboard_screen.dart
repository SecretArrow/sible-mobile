/// Dashboard: fleet overview + one-tap controls.
library;

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../services/account_manager.dart';
import '../../services/background_service.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

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
    if (await service.isRunning()) {
      requestRunNow(service);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Triggered background cycle')),
        );
      }
    } else {
      // Service not running - run inline.
      await deps.accountManager.runAllCycles(notifySummary: true);
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
        await settings.setServiceEnabled(newValue);
        if (newValue) {
          await service.startService();
        } else {
          await stopBackgroundService(service);
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
