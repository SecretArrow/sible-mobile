/// Global activity feed with search, level/account filters and CSV export.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../services/account_manager.dart';
import '../../services/log_filter.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import 'logs_controls.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final LogsFilterState _filter = LogsFilterState();

  /// Events persisted by BOTH isolates (the background service writes here
  /// too) - without reading from disk, background cycles were invisible.
  List<LogEvent> _disk = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final deps = context.read<AppDependencies>();
      final logs = await deps.store.readGlobalLog(tail: 400);
      if (mounted) setState(() => _disk = logs);
    } catch (_) {
      // Log read failure must never break the screen.
    }
  }

  /// Disk log + live in-memory log, deduplicated.
  List<LogEvent> _merged(List<LogEvent> live) {
    final seen = <String>{};
    final out = <LogEvent>[];
    for (final e in [..._disk, ...live]) {
      final k =
          '${e.ts.millisecondsSinceEpoch}|${e.message}|${e.accountId}|${e.category}';
      if (seen.add(k)) out.add(e);
    }
    return out;
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mgr = context.watch<AccountManager>();
    final all = _merged(mgr.liveLog);
    final accounts = all
        .map((e) => e.accountLabel)
        .where((l) => l.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    // OPS: unified text/level/account filtering.
    final filtered = applyLogFilter<LogEvent>(
      all,
      _filter,
      account: (e) => e.accountLabel.isEmpty ? null : e.accountLabel,
      level: (e) => e.level.name,
      message: (e) => e.message,
    ).toList()
      ..sort((a, b) => b.ts.compareTo(a.ts));

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t(context, 'nav.logs'),
                    style: const TextStyle(
                      color: SibleTheme.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                // OPS: export the filtered feed as CSV.
                LogsCsvAction(
                  collectRows: () => filtered
                      .map((e) => LogRow(
                            at: e.ts.toIso8601String(),
                            account: e.accountLabel,
                            level: e.level.name,
                            message: e.message,
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          // OPS: search + level chips + account picker.
          ListenableBuilder(
            listenable: _filter,
            builder: (context, _) => LogsFilterBar(
              state: _filter,
              accountOptions: accounts,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                t(context, 'logs.results')
                    .replaceAll('{n}', '${filtered.length}'),
                style: const TextStyle(
                  color: SibleTheme.textSecondary,
                  fontSize: 10.5,
                ),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? EmptyState(
                    icon: Icons.bolt_outlined,
                    title: t(context, 'common.empty'),
                    subtitle: t(context, 'logs.filterText'),
                  )
                : RefreshIndicator(
                    color: SibleTheme.primary,
                    onRefresh: _refresh,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(top: 4, bottom: 24),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) => LogTile(event: filtered[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
