import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'db.dart';
import 'repo.dart';

class SyncResult {
  SyncResult({required this.success, this.message, this.uploadedCount = 0});
  final bool success;
  final String? message;
  final int uploadedCount;
}

class SyncService {
  SyncService(this.l, this.api, this.repo);
  final LocalDb l;
  final Api api;
  final Repo repo;

  final pending = ValueNotifier<int>(0); // the waiting-to-upload badge count
  final isSyncing = ValueNotifier<bool>(false);
  final lastError = ValueNotifier<String?>(null);
  final lastSyncedAt = ValueNotifier<DateTime?>(null);

  bool _running = false;

  Future<void> refreshCount() async {
    try {
      final o = (await l.db.rawQuery('SELECT COUNT(*) c FROM outbox')).first['c'] as int;
      // Do not double-count photos that are already queued in outbox
      final p = (await l.db.rawQuery(
          "SELECT COUNT(*) c FROM photo WHERE uploaded=0 AND NOT EXISTS (SELECT 1 FROM outbox o WHERE o.id=photo.id AND o.type='photo')")).first['c'] as int;
      pending.value = o + p;
    } catch (_) {
      // ignore during wipe or initial setup
    }
  }

  /// Full sync workflow: records first -> photos binary -> pull fresh server state.
  Future<SyncResult> run() async {
    if (_running) {
      return SyncResult(success: false, message: 'Sync already in progress');
    }
    if (!await api.hasSession()) {
      return SyncResult(success: false, message: 'No active session. Please sign in.');
    }
    _running = true;
    isSyncing.value = true;
    lastError.value = null;
    int uploaded = 0;

    try {
      uploaded += await _push();
      uploaded += await _photos();
      await _pull();
      lastSyncedAt.value = DateTime.now();
      await refreshCount();
      return SyncResult(
        success: true,
        message: uploaded > 0 ? 'Uploaded $uploaded record(s)' : 'Everything is up to date',
        uploadedCount: uploaded,
      );
    } on SocketException catch (e) {
      final msg = 'Network unreachable (${e.osError?.message ?? e.message})';
      lastError.value = msg;
      return SyncResult(success: false, message: msg);
    } on http.ClientException catch (e) {
      final msg = 'Connection failed: ${e.message}';
      lastError.value = msg;
      return SyncResult(success: false, message: msg);
    } on TimeoutException {
      const msg = 'Network timeout. Will retry when connection improves.';
      lastError.value = msg;
      return SyncResult(success: false, message: msg);
    } on ApiException catch (e) {
      final msg = 'Server error (${e.status}): ${e.body}';
      lastError.value = msg;
      await _logError(msg);
      return SyncResult(success: false, message: msg);
    } catch (e) {
      final msg = 'Sync error: $e';
      lastError.value = msg;
      await _logError(msg);
      return SyncResult(success: false, message: msg);
    } finally {
      _running = false;
      isSyncing.value = false;
      await refreshCount();
    }
  }

  Future<int> _push() async {
    int totalPushed = 0;
    while (true) {
      final rows = await l.db.query('outbox', orderBy: 'seq', limit: 50);
      if (rows.isEmpty) break;
      final items = rows.map((r) => {'type': r['type'], 'id': r['id'], 'data': jsonDecode(r['payload'] as String)}).toList();
      final res = await api.push(items);
      var removed = 0;
      for (final r in (res['results'] as List)) {
        final status = r['status'];
        final id = r['id'] as String;
        final type = r['type'] as String;

        if (status == 'ok' || status == 'duplicate') {
          await l.db.delete('outbox', where: 'id=? AND type=?', whereArgs: [id, type]);
          removed++;
          totalPushed++;
        } else if (status == 'rejected') {
          await l.db.delete('outbox', where: 'id=? AND type=?', whereArgs: [id, type]);
          removed++;
          // If rejected photo, mark as rejected in local photo table so it doesn't stay pending
          if (type == 'photo') {
            await l.db.update('photo', {'uploaded': -1}, where: 'id=?', whereArgs: [id]);
          }
          await _logError('$type $id rejected: ${r['detail']}');
        }
      }
      if (removed == 0) break; // only 'retry' items left - break loop
    }
    return totalPushed;
  }

  Future<void> _logError(String msg) async {
    try {
      final cur = jsonDecode(await l.kvGet('sync_errors') ?? '[]') as List;
      cur.insert(0, '${DateTime.now().toIso8601String()} $msg');
      await l.kvSet('sync_errors', jsonEncode(cur.take(30).toList()));
    } catch (_) {}
  }

  Future<int> _photos() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Photos ready for binary upload: metadata already pushed (or not in outbox)
    final rows = await l.db.rawQuery(
        "SELECT * FROM photo WHERE uploaded=0 AND next_try<=? AND NOT EXISTS (SELECT 1 FROM outbox o WHERE o.id=photo.id AND o.type='photo') ORDER BY rowid",
        [now]);

    int uploadedCount = 0;
    for (final r in rows) {
      final id = r['id'] as String;
      final path = r['path'] as String;
      try {
        final f = File(path);
        if (!await f.exists()) {
          // File missing from storage, mark as uploaded to unblock queue
          await l.db.update('photo', {'uploaded': 1}, where: 'id=?', whereArgs: [id]);
          continue;
        }
        final bytes = await f.readAsBytes();
        await api.uploadPhoto(id, bytes);
        await l.db.update('photo', {'uploaded': 1}, where: 'id=?', whereArgs: [id]);
        if (await f.exists()) await f.delete();
        uploadedCount++;
      } on SocketException {
        rethrow; // let run() handle offline
      } on http.ClientException {
        rethrow;
      } catch (e) {
        final tries = (r['tries'] as int) + 1;
        // exponential back-off: 10s, 30s, 1m, 2m ... capped at 10m
        final wait = min(10 * pow(2, tries).toInt(), 600);
        await l.db.update('photo', {'tries': tries, 'next_try': DateTime.now().millisecondsSinceEpoch + wait * 1000}, where: 'id=?', whereArgs: [id]);
        await _logError('Photo $id upload error: $e');
      }
    }
    return uploadedCount;
  }

  Future<void> _pull() async {
    final res = await api.pull(await l.kvGet('sync_token'));
    await l.db.transaction((txn) async {
      for (final z in res['zones']) await l.upsert(txn, 'zone', 'id', z['id'], z);
      for (final t in res['asset_types']) await l.upsert(txn, 'asset_type', 'id', t['id'], t);
      for (final t in res['templates']) await l.upsert(txn, 'template', 'id', t['id'], t);
      for (final a in res['assets']) await l.upsert(txn, 'asset', 'id', a['id'], a); // server wins
      for (final t in res['tags']) await l.upsert(txn, 'tag', 'code', t['code'], t);
      for (final i in res['issues']) {
        if (i['status'] == 'verified') {
          await txn.delete('issue', where: 'id=?', whereArgs: [i['id']]);
        } else {
          await l.upsert(txn, 'issue', 'id', i['id'], i);
        }
      }
    });
    await l.kvSet('users', jsonEncode(res['users']));
    await l.kvSet('sync_token', res['token']);
  }
}
