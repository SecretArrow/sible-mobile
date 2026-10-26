/// Statistics screen: earnings KPIs, daily chart and top accounts.
library;

import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/account_manager.dart';
import '../../services/background_service.dart' show resolveRootDir;
import '../../services/stats_service.dart';
import '../widgets/common.dart';

/// Amount formatter: up to 6 decimals, no trailing zeros.
final NumberFormat _amountFmt = NumberFormat('#,##0.######', 'en_US');

/// Compact formatter for chart axis labels (1.2K, 3.4M, ...).
final NumberFormat _axisFmt = NumberFormat.compact(locale: 'en_US');

/// Shared dropdown item text style.
const TextStyle _menuStyle = TextStyle(
  color: SibleTheme.textPrimary,
  fontSize: 13,
);

/// Statistics & earnings charts (feature #1).
///
/// Resolves its own [StatsStore] when [StatsScreen.store] is not injected,
/// using the same documents-dir pattern as the rest of the app.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.store});

  /// Named-route id (`Navigator.pushNamed(context, StatsScreen.routeName)`).
  static const String routeName = '/stats';

  /// Optional store override (tests / custom wiring). When null, a store is
  /// built from the app documents dir and `init()` is called on it.
  final StatsStore? store;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  static const List<int> _ranges = [7, 30, 90];
  static const int _topAccounts = 5;

  StatsStore? _store;
  List<EarningRecord> _records = const [];
  bool _loading = true;
  int _range = 7;
  String? _accountFilter;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    var store = widget.store;
    if (store == null) {
      // Same root-dir pattern as main.dart (without editing it).
      final root = await resolveRootDir();
      store = StatsStore(rootDir: root);
    }
    _store = store;
    await store.init();
    await _reload();
  }

  Future<void> _reload() async {
    final store = _store;
    if (store == null) return;
    final records = await store.loadAll();
    if (!mounted) return;
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  /// Soft provider lookup: the screen also renders without a Provider scope.
  AccountManager? _manager(BuildContext context) {
    try {
      return Provider.of<AccountManager>(context);
    } on ProviderNotFoundException {
      return null;
    }
  }

  Set<String> _knownIds(List<Account> accounts) => <String>{
        for (final r in _records) r.accountId,
        for (final a in accounts) a.id,
      };

  String _labelFor(List<Account> accounts, String id) {
    for (final a in accounts) {
      if (a.id == id) return a.displayName;
    }
    return '#${id.length <= 6 ? id : id.substring(0, 6)}';
  }

  List<ButtonSegment<int>> get _rangeSegments => _ranges
      .map((r) => ButtonSegment<int>(
            value: r,
            label: Text(t(context, 'stats.range$r')),
          ))
      .toList();

  List<DropdownMenuItem<String?>> _accountItems(List<Account> accounts) {
    final items = <DropdownMenuItem<String?>>[
      DropdownMenuItem<String?>(
        value: null,
        child: Text(t(context, 'stats.allAccounts'), style: _menuStyle),
      ),
    ];
    final ids = _knownIds(accounts).toList()..sort();
    for (final id in ids) {
      items.add(
        DropdownMenuItem<String?>(
          value: id,
          child: Text(
            _labelFor(accounts, id),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _menuStyle,
          ),
        ),
      );
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final mgr = _manager(context);
    final accounts = mgr?.accounts ?? const <Account>[];
    final known = _knownIds(accounts);
    final filter = known.contains(_accountFilter) ? _accountFilter : null;
    final filtered = filter == null
        ? _records
        : _records.where((r) => r.accountId == filter).toList(growable: false);

    final nowUtc = DateTime.now().toUtc();
    final todayStart = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    final total = totalEarned(filtered);
    final todayTotal = earnedSince(filtered, todayStart);
    final weekTotal = earnedSince(
      filtered,
      todayStart.subtract(const Duration(days: 6)),
    );
    final avg = averagePerDay(filtered, days: _range);
    final daily = aggregateDaily(filtered, days: _range, now: nowUtc);
    final tops = aggregateByAccount(filtered, topN: _topAccounts);
    final best = bestDay(filtered);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text(
                t(context, 'stats.title'),
                style: const TextStyle(
                  color: SibleTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            GlowCard(
              padding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.filter_alt_outlined,
                    size: 17,
                    color: SibleTheme.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: filter,
                        isExpanded: true,
                        dropdownColor: SibleTheme.surfaceHigh,
                        icon: const Icon(
                          Icons.expand_more,
                          size: 18,
                          color: SibleTheme.textSecondary,
                        ),
                        items: _accountItems(accounts),
                        onChanged: (v) => setState(() => _accountFilter = v),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filtered.isEmpty)
              EmptyState(
                icon: Icons.query_stats,
                title: t(context, 'stats.noData'),
                subtitle: t(context, 'stats.noDataHint'),
              )
            else ...[
              _buildCards(
                total: total,
                today: todayTotal,
                week: weekTotal,
                avg: avg,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: SegmentedButton<int>(
                  segments: _rangeSegments,
                  selected: {_range},
                  onSelectionChanged: (s) => setState(() => _range = s.first),
                ),
              ),
              SectionHeader(t(context, 'stats.earnedPerDay')),
              _buildChart(daily),
              const SizedBox(height: 12),
              _buildBestDay(best),
              SectionHeader(t(context, 'stats.topAccounts')),
              _buildTopAccounts(accounts, tops),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCards({
    required double total,
    required double today,
    required double week,
    required double avg,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.45,
        padding: EdgeInsets.zero,
        children: [
          _StatCard(
            label: t(context, 'stats.totalEarned'),
            value: _amountFmt.format(total),
            icon: Icons.diamond_outlined,
            color: SibleTheme.primary,
          ),
          _StatCard(
            label: t(context, 'stats.todayEarned'),
            value: _amountFmt.format(today),
            icon: Icons.today_outlined,
            color: SibleTheme.cyan,
          ),
          _StatCard(
            label: t(context, 'stats.weekEarned'),
            value: _amountFmt.format(week),
            icon: Icons.date_range_outlined,
            color: SibleTheme.success,
          ),
          _StatCard(
            label: t(context, 'stats.avgPerDay'),
            value: _amountFmt.format(avg),
            icon: Icons.trending_up_outlined,
            color: SibleTheme.warning,
          ),
        ],
      ),
    );
  }

  Widget _buildChart(List<DailyTotal> daily) {
    final cs = Theme.of(context).colorScheme;
    final maxTotal = daily.fold(0.0, (m, d) => d.total > m ? d.total : m);
    final step = _niceStep(maxTotal / 4);
    final barWidth = _range <= 7
        ? 14.0
        : _range <= 30
            ? 5.0
            : 2.0;
    return GlowCard(
      padding: const EdgeInsets.fromLTRB(8, 14, 12, 8),
      child: SizedBox(
        height: 220,
        width: double.infinity,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceBetween,
            maxY: maxTotal <= 0 ? 1 : maxTotal * 1.15,
            barTouchData: _barTouchData(),
            gridData: _gridData(step),
            borderData: FlBorderData(show: false),
            titlesData: _titlesData(daily, step),
            barGroups: _barGroups(daily, barWidth, cs.primary),
          ),
        ),
      ),
    );
  }

  BarTouchData _barTouchData() {
    return BarTouchData(
      touchTooltipData: BarTouchTooltipData(
        // fl_chart 0.69.x: GetBarTooltipColor takes only the touched group.
        getTooltipColor: (group) => SibleTheme.surfaceHigh,
        getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
          '${_amountFmt.format(rod.toY)} SIBLE',
          const TextStyle(
            color: SibleTheme.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  FlGridData _gridData(double step) {
    return FlGridData(
      drawVerticalLine: false,
      horizontalInterval: step,
      getDrawingHorizontalLine: (v) => FlLine(
        color: Colors.white.withValues(alpha: 0.05),
        strokeWidth: 1,
      ),
    );
  }

  FlTitlesData _titlesData(List<DailyTotal> daily, double step) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 42,
          interval: step,
          getTitlesWidget: (value, meta) =>
              _AxisLabel(_axisFmt.format(value), alignEnd: true),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 22,
          interval: _bottomInterval(daily.length),
          getTitlesWidget: (value, meta) {
            final i = value.toInt();
            if (i < 0 || i >= daily.length) return const SizedBox.shrink();
            final d = daily[i].day;
            return _AxisLabel('${d.day}/${d.month}');
          },
        ),
      ),
    );
  }

  List<BarChartGroupData> _barGroups(
    List<DailyTotal> daily,
    double barWidth,
    Color barColor,
  ) {
    return [
      for (var i = 0; i < daily.length; i++)
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: daily[i].total,
              width: barWidth,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(barWidth < 4 ? 1 : 3),
              ),
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [barColor.withValues(alpha: 0.35), barColor],
              ),
            ),
          ],
        ),
    ];
  }

  double _bottomInterval(int days) {
    if (days <= 7) return 1;
    if (days <= 30) return 5;
    return 15;
  }

  /// Rounds [raw] up to a human-friendly axis step (1/2/5 x 10^n).
  double _niceStep(double raw) {
    if (raw <= 0) return 1;
    final exp = (log(raw) / ln10).floor();
    final mag = pow(10.0, exp).toDouble();
    for (final m in const [1.0, 2.0, 5.0]) {
      if (mag * m >= raw) return mag * m;
    }
    return mag * 10;
  }

  Widget _buildBestDay(DailyTotal? best) {
    return GlowCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: SibleTheme.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.emoji_events_outlined,
              size: 16,
              color: SibleTheme.warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(context, 'stats.bestDay'),
                  style: const TextStyle(
                    color: SibleTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  best == null
                      ? '-'
                      : '${_amountFmt.format(best.total)} SIBLE · '
                          '${best.day.day}/${best.day.month}',
                  style: const TextStyle(
                    color: SibleTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopAccounts(List<Account> accounts, List<AccountTotal> tops) {
    final top = tops.isEmpty ? 0.0 : tops.first.total;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (var i = 0; i < tops.length; i++)
            _TopAccountRow(
              rank: i + 1,
              label: _labelFor(accounts, tops[i].accountId),
              claims: tops[i].claims,
              amount: tops[i].total,
              fraction: top > 0
                  ? (tops[i].total / top).clamp(0.04, 1.0).toDouble()
                  : 0,
            ),
        ],
      ),
    );
  }
}

