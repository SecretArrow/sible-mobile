/// Proxy engine: fetches free proxy lists, validates them, and guarantees
/// a *unique* proxy per account (no two accounts share an egress IP).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../core/constants.dart';
import '../core/utils.dart';
import '../models/models.dart';

class ProxySource {
  final String name;
  final Uri url;
  final bool geonodeFormat;
  const ProxySource(this.name, this.url, {this.geonodeFormat = false});

  static ProxySource proxyscrape() => ProxySource(
      'proxyscrape',
      Uri.parse(
          'https://api.proxyscrape.com/v2/?request=displayproxies&protocol=http&timeout=10000&country=all&ssl=all&anonymity=all'));

  static ProxySource thespeedx() => ProxySource(
      'thespeedx',
      Uri.parse(
          'https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/http.txt'));

  static ProxySource monosans() => ProxySource(
      'monosans',
      Uri.parse(
          'https://raw.githubusercontent.com/monosans/proxy-list/main/proxies/http.txt'));

  static ProxySource geonode() => ProxySource(
      'geonode',
      Uri.parse(
          'https://proxylist.geonode.com/api/proxy-list?protocols=http%2Chttps&limit=500&page=1&sort_by=lastChecked&sort_type=desc'),
      geonodeFormat: true);
}

class ProxyStats {
  final int total;
  final int alive;
  final int assigned;

  const ProxyStats(
      {required this.total, required this.alive, required this.assigned});
}

class ProxyEngine {
  /// Ordered list of free proxy sources.
  static final List<ProxySource> sources = [
    ProxySource.proxyscrape(),
    ProxySource.thespeedx(),
    ProxySource.monosans(),
    ProxySource.geonode(),
  ];

  final Map<String, ProxyEntry> _pool = {};
  final Set<String> _blacklistedFor = {}; // "accountId|proxyKey"
  final String Function() _storePathResolver;
  final void Function(String message)? onLog;

  /// Serializes all pool writes (concurrent workers must never interleave
  /// writeAsString on the same file) and makes them atomic (tmp + rename),
  /// so a process kill mid-write can never corrupt the pool.
  Future<void> _saveQueue = Future.value();
  bool _refreshInFlight = false;

  ProxyEngine({required String Function() storePathResolver, this.onLog})
      : _storePathResolver = storePathResolver;

  Future<void> _persist() {
    _saveQueue = _saveQueue.then((_) => _doSave());
    return _saveQueue;
  }

  Future<void> _doSave() async {
    try {
      final f = File(_storePathResolver());
      await f.parent.create(recursive: true);
      final payload = jsonEncode({
        'savedAt': DateTime.now().toIso8601String(),
        'pool': _pool.values
            .take(Limits.maxPoolTarget)
            .map((p) => p.toJson())
            .toList(),
        'blacklist': _blacklistedFor.toList(),
      });
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(payload, flush: true);
      try {
        await tmp.rename(f.path);
      } catch (_) {
        // Fallback (rename can fail across some FS): non-atomic but valid.
        await f.writeAsString(payload, flush: true);
        try {
          await tmp.delete();
        } catch (_) {}
      }
    } catch (e) {
      onLog?.call('proxy pool save failed: $e');
    }
  }

  List<ProxyEntry> get all => _pool.values.toList();
  int get aliveCount => _pool.values.where((p) => p.alive).length;
  int get assignedCount =>
      _pool.values.where((p) => p.assignedTo != null).length;

  ProxyStats stats() => ProxyStats(
      total: _pool.length, alive: aliveCount, assigned: assignedCount);

  String? labelFor(String? key) {
    if (key == null) return null;
    final p = _pool[key];
    if (p == null) return key;
    final country = '';
    return '$country${p.host}:${p.port}';
  }

  // --------------------------------------------------------------------------
  // Persistence
  // --------------------------------------------------------------------------

