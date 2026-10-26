/// FIX SHEET: "Cara atasi error" for a problem account.
///
/// Rendered from the accounts list / detail sheet whenever an account is in
/// an error state. Shows a title, ordered fix steps (localized) and action
/// buttons wired to the manager/proxy engine. Also owns the manual OTP
/// entry dialog used by the gmail.com manual account flow.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/account_manager.dart';
import '../../services/error_advisor.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

// ---------------------------------------------------------------------------
// Manual OTP dialog
// ---------------------------------------------------------------------------

/// Opens the manual OTP verification dialog. Returns true when the code was
/// accepted (account state refreshed inside). Safe to call from anywhere.
Future<bool> showOtpDialog(BuildContext context, Account account) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _OtpDialog(account: account),
  );
  return ok == true;
}

class _OtpDialog extends StatefulWidget {
  final Account account;

  const _OtpDialog({required this.account});

  @override
  State<_OtpDialog> createState() => _OtpDialogState();
}

class _OtpDialogState extends State<_OtpDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final mgr = context.read<AccountManager>();
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await mgr.verifyOtpForAccount(widget.account, code);
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _busy = false;
          _error = t(context, 'account.otp.invalid');
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _resend() async {
    final mgr = context.read<AccountManager>();
    try {
      await mgr.resendOtpForAccount(widget.account);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'account.otp.sent'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Resend failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SibleTheme.surface,
      title: Text(
        t(context, 'account.otp.title'),
        style: const TextStyle(
            color: SibleTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w800),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${t(context, 'account.otp.subtitle')}\n${widget.account.email}',
            style: const TextStyle(
                color: SibleTheme.textSecondary, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
                color: SibleTheme.textPrimary,
                fontSize: 20,
                letterSpacing: 8,
                fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              hintText: t(context, 'account.otp.hint'),
              counterText: '',
              errorText: _error,
            ),
            onSubmitted: (_) => _verify(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _resend,
          child: Text(t(context, 'account.otp.resend')),
        ),
        FilledButton(
          onPressed: _busy ? null : _verify,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(t(context, 'account.otp.verify')),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Fix sheet
// ---------------------------------------------------------------------------

/// Shows the error-advisor sheet for [accountId]. Returns when closed.
Future<void> showFixSheet(BuildContext context, String accountId) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FixSheet(accountId: accountId),
  );
}

class FixSheet extends StatefulWidget {
  final String accountId;

  const FixSheet({super.key, required this.accountId});

  @override
  State<FixSheet> createState() => _FixSheetState();
}

class _FixSheetState extends State<FixSheet> {
  bool _busy = false;
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Account? _find(AccountManager mgr) {
    for (final a in mgr.accounts) {
      if (a.id == widget.accountId) return a;
    }
    return null;
  }

  Future<void> _run(
    Future<bool> Function() action, {
    String? okMsg,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    // Capture translated strings before any await (BuildContext must never
    // cross an async gap).
    final done = t(context, 'fix.done');
    final failed = t(context, 'fix.failed');
    try {
      final ok = await action();
      _toast(ok ? (okMsg ?? done) : failed);
    } catch (e) {
      _toast('$failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleAction(FixAction action, Account acc) async {
    final mgr = context.read<AccountManager>();
    final deps = context.read<AppDependencies>();
    switch (action) {
      case FixAction.enterOtp:
        final ok = await showOtpDialog(context, acc);
        if (ok && mounted) Navigator.pop(context);
        return;
      case FixAction.openGmail:
        try {
          await launchUrl(
            Uri.parse('https://mail.google.com/'),
            mode: LaunchMode.externalApplication,
          );
        } catch (e) {
          _toast('Gmail: $e');
        }
        return;
      case FixAction.retryLogin:
        await _run(
          () => mgr.testLogin(acc),
          okMsg: t(context, 'account.add.ok'),
        );
        return;
      case FixAction.updatePassword:
        // Inline: handled by the password field below, not a button tap.
        return;
      case FixAction.refreshProxyPool:
        await _run(() async {
          final st = await deps.proxyEngine.refreshPool();
          _toast('Pool: ${st.alive} alive / ${st.total}');
          return true;
        });
        return;
      case FixAction.disableProxies:
        await _run(() async {
          await deps.settings.setProxyEnabled(false);
          return true;
        });
        return;
      case FixAction.allowDirectFallback:
        await _run(() async {
          await deps.settings.setAllowDirectFallback(true);
          return true;
        });
        return;
      case FixAction.runCycle:
        await _run(
          () => mgr.runCycle(acc),
          okMsg: t(context, 'fix.done'),
        );
        return;
      case FixAction.removeAccount:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: SibleTheme.surface,
            title: Text(t(context, 'fix.removeAccount')),
            content:
                Text('${acc.displayName} ${t(context, 'fix.removeAccount')}?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(t(context, 'common.cancel'))),
              FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: SibleTheme.danger),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(t(context, 'common.delete'))),
            ],
          ),
        );
        if (confirmed == true) {
          try {
            await mgr.removeAccount(acc.id);
            if (mounted) Navigator.pop(context);
          } catch (e) {
            _toast('Remove failed: $e');
          }
        }
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mgr = context.watch<AccountManager>();
    final acc = _find(mgr);
    if (acc == null) {
      return SizedBox(
          height: 160, child: Center(child: Text(t(context, 'common.empty'))));
    }
    final advice = ErrorAdvisor.adviseFor(acc);

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const Icon(Icons.healing_outlined,
                    color: SibleTheme.warning, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t(context, advice.titleKey),
                    style: const TextStyle(
                        color: SibleTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800),
                  ),
                ),
                StatusChip(
                    label: statusLabel(acc.status),
                    color: statusColor(acc.status)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              acc.email,
              style: const TextStyle(
                  color: SibleTheme.textSecondary, fontSize: 12),
            ),
            if (acc.lastError != null && acc.lastError!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: SibleTheme.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: SibleTheme.danger.withValues(alpha: 0.3)),
                ),
                child: Text(
                  acc.lastError!,
                  style:
                      const TextStyle(color: SibleTheme.danger, fontSize: 11.5),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: SibleTheme.cyan.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: SibleTheme.cyan.withValues(alpha: 0.3)),
              ),
              child: Text(
                t(context, advice.stepsKey),
                style: const TextStyle(
                    color: SibleTheme.textPrimary, fontSize: 12.5, height: 1.6),
              ),
            ),
            const SizedBox(height: 16),

            // Password update for needsRelogin.
            if (advice.actions.contains(FixAction.updatePassword)) ...[
              TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: t(context, 'fix.newPassword'),
                ),
              ),
              const SizedBox(height: 10),
              GradientButton(
                label: t(context, 'fix.updatePassword'),
                icon: Icons.save_outlined,
                busy: _busy,
                onPressed: () async {
                  if (_password.text.isEmpty) {
                    _toast(t(context, 'account.add.required'));
                    return;
                  }
                  await _run(
                    () => mgr.updatePassword(acc, _password.text),
                    okMsg: t(context, 'account.add.ok'),
                  );
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(height: 12),
            ],

            // Action buttons.
            ...advice.actions
                .where((a) => a != FixAction.updatePassword)
                .map((a) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _actionButton(a, acc),
                    )),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(FixAction action, Account acc) {
    switch (action) {
      case FixAction.enterOtp:
        return OutlinedButton.icon(
          onPressed: _busy ? null : () => _handleAction(action, acc),
          icon: const Icon(Icons.password_outlined, size: 18),
          label: Text(t(context, 'fix.enterOtp')),
        );
      case FixAction.openGmail:
        return OutlinedButton.icon(
          onPressed: _busy ? null : () => _handleAction(action, acc),
          icon: const Icon(Icons.mail_outline, size: 18),
          label: Text(t(context, 'account.detail.openGmail')),
        );
      case FixAction.retryLogin:
        return OutlinedButton.icon(
          onPressed: _busy ? null : () => _handleAction(action, acc),
          icon: const Icon(Icons.login, size: 18),
          label: Text(t(context, 'fix.retryLogin')),
        );
      case FixAction.refreshProxyPool:
        return OutlinedButton.icon(
          onPressed: _busy ? null : () => _handleAction(action, acc),
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(t(context, 'fix.refreshPool')),
        );
      case FixAction.disableProxies:
        return OutlinedButton.icon(
          onPressed: _busy ? null : () => _handleAction(action, acc),
          icon: const Icon(Icons.vpn_key_off_outlined, size: 18),
          label: Text(t(context, 'fix.disableProxies')),
        );
      case FixAction.allowDirectFallback:
        return OutlinedButton.icon(
          onPressed: _busy ? null : () => _handleAction(action, acc),
          icon: const Icon(Icons.public, size: 18),
          label: Text(t(context, 'fix.allowDirect')),
        );
      case FixAction.runCycle:
        return OutlinedButton.icon(
          onPressed: _busy ? null : () => _handleAction(action, acc),
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: Text(t(context, 'fix.runCycle')),
        );
      case FixAction.removeAccount:
        return OutlinedButton.icon(
          onPressed: _busy ? null : () => _handleAction(action, acc),
          style: OutlinedButton.styleFrom(
            foregroundColor: SibleTheme.danger,
            side: BorderSide(color: SibleTheme.danger.withValues(alpha: 0.4)),
          ),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text(t(context, 'fix.removeAccount')),
        );
      case FixAction.updatePassword:
        return const SizedBox.shrink();
    }
  }
}
