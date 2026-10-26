/// Accounts fleet: search, list, add (manual gmail.com flow) + guided error
/// fixes ("cara atasi error") on problem accounts.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import '../../services/account_manager.dart';
import '../../services/error_advisor.dart';
import '../widgets/common.dart';
import 'account_sheet.dart';
import 'fix_sheet.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final mgr = context.watch<AccountManager>();
    final list = mgr.accounts
        .where((a) =>
            _query.isEmpty ||
            a.email.toLowerCase().contains(_query) ||
            a.displayName.toLowerCase().contains(_query))
        .toList();

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Accounts',
                    style: TextStyle(
                      color: SibleTheme.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                Text(
                  '${mgr.accounts.length}/${Limits.maxAccounts}',
                  style: TextStyle(
                    color: mgr.accounts.length >= Limits.maxAccounts
                        ? SibleTheme.warning
                        : SibleTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filledTonal(
                  onPressed: () => _showAddSheet(context),
                  icon: const Icon(Icons.person_add_alt_1, size: 20),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search email or label...',
                prefixIcon: const Icon(Icons.search,
                    size: 20, color: SibleTheme.textSecondary),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: mgr.accounts.isEmpty
                ? EmptyState(
                    icon: Icons.group_add_outlined,
                    title: 'No accounts yet',
                    subtitle:
                        'Add the gmail.com accounts you registered manually on sible.network, one by one. The app keeps every session alive.',
                    action: GradientButton(
                      label: 'Add account',
                      icon: Icons.add,
                      onPressed: () => _showAddSheet(context),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 6, bottom: 24),
                    itemCount: list.length,
                    itemBuilder: (context, i) => AccountTile(account: list[i]),
                  ),
          ),
        ],
      ),
    );
  }

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const AddAccountSheet(),
    );
  }
}

class AccountTile extends StatelessWidget {
  final Account account;

  const AccountTile({super.key, required this.account});

  @override
  Widget build(BuildContext context) {
    final mgr = context.read<AccountManager>();
    final color = statusColor(account.status);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => AccountDetailSheet(accountId: account.id),
          ),
          child: Ink(
            decoration: BoxDecoration(
              color: SibleTheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: account.enabled
                    ? SibleTheme.border
                    : SibleTheme.danger.withValues(alpha: 0.25),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          color.withValues(alpha: 0.35),
                          SibleTheme.surfaceHigh,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Text(
                      account.displayName.isNotEmpty
                          ? account.displayName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: SibleTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                account.displayName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: SibleTheme.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            StatusChip(
                              label: statusLabel(account.status),
                              color: color,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '${account.balance.toStringAsFixed(2)} SIBLE',
                              style: const TextStyle(
                                color: SibleTheme.cyan,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '+${account.ratePerHour.toStringAsFixed(2)}/h',
                              style: const TextStyle(
                                color: SibleTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            if (account.boostPct > 0) ...[
                              const SizedBox(width: 6),
                              StatusChip(
                                label: '+${account.boostPct}%',
                                color: SibleTheme.warning,
                                dot: false,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.lan,
                                size: 11, color: SibleTheme.textSecondary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                account.proxyKey ?? 'no proxy assigned',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: SibleTheme.textSecondary,
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                            Text(
                              timeAgo(account.lastCheck),
                              style: const TextStyle(
                                color: SibleTheme.textSecondary,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // FIX: one-tap guided remediation for problem accounts.
                  if (ErrorAdvisor.hasProblem(account))
                    IconButton(
                      tooltip: 'How to fix',
                      onPressed: () => showFixSheet(context, account.id),
                      icon: Icon(
                        Icons.healing_outlined,
                        size: 19,
                        color: account.status == AccountStatus.banned
                            ? SibleTheme.danger
                            : SibleTheme.warning,
                      ),
                    ),
                  Column(
                    children: [
                      SizedBox(
                        height: 30,
                        child: Switch(
                          value: account.enabled,
                          onChanged: (v) async {
                            try {
                              await mgr.saveAccount(account..enabled = v);
                            } catch (e) {
                              // Revert on disk failure + tell the user.
                              try {
                                await mgr.saveAccount(account..enabled = !v);
                              } catch (_) {}
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Gagal menyimpan: $e')),
                                );
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
