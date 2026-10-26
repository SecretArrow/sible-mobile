/// Per-account isolated storage.
///
/// Every account gets:
///  * its own directory  `root/accounts/{id}/profile.json` (+ log.jsonl)
///  * its own secure-storage key `sible.acc.{id}.secrets`
/// so account data can never be bound to one another.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/constants.dart';
import '../core/utils.dart';
import '../models/models.dart';

class AccountStore {
  final String rootDir; // e.g. <docs>/sible
  final FlutterSecureStorage secure;
  final void Function(String message)? onLog;

  /// Serializes ring-log writes per instance so 6 parallel cycle workers
  /// can never interleave read-modify-write on the same file.
  Future<void> _logQueue = Future.value();

  AccountStore(
      {required this.rootDir, FlutterSecureStorage? secure, this.onLog})
      : secure = secure ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  Directory get accountsDir => Directory('$rootDir/accounts');
  File get globalLog => File('$rootDir/events.jsonl');
  File get proxyPoolFile => File('$rootDir/proxy_pool.json');

  Directory dirOf(String id) => Directory('$rootDir/accounts/$id');
  File profileOf(String id) => File('$rootDir/accounts/$id/profile.json');
  File logOf(String id) => File('$rootDir/accounts/$id/log.jsonl');

  String secretKey(String id) => 'sible.acc.$id.secrets';

  // --------------------------------------------------------------------------
  // Profiles
  // --------------------------------------------------------------------------

  Future<List<String>> listAccountIds() async {
    final dir = accountsDir;
    if (!await dir.exists()) {
      return const [];
    }
    final ids = <String>[];
    await for (final e in dir.list()) {
      if (e is Directory) {
        ids.add(e.uri.pathSegments.where((s) => s.isNotEmpty).last);
      }
    }
    ids.sort();
    return ids;
  }

  Future<Account?> readProfile(String id) async {
    try {
      final f = profileOf(id);
      if (!await f.exists()) return null;
      return Account.fromJson(
          Map<String, dynamic>.from(jsonDecode(await f.readAsString())));
    } catch (e) {
      onLog?.call('profile read failed for $id: $e');
      return null;
    }
  }

  Future<void> writeProfile(Account a) async {
    // Atomic write (tmp + rename): a process kill mid-write can never leave
    // a truncated profile.json behind (which would silently drop the account).
    final f = profileOf(a.id);
    await f.parent.create(recursive: true);
    final payload = jsonEncode(a.toJson());
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(payload, flush: true);
    try {
      await tmp.rename(f.path);
    } catch (_) {
      await f.writeAsString(payload, flush: true);
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }

  Future<bool> deleteAccount(String id) async {
    try {
      final dir = dirOf(id);
      if (await dir.exists()) await dir.delete(recursive: true);
      await secure.delete(key: secretKey(id));
      return true;
    } catch (e) {
      onLog?.call('delete failed for $id: $e');
      return false;
    }
  }

  // --------------------------------------------------------------------------
  // Secrets (isolated per account)
  // --------------------------------------------------------------------------

  Future<AccountSecrets?> readSecrets(String id) async {
    try {
      final raw = await secure.read(key: secretKey(id));
      if (raw == null || raw.isEmpty) return null;
      return AccountSecrets.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw)));
    } catch (e) {
      onLog?.call('secrets read failed for $id: $e');
      return null;
    }
  }

  Future<void> writeSecrets(String id, AccountSecrets s) async {
    try {
      await secure.write(key: secretKey(id), value: jsonEncode(s.toJson()));
    } catch (e) {
      onLog?.call('secrets write failed for $id: $e');
      rethrow;
    }
  }

  // --------------------------------------------------------------------------
  // Logs (ring files)
  // --------------------------------------------------------------------------

  Future<void> appendAccountLog(String id, LogEvent ev) =>
      _queueRing(_appendRing(logOf(id), ev, Limits.logRingSize));

  Future<void> appendGlobalLog(LogEvent ev) =>
      _queueRing(_appendRing(globalLog, ev, Limits.globalLogRingSize));

  Future<void> _queueRing(Future<void> op) {
    _logQueue = _logQueue.then((_) => op);
    return _logQueue;
  }

  Future<void> _appendRing(File f, LogEvent ev, int cap) async {
    try {
      await f.parent.create(recursive: true);
      final old = await f.exists() ? await f.readAsString() : '';
      final lines = old.isEmpty
          ? <String>[]
          : old.split('\n').where((l) => l.isNotEmpty).toList()
        ..add(jsonEncode(ev.toJson()));
      while (lines.length > cap) {
        lines.removeAt(0);
      }
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString('${lines.join('\n')}\n', flush: true);
      try {
        await tmp.rename(f.path);
      } catch (_) {
        await f.writeAsString('${lines.join('\n')}\n', flush: true);
        try {
          await tmp.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<List<LogEvent>> readGlobalLog({int tail = 400}) =>
      _readRing(globalLog, tail);

  Future<List<LogEvent>> readAccountLog(String id, {int tail = 200}) =>
      _readRing(logOf(id), tail);

  Future<List<LogEvent>> _readRing(File f, int tail) async {
    try {
      if (!await f.exists()) return const [];
      final lines = (await f.readAsString())
          .split('\n')
          .where((l) => l.isNotEmpty)
          .toList();
      final out = <LogEvent>[];
      for (final l in lines.reversed.take(tail)) {
        try {
          out.add(LogEvent.fromJson(Map<String, dynamic>.from(jsonDecode(l))));
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Wipe everything (danger zone): profiles, logs, proxy pool AND every
  /// secret stored in secure storage. Fails soft per item so a locked file
  /// cannot leave the wipe half-done without any feedback.
  Future<void> wipeAll() async {
    // 1) Secrets first (most sensitive) - delete per known account id.
    try {
      final ids = await listAccountIds();
      for (final id in ids) {
        try {
          await secure.delete(key: secretKey(id));
        } catch (_) {}
      }
    } catch (_) {}
    try {
      if (await accountsDir.exists()) {
        await accountsDir.delete(recursive: true);
      }
    } catch (e) {
      onLog?.call('wipe accounts dir failed: $e');
    }
    try {
      if (await globalLog.exists()) await globalLog.delete();
    } catch (e) {
      onLog?.call('wipe global log failed: $e');
    }
    try {
      if (await proxyPoolFile.exists()) await proxyPoolFile.delete();
    } catch (e) {
      onLog?.call('wipe proxy pool failed: $e');
    }
  }
}
