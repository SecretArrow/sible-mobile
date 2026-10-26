/// Logs screen controls (#6): filter bar + CSV export action.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../services/log_filter.dart';

/// Compact, modern filter bar bound to a [LogsFilterState]: free-text
/// search, level choice chips and an account picker popup.
///
/// Standalone: the parent only supplies [state] (whose setters already
/// notify listeners, so wrapping the bar in an `AnimatedBuilder` rebuilds
/// the list) and [accountOptions] (distinct non-empty account labels).
class LogsFilterBar extends StatefulWidget {
  /// Shared filter state (owned by the screen).
  final LogsFilterState state;

  /// Account labels offered in the picker.
  final List<String> accountOptions;

  const LogsFilterBar({
    super.key,
    required this.state,
    this.accountOptions = const [],
  });

  @override
  State<LogsFilterBar> createState() => _LogsFilterBarState();
}

class _LogsFilterBarState extends State<LogsFilterBar> {
  late final TextEditingController _search =
      TextEditingController(text: widget.state.textQuery);

  @override
  void didUpdateWidget(covariant LogsFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _search.text = widget.state.textQuery;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setLevel(LogLevelFilter v) {
    widget.state.setLevel(v);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _search,
            onChanged: (v) {
              widget.state.setTextQuery(v);
              if (mounted) setState(() {});
            },
            style: const TextStyle(color: SibleTheme.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: t(context, 'logs.filterText'),
              hintStyle: const TextStyle(
                  color: SibleTheme.textSecondary, fontSize: 12.5),
              prefixIcon: const Icon(Icons.search,
                  size: 18, color: SibleTheme.textSecondary),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close,
                          size: 16, color: SibleTheme.textSecondary),
                      onPressed: () {
                        _search.clear();
                        widget.state.setTextQuery('');
                        if (mounted) setState(() {});
                      },
                    ),
              filled: true,
              fillColor: SibleTheme.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: SibleTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: SibleTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: SibleTheme.primary, width: 1.2),
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
              _chip(t(context, 'common.all'), LogLevelFilter.all),
              _chip(t(context, 'logs.levelInfo'), LogLevelFilter.info),
              _chip(t(context, 'logs.levelWarn'), LogLevelFilter.warn),
              _chip(t(context, 'logs.levelError'), LogLevelFilter.error),
              _AccountChip(state: widget.state, options: widget.accountOptions),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, LogLevelFilter value) {
    final selected = widget.state.level == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        labelPadding: const EdgeInsets.symmetric(horizontal: 10),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        onSelected: (_) => _setLevel(value),
        labelStyle: TextStyle(
          color: selected ? SibleTheme.textPrimary : SibleTheme.textSecondary,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
        selectedColor: SibleTheme.primary.withValues(alpha: 0.3),
        backgroundColor: SibleTheme.surface,
        side: BorderSide(
          color: selected ? SibleTheme.primary : SibleTheme.border,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}

/// Account picker rendered as a pill chip with a popup menu.
class _AccountChip extends StatelessWidget {
  final LogsFilterState state;
  final List<String> options;

  const _AccountChip({required this.state, required this.options});

  @override
  Widget build(BuildContext context) {
    final selected = state.accountFilter;
    final active = selected != null && selected.isNotEmpty;
    final label = active ? selected! : t(context, 'common.all');
    return PopupMenuButton<String>(
      initialValue: active ? selected : null,
      onSelected: (v) => state.setAccountFilter(v.isEmpty ? null : v),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: '',
          child: Text(
            t(context, 'common.all'),
            style:
                const TextStyle(color: SibleTheme.textPrimary, fontSize: 12.5),
          ),
        ),
        ...options.map(
          (a) => PopupMenuItem(
            value: a,
            child: Text(
              a,
              style: const TextStyle(
                  color: SibleTheme.textPrimary, fontSize: 12.5),
            ),
          ),
        ),
      ],
      child: Container(
        constraints: const BoxConstraints(maxWidth: 170),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? SibleTheme.primary.withValues(alpha: 0.3)
              : SibleTheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? SibleTheme.primary : SibleTheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline,
                size: 13, color: SibleTheme.textSecondary),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active
                      ? SibleTheme.textPrimary
                      : SibleTheme.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down,
                size: 14, color: SibleTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Export icon button: writes the rows returned by [collectRows] to a temp
/// CSV file and opens the system share sheet; if that fails the raw CSV
/// text is shared instead. Confirms with a `logs.exported` snackbar.
class LogsCsvAction extends StatelessWidget {
  /// Collects the (already filtered) rows to export.
  final List<LogRow> Function() collectRows;

  const LogsCsvAction({super.key, required this.collectRows});

  Future<void> _export(BuildContext context) async {
    final rows = collectRows();
    final csv = logsToCsv(rows);
    final messenger = ScaffoldMessenger.of(context);
    final subject = t(context, 'logs.exportCsv');
    final done = t(context, 'logs.exported').replaceAll(
      '{n}',
      '${rows.length}',
    );
    try {
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/sible_logs_$stamp.csv');
      await file.writeAsString(csv, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: subject,
      );
    } catch (e) {
      debugPrint('[logs-csv] file share failed, using text fallback: $e');
      try {
        await Share.share(csv, subject: subject);
      } catch (e2) {
        debugPrint('[logs-csv] text share failed: $e2');
      }
    }
    messenger.showSnackBar(SnackBar(content: Text(done)));
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: t(context, 'logs.exportCsv'),
      color: SibleTheme.textSecondary,
      icon: const Icon(Icons.ios_share, size: 20),
      onPressed: () => _export(context),
    );
  }
}