  Future<void> load() async {
    try {
      final f = File(_storePathResolver());
      if (await f.exists()) {
        final decoded = jsonDecode(await f.readAsString());
        if (decoded is Map) {
          final list = decoded['pool'] as List? ?? const [];
          final black = decoded['blacklist'] as List? ?? const [];
          for (final item in list) {
            if (item is Map) {
              final p = ProxyEntry.fromJson(Map<String, dynamic>.from(item));
              _pool[p.key] = p;
            }
          }
          _blacklistedFor
            ..clear()
            ..addAll(black.cast<String>());
        }
      }
    } catch (e) {
      onLog?.call('proxy pool load failed: $e');
    }
  }

  Future<void> save() => _persist();

  // --------------------------------------------------------------------------
  // Fetch + validate
  // --------------------------------------------------------------------------

  Future<List<ProxyEntry>> fetchFromSources(
      {Duration timeout = const Duration(seconds: 15)}) async {
    final out = <ProxyEntry>[];
    for (final src in sources) {
      HttpClient? client;
      try {
        client = HttpClient()..connectionTimeout = timeout;
        final req = await client.getUrl(src.url);
        final res = await req.close().timeout(timeout);
        // Body read is bounded - a stalled source must not hang the refresh.
        final body = await res.transform(utf8.decoder).join().timeout(timeout);
        final parsed = src.geonodeFormat
            ? ProxyEntry.parseGeonode(body)
            : ProxyEntry.parseRawList(body);
        out.addAll(parsed);
        onLog?.call('${src.name}: +${parsed.length} proxies');
      } catch (e) {
        onLog?.call('${src.name} fetch failed: $e');
      } finally {
        // ALWAYS release the socket pool, success or failure (no fd leak).
        try {
          client?.close(force: true);
        } catch (_) {}
      }
    }
    // Deduplicate by host:port.
    final map = <String, ProxyEntry>{for (final p in out) p.key: p};
    return map.values.toList();
  }

  /// Validate [candidates] against the Sible API host. Returns alive entries.
  Future<List<ProxyEntry>> validateProxies(
    List<ProxyEntry> candidates, {
    int concurrency = 40,
    Duration timeout = const Duration(seconds: 10),
    Uri? testUrl,
    void Function(int done, int total)? onProgress,
  }) async {
    final url =
        testUrl ?? Uri.parse('https://prod.sible.network/mining/status');
    final alive = <ProxyEntry>[];
    var done = 0;
    final total = candidates.length;

    Future<void> worker(int index) async {
      for (var i = index; i < total; i += concurrency) {
        final c = candidates[i];
        final sw = Stopwatch()..start();
        var ok = false;
        HttpClient? client;
        try {
          client = HttpClient();
          client.connectionTimeout = timeout;
          client.findProxy = (uri) => 'PROXY ${c.host}:${c.port}';
          final req = await client.getUrl(url);
          req.followRedirects = false;
          final res = await req.close().timeout(timeout);
          // Drain is bounded - one zombie candidate must not hang the refresh.
          await res.drain<void>().timeout(timeout);
          // Any HTTP response means the proxy reached the target.
          ok = res.statusCode > 0;
        } catch (_) {
          ok = false;
        } finally {
          // ALWAYS close, success or failure (no per-candidate fd leak).
          try {
            client?.close(force: true);
          } catch (_) {}
        }
        sw.stop();
        done++;
        onProgress?.call(done, total);
        if (ok) {
          alive.add(ProxyEntry(
            host: c.host,
            port: c.port,
            protocol: c.protocol,
            latencyMs: sw.elapsedMilliseconds,
            alive: true,
            lastChecked: DateTime.now().toUtc(),
          ));
        }
      }
    }

    final workers = List.generate(min(concurrency, max(total, 1)), worker);
    await Future.wait(workers);
    alive.sort((a, b) => a.latencyMs.compareTo(b.latencyMs));
    return alive;
  }

