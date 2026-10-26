/// OPS: SharedPreferences-backed per-account manual proxy override.
///
/// Storage contract (wired into `AccountManager._ensureProxy`):
/// * `proxy.override.<accountId>` — normalized proxy URI
///   (`user:pass@host:port`, scheme stripped), absent when unset.
/// * `proxy.override.enabled.<accountId>` — bool switch state.
/// * An override is *effective* only when enabled == true AND the stored URI
///   passes [isValidProxyUri]; otherwise the account falls back to the
///   proxy pool (see [effectiveOverride]).
///
/// Lives in `services/` (not `ui/`) so background isolates can import it
/// without pulling in widgets.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'proxy_tester.dart';

class ProxyOverrideStore {
  ProxyOverrideStore._();

  /// Exact pref key holding the override URI for [accountId].
  static String uriKey(String accountId) => 'proxy.override.$accountId';

  /// Exact pref key holding the enabled flag for [accountId].
  static String enabledKey(String accountId) =>
      'proxy.override.enabled.$accountId';

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  /// Stored override URI for [accountId] (may be null / user-edited).
  static Future<String?> getOverride(String accountId) async =>
      (await _prefs()).getString(uriKey(accountId));

  /// Whether the manual-proxy switch is on for [accountId].
  static Future<bool> isEnabled(String accountId) async =>
      (await _prefs()).getBool(enabledKey(accountId)) ?? false;

  /// Persists both keys for [accountId]; a null/empty [uri] is removed so
  /// stale values never linger after the field is cleared.
  static Future<void> set(
    String accountId, {
    required bool enabled,
    String? uri,
  }) async {
    final prefs = await _prefs();
    if (uri == null || uri.isEmpty) {
      await prefs.remove(uriKey(accountId));
    } else {
      await prefs.setString(uriKey(accountId), uri);
    }
    await prefs.setBool(enabledKey(accountId), enabled);
  }

  /// Resolves the *effective* override for [accountId]: the normalized URI
  /// when the switch is on and the stored URI is valid, otherwise null
  /// (meaning: use the proxy pool as usual).
  static Future<String?> effectiveOverride(String accountId) async {
    final prefs = await _prefs();
    if (!(prefs.getBool(enabledKey(accountId)) ?? false)) return null;
    final uri = prefs.getString(uriKey(accountId));
    if (uri == null || !isValidProxyUri(uri)) return null;
    return uri;
  }

  /// PURE: splits a normalized override URI (`[user:pass@]host:port`)
  /// into `(host, port)`, or null when it cannot be parsed.
  static (String, int)? hostPortOf(String uri) {
    var rest = uri.trim();
    final at = rest.lastIndexOf('@');
    if (at >= 0) rest = rest.substring(at + 1);
    final colon = rest.lastIndexOf(':');
    if (colon <= 0 || colon == rest.length - 1) return null;
    final host = rest.substring(0, colon);
    final port = int.tryParse(rest.substring(colon + 1));
    if (host.isEmpty || port == null || port <= 0 || port > 65535) {
      return null;
    }
    return (host, port);
  }
}
