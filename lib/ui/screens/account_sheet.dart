/// Account detail sheet + add-account sheet (manual & mail.tm auto factory).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import '../../services/account_manager.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
// OPS: manual per-account proxy override card.
import 'proxy_override_card.dart';

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
// Add account
// ---------------------------------------------------------------------------

class AddAccountSheet extends StatefulWidget {
  const AddAccountSheet({super.key});

  @override
  State<AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends State<AddAccountSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _label = TextEditingController();
  final _referral = TextEditingController();
  final _count = TextEditingController(text: '1');
  bool _busy = false;
  final List<(int, String, bool)> _progress = [];

  @override
  void dispose() {
    _tabs.dispose();
    _email.dispose();
    _password.dispose();
    _label.dispose();
    _referral.dispose();
    _count.dispose();
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
        height: MediaQuery.of(context).size.height * 0.82,
        child: Column(
          children: [
            TabBar(
              controller: _tabs,
              dividerColor: SibleTheme.border,
              labelColor: SibleTheme.textPrimary,
              unselectedLabelColor: SibleTheme.textSecondary,
              indicatorColor: SibleTheme.primary,
              tabs: const [
                Tab(text: 'Manual login'),
                Tab(text: 'mail.tm auto'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _buildManual(roomLeft),
                  _buildMailTm(roomLeft),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManual(int roomLeft) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: 'Email'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'Password'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _label,
          decoration:
              const InputDecoration(hintText: 'Label (optional, e.g. "Main")'),
        ),
        const SizedBox(height: 18),
        GradientButton(
          label: 'Add & verify login',
          icon: Icons.login,
          busy: _busy,
          onPressed: roomLeft <= 0
              ? null
              : () async {
                  final mgr = context.read<AccountManager>();
                  if (_email.text.trim().isEmpty || _password.text.isEmpty) {
                    _toast(context, 'Email & password are required');
                    return;
                  }
                  setState(() => _busy = true);
                  try {
                    final acc = await mgr.addManualAccount(
                      email: _email.text,
                      password: _password.text,
                      label: _label.text,
                    );
                    if (acc != null) {
                      final ok = await mgr.testLogin(acc);
                      if (!mounted) return;
                      _toast(
                          context,
                          ok
                              ? 'Login OK - account ready'
                              : 'Login failed - check details');
                      if (ok && Navigator.canPop(context)) {
                        Navigator.pop(context);
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      _toast(context, '$e');
                    }
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
        ),
        if (roomLeft <= 0)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Account limit of ${Limits.maxAccounts} reached.',
              textAlign: TextAlign.center,
              style: TextStyle(color: SibleTheme.warning, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildMailTm(int roomLeft) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SibleTheme.cyan.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: SibleTheme.cyan.withValues(alpha: 0.3)),
          ),
          child: const Text(
            'Creates disposable mail.tm mailboxes, registers on Sible, '
            'auto-reads the verification OTP and logs in. Use for testing only.',
            style: TextStyle(
                color: SibleTheme.textSecondary, fontSize: 11.5, height: 1.5),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _count,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              hintText: 'How many accounts? (1-10 per batch)'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _referral,
          decoration:
              const InputDecoration(hintText: 'Referral code (optional)'),
        ),
        const SizedBox(height: 18),
        GradientButton(
          label: 'Auto-create accounts',
          icon: Icons.auto_fix_high,
          busy: _busy,
          onPressed: roomLeft <= 0
              ? null
              : () async {
                  final mgr = context.read<AccountManager>();
                  final n = int.tryParse(_count.text) ?? 1;
                  if (n < 1 || n > 10) {
                    _toast(context, 'Batch size must be 1..10');
                    return;
                  }
                  setState(() {
                    _busy = true;
                    _progress.clear();
                  });
                  try {
                    final created = await mgr.createMailTmAccounts(
                      count: n,
                      referralCode: _referral.text.trim(),
                      startIndex: 0,
                      onProgress: (i, stage, {ok = true}) {
                        if (mounted) {
                          setState(() => _progress.add((i, stage, ok)));
                        }
                      },
                    );
                    if (mounted) {
                      _toast(context, 'Created $created account(s)');
                    }
                  } catch (e) {
                    if (mounted) _toast(context, 'Failed: $e');
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
        ),
        const SizedBox(height: 14),
        ..._progress.reversed.take(20).map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    p.$3 ? Icons.check_circle_outline : Icons.error_outline,
                    size: 14,
                    color: p.$3 ? SibleTheme.success : SibleTheme.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '#${p.$1 + 1}  ${p.$2}',
                      style: const TextStyle(
                          color: SibleTheme.textSecondary, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
