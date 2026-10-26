/// Account detail sheet + add-account sheet (manual gmail.com flow).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import '../../services/account_manager.dart';
import '../../services/error_advisor.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
// OPS: manual per-account proxy override card.
import 'proxy_override_card.dart';
// FIX: error-advisor sheet + manual OTP dialog.
import 'fix_sheet.dart';

// ---------------------------------------------------------------------------
// Account detail
// ---------------------------------------------------------------------------

class AccountDetailSheet extends StatefulWidget {
  final String accountId;

  const AccountDetailSheet({super.key, required this.accountId});

  @override
  State<AccountDetailSheet> createState() => _AccountDetailSheetState();
}

class _AccountDetailSheetState extends State<AccountDetailSheet> {
  List<LogEvent> _logs = const [];
  bool _cycleBusy = false;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final deps = context.read<AppDependencies>();
    final logs = await deps.store.readAccountLog(widget.accountId, tail: 40);
    if (mounted) setState(() => _logs = logs);
  }

  /// Persists the account with try/catch + user feedback - a disk failure
  /// must never surface as a silent unhandled async error.
  Future<void> _saveAcc(AccountManager mgr, Account acc) async {
    try {
      await mgr.saveAccount(acc);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mgr = context.watch<AccountManager>();
    final acc = mgr.accounts.where((a) => a.id == widget.accountId).firstOrNull;
    if (acc == null) {
      return const SizedBox(
          height: 200, child: Center(child: Text('Account removed')));
    }
    final color = statusColor(acc.status);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: color.withValues(alpha: 0.2),
                      child: Text(
                        acc.displayName.isNotEmpty
                            ? acc.displayName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w800,
                            fontSize: 17),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            acc.displayName,
                            style: const TextStyle(
                              color: SibleTheme.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            acc.email,
                            style: const TextStyle(
                                color: SibleTheme.textSecondary,
                                fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                    StatusChip(label: statusLabel(acc.status), color: color),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        label: 'Balance',
                        value: acc.balance.toStringAsFixed(3),
                        icon: Icons.diamond_outlined,
                        color: SibleTheme.cyan,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StatTile(
                        label: 'Boost',
                        value: '+${acc.boostPct}%',
                        icon: Icons.bolt,
                        color: SibleTheme.warning,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StatTile(
                        label: 'Claims today',
                        value: '${acc.claimsToday}',
                        icon: Icons.redeem_outlined,
                        color: SibleTheme.success,
                      ),
                    ),
                  ],
                ),
                if (acc.lastError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: SibleTheme.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: SibleTheme.danger.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            size: 16, color: SibleTheme.danger),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            acc.lastError!,
                            style: const TextStyle(
                                color: SibleTheme.danger, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // FIX: guided remediation for problem accounts + inline OTP
                // entry card so gmail.com accounts can verify in one place.
                if (ErrorAdvisor.hasProblem(acc)) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SibleTheme.warning,
                      side: BorderSide(
                          color: SibleTheme.warning.withValues(alpha: 0.5)),
                    ),
                    onPressed: () => showFixSheet(context, acc.id),
                    icon: const Icon(Icons.healing_outlined, size: 18),
                    label: Text(t(context, 'fix.title')),
                  ),
                ],
                if (acc.status == AccountStatus.needsOtp) ...[
                  const SizedBox(height: 10),
                  _OtpCard(acc: acc),
                ],
                const SizedBox(height: 12),
                // KEEPALIVE: when the session was last confirmed alive.
                GlowCard(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    leading: const Icon(Icons.verified_user_outlined,
                        color: SibleTheme.success),
                    title: Text(
                      t(context, 'account.detail.keepalive'),
                      style: const TextStyle(
                          color: SibleTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${t(context, 'keepalive.lastRun')}: ${acc.lastKeepalive == null ? t(context, 'keepalive.never') : timeAgo(acc.lastKeepalive)}',
                      style: const TextStyle(
                          color: SibleTheme.textSecondary, fontSize: 11),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Per-account automation settings.
                GlowCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _SwitchRow(
                        title: 'Account enabled',
                        subtitle: 'Include this account in every cycle',
                        value: acc.enabled,
                        onChanged: (v) async {
                          acc.enabled = v;
                          await _saveAcc(mgr, acc);
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _SwitchRow(
                        title: 'Auto accelerate',
                        subtitle: 'Watch acceleration slots automatically',
                        value: acc.autoAccelerate,
                        onChanged: (v) async {
                          acc.autoAccelerate = v;
                          await _saveAcc(mgr, acc);
                        },
                      ),
                      if (acc.autoAccelerate)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                          child: SegmentedButton<int>(
                            segments: const [
                              ButtonSegment(value: 20, label: Text('20%')),
                              ButtonSegment(value: 40, label: Text('40%')),
                              ButtonSegment(value: 60, label: Text('60%')),
                            ],
                            selected: {acc.accelerateTargetPct},
                            onSelectionChanged: (s) async {
                              acc.accelerateTargetPct = s.first;
                              await _saveAcc(mgr, acc);
                            },
                          ),
                        ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _SwitchRow(
                        title: 'Auto extension',
                        subtitle: 'Open explorer/extension apps each cycle',
                        value: acc.autoExtension,
                        onChanged: (v) async {
                          acc.autoExtension = v;
                          await _saveAcc(mgr, acc);
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _SwitchRow(
                        title: 'Auto reward tasks',
                        subtitle: 'Claim eligible reward tasks',
                        value: acc.autoClaimTasks,
                        onChanged: (v) async {
                          acc.autoClaimTasks = v;
                          await _saveAcc(mgr, acc);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Proxy binding.
                GlowCard(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    leading:
                        const Icon(Icons.lan_outlined, color: SibleTheme.cyan),
                    title: Text(
                      acc.proxyKey ?? 'No proxy assigned',
                      style: const TextStyle(
                          color: SibleTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      'Unique egress per account · latency ${acc.proxyLabel ?? '-'}',
                      style: const TextStyle(
                          color: SibleTheme.textSecondary, fontSize: 11),
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        try {
                          await mgr.proxyEngine.release(acc.id);
                          acc.proxyKey = null;
                          await mgr.saveAccount(acc);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Proxy released - will re-assign next cycle')),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Gagal release proxy: $e')),
                            );
                          }
                        }
                      },
                      child: const Text('Reassign'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // OPS: manual per-account proxy override + live test.
                ProxyOverrideCard(accountId: acc.id),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        // The real per-account busy state (cycleRunning is
                        // only set by runAllCycles) + a local busy flag.
                        onPressed: (_cycleBusy || mgr.cycleRunning)
                            ? null
                            : () async {
                                setState(() => _cycleBusy = true);
                                try {
                                  final ok = await mgr.runCycle(acc);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(ok
                                              ? 'Cycle finished OK'
                                              : 'Cycle finished with errors')),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text('Cycle gagal: $e')),
                                    );
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _cycleBusy = false);
                                  }
                                }
                                await _loadLogs();
                              },
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: Text(_cycleBusy ? 'Running...' : 'Run cycle'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Remove account?'),
                              content: Text(
                                  '${acc.displayName} and its isolated data will be deleted.'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel')),
                                FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Remove')),
                              ],
                            ),
                          );
                          if (confirmed == true && context.mounted) {
                            try {
                              await mgr.removeAccount(acc.id);
                              if (context.mounted) Navigator.pop(context);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Gagal menghapus: $e')),
                                );
                              }
                            }
                          }
                        },
                        style: OutlinedButton.styleFrom(
                            foregroundColor: SibleTheme.danger,
                            side: BorderSide(
                                color:
                                    SibleTheme.danger.withValues(alpha: 0.4))),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Remove'),
                      ),
                    ),
                  ],
                ),
                SectionHeader('Account log',
                    padding: const EdgeInsets.fromLTRB(4, 18, 4, 8)),
                if (_logs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'No log entries yet.',
                      style: TextStyle(
                          color: SibleTheme.textSecondary, fontSize: 12),
                    ),
                  )
                else
                  ..._logs.map((e) => LogTile(event: e)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text(
        title,
        style: const TextStyle(
          color: SibleTheme.textPrimary,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: SibleTheme.textSecondary, fontSize: 11.5),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add account (manual gmail.com flow)
// ---------------------------------------------------------------------------

class AddAccountSheet extends StatefulWidget {
  const AddAccountSheet({super.key});

  @override
  State<AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends State<AddAccountSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _label = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mgr = context.watch<AccountManager>();
    final roomLeft = Limits.maxAccounts - mgr.accounts.length;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              t(context, 'account.add.title'),
              style: const TextStyle(
                  color: SibleTheme.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SibleTheme.cyan.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: SibleTheme.cyan.withValues(alpha: 0.3)),
              ),
              child: Text(
                t(context, 'account.add.gmailHint'),
                style: const TextStyle(
                    color: SibleTheme.textSecondary,
                    fontSize: 11.5,
                    height: 1.5),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(hintText: 'you@gmail.com'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              obscureText: true,
              decoration:
                  InputDecoration(hintText: t(context, 'account.add.password')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _label,
              decoration:
                  InputDecoration(hintText: t(context, 'account.add.label')),
            ),
            const SizedBox(height: 18),
            GradientButton(
              label: t(context, 'account.add.cta'),
              icon: Icons.login,
              busy: _busy,
              onPressed: roomLeft <= 0 ? null : () => _submit(mgr),
            ),
            if (roomLeft <= 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  t(context, 'account.add.limitReached'),
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: SibleTheme.warning, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(AccountManager mgr) async {
    if (_busy) return;
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      _toast(context, t(context, 'account.add.required'));
      return;
    }
    setState(() => _busy = true);
    Account? acc;
    try {
      acc = await mgr.addManualAccount(
        email: _email.text,
        password: _password.text,
        label: _label.text,
      );
    } catch (e) {
      if (mounted) _toast(context, '$e');
    }
    if (acc == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    // Verify the login immediately; if the server demands an OTP challenge
    // (common for gmail.com accounts), open the manual OTP dialog right
    // away so the user finishes setup in one flow.
    bool ok = false;
    try {
      ok = await mgr.testLogin(acc);
    } catch (e) {
      if (mounted) _toast(context, '$e');
    }
    if (!ok && mounted && acc.status == AccountStatus.needsOtp) {
      final verified = await showOtpDialog(context, acc);
      ok = verified;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(
      context,
      ok
          ? t(context, 'account.add.ok')
          : t(context, 'account.add.savedNoVerify'),
    );
    if (Navigator.canPop(context)) Navigator.pop(context);
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

// ---------------------------------------------------------------------------
// Inline OTP card (account detail)
// ---------------------------------------------------------------------------

class _OtpCard extends StatefulWidget {
  final Account acc;

  const _OtpCard({required this.acc});

  @override
  State<_OtpCard> createState() => _OtpCardState();
}

class _OtpCardState extends State<_OtpCard> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final mgr = context.read<AccountManager>();
    if (_code.text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final ok = await mgr.verifyOtpForAccount(widget.acc, _code.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? t(context, 'account.add.ok')
              : t(context, 'account.otp.invalid')),
        ),
      );
      if (ok) _code.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t(context, 'fix.failed')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SibleTheme.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SibleTheme.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(context, 'account.otp.title'),
            style: const TextStyle(
                color: SibleTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            t(context, 'account.otp.subtitle'),
            style: const TextStyle(
                color: SibleTheme.textSecondary, fontSize: 11.5, height: 1.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  style: const TextStyle(
                      color: SibleTheme.textPrimary,
                      letterSpacing: 6,
                      fontWeight: FontWeight.w800),
                  decoration: InputDecoration(
                    hintText: t(context, 'account.otp.hint'),
                    counterText: '',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _verify(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _busy ? null : _verify,
                style:
                    FilledButton.styleFrom(backgroundColor: SibleTheme.warning),
                child: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(t(context, 'account.otp.verify')),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      final mgr = context.read<AccountManager>();
                      // Capture before the async gap (context-safety lint).
                      final messenger = ScaffoldMessenger.of(context);
                      final sentMsg = t(context, 'account.otp.sent');
                      try {
                        await mgr.resendOtpForAccount(widget.acc);
                        messenger.showSnackBar(
                          SnackBar(content: Text(sentMsg)),
                        );
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(content: Text('Resend failed: $e')),
                        );
                      }
                    },
              child: Text(t(context, 'account.otp.resend')),
            ),
          ),
        ],
      ),
    );
  }
}
