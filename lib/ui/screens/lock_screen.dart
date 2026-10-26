/// Biometric app lock: full-screen [LockScreen] gate + [LockGate] wiring.
library;

import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../services/app_lock_service.dart';
import '../../services/security_settings.dart';

/// Full-screen gate that blocks the app until authentication succeeds.
///
/// The unlock button auto-presses exactly once when the gate appears; on
/// failure a retry message is shown, and when no biometric hardware is
/// available a notice is displayed (device credential is still offered).
class LockScreen extends StatefulWidget {
  /// Called on successful unlock when used as an overlay child.
  final VoidCallback? onSuccess;

  /// Whether the route should be popped with `true` on success.
  final bool popOnSuccess;

  const LockScreen({super.key, this.onSuccess, this.popOnSuccess = true});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _busy = false;
  bool _failed = false;
  bool? _hardwareAvailable;

  @override
  void initState() {
    super.initState();
    _checkHardware();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Auto-press the unlock action exactly once on appearance.
      _authenticate();
    });
  }

  Future<void> _checkHardware() async {
    final ok = await AppLockService().canAuthenticate();
    if (!mounted) return;
    setState(() => _hardwareAvailable = ok);
  }

  Future<void> _authenticate() async {
    if (_busy) return;
    _busy = true;
    setState(() => _failed = false);
    final reason = t(context, 'lock.unlockPrompt');
    final service = AppLockService();
    final result = await service.authenticate(localizedReason: reason);
    _busy = false;
    if (!mounted) return;
    if (result.ok) {
      widget.onSuccess?.call();
      if (widget.popOnSuccess) Navigator.maybeOf(context)?.pop(true);
      return;
    }
    setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    final noHardware = _hardwareAvailable == false;
    return PopScope(
      // The gate must not be bypassable with the back gesture.
      canPop: false,
      child: Scaffold(
        backgroundColor: SibleTheme.bg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: SibleTheme.cardGradient,
                      shape: BoxShape.circle,
                      border: Border.all(color: SibleTheme.border),
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      size: 42,
                      color: SibleTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    t(context, 'app.name'),
                    style: const TextStyle(
                      color: SibleTheme.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t(context, 'lock.unlockSubtitle'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: SibleTheme.textSecondary,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  if (noHardware) ...[
                    const SizedBox(height: 16),
                    _Notice(text: t(context, 'lock.unavailable')),
                  ],
                  if (_failed) ...[
                    const SizedBox(height: 16),
                    _Notice(text: t(context, 'lock.failed')),
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    width: 280,
                    height: 52,
                    child: FilledButton(
                      onPressed: _busy ? null : _authenticate,
                      style: FilledButton.styleFrom(
                        backgroundColor: SibleTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.fingerprint, size: 20),
                                const SizedBox(width: 8),
                                Text(t(context, 'lock.unlockPrompt')),
                              ],
                            ),
                    ),
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

/// Warning pill used for the failure / hardware-unavailable notices.
class _Notice extends StatelessWidget {
  final String text;

  const _Notice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: SibleTheme.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SibleTheme.warning.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: SibleTheme.warning,
          fontSize: 12,
          height: 1.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Enforces the biometric app lock around [child] (lifecycle observer).
///
/// Wiring inside `MaterialApp`:
/// ```dart
/// MaterialApp(
///   builder: (context, child) =>
///       LockGate(child: child ?? const SizedBox.shrink()),
///   home: const HomeShell(),
/// )
/// ```
/// * Above the Navigator (builder wiring): the gate renders as a
///   full-screen overlay on top of the whole app.
/// * Below the Navigator (e.g. `home: LockGate(...)`): the gate is pushed
///   as an opaque fullscreenDialog route and its result is awaited.
///
/// The gate engages on app resume after the [kLockGracePeriod] has elapsed
/// since the last successful unlock, and on cold start when required.
class LockGate extends StatefulWidget {
  /// The guarded app subtree.
  final Widget child;

  const LockGate({super.key, required this.child});

  @override
  State<LockGate> createState() => _LockGateState();

  /// Shows the gate immediately (Settings -> "Lock now").
  ///
  /// The grace-period timestamp is cleared first so the resume check keeps
  /// the lock engaged until the user authenticates again.
  static Future<void> lockNow(BuildContext context) async {
    final nav = Navigator.maybeOf(context);
    final session = LockSession.instance;
    await session.clear();
    if (nav == null) return;
    final ok = await nav.push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => const LockScreen(),
      ),
    );
    if (ok == true) await session.markUnlocked();
  }
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  SecuritySettings? _settings;
  bool _overlayLocked = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settings?.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  /// Restores the lock session, then locks on cold start when required.
  Future<void> _bootstrap() async {
    final session = LockSession.instance;
    await session.restore();
    final settings = await SecuritySettings.load();
    if (!mounted) return;
    setState(() => _settings = settings);
    settings.addListener(_onSettingsChanged);
    if (session.needsLock(settings.lockEnabled)) await _showGate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _maybeLock();
  }

  Future<void> _maybeLock() async {
    if (_busy) return;
    final settings = _settings;
    if (settings == null) return;
    if (!LockSession.instance.needsLock(settings.lockEnabled)) return;
    await _showGate();
  }

  Future<void> _showGate() async {
    if (_busy) return;
    _busy = true;
    try {
      final nav = Navigator.maybeOf(context);
      if (nav == null) {
        // Above the Navigator: overlay the gate on top of everything.
        setState(() => _overlayLocked = true);
        return;
      }
      // Below the Navigator: await the gate route before continuing.
      while (mounted) {
        final ok = await nav.push<bool>(
          MaterialPageRoute<bool>(
            fullscreenDialog: true,
            builder: (_) => const LockScreen(),
          ),
        );
        if (ok == true) {
          await LockSession.instance.markUnlocked();
          break;
        }
        if (!mounted) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _onOverlayUnlocked() async {
    if (!mounted) return;
    setState(() => _overlayLocked = false);
    await LockSession.instance.markUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    final locked = _overlayLocked && (_settings?.lockEnabled ?? false);
    return Stack(
      children: [
        widget.child,
        if (locked)
          Positioned.fill(
            child: LockScreen(
              onSuccess: _onOverlayUnlocked,
              popOnSuccess: false,
            ),
          ),
      ],
    );
  }
}
