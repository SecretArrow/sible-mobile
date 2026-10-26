/// Maintenance section for the Settings screen (Features #2 + #3).
///
/// Self-contained cards that replicate the Settings `_Group` visual style:
///  * Backup & restore - encrypted export/restore of every account through
///    [BackupService] (password dialog -> progress overlay -> snackbar).
///  * App updates - GitHub release check through [UpdateService] with an
///    animated result banner, release notes and an auto-check switch.
///
/// Drop-in usage: append `const MaintenanceSettingsSection()` to the
/// Settings screen `ListView` children. Dependency wiring is done via
/// `AppDependencies` (provider) unless custom closures are injected.
library;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/backup_service.dart';
import '../../services/update_service.dart';
import '../../state/providers.dart';

/// Default export closure: every profile (+ nested secrets) in the store.
Future<List<Map<String, dynamic>>> _defaultExportAll(
  AppDependencies deps,
) async {
  final ids = await deps.store.listAccountIds();
  final out = <Map<String, dynamic>>[];
  for (final id in ids) {
    final acc = await deps.store.readProfile(id);
    if (acc == null) continue;
    final map = acc.toJson();
    final secrets = await deps.store.readSecrets(id);
    if (secrets != null) map['secrets'] = secrets.toJson();
    out.add(map);
  }
  return out;
}

/// Default import closure: write profiles (+ secrets), skipping duplicate
/// ids, then refresh the in-memory [AccountManager] list.
Future<({int imported, int skipped})> _defaultImportAll(
  AppDependencies deps,
  List<Map<String, dynamic>> accounts,
) async {
  var imported = 0;
  var skipped = 0;
  final existing = (await deps.store.listAccountIds()).toSet();
  for (final raw in accounts) {
    try {
      final acc = Account.fromJson(raw);
      if (existing.contains(acc.id)) {
        skipped++;
        continue;
      }
      await deps.store.writeProfile(acc);
      final secrets = raw['secrets'];
      if (secrets is Map) {
        await deps.store.writeSecrets(
          acc.id,
          AccountSecrets.fromJson(Map<String, dynamic>.from(secrets)),
        );
      }
      existing.add(acc.id);
      imported++;
    } catch (e) {
      debugPrint('[backup] import skipped an account: $e');
      skipped++;
    }
  }
  if (imported > 0) await deps.accountManager.loadAll();
  return (imported: imported, skipped: skipped);
}

/// Backup/restore + update-check cards for the Settings screen.
class MaintenanceSettingsSection extends StatefulWidget {
  /// Optional custom bulk-export closure (defaults to the local
  /// [AppDependencies.store] wiring above).
  final Future<List<Map<String, dynamic>>> Function()? exportAll;

  /// Optional custom bulk-import closure (defaults to the local
  /// [AppDependencies.store] wiring above).
  final Future<({int imported, int skipped})> Function(
      List<Map<String, dynamic>> accounts)? importAll;

  const MaintenanceSettingsSection({super.key, this.exportAll, this.importAll});

  @override
  State<MaintenanceSettingsSection> createState() =>
      _MaintenanceSettingsSectionState();
}

enum _Flow { none, export, restore }