  /// Full refresh: fetch fresh lists, validate, rebuild the pool (keeping
  /// assignments to accounts whose proxy is still alive).
  ///
  /// Single-flight: concurrent callers await the SAME in-progress refresh
  /// instead of launching parallel fetch/validate storms (rate-limit +
  /// battery protection when the pool runs dry with many accounts).
  Future<ProxyStats> refreshPool({
    int target = Limits.defaultPoolTarget,
    void Function(String stage)? onStage,
  }) async {
    if (_refreshInFlight) {
      onLog?.call('refreshPool: already in progress - joining');
      while (_refreshInFlight) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      return stats();
    }
    _refreshInFlight = true;
    try {
      onStage?.call('fetching');
      final candidates = await fetchFromSources();
      if (candidates.isEmpty) {
        onLog?.call('no proxy candidates found from sources');
        await _persist();
        return stats();
      }
      candidates.shuffle(rng);
      final limited = candidates.take(max(target * 3, target)).toList();

      onStage?.call('validating');
      final alive = await validateProxies(limited,
          onProgress: null, timeout: const Duration(seconds: 10));
      final trimmed = alive.take(target).toList();

      // Preserve assignments for still-alive proxies.
      final oldAssignments = {
        for (final p in _pool.values)
          if (p.assignedTo != null) p.key: p.assignedTo,
      };
      _pool
        ..clear()
        ..addEntries([for (final p in trimmed) MapEntry(p.key, p)]);
      for (final entry in _pool.values) {
        final acct = oldAssignments[entry.key];
        entry.assignedTo = acct;
      }
      await _persist();
      onLog?.call('pool refreshed: ${_pool.length} alive proxies');
      return stats();
    } finally {
      _refreshInFlight = false;
    }
  }

  /// Replace the whole pool with a freshly validated list while preserving
  /// account bindings for proxies that are still alive.
  Future<void> replacePool(
    List<ProxyEntry> fresh, {
    Map<String, String?> keepAssignments = const {},
  }) async {
    _pool
      ..clear()
      ..addEntries([for (final p in fresh) MapEntry(p.key, p)]);
    for (final entry in _pool.values) {
      final acct = keepAssignments[entry.key];
      if (acct != null) entry.assignedTo = acct;
    }
    await save();
  }

  // --------------------------------------------------------------------------
  // Assignment - one unique proxy per account
  // --------------------------------------------------------------------------

  bool isBlacklistedFor(String accountId, String proxyKey) =>
      _blacklistedFor.contains('$accountId|$proxyKey');

  void blacklistFor(String accountId, String proxyKey) {
    _blacklistedFor.add('$accountId|$proxyKey');
    final p = _pool[proxyKey];
    if (p != null) {
      p.failures++;
      if (p.failures >= 2) {
        p.alive = false;
        p.assignedTo = null;
      }
    }
    // Serialized through the save queue - never interleaves with other saves.
    _persist();
  }

  /// Release the proxy bound to [accountId] (if any).
  Future<void> release(String accountId) async {
    for (final p in _pool.values) {
      if (p.assignedTo == accountId) p.assignedTo = null;
    }
    await save();
  }

  /// Acquire an exclusive alive proxy for [accountId]. Never returns a proxy
  /// already bound to another account.
  Future<ProxyEntry?> acquireFor(String accountId,
      {bool rebalance = false}) async {
    // Existing binding that is still healthy?
    if (!rebalance) {
      for (final p in _pool.values) {
        if (p.assignedTo == accountId && p.alive) return p;
      }
    } else {
      await release(accountId);
    }
    final candidates = _pool.values
        .where((p) => p.alive && p.assignedTo == null)
        .where((p) => !isBlacklistedFor(accountId, p.key))
        .toList()
      ..sort((a, b) => a.latencyMs.compareTo(b.latencyMs));
    if (candidates.isEmpty) return null;
    final pick = candidates.first;
    pick.assignedTo = accountId;
    await save();
    return pick;
  }

  /// Drop proxies that have been dead for a while and prune blacklist noise.
  Future<void> prune({int keepTop = Limits.maxPoolTarget}) async {
    final dead = _pool.values.where((p) => !p.alive).map((p) => p.key).toList();
    for (final k in dead) {
      _pool.remove(k);
    }
    if (_pool.length > keepTop) {
      final sorted = _pool.values.toList()
        ..sort((a, b) => a.latencyMs.compareTo(b.latencyMs));
      final keep = sorted.take(keepTop).map((p) => p.key).toSet();
      _pool.removeWhere((k, _) => !keep.contains(k));
    }
    if (_blacklistedFor.length > 5000) _blacklistedFor.clear();
    await _persist();
  }
}
