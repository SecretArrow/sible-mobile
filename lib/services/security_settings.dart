/// Security preferences: biometric app lock + keep-alive (anti-kill) flags.
///
/// Backed by `SharedPreferences` under the `security.*` key namespace. On
/// Android the shared_preferences plugin stores these as `flutter.security.*`
/// which is exactly what the native `BootReceiver` and the `sible/security`
/// method channel read back.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences-backed security settings with change notifications.
class SecuritySettings extends ChangeNotifier {
  /// Underlying store (shared with the app-wide singleton instance).
  final SharedPreferences prefs;

  SecuritySettings(this.prefs);

  /// Loads the security settings (SharedPreferences is a cached singleton,
  /// so all instances share the same values).
  static Future<SecuritySettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SecuritySettings(prefs);
  }

  /// Whether the app must be unlocked with biometrics/device credential.
  bool get lockEnabled => prefs.getBool('security.lockEnabled') ?? false;

  /// Whether the worker should restart after a phone reboot. Consumed by the
  /// native `BootReceiver` and the `sible/security` method channel.
  bool get bootStart => prefs.getBool('security.bootStart') ?? true;

  /// Whether a killed service should be relaunched. Persisted only; the
  /// native side reads this flag through the `sible/security` channel.
  bool get relaunchOnKill => prefs.getBool('security.relaunchOnKill') ?? true;

  /// Persists [v] and notifies listeners.
  Future<void> setLockEnabled(bool v) async {
    await prefs.setBool('security.lockEnabled', v);
    notifyListeners();
  }

  /// Persists [v] and notifies listeners.
  Future<void> setBootStart(bool v) async {
    await prefs.setBool('security.bootStart', v);
    notifyListeners();
  }

  /// Persists [v] and notifies listeners.
  Future<void> setRelaunchOnKill(bool v) async {
    await prefs.setBool('security.relaunchOnKill', v);
    notifyListeners();
  }
}
