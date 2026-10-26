/// Settings section for the smart notification policy (#7).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../services/smart_notifications.dart';
import '../../state/providers.dart';

/// Settings card bound to [NotifPolicy]: smart mode master switch,
/// error-only mode, daily summary and the repeat-alert cooldown slider.
///
/// Visual style replicates the private `_Group` card from
/// `settings_screen.dart` (kept local on purpose — that file is not edited).
/// Drop it into the Settings screen's `ListView`.
class SmartNotificationsSection extends StatefulWidget {
  /// Optional injected policy (e.g. for previews/tests). When null, one is
  /// created from the app-wide SharedPreferences (`AppDependencies`).
  final NotifPolicy? policy;

  const SmartNotificationsSection({super.key, this.policy});

  @override
  State<SmartNotificationsSection> createState() =>
      _SmartNotificationsSectionState();
}

class _SmartNotificationsSectionState extends State<SmartNotificationsSection> {
  NotifPolicy? _ownPolicy;

  NotifPolicy get _policy => widget.policy ?? _ownPolicy!;

  @override
  void initState() {
    super.initState();
    if (widget.policy == null) {
      _ownPolicy = NotifPolicy(context.read<AppDependencies>().prefs);
    }
  }

  @override
  void dispose() {
    if (widget.policy == null) _ownPolicy?.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _policy,
      builder: (context, _) => _group(
        t(context, 'settings.notifications'),
        [
          SwitchListTile(
            title: _t(t(context, 'notif.smart')),
            subtitle: _s(t(context, 'notif.smartHint')),
            value: _policy.smartEnabled,
            onChanged: (v) => _policy.setSmartEnabled(v),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            title: _t(t(context, 'notif.errorOnly')),
            subtitle: _s(t(context, 'notif.errorOnlyHint')),
            value: _policy.errorOnly,
            onChanged: (v) => _policy.setErrorOnly(v),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            title: _t(t(context, 'notif.summary')),
            subtitle: _s(t(context, 'notif.summaryHint')),
            value: _policy.dailySummary,
            onChanged: (v) => _policy.setDailySummary(v),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: _t(t(context, 'notif.cooldown')),
            subtitle: _s('${_policy.cooldownMinutes} min'),
            trailing: SizedBox(
              width: 160,
              child: Slider(
                value: _policy.cooldownMinutes.clamp(0, 120).toDouble(),
                min: 0,
                max: 120,
                divisions: 24,
                label: '${_policy.cooldownMinutes}m',
                onChanged: (v) => _policy.setCooldownMinutes(v.round()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _group(String title, List<Widget> children) {
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
