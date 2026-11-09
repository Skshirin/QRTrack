import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'db.dart';

class PhotoDraft {
  PhotoDraft({required this.id, required this.path, required this.sha256, required this.takenAt, this.lat, this.lng, required this.width, required this.height, required this.kind});
  final String id, path, sha256, kind;
  final DateTime takenAt;
  final double? lat, lng;
  final int width, height;
  Map<String, dynamic> payload({String? inspectionId, String? issueId}) => {
        'inspection_id': inspectionId, 'issue_id': issueId, 'kind': kind, 'sha256': sha256,
        'taken_at': takenAt.toIso8601String(), 'gps_lat': lat, 'gps_lng': lng, 'width': width, 'height': height,
      };
}

class Repo {
  Repo(this.l);
  final LocalDb l;
  Database get db => l.db;
  static const _uuid = Uuid();
  String newId() => _uuid.v4(); // UUIDs are generated on the phone so offline records never clash

  Future<Map<String, dynamic>?> me() async {
    final s = await l.kvGet('user');
    return s == null ? null : jsonDecode(s) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> _one(String table, String col, String key) async {
    final r = await db.query(table, where: '$col=?', whereArgs: [key]);
    return r.isEmpty ? null : jsonDecode(r.first['json'] as String) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> tag(String code) => _one('tag', 'code', code);
  Future<Map<String, dynamic>?> asset(String id) => _one('asset', 'id', id);
  Future<Map<String, dynamic>?> assetType(String id) => _one('asset_type', 'id', id);

  Future<Map<String, dynamic>?> templateFor(String typeId) async {
    final t = (await l.all('template')).where((x) => x['asset_type_id'] == typeId && x['active'] == true).toList();
    if (t.isEmpty) return null;
    t.sort((a, b) => (b['version'] as int).compareTo(a['version'] as int));
    return t.first;
  }

  Future<List<Map<String, dynamic>>> dueToday() async {
    final n = DateTime.now();
    final end = DateTime(n.year, n.month, n.day, 23, 59, 59);
    final list = (await l.all('asset'))
        .where((a) => a['status'] == 'active' && a['next_due_at'] != null && DateTime.parse(a['next_due_at']).toLocal().isBefore(end))
        .toList();
    list.sort((a, b) => (a['next_due_at'] as String).compareTo(b['next_due_at'] as String));
    return list;
  }

  Future<void> _addPhoto(DatabaseExecutor txn, PhotoDraft p, {String? inspectionId, String? issueId}) async {
    final payload = p.payload(inspectionId: inspectionId, issueId: issueId);
    await l.upsert(txn, 'photo', 'id', p.id, payload, {'path': p.path});
    await txn.insert('outbox', {'type': 'photo', 'id': p.id, 'payload': jsonEncode(payload)});
  }

  /// Inspection + its photos + outbox rows are written in ONE transaction: nothing is lost if the app is killed.
  Future<void> submitInspection({
    required String tagCode, Map<String, dynamic>? asset, required Map<String, dynamic> answers,
    required String scanMethod, required DateTime scannedAt, Position? pos, int? templateVersion,
    List<PhotoDraft> photos = const [],
  }) async {
    final id = newId();
    final data = {
      'tag_code': tagCode, 'asset_id': asset?['id'], 'answers': answers, 'scan_method': scanMethod,
      'scanned_at': scannedAt.toIso8601String(), 'device_time': DateTime.now().toUtc().toIso8601String(),
      'template_version': templateVersion, 'gps_lat': pos?.latitude, 'gps_lng': pos?.longitude,
      'gps_accuracy_m': pos?.accuracy, 'is_mocked': pos?.isMocked ?? false,
    };
    await db.transaction((txn) async {
      await l.upsert(txn, 'inspection', 'id', id, data, {'scanned_at': data['scanned_at']});
      await txn.insert('outbox', {'type': 'inspection', 'id': id, 'payload': jsonEncode(data)});
      for (final p in photos) {
        await _addPhoto(txn, p, inspectionId: id);
      }
      if (asset != null) {
        final a = Map<String, dynamic>.from(asset);
        a['next_due_at'] = scannedAt.add(Duration(days: a['interval_days'] as int)).toIso8601String();
        await l.upsert(txn, 'asset', 'id', a['id'], a); // local guess; the server's value wins on the next pull
      }
    });
  }

  Future<void> createAsset({required Map<String, dynamic> type, required String zoneId, required String name, required double lat, required double lng, required String tagCode}) async {
    final id = newId();
    final now = DateTime.now().toUtc();
    final interval = type['default_interval_days'] as int;
    final asset = {
      'id': id, 'type_id': type['id'], 'zone_id': zoneId, 'name': name, 'lat': lat, 'lng': lng, 'status': 'active',
      'interval_days': interval, 'next_due_at': now.add(Duration(days: interval)).toIso8601String(),
    };
    await db.transaction((txn) async {
      await l.upsert(txn, 'asset', 'id', id, asset);
      await txn.insert('outbox', {'type': 'asset', 'id': id, 'payload': jsonEncode({...asset, 'created_at': now.toIso8601String()})});
      final linkId = newId();
      await txn.insert('outbox', {'type': 'tag_link', 'id': linkId, 'payload': jsonEncode({'tag_code': tagCode, 'asset_id': id})});
      await l.upsert(txn, 'tag', 'code', tagCode, {'code': tagCode, 'asset_id': id, 'active': true, 'kind': 'qr'});
    });
  }

  Future<List<Map<String, dynamic>>> myIssues() async {
    final u = await me();
    final isLead = u != null && ['supervisor', 'manager', 'admin'].contains(u['role']);
    return (await l.all('issue')).where((i) => i['status'] != 'verified' && (isLead || i['assigned_to'] == u?['id'])).toList();
  }

  Future<void> submitIssueFix(Map<String, dynamic> issue, PhotoDraft after) async {
    await db.transaction((txn) async {
      await _addPhoto(txn, after, issueId: issue['id']);
      await txn.insert('outbox', {'type': 'issue_update', 'id': newId(), 'payload': jsonEncode({'issue_id': issue['id'], 'status': 'fixed'})});
      await l.upsert(txn, 'issue', 'id', issue['id'], {...issue, 'status': 'fixed'});
    });
  }
}