/// Small chart axis label.
class _AxisLabel extends StatelessWidget {
  final String text;
  final bool alignEnd;

  const _AxisLabel(this.text, {this.alignEnd = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: alignEnd
          ? const EdgeInsets.only(right: 6)
          : const EdgeInsets.only(top: 5),
      child: Text(
        text,
        textAlign: alignEnd ? TextAlign.right : TextAlign.center,
        style: const TextStyle(
          color: SibleTheme.textSecondary,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// KPI card used in the 2x2 overview grid.
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SibleTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SibleTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                color: SibleTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: SibleTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// One ranked account row with a proportional gradient bar.
class _TopAccountRow extends StatelessWidget {
  final int rank;
  final String label;
  final int claims;
  final double amount;
  final double fraction;

  const _TopAccountRow({
    required this.rank,
    required this.label,
    required this.claims,
    required this.amount,
    required this.fraction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SibleTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SibleTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$rank.',
                style: TextStyle(
                  color: rank == 1 ? SibleTheme.cyan : SibleTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SibleTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_amountFmt.format(amount)} SIBLE',
                style: const TextStyle(
                  color: SibleTheme.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Container(
              height: 5,
              color: SibleTheme.surfaceHigh,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: SibleTheme.brandGradient,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$claims ${t(context, 'stats.claims')}',
            style: const TextStyle(
              color: SibleTheme.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
