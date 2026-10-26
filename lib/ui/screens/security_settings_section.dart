/// Security settings section: biometric app lock + keep-alive hardening.
///
/// Self-contained card group intended to be dropped into the settings
/// screen's `ListView`; the visual style mirrors the private `_Group`
/// widget used there.
library;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../services/app_lock_service.dart';
import '../../services/security_settings.dart';
import '../widgets/common.dart';
import 'lock_screen.dart';

/// Card group hosting the "App lock" and "Keep-alive (anti-kill)" controls.
///
/// Manages its own [SecuritySettings] instance; because SharedPreferences is
/// a cached singleton, every instance stays in sync automatically.
class SecuritySettingsSection extends StatefulWidget {
  const SecuritySettingsSection({super.key});

  @override
  State<SecuritySettingsSection> createState() =>
      _SecuritySettingsSectionState();
}

class _SecuritySettingsSectionState extends State<SecuritySettingsSection> {
  SecuritySettings? _settings;
  bool? _canAuth;
  bool _batteryKnown = false;
  bool _batteryOk = false;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _settings?.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    final settings = await SecuritySettings.load();
    final canAuth = await AppLockService().canAuthenticate();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _canAuth = canAuth;
    });
    settings.addListener(_onSettingsChanged);
    await _refreshBattery();
  }

  /// `isGranted`/`limited` means the battery-optimization exemption is on.
  Future<void> _refreshBattery() async {
    PermissionStatus status;
    try {
      status = await Permission.ignoreBatteryOptimizations.status;
    } catch (e) {
      debugPrint('[security] battery status failed: $e');
      return;
    }
    if (!mounted) return;
    setState(() {
      _batteryKnown = true;
      _batteryOk = status == PermissionStatus.granted ||
          status == PermissionStatus.limited;
    });
  }

  Future<void> _requestExemption() async {
    setState(() => _requesting = true);
    try {
      await Permission.ignoreBatteryOptimizations.request();
    } catch (e) {
      debugPrint('[security] exemption request failed: $e');
    }
    await _refreshBattery();
    if (mounted) setState(() => _requesting = false);
  }

  Future<void> _onLockToggle(bool want) async {
    final settings = _settings;
    if (settings == null) return;
    if (!want) {
      await settings.setLockEnabled(false);
      return;
    }
    // First enable: verify the device can actually authenticate; otherwise
    // keep the switch off and explain why.
    final service = AppLockService();
    final can = await service.canAuthenticate();
    if (!mounted) return;
    if (!can) {
      _snack(t(context, 'lock.unavailable'));
      await settings.setLockEnabled(false);
      return;
    }
    final reason = t(context, 'lock.unlockPrompt');
    final result = await service.authenticate(localizedReason: reason);
    if (!mounted) return;
    if (!result.ok) {
      _snack(t(context, 'lock.setupFailed'));
      await settings.setLockEnabled(false);
      return;
    }
    await LockSession.instance.markUnlocked();
    await settings.setLockEnabled(true);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) return const SizedBox.shrink();
    return Column(
      children: [
        _lockCard(context, settings),
        _keepAliveCard(context, settings),
      ],
    );
  }

  Widget _lockCard(BuildContext context, SecuritySettings settings) {
    final note = _canAuth == false
        ? t(context, 'lock.unavailable')
        : t(context, 'lock.availableNote');
    return _Group(
      title: t(context, 'lock.title'),
      children: [
        SwitchListTile(
          title: _t(t(context, 'lock.enable')),
          subtitle: _s(t(context, 'lock.enableHint')),
          value: settings.lockEnabled,
          onChanged: _onLockToggle,
        ),
        ListTile(
          title: _s(note),
          trailing: OutlinedButton(
            onPressed: () => LockGate.lockNow(context),
            child: Text(t(context, 'lock.lockNow')),
          ),
        ),
      ],
    );
  }

  Widget _keepAliveCard(BuildContext context, SecuritySettings settings) {
    return _Group(
      title: t(context, 'battery.title'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
          child: Text(
            t(context, 'battery.hint'),
            style: const TextStyle(
              color: SibleTheme.textSecondary,
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
        ),
        ListTile(
          title: _batteryKnown
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusChip(
                      label: t(
                        context,
                        _batteryOk ? 'battery.statusOk' : 'battery.statusBad',
                      ),
                      color: _batteryOk
                          ? SibleTheme.success
                          : SibleTheme.warning,
                    ),
                  ],
                )
              : _s(t(context, 'common.loading')),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _requesting ? null : _requestExemption,
              child: _requesting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(t(context, 'battery.requestExemption')),
            ),
          ),
        ),
        SwitchListTile(
          title: _t(t(context, 'battery.bootStart')),
          value: settings.bootStart,
          onChanged: (v) => settings.setBootStart(v),
        ),
        SwitchListTile(
          title: _t(t(context, 'battery.relaunchOnKill')),
          value: settings.relaunchOnKill,
          onChanged: (v) => settings.setRelaunchOnKill(v),
        ),
        ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 18),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          iconColor: SibleTheme.textSecondary,
          collapsedIconColor: SibleTheme.textSecondary,
          textColor: SibleTheme.textPrimary,
          collapsedTextColor: SibleTheme.textPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Text(
            t(context, 'battery.vendorGuide'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          children: [
            _vendor(t(context, 'battery.vendorGeneric')),
            _vendor(t(context, 'battery.vendorXiaomi')),
            _vendor(t(context, 'battery.vendorHuawei')),
            _vendor(t(context, 'battery.vendorSamsung')),
            _vendor(t(context, 'battery.vendorOppo')),
          ],
        ),
      ],
    );
  }

  Widget _vendor(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(Icons.chevron_right, size: 14, color: SibleTheme.cyan),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: SibleTheme.textSecondary,
                fontSize: 11.5,
                height: 1.5,
              ),
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

/// Card container replicating the settings screen group style.
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
