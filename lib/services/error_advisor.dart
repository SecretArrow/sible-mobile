/// ERROR ADVISOR: turns an account's failure state into human guidance.
///
/// "Beri cara atasi error" - every problem status maps to a structured
/// advice object: a title, ordered fix steps and machine-actionable buttons
/// the UI can wire up (retry login, enter OTP, refresh proxies, ...).
/// Pure logic, no Flutter imports, fully unit-testable.
library;

import '../models/models.dart';

/// Actions the fix-sheet can perform. Kept as an enum so the advisor stays
/// decoupled from widgets and every button is explicit + testable.
enum FixAction {
  enterOtp,
  retryLogin,
  updatePassword,
  refreshProxyPool,
  disableProxies,
  allowDirectFallback,
  runCycle,
  removeAccount,
  openGmail,
}

class ErrorAdvice {
  final String titleKey;
  final String stepsKey;
  final List<FixAction> actions;

  const ErrorAdvice({
    required this.titleKey,
    required this.stepsKey,
    required this.actions,
  });
}

class ErrorAdvisor {
  const ErrorAdvisor._();

  /// Returns the best guidance for [a]'s current status + last error text.
  /// Never returns null - unknown problems fall back to generic advice.
  static ErrorAdvice adviseFor(Account a) {
    switch (a.status) {
      case AccountStatus.needsOtp:
        return const ErrorAdvice(
          titleKey: 'fix.needsOtp.title',
          stepsKey: 'fix.needsOtp.steps',
          actions: [
            FixAction.enterOtp,
            FixAction.openGmail,
            FixAction.retryLogin,
          ],
        );
      case AccountStatus.needsRelogin:
        return const ErrorAdvice(
          titleKey: 'fix.needsRelogin.title',
          stepsKey: 'fix.needsRelogin.steps',
          actions: [
            FixAction.updatePassword,
            FixAction.retryLogin,
            FixAction.enterOtp,
          ],
        );
      case AccountStatus.banned:
        return const ErrorAdvice(
          titleKey: 'fix.banned.title',
          stepsKey: 'fix.banned.steps',
          actions: [FixAction.removeAccount],
        );
      case AccountStatus.error:
        final err = (a.lastError ?? '').toLowerCase();
        final networkish = err.contains('timeout') ||
            err.contains('network') ||
            err.contains('proxy') ||
            err.contains('socket') ||
            err.contains('connection') ||
            err.contains('no healthy proxy');
        if (networkish) {
          return const ErrorAdvice(
            titleKey: 'fix.proxyError.title',
            stepsKey: 'fix.proxyError.steps',
            actions: [
              FixAction.refreshProxyPool,
              FixAction.runCycle,
              FixAction.disableProxies,
              FixAction.allowDirectFallback,
            ],
          );
        }
        if (err.contains('otp')) {
          return const ErrorAdvice(
            titleKey: 'fix.needsOtp.title',
            stepsKey: 'fix.needsOtp.steps',
            actions: [
              FixAction.enterOtp,
              FixAction.openGmail,
            ],
          );
        }
        return const ErrorAdvice(
          titleKey: 'fix.generic.title',
          stepsKey: 'fix.generic.steps',
          actions: [FixAction.runCycle, FixAction.retryLogin],
        );
      case AccountStatus.newAccount:
      case AccountStatus.idle:
      case AccountStatus.mining:
      case AccountStatus.claiming:
      case AccountStatus.disabled:
        return const ErrorAdvice(
          titleKey: 'fix.generic.title',
          stepsKey: 'fix.generic.steps',
          actions: [FixAction.runCycle],
        );
    }
  }

  /// Whether the account tile should surface a "fix" affordance.
  static bool hasProblem(Account a) =>
      a.status == AccountStatus.error ||
      a.status == AccountStatus.banned ||
      a.status == AccountStatus.needsOtp ||
      a.status == AccountStatus.needsRelogin;
}
