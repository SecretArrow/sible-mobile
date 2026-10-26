/// GitHub Releases update checker for the Sible Miner app.
///
/// Fetches the latest releases from the public GitHub API (no auth), parses
/// tags like `v2.1.0+build.6` (also `v2.1.0+6` and plain `v2.1.0`) and
/// compares them against the running app version from package_info_plus.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Failure thrown by [UpdateService.checkForUpdate] with a stable [code].
class UpdateException implements Exception {
  /// DNS/socket/timeout failures.
  static const String network = 'NETWORK';

  /// GitHub answered with a non-200 status.
  static const String httpError = 'HTTP';

  /// Response was not the expected JSON array.
  static const String badResponse = 'BAD_RESPONSE';

  /// Stable error code, one of the static constants above.
  final String code;

  /// Human-readable details (safe to show in a snackbar).
  final String message;

  const UpdateException(this.code, this.message);

  @override
  String toString() => 'UpdateException($code): $message';
}

/// A published GitHub release, narrowed down to update-check fields.
class UpdateInfo {
  /// Raw tag, e.g. `v2.2.0+build.22`.
  final String tag;

  /// Semver triple without the `v` prefix, e.g. `2.2.0`.
  final String version;

  /// Build number from the tag (0 when the tag carries none).
  final int build;

  /// Release display name (falls back to [tag]).
  final String name;

  /// Release notes body (Markdown).
  final String body;

  /// Web page of the release, opened in an external browser.
  final String htmlUrl;

  /// When GitHub recorded the release as published.
  final DateTime? publishedAt;

  const UpdateInfo({
    required this.tag,
    required this.version,
    required this.build,
    required this.name,
    required this.body,
    required this.htmlUrl,
    this.publishedAt,
  });
}

/// Checks GitHub Releases for a newer stable build of the app.
class UpdateService {
  /// Public releases endpoint (no auth token needed).
  static const String repoApiUrl =
      'https://api.github.com/repos/SecretArrow/sible-mobile/releases'
      '?per_page=10';

  /// SharedPreferences key for the auto-check-at-startup switch.
  static const String prefKeyAutoCheck = 'update.autoCheck';

  /// Request timeout before the check is reported as a network failure.
  static const Duration timeout = Duration(seconds: 15);

  /// GitHub rejects requests without a User-Agent.
  static const String userAgent = 'sible-mobile-app';

  final http.Client _client;
  final bool _ownsClient;

  UpdateService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  // ---------------------------------------------------------------------------
  // Pure helpers (no plugins - safe for unit tests)
  // ---------------------------------------------------------------------------

  /// Parses a release tag into `(version, build)`.
  ///
  /// Tolerated shapes: `v2.1.0+build.6`, `v2.1.0+6`, `v2.1.0` and the same
  /// without the leading `v`. Returns `null` for anything unparseable.
  static ({int build, String version})? parseTag(String tag) {
    var t = tag.trim();
    if (t.startsWith('v')) t = t.substring(1);

    var versionPart = t;
    var build = 0;
    final plus = t.indexOf('+');
    if (plus >= 0) {
      versionPart = t.substring(0, plus);
      final raw = t.substring(plus + 1).trim();
      final m = RegExp(r'^build[.\-_]?(\d+)$').firstMatch(raw);
      build = int.tryParse(m?.group(1) ?? raw) ?? -1;
      if (build < 0) return null;
    }

    final parts = versionPart.split('.');
    if (parts.length != 3) return null;
    final nums = parts.map<int?>(int.tryParse).toList();
    for (final n in nums) {
      if (n == null || n < 0) return null;
    }
    return (version: parts.join('.'), build: build);
  }