class _MaintenanceSettingsSectionState
    extends State<MaintenanceSettingsSection> {
  BackupService? _backup;
  UpdateService? _updater;
  PackageInfo? _pkg;

  bool _busy = false; // export/restore overlay
  bool _checking = false; // update-check spinner
  bool _checked = false; // a check has finished
  bool _autoCheck = true;
  _Flow _pendingFlow = _Flow.none;
  UpdateInfo? _update;
  int _exportCount = 0;

  @override
  void initState() {
    super.initState();
    final deps = context.read<AppDependencies>();
    _autoCheck = UpdateService.loadAutoCheck(deps.prefs);
    _backup = BackupService(
      // Wrap the closure (injected or default) to capture the export count
      // for the success snackbar without changing BackupService's API.
      exportAll: () async {
        final accounts =
            await (widget.exportAll ?? (() => _defaultExportAll(deps)))();
        _exportCount = accounts.length;
        return accounts;
      },
      importAll:
          widget.importAll ?? (accounts) => _defaultImportAll(deps, accounts),
    );
    _updater = UpdateService();
    _loadPackageInfo();
  }

  @override
  void dispose() {
    _updater?.dispose();
    super.dispose();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _pkg = info);
    } on Exception catch (e) {
      debugPrint('[maintenance] package_info unavailable: $e');
    }
  }

  /// Falls back to the compile-time constants when the plugin is missing.
  String get _versionLabel {
    final v = _pkg?.version ?? SibleApi.appVersion;
    final b =
        _pkg != null ? int.tryParse(_pkg!.buildNumber) ?? 0 : SibleApi.appBuild;
    return 'v$v+build.$b';
  }

  int get _currentBuild {
    if (_pkg != null) return int.tryParse(_pkg!.buildNumber) ?? 0;
    return SibleApi.appBuild;
  }

  // ---------------------------------------------------------------------------
  // Backup flows
  // ---------------------------------------------------------------------------

  Future<void> _startExport() async {
    final password = await _askPassword(isExport: true);
    if (password == null || !mounted) return;
    setState(() {
      _pendingFlow = _Flow.export;
      _busy = true;
    });
    try {
      final path = await _backup!.exportToFile(password: password);
      if (!mounted) return;
      if (path.isEmpty) return; // save dialog cancelled
      _snack(
          t(context, 'backup.exportDone').replaceAll('{n}', '$_exportCount'));
    } on BackupException catch (e) {
      if (mounted) _showBackupError(e);
    } catch (e) {
      if (mounted) {
        _snack(t(context, 'backup.failed').replaceAll('{e}', '$e'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startImport() async {
    final password = await _askPassword(isExport: false);
    if (password == null || !mounted) return;
    final ok = await _confirmRestore();
    if (ok != true || !mounted) return;
    setState(() {
      _pendingFlow = _Flow.restore;
      _busy = true;
    });
    try {
      final res = await _backup!.importFromFile(password: password);
      if (!mounted) return;
      if (res.isEmpty) return; // picker cancelled / empty backup
      var msg =
          t(context, 'backup.importDone').replaceAll('{n}', '${res.imported}');
      if (res.skipped > 0) {
        final conflict = t(context, 'backup.importConflict')
            .replaceAll('{n}', '${res.skipped}');
        msg += '\n$conflict';
      }
      _snack(msg);
    } on BackupException catch (e) {
      if (mounted) _showBackupError(e);
    } catch (e) {
      if (mounted) {
        _snack(t(context, 'backup.failed').replaceAll('{e}', '$e'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showBackupError(BackupException e) {
    if (e.code == BackupException.wrongPassword) {
      _snack(t(context, 'backup.wrongPassword'));
    } else {
      _snack(t(context, 'backup.failed').replaceAll('{e}', e.message));
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _askPassword({required bool isExport}) => showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PasswordDialog(isExport: isExport),
      );

  Future<bool?> _confirmRestore() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t(ctx, 'backup.restoreConfirmTitle')),
          content: Text(t(ctx, 'backup.restoreConfirmBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t(ctx, 'common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t(ctx, 'common.confirm')),
            ),
          ],
        ),
      );

  // ---------------------------------------------------------------------------
  // Update flows
  // ---------------------------------------------------------------------------

  Future<void> _checkForUpdates() async {
    setState(() => _checking = true);
    try {
      final info = await _updater!.checkForUpdate(
        currentVersion: _pkg?.version ?? SibleApi.appVersion,
        currentBuild: _currentBuild,
      );
      if (!mounted) return;
      setState(() {
        _update = info;
        _checked = true;
      });
    } on UpdateException catch (e) {
      if (!mounted) return;
      _snack(t(context, 'update.checkFailed').replaceAll('{e}', e.message));
    } catch (e) {
      if (!mounted) return;
      _snack(t(context, 'update.checkFailed').replaceAll('{e}', '$e'));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _toggleAutoCheck(bool v) async {
    setState(() => _autoCheck = v);
    final deps = context.read<AppDependencies>();
    await UpdateService.saveAutoCheck(deps.prefs, v);
  }

  Future<void> _openRelease() async {
    final info = _update;
    if (info == null) return;
    try {
      await launchUrl(
        Uri.parse(info.htmlUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('[maintenance] cannot open release page: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Group(
          title: t(context, 'backup.title'),
          children: [_buildBackupCard()],
        ),
        _Group(
          title: t(context, 'update.title'),
          children: [_buildUpdateCard()],
        ),
      ],
    );
  }

  Widget _buildBackupCard() {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Text(
                t(context, 'backup.hint'),
                style: const TextStyle(
                  color: SibleTheme.textSecondary,
                  fontSize: 11.5,
                  height: 1.45,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: _busy ? null : _startExport,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.enhanced_encryption, size: 17),
                      const SizedBox(width: 8),
                      Text(t(context, 'backup.export')),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: _busy ? null : _startImport,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.restore, size: 17),
                      const SizedBox(width: 8),
                      Text(t(context, 'backup.import')),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
        if (_busy) _buildOverlay(),
      ],
    );
  }

  Widget _buildOverlay() => Positioned.fill(
        child: Container(
          decoration: BoxDecoration(
            color: SibleTheme.surface.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                const SizedBox(height: 10),
                Text(
                  t(context,
                      _exporting ? 'backup.exporting' : 'backup.restoring'),
                  style: const TextStyle(
                    color: SibleTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  bool get _exporting => _pendingFlow == _Flow.export;

  Widget _buildUpdateCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: Row(
            children: [
              Text(
                t(context, 'common.version'),
                style: const TextStyle(
                  color: SibleTheme.textSecondary,
                  fontSize: 11.5,
                ),
              ),
              const Spacer(),
              Text(
                _versionLabel,
                style: const TextStyle(
                  color: SibleTheme.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _checked
              ? (_update != null
                  ? _buildUpdateBanner(_update!)
                  : _buildUpToDate())
              : const SizedBox(width: double.infinity),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: _checking ? null : _checkForUpdates,
              child: _checking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.system_update_alt, size: 17),
                        const SizedBox(width: 8),
                        Text(t(context, 'update.checkNow')),
                      ],
                    ),
            ),
          ),
        ),
        SwitchListTile(
          dense: true,
          title: Text(
            t(context, 'update.autoCheck'),
            style: const TextStyle(
              color: SibleTheme.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          value: _autoCheck,
          onChanged: (v) => _toggleAutoCheck(v),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildUpdateBanner(UpdateInfo info) {
    final headline = t(context, 'update.available')
        .replaceAll('{v}', info.version)
        .replaceAll('{b}', '${info.build}');
    return Container(
      key: ValueKey('update-${info.tag}'),
      margin: const EdgeInsets.fromLTRB(18, 4, 18, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SibleTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: SibleTheme.primary.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.rocket_launch_outlined,
                  size: 16, color: SibleTheme.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headline,
                  style: const TextStyle(
                    color: SibleTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              iconColor: SibleTheme.textSecondary,
              collapsedIconColor: SibleTheme.textSecondary,
              title: Text(
                t(context, 'update.notes'),
                style: const TextStyle(
                  color: SibleTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: 4),
                  child: SelectableText(
                    info.body.isEmpty ? '-' : info.body,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      height: 1.45,
                      color: SibleTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _openRelease,
              icon: const Icon(Icons.open_in_new, size: 15),
              label: Text(t(context, 'update.download')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpToDate() => Container(
        key: const ValueKey('update-latest'),
        margin: const EdgeInsets.fromLTRB(18, 4, 18, 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SibleTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SibleTheme.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                size: 16, color: SibleTheme.success),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t(context, 'update.upToDate'),
                style: const TextStyle(
                  color: SibleTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Replica of the Settings screen private `_Group` card (kept local so the
/// settings screen file stays untouched).
class _Group extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Group({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: SibleTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: SibleTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
              child: Text(
                title.toUpperCase(),
                style: const TextStyle(
                  color: SibleTheme.textSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Password entry dialog: single field for restore, double-confirm for
/// export (min 8 chars). Returns the password or `null` when cancelled.
class _PasswordDialog extends StatefulWidget {
  final bool isExport;

  const _PasswordDialog({required this.isExport});

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final TextEditingController _pw = TextEditingController();
  final TextEditingController _pw2 = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  void _submit() {
    final p = _pw.text;
    if (p.isEmpty) {
      setState(() => _error = t(context, 'backup.passwordRequired'));
      return;
    }
    if (widget.isExport && p.length < 8) {
      setState(() => _error = t(context, 'backup.passwordTooShort'));
      return;
    }
    if (widget.isExport && p != _pw2.text) {
      setState(() => _error = t(context, 'backup.passwordMismatch'));
      return;
    }
    Navigator.of(context).pop(p);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t(context, 'backup.passwordPrompt')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _pw,
              obscureText: true,
              autofocus: true,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: t(context, 'backup.passwordPrompt'),
                helperText:
                    widget.isExport ? t(context, 'backup.passwordHint') : null,
                errorText: _error,
              ),
            ),
            if (widget.isExport) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _pw2,
                obscureText: true,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: t(context, 'backup.confirmPassword'),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t(context, 'common.cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(t(context, 'common.confirm')),
        ),
      ],
    );
  }
}
