/// Proxy pool console: stats, refresh, assignment overview.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

class ProxiesScreen extends StatefulWidget {
  const ProxiesScreen({super.key});

  @override
  State<ProxiesScreen> createState() => _ProxiesScreenState();
}

class _ProxiesScreenState extends State<ProxiesScreen> {
  bool _refreshing = false;
  String _stage = '';
  double _progress = 0;

  Future<void> _refreshPool(AppDependencies deps) async {
    setState(() {
      _refreshing = true;
      _stage = 'fetching sources...';
      _progress = 0;
    });
    try {
      final candidates = await deps.proxyEngine.fetchFromSources();
      if (!mounted) return;
      setState(() => _stage = 'validating 0/${candidates.length}...');
      final alive = await deps.proxyEngine.validateProxies(
        candidates.take(deps.settings.poolTarget * 3).toList(),
        onProgress: (done, total) {
          if (mounted && total > 0) {
            setState(() {
              _stage = 'validating $done/$total...';
              _progress = done / total;
            });
          }
        },
      );
      // Rebuild pool while preserving account bindings that are still alive.
      final oldAssign = {
        for (final p in deps.proxyEngine.all)
          if (p.assignedTo != null) p.key: p.assignedTo,
      };
      await deps.proxyEngine.replacePool(
          alive.take(deps.settings.poolTarget).toList(),
          keepAssignments: oldAssign);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Pool refreshed - ${alive.length} alive proxies'),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deps = context.read<AppDependencies>();
    final pool = deps.proxyEngine.all;
    final alive = pool.where((p) => p.alive).toList()
      ..sort((a, b) => a.latencyMs.compareTo(b.latencyMs));
    final free = alive.where((p) => p.assignedTo == null).length;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Text(
              'Proxy pool',
              style: TextStyle(
                color: SibleTheme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Every account gets its own exclusive egress IP. Dead proxies are '
              'rotated out automatically on the next cycle.',
              style: TextStyle(
                color: SibleTheme.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Alive / total',
                    value: '${alive.length}/${pool.length}',
                    icon: Icons.lan_outlined,
                    color: SibleTheme.success,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    label: 'Free slots',
                    value: '$free',
                    icon: Icons.power_settings_new,
                    color: SibleTheme.cyan,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    label: 'Assigned',
                    value: '${alive.length - free}',
                    icon: Icons.link,
                    color: SibleTheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GradientButton(
              label: _refreshing ? _stage : 'Refresh pool',
              icon: Icons.refresh,
              busy: _refreshing,
              onPressed: () => _refreshPool(deps),
            ),
          ),
          if (_refreshing) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                minHeight: 4,
                borderRadius: BorderRadius.circular(4),
                color: SibleTheme.primary,
                backgroundColor: SibleTheme.surfaceHigh,
              ),
            ),
          ],
          SectionHeader('Fastest proxies'),
          if (alive.isEmpty)
            const EmptyState(
              icon: Icons.lan_outlined,
              title: 'Pool is empty',
              subtitle:
                  'Tap "Refresh pool" to fetch & validate fresh free proxies. The background worker also auto-refills when the pool runs dry.',
            )
          else
            ...alive.take(60).map((p) => _ProxyTile(entry: p)),
        ],
      ),
    );
  }
}

class _ProxyTile extends StatelessWidget {
  final ProxyEntry entry;

  const _ProxyTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final deps = context.read<AppDependencies>();
    final mgr = deps.accountManager;
    final assigned = entry.assignedTo == null
        ? null
        : mgr.accounts.where((a) => a.id == entry.assignedTo).firstOrNull;
    final latencyColor = entry.latencyMs < 1500
        ? SibleTheme.success
        : entry.latencyMs < 4000
            ? SibleTheme.warning
            : SibleTheme.danger;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SibleTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SibleTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SibleTheme.success,
              boxShadow: [
                BoxShadow(
                  color: SibleTheme.success.withValues(alpha: 0.6),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.key,
                  style: const TextStyle(
                    color: SibleTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  assigned != null ? 'used by ${assigned.displayName}' : 'free',
                  style: const TextStyle(
                    color: SibleTheme.textSecondary,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          StatusChip(
            label: '${entry.latencyMs}ms',
            color: latencyColor,
            dot: false,
          ),
        ],
      ),
    );
  }
}
