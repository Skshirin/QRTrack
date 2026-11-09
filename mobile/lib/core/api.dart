import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.status, this.body);
  final int status;
  final String body;
  @override
  String toString() => 'HTTP $status: $body';
}

class Api {
  // Android emulator -> your PC is 10.0.2.2. For a real phone use: --dart-define=API_BASE=http://<PC-LAN-IP>:8000/api/v1
  static const base = String.fromEnvironment('API_BASE', defaultValue: 'http://10.0.2.2:8000/api/v1');
  static const _ss = FlutterSecureStorage(); // Keystore / Keychain

  Future<void> saveTokens(String access, String refresh) async {
    await _ss.write(key: 'access', value: access);
    await _ss.write(key: 'refresh', value: refresh);
  }

  Future<bool> hasSession() async => (await _ss.read(key: 'refresh')) != null;
  Future<void> clearTokens() async {
    await _ss.delete(key: 'access');
    await _ss.delete(key: 'refresh');
  }

  Future<http.Response> _req(String method, String path, {Object? body, bool retry = true}) async {
    final uri = Uri.parse('$base$path');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${await _ss.read(key: 'access') ?? ''}',
    };
    final res = await (method == 'GET'
            ? http.get(uri, headers: headers)
            : http.post(uri, headers: headers, body: body == null ? null : jsonEncode(body)))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode == 401 && retry && await _refresh()) return _req(method, path, body: body, retry: false);
    return res;
  }

  Future<bool> _refresh() async {
    final r = await _ss.read(key: 'refresh');
    if (r == null) return false;
    final res = await http
        .post(Uri.parse('$base/auth/refresh'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'refresh': r}))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) return false;
    final d = jsonDecode(res.body);
    await saveTokens(d['access'], d['refresh']);
    return true;
  }

  Map<String, dynamic> _ok(http.Response r) {
    if (r.statusCode >= 300) throw ApiException(r.statusCode, r.body);
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> requestOtp(String phone) async =>
      _ok(await http.post(Uri.parse('$base/auth/otp'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'phone': phone})));

  Future<Map<String, dynamic>> login(String phone, String code) async {
    final d = _ok(await http.post(Uri.parse('$base/auth/verify'),
        headers: {'Content-Type': 'application/json'}, body: jsonEncode({'phone': phone, 'code': code})));
    await saveTokens(d['access'], d['refresh']);
    return d['user'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> pull(String? since) async => _ok(await _req('GET', '/sync/pull${since == null ? '' : '?since=${Uri.encodeQueryComponent(since)}'}'));
  Future<Map<String, dynamic>> push(List<Map<String, dynamic>> items) async =>
      _ok(await _req('POST', '/sync/push', body: {'device_now': DateTime.now().toUtc().toIso8601String(), 'items': items}));

  Future<void> uploadPhoto(String id, Uint8List bytes) async {
    final u = _ok(await _req('POST', '/photos/upload-url', body: {'photo_id': id}));
    final put = await http.put(Uri.parse(u['url']), headers: {'Content-Type': 'image/jpeg'}, body: bytes).timeout(const Duration(minutes: 2));
    if (put.statusCode >= 300) throw ApiException(put.statusCode, 'storage upload failed');
    _ok(await _req('POST', '/photos/$id/confirm'));
  }
}
