/// Settings: service, schedule, notifications, proxy, danger zone + feature
/// sections (InferHub AI brain, maintenance, security, smart notifications).
///
/// Every async handler is guarded: failures revert the UI state and show a
/// snackbar instead of dying silently or corrupting the toggle state.
library;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../services/background_service.dart';
import '../../services/notification_service.dart';
import '../../state/providers.dart';

// INFERHUB: AI brain settings card (optional InferHub integration).
import 'inferhub_settings_section.dart';
// MAINTENANCE: encrypted backup/restore + update checker.
import 'maintenance_settings_section.dart';
// SECURITY: app lock + keep-alive (anti-kill).
import 'security_settings_section.dart';
// OPS: smart notifications (error-only, grouping, cooldown).
import 'notification_settings_section.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _referral;
  bool _serviceBusy = false;

  @override
  void initState() {
    super.initState();
    _referral =
        TextEditingController(text: context.read<SettingsStore>().referralCode);
  }

  @override
  void dispose() {
    _referral.dispose();
    super.dispose();
  }

  /// Runs an async action with try/catch + user feedback. Returns true on
  /// success, false on failure - so callers never report false success.
  Future<bool> _guard(Future<void> Function() action, {String? label}) async {
    try {
      await action();
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(label != null ? '$label gagal: $e' : 'Error: $e')),
      );
      return false;
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toggleService(bool v) async {
    if (_serviceBusy) return; // spam guard
    _serviceBusy = true;
    final settings = context.read<SettingsStore>();
    try {
      final service = await configureBackgroundService(enabled: v);
      if (v) {
        await service.startService();
        await settings.setServiceEnabled(true);
        await NotificationService.instance.requestPermission();
      } else {
        await settings.setServiceEnabled(false);
        await stopBackgroundService(service);
      }
    } catch (e) {
      await settings.setServiceEnabled(!v); // revert on failure
      _toast('Gagal ${v ? 'menyalakan' : 'mematikan'} service: $e');
    } finally {
      _serviceBusy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final deps = context.read<AppDependencies>();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Text(
              'Settings',
              style: TextStyle(
                color: SibleTheme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          _Group(
            title: 'Automation',
            children: [
              SwitchListTile(
                title: _t('Background service'),
                subtitle: _s(
                    'Foreground worker keeps cycles running, even after reboot'),
                value: settings.serviceEnabled,
                onChanged: (v) => _guard(() => _toggleService(v),
                    label: 'Background service'),
              ),
              ListTile(
                title: _t('Check interval'),
                subtitle: _s('Cron between automation cycles'),
                trailing: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 5, label: Text('5m')),
                    ButtonSegment(value: 10, label: Text('10m')),
                    ButtonSegment(value: 15, label: Text('15m')),
                  ],
                  selected: {settings.intervalMinutes},
                  onSelectionChanged: (s) => _guard(
                      () => settings.setIntervalMinutes(s.first),
                      label: 'Interval'),
                ),
              ),
              ListTile(
                title: _t('Parallel accounts'),
                subtitle: _s(
                    'Concurrent account cycles (${settings.cycleConcurrency}x)'),
                trailing: SizedBox(
                  width: 160,
                  child: Slider(
                    value: settings.cycleConcurrency.toDouble(),
                    min: 1,
                    max: 12,
                    divisions: 11,
                    label: '${settings.cycleConcurrency}',
                    onChanged: (v) => settings.setCycleConcurrency(v.round()),
                  ),
                ),
              ),
            ],
          ),
          _Group(
            title: 'Notifications',
            children: [
              SwitchListTile(
                title: _t('Cycle summary'),
                subtitle: _s('One aggregated notification per cycle'),
                value: settings.notifyCycleSummary,
                onChanged: (v) => _guard(
                    () => settings.setNotifyCycleSummary(v),
                    label: 'Notifikasi'),
              ),
              SwitchListTile(
                title: _t('Alerts'),
                subtitle: _s('Bans, login failures, proxy exhaustion'),
                value: settings.notifyAlerts,
                onChanged: (v) => _guard(() async {
                  await settings.setNotifyAlerts(v);
                  if (v) await NotificationService.instance.requestPermission();
                }, label: 'Alerts'),
              ),
              ListTile(
                title: _t('Grant notification permission'),
                subtitle: _s('Required on Android 13+'),
                trailing: OutlinedButton(
                  onPressed: () => _guard(() async {
                    final granted =
                        await NotificationService.instance.requestPermission();
                    await Permission.notification.request();
                    _toast(granted
                        ? 'Notifikasi diizinkan'
                        : 'Izin diminta - cek pengaturan sistem');
                  }, label: 'Izin notifikasi'),
                  child: const Text('Request'),
                ),
              ),
              ListTile(
                title: _t('Disable battery optimization'),
                subtitle: _s('Prevents Android from killing the worker'),
                trailing: OutlinedButton(
                  onPressed: () => _guard(() async {
                    final status =
                        await Permission.ignoreBatteryOptimizations.request();
                    _toast(status.isGranted
                        ? 'Battery optimization dinonaktifkan'
                        : 'Permintaan ditolak/dibatalkan');
                  }, label: 'Battery optimization'),
                  child: const Text('Allow'),
                ),
              ),
            ],
          ),
          _Group(
            title: 'Proxy engine',
            children: [
              SwitchListTile(
                title: _t('Use proxies'),
                subtitle: _s('Auto-fetch free proxies, unique per account'),
                value: settings.proxyEnabled,
                onChanged: (v) =>
                    _guard(() => settings.setProxyEnabled(v), label: 'Proxy'),
              ),
              SwitchListTile(
                title: _t('Direct fallback'),
                subtitle:
                    _s('Use the device IP when no healthy proxy is available'),
                value: settings.allowDirectFallback,
                onChanged: (v) => _guard(
                    () => settings.setAllowDirectFallback(v),
                    label: 'Direct fallback'),
              ),
              ListTile(
                title: _t('Pool target'),
                subtitle: _s(
                    'Keep up to N validated proxies (${settings.poolTarget})'),
                trailing: SizedBox(
                  width: 160,
                  child: Slider(
                    value: settings.poolTarget.toDouble(),
                    min: 60,
                    max: Limits.maxPoolTarget.toDouble(),
                    divisions: 11,
                    label: '${settings.poolTarget}',
                    onChanged: (v) => settings.setPoolTarget(v.round()),
                  ),
                ),
              ),
            ],
          ),
          // INFERHUB: AI brain settings card (optional InferHub integration).
          const InferHubSettingsSection(),
          // MAINTENANCE: encrypted backup/restore + update checker.
          const MaintenanceSettingsSection(),
          // SECURITY: biometric app lock + keep-alive hardening.
          const SecuritySettingsSection(),
          // OPS: smart notification policy.
          const SmartNotificationsSection(),
          _Group(
            title: t(context, 'common.language'),
            children: [
              ListTile(
                title: _t(t(context, 'settings.language')),
                subtitle: _s(LocaleController.instance.lang.label),
                trailing: PopupMenuButton<AppLang>(
                  initialValue: LocaleController.instance.lang,
                  onSelected: (lang) async {
                    LocaleController.instance.set(lang);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('settings.lang', lang.code);
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(value: AppLang.en, child: Text('English')),
                    PopupMenuItem(
                        value: AppLang.id, child: Text('Bahasa Indonesia')),
                  ],
                ),
              ),
            ],
          ),
          _Group(
            title: 'Account factory',
            children: [
              ListTile(
                title: _t('Default referral code'),
                subtitle: _s('Applied to new mail.tm registrations'),
                trailing: SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _referral,
                    decoration:
                        const InputDecoration(hintText: 'code', isDense: true),
                    onSubmitted: (v) => _guard(
                        () => settings.setReferralCode(v.trim()),
                        label: 'Referral'),
                  ),
                ),
              ),
            ],
          ),
          _Group(
            title: 'Danger zone',
            children: [
              ListTile(
                title: _t('Wipe all local data', color: SibleTheme.danger),
                subtitle:
                    _s('Removes every account, log, secret and proxy binding'),
                trailing: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SibleTheme.danger,
                    side: BorderSide(
                        color: SibleTheme.danger.withValues(alpha: 0.4)),
                  ),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Wipe everything?'),
                        content: const Text(
                            'All ${Limits.maxAccounts}-account data, secrets, logs and the proxy pool will be permanently deleted from this device.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel')),
                          FilledButton(
                              style: FilledButton.styleFrom(
                                  backgroundColor: SibleTheme.danger),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Wipe')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      final wiped = await _guard(() async {
                        await deps.store.wipeAll();
                        await deps.proxyEngine.prune(keepTop: 0);
                        // Also clear in-memory state so the wipe is real even
                        // before restart (accounts, logs, counters).
                        deps.accountManager.accounts.clear();
                        deps.accountManager.notifyListeners();
                      }, label: 'Wipe');
                      if (wiped) {
                        _toast('All data wiped. Restart the app.');
                      }
                    }
                  },
                  child: const Text('Wipe'),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Sible Miner v${SibleApi.appVersion} · data is stored locally and '
              'isolated per account · use responsibly and respect '
              'Sible Network terms.',
              style: TextStyle(
                  color: SibleTheme.textSecondary, fontSize: 11, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Text _t(String s, {Color color = SibleTheme.textPrimary}) => Text(
        s,
        style:
            TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600),
      );

  Text _s(String s) => Text(
        s,
        style: const TextStyle(color: SibleTheme.textSecondary, fontSize: 11.5),
      );
}

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
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}
