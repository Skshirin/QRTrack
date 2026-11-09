import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'db.dart';
import 'repo.dart';

class SyncService {
  SyncService(this.l, this.api, this.repo);
  final LocalDb l;
  final Api api;
  final Repo repo;
  final pending = ValueNotifier<int>(0); // the "12 waiting to upload" badge
  bool _running = false;

  Future<void> refreshCount() async {
    final o = (await l.db.rawQuery('SELECT COUNT(*) c FROM outbox')).first['c'] as int;
    final p = (await l.db.rawQuery('SELECT COUNT(*) c FROM photo WHERE uploaded=0')).first['c'] as int;
    pending.value = o + p;
  }

  /// records first -> photos one at a time -> pull. A photo failure never blocks the records.
  Future<void> run() async {
    if (_running || !await api.hasSession()) return;
    _running = true;
    try {
      await _push();
      await _photos();
      await _pull();
    } on SocketException {
      // offline - try again later
    } on http.ClientException {
      // offline
    } on TimeoutException {
      // slow network
    } catch (e) {
      debugPrint('sync error: $e');
    } finally {
      _running = false;
      await refreshCount();
    }
  }

  Future<void> _push() async {
    while (true) {
      final rows = await l.db.query('outbox', orderBy: 'seq', limit: 50);
      if (rows.isEmpty) return;
      final items = rows.map((r) => {'type': r['type'], 'id': r['id'], 'data': jsonDecode(r['payload'] as String)}).toList();
      final res = await api.push(items);
      var removed = 0;
      for (final r in (res['results'] as List)) {
        final status = r['status'];
        if (status == 'ok' || status == 'duplicate' || status == 'rejected') {
          await l.db.delete('outbox', where: 'id=? AND type=?', whereArgs: [r['id'], r['type']]);
          removed++;
          if (status == 'rejected') await _logError('${r['type']} ${r['id']}: ${r['detail']}');
        }
      }
      if (removed == 0) return; // only 'retry' items left - wait for the next run (no tight loop)
    }
  }

  Future<void> _logError(String msg) async {
    final cur = jsonDecode(await l.kvGet('sync_errors') ?? '[]') as List;
    cur.insert(0, '${DateTime.now().toIso8601String()} $msg');
    await l.kvSet('sync_errors', jsonEncode(cur.take(30).toList()));
  }

  Future<void> _photos() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await l.db.rawQuery(
        "SELECT * FROM photo WHERE uploaded=0 AND next_try<=? AND NOT EXISTS (SELECT 1 FROM outbox o WHERE o.id=photo.id AND o.type='photo') ORDER BY rowid",
        [now]);
    for (final r in rows) {
      final id = r['id'] as String;
      try {
        final f = File(r['path'] as String);
        await api.uploadPhoto(id, await f.readAsBytes());
        await l.db.update('photo', {'uploaded': 1}, where: 'id=?', whereArgs: [id]);
        if (await f.exists()) await f.delete();
      } on SocketException {
        return;
      } on http.ClientException {
        return;
      } catch (_) {
        final tries = (r['tries'] as int) + 1; // exponential back-off: 30s, 60s, 2m ... capped at 1h
        final wait = min(30 * pow(2, tries).toInt(), 3600);
        await l.db.update('photo', {'tries': tries, 'next_try': DateTime.now().millisecondsSinceEpoch + wait * 1000}, where: 'id=?', whereArgs: [id]);
      }
    }
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
