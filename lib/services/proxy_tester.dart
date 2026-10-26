/// Manual proxy helpers (#8): URI validation / normalization and an
/// end-to-end proxy tester (exit IP, country, latency).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Optional scheme prefix (`http://`, `https://`, `socks5://`, …).
final RegExp _schemeRe = RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]*://');

/// Digits-only port (rejects `+80`, `0x10`, `-1`, …).
final RegExp _portRe = RegExp(r'^\d+$');

/// Parsed proxy URI: optional `user:pass` credentials, host, port.
class ProxyParts {
  /// Credentials as written, e.g. `user:pass` (null when absent).
  final String? userpass;

  /// Host name or IPv4 address (no scheme, no port).
  final String host;

  /// Port in the 1..65535 range.
  final int port;

  const ProxyParts(this.userpass, this.host, this.port);
}

/// Parses a proxy URI of the form `host:port`, `user:pass@host:port` with
/// an optional `scheme://` prefix (stripped). Returns null when malformed:
/// empty host/userinfo, non-numeric port or a port outside 1..65535.
ProxyParts? parseProxyUri(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  s = s.replaceFirst(_schemeRe, '');
  if (s.isEmpty || s.contains(RegExp(r'[\s/]'))) return null;
  String? userpass;
  final at = s.lastIndexOf('@');
  if (at >= 0) {
    userpass = s.substring(0, at);
    if (userpass.isEmpty || userpass.contains('@')) return null;
    s = s.substring(at + 1);
  }
  final colon = s.lastIndexOf(':');
  if (colon <= 0 || colon == s.length - 1) return null;
  final host = s.substring(0, colon);
  final portStr = s.substring(colon + 1);
  if (host.isEmpty || host.contains(':')) return null;
  if (!_portRe.hasMatch(portStr)) return null;
  final port = int.tryParse(portStr);
  if (port == null || port < 1 || port > 65535) return null;
  return ProxyParts(userpass, host, port);
}

/// Whether [raw] is a usable proxy URI (`host:port` or `user:pass@host:port`,
/// optional scheme prefix, port 1..65535).
bool isValidProxyUri(String raw) => parseProxyUri(raw) != null;

/// Canonical `user:pass@host:port` (credentials preserved, scheme dropped),
/// or null when [raw] is not a valid proxy URI.
String? normalizeProxyUri(String raw) {
  final p = parseProxyUri(raw);
  if (p == null) return null;
  final creds = p.userpass == null ? '' : '${p.userpass}@';
  return '$creds${p.host}:${p.port}';
}

/// Outcome of [testProxyUri].
class ProxyTestResult {
  /// Whether the proxy reached the check endpoints.
  final bool ok;

  /// Exit IP as seen by the internet (null on failure).
  final String? ip;

  /// Country of the exit IP (null when lookup failed — best effort only).
  final String? country;

  /// Round-trip latency of the IP check in milliseconds.
  final int? latencyMs;

  /// Short human-readable failure reason (null on success).
  final String? error;

  const ProxyTestResult({
    required this.ok,
    this.ip,
    this.country,
    this.latencyMs,
    this.error,
  });
}

/// Tests a proxy end-to-end: routes a GET to `https://api.ipify.org` through
/// `PROXY <host:port>` for the exit IP (this also measures latency), then
/// asks `https://ipwho.is/` for the country (best effort — its failure is
/// ignored). Any exception becomes a friendly [ProxyTestResult.error].
Future<ProxyTestResult> testProxyUri(
  String uri, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final parts = parseProxyUri(uri);
  if (parts == null) {
    return const ProxyTestResult(ok: false, error: 'invalid proxy URI');
  }
  final client = HttpClient();
  try {
    client.connectionTimeout = timeout;
    client.findProxy = (u) => 'PROXY ${parts.host}:${parts.port}';
    final sw = Stopwatch()..start();
    final ip = await _getIp(client, timeout);
    sw.stop();
    final country = await _getCountry(client, ip, timeout);
    return ProxyTestResult(
      ok: true,
      ip: ip,
      country: country,
      latencyMs: sw.elapsedMilliseconds,
    );
  } on TimeoutException {
    return const ProxyTestResult(ok: false, error: 'timed out');
  } on HandshakeException {
    return const ProxyTestResult(ok: false, error: 'TLS handshake failed');
  } on SocketException catch (e) {
    return ProxyTestResult(ok: false, error: _friendly(e));
  } catch (e) {
    return ProxyTestResult(ok: false, error: _friendly(e));
  } finally {
    client.close(force: true);
  }
}

Future<String> _getIp(HttpClient client, Duration timeout) async {
  final req = await client
      .getUrl(Uri.parse('https://api.ipify.org?format=json'))
      .timeout(timeout);
  final res = await req.close().timeout(timeout);
  final body = await res.transform(utf8.decoder).join().timeout(timeout);
  if (res.statusCode != 200) {
    throw HttpException('HTTP ${res.statusCode} from ipify');
  }
  final decoded = jsonDecode(body);
  final ip = decoded is Map ? decoded['ip'] : null;
  if (ip is! String || ip.isEmpty) {
    throw const FormatException('unexpected ipify response');
  }
  return ip;
}

/// Best-effort country lookup; returns null on any failure (spec: ignored).
Future<String?> _getCountry(HttpClient client, String ip, Duration t) async {
  try {
    final req =
        await client.getUrl(Uri.parse('https://ipwho.is/$ip')).timeout(t);
    final res = await req.close().timeout(t);
    final body = await res.transform(utf8.decoder).join().timeout(t);
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(body);
    final country = decoded is Map ? decoded['country'] : null;
    return country is String && country.isNotEmpty ? country : null;
  } catch (_) {
    return null;
  }
}

/// Collapses an exception into a single short snackbar-friendly line.
String _friendly(Object e) {
  var s = e.toString();
  final nl = s.indexOf('\n');
  if (nl > 0) s = s.substring(0, nl);
  if (s.length > 120) s = '${s.substring(0, 117)}...';
  return s;
}