  /// Compares two version strings (`2.1.0`, `v2.1.0+build.6`, `2.1.0+21`).
  ///
  /// Returns -1 when [current] is older than [other], 1 when newer and 0
  /// when equal. The semver triple is compared first, then the build number.
  /// Throws [ArgumentError] when either string is unparseable.
  static int compareVersions(String current, String other) {
    final a = parseTag(current);
    final b = parseTag(other);
    if (a == null) {
      throw ArgumentError.value(current, 'current', 'unparseable version');
    }
    if (b == null) {
      throw ArgumentError.value(other, 'other', 'unparseable version');
    }
    final av = a.version.split('.').map(int.parse).toList();
    final bv = b.version.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      if (av[i] != bv[i]) return av[i] < bv[i] ? -1 : 1;
    }
    if (a.build != b.build) return a.build < b.build ? -1 : 1;
    return 0;
  }

  /// Pure release picker: walks the GitHub releases array (newest first),
  /// skips drafts, prereleases and unparseable tags and returns an
  /// [UpdateInfo] for the first stable release strictly newer than
  /// `[currentVersion]+[currentBuild]` - or `null` when up to date.
  ///
  /// Malformed entries (non-objects, missing `tag_name`) are skipped.
  static UpdateInfo? firstNewerRelease(
    List<dynamic> releases,
    String currentVersion,
    int currentBuild,
  ) {
    for (final item in releases) {
      if (item is! Map) continue;
      if (item['draft'] == true || item['prerelease'] == true) continue;
      final tag = item['tag_name'];
      if (tag is! String) continue;
      final parsed = parseTag(tag);
      if (parsed == null) continue;
      if (compareVersions('$currentVersion+$currentBuild', tag) < 0) {
        return UpdateInfo(
          tag: tag,
          version: parsed.version,
          build: parsed.build,
          name: item['name'] is String && (item['name'] as String).isNotEmpty
              ? item['name'] as String
              : tag,
          body: item['body'] is String ? item['body'] as String : '',
          htmlUrl: item['html_url'] is String
              ? item['html_url'] as String
              : 'https://github.com/SecretArrow/sible-mobile/releases',
          publishedAt: DateTime.tryParse(item['published_at'] as String? ?? ''),
        );
      }
      // Newest stable release is not newer -> nothing newer exists.
      return null;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Network flow
  // ---------------------------------------------------------------------------

  /// Checks GitHub for a newer stable release.
  ///
  /// Returns the [UpdateInfo] when an update is available, `null` when the
  /// app is up to date. Network/HTTP/parse failures are rethrown as
  /// [UpdateException]. [currentVersion]/[currentBuild] default to the
  /// values reported by package_info_plus (injected for testability).
  Future<UpdateInfo?> checkForUpdate({
    String? currentVersion,
    int? currentBuild,
  }) async {
    String version;
    int build;
    if (currentVersion != null) {
      version = currentVersion;
      build = currentBuild ?? 0;
    } else {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      build = int.tryParse(info.buildNumber) ?? 0;
    }
    final releases = await _fetchReleases();
    return firstNewerRelease(releases, version, build);
  }

  Future<List<dynamic>> _fetchReleases() async {
    http.Response resp;
    try {
      resp = await _client.get(
        Uri.parse(repoApiUrl),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': userAgent,
        },
      ).timeout(timeout);
    } on TimeoutException catch (e) {
      throw UpdateException(UpdateException.network, 'Request timed out: $e');
    } on Exception catch (e) {
      throw UpdateException(UpdateException.network, 'Network error: $e');
    }
    if (resp.statusCode != 200) {
      throw UpdateException(
          UpdateException.httpError, 'GitHub answered HTTP ${resp.statusCode}');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    } on FormatException catch (e) {
      throw UpdateException(UpdateException.badResponse, 'Bad JSON: $e');
    }
    if (decoded is! List) {
      throw const UpdateException(
          UpdateException.badResponse, 'Expected a JSON array of releases');
    }
    return decoded;
  }

  /// Releases the HTTP client when this service created it.
  void dispose() {
    if (_ownsClient) _client.close();
  }

  // ---------------------------------------------------------------------------
  // Preferences
  // ---------------------------------------------------------------------------

  /// Reads `update.autoCheck` (default: true).
  static bool loadAutoCheck(SharedPreferences prefs) =>
      prefs.getBool(prefKeyAutoCheck) ?? true;

  /// Persists `update.autoCheck`.
  static Future<void> saveAutoCheck(SharedPreferences prefs, bool value) =>
      prefs.setBool(prefKeyAutoCheck, value);
}
