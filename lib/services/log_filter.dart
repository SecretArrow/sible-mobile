/// Log filter state + pure filtering / CSV export helpers (#6).
library;

import 'package:flutter/foundation.dart';

/// Coarse level bucket exposed by the logs filter UI.
///
/// [LogLevelFilter.info] intentionally matches both `info` and `success`
/// rows: the UI exposes only three non-`all` buckets (info / warn / error)
/// while [LogLevel] (see `core/utils.dart`) has four levels.
enum LogLevelFilter { all, info, warn, error }

/// Observable filter state for the logs screen.
///
/// Holds the account filter, the level bucket and a free-text query; every
/// setter is a no-op when the value is unchanged and calls
/// [notifyListeners] otherwise.
class LogsFilterState extends ChangeNotifier {
  String? _accountFilter;
  LogLevelFilter _level = LogLevelFilter.all;
  String _textQuery = '';

  /// Selected account label, or `null` for all accounts.
  String? get accountFilter => _accountFilter;

  /// Selected level bucket (defaults to [LogLevelFilter.all]).
  LogLevelFilter get level => _level;

  /// Free-text query matched case-insensitively against log messages.
  String get textQuery => _textQuery;

  /// Sets the account filter (`null` or empty = all accounts).
  void setAccountFilter(String? account) {
    if (account == _accountFilter) return;
    _accountFilter = account;
    notifyListeners();
  }

  /// Sets the level bucket.
  void setLevel(LogLevelFilter level) {
    if (level == _level) return;
    _level = level;
    notifyListeners();
  }

  /// Sets the free-text query (trimmed; empty = no text filter).
  void setTextQuery(String query) {
    final q = query.trim();
    if (q == _textQuery) return;
    _textQuery = q;
    notifyListeners();
  }

  /// Resets account, level and text back to their defaults.
  void reset() {
    if (_accountFilter == null &&
        _level == LogLevelFilter.all &&
        _textQuery.isEmpty) {
      return;
    }
    _accountFilter = null;
    _level = LogLevelFilter.all;
    _textQuery = '';
    notifyListeners();
  }
}

/// Pure, generic log filter.
///
/// Keeps entries for which:
/// * [account] equals [LogsFilterState.accountFilter] (a null/empty filter
///   or account means "all"), and
/// * [level] maps into the selected bucket (`success` counts as `info`), and
/// * [message] contains [LogsFilterState.textQuery] case-insensitively
///   (an empty query passes).
///
/// Returns a new list; never mutates [logs] or [state].
List<T> applyLogFilter<T>(
  List<T> logs,
  LogsFilterState state, {
  required String? Function(T) account,
  required String Function(T) level,
  required String Function(T) message,
}) {
  final allowed = switch (state.level) {
    LogLevelFilter.all => null,
    LogLevelFilter.info => const {'info', 'success'},
    LogLevelFilter.warn => const {'warn'},
    LogLevelFilter.error => const {'error'},
  };
  final query = state.textQuery.toLowerCase();
  final accountFilter = state.accountFilter;
  bool pass(T e) {
    if (allowed != null && !allowed.contains(level(e))) return false;
    if (accountFilter != null &&
        accountFilter.isNotEmpty &&
        account(e) != accountFilter) {
      return false;
    }
    if (query.isNotEmpty && !message(e).toLowerCase().contains(query)) {
      return false;
    }
    return true;
  }

  return logs.where(pass).toList();
}

/// One flat log row destined for CSV export.
class LogRow {
  /// Timestamp string (e.g. ISO-8601) of the event.
  final String at;

  /// Human account label (may be empty for global events).
  final String account;

  /// Raw level name (`info` / `success` / `warn` / `error`).
  final String level;

  /// Log message text.
  final String message;

  const LogRow({
    required this.at,
    required this.account,
    required this.level,
    required this.message,
  });
}

/// Escapes a single CSV field per RFC 4180.
///
/// Fields containing a comma, double quote, newline or carriage return are
/// wrapped in double quotes; internal double quotes are doubled.
String csvEscapeField(String field) {
  final needsQuoting = field.contains(',') ||
      field.contains('"') ||
      field.contains('\n') ||
      field.contains('\r');
  if (!needsQuoting) return field;
  return '"${field.replaceAll('"', '""')}"';
}

/// Renders [rows] as an RFC 4180 CSV document with the header
/// `at,account,level,message`.
String logsToCsv(List<LogRow> rows) {
  final out = StringBuffer('at,account,level,message');
  for (final r in rows) {
    out
      ..write('\n')
      ..write(csvEscapeField(r.at))
      ..write(',')
      ..write(csvEscapeField(r.account))
      ..write(',')
      ..write(csvEscapeField(r.level))
      ..write(',')
      ..write(csvEscapeField(r.message));
  }
  return out.toString();
}
