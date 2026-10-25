/// Global activity feed with filters.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../services/account_manager.dart';
import '../widgets/common.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final mgr = context.watch<AccountManager>();
    final all = mgr.liveLog;
    final accounts =
        all.map((e) => e.accountLabel).where((l) => l.isNotEmpty).toSet();
    final filtered = all.where((e) {
      if (_filter == 'all') return true;
      if (_filter == 'errors') {
        return e.level == LogLevel.error || e.level == LogLevel.warn;
      }
      return e.accountLabel == _filter;
    }).toList()
      ..sort((a, b) => b.ts.compareTo(a.ts));

    return SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                'Activity',
                style: TextStyle(
                  color: SibleTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _FilterChip(
                    label: 'All',
                    selected: _filter == 'all',
                    onTap: () => setState(() => _filter = 'all')),
                _FilterChip(
                    label: 'Errors',
                    selected: _filter == 'errors',
                    onTap: () => setState(() => _filter = 'errors')),
                ...accounts.map((a) => _FilterChip(
                      label: a,
                      selected: _filter == a,
                      onTap: () => setState(() => _filter = a),
                    )),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const EmptyState(
                    icon: Icons.bolt_outlined,
                    title: 'Nothing here yet',
                    subtitle:
                        'Cycles, claims, accelerations and proxy rotations will appear here as they happen.',
                  )
                : RefreshIndicator(
                    color: SibleTheme.primary,
                    onRefresh: () async {},
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

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? SibleTheme.primary.withValues(alpha: 0.3)
                : SibleTheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? SibleTheme.primary : SibleTheme.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color:
                  selected ? SibleTheme.textPrimary : SibleTheme.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
