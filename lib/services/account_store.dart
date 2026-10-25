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
    final f = profileOf(a.id);
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(a.toJson()), flush: true);
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

  Future<void> writeSecrets(String id, AccountSecrets s) =>
      secure.write(key: secretKey(id), value: jsonEncode(s.toJson()));

  // --------------------------------------------------------------------------
  // Logs (ring files)
  // --------------------------------------------------------------------------

  Future<void> appendAccountLog(String id, LogEvent ev) =>
      _appendRing(logOf(id), ev, Limits.logRingSize);

  Future<void> appendGlobalLog(LogEvent ev) =>
      _appendRing(globalLog, ev, Limits.globalLogRingSize);

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
      await f.writeAsString('${lines.join('\n')}\n', flush: true);
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

  /// Wipe everything (danger zone).
  Future<void> wipeAll() async {
    if (await accountsDir.exists()) await accountsDir.delete(recursive: true);
    if (await globalLog.exists()) await globalLog.delete();
    if (await proxyPoolFile.exists()) await proxyPoolFile.delete();
  }
}
