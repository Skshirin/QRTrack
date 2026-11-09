import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/gps.dart';
import '../core/repo.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';

/// In-app camera ONLY. There is deliberately no gallery picker, so old photos cannot be reused.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, this.kind = 'evidence'});
  final String kind;
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  CameraController? cam;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      cam = CameraController(back, ResolutionPreset.veryHigh, enableAudio: false);
      await cam!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  void dispose() {
    cam?.dispose();
    super.dispose();
  }

  Future<ui.Size> _size(String path) async {
    final buf = await ui.ImmutableBuffer.fromUint8List(await File(path).readAsBytes());
    final d = await ui.ImageDescriptor.encoded(buf); // reads only the header
    final s = ui.Size(d.width.toDouble(), d.height.toDouble());
    d.dispose();
    buf.dispose();
    return s;
  }

  Future<void> _snap() async {
    if (busy || cam == null) return;
    setState(() => busy = true);
    try {
      final gpsF = Gps.read(); // position + time recorded at the moment of capture (EXIF is NOT trusted)
      final shot = await cam!.takePicture();
      final takenAt = DateTime.now().toUtc();
      final pos = await gpsF;

      final src = await _size(shot.path);
      final scale = min(1.0, 1600 / max(src.width, src.height)); // long side ~1600 px
      final id = svc.repo.newId();
      final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'photos'));
      await dir.create(recursive: true);
      final target = p.join(dir.path, '$id.jpg');
      final out = await FlutterImageCompress.compressAndGetFile(
        shot.path, target,
        minWidth: (src.width * scale).round(), minHeight: (src.height * scale).round(), quality: 80, format: CompressFormat.jpeg,
      );
      final outPath = out?.path ?? shot.path;
      final bytes = await File(outPath).readAsBytes();
      final dims = await _size(outPath);
      if (outPath != shot.path) await File(shot.path).delete().catchError((_) => File(shot.path));

      if (!mounted) return;
      Navigator.pop(context, PhotoDraft(
        id: id, path: outPath, sha256: sha256.convert(bytes).toString(), takenAt: takenAt, lat: pos?.latitude, lng: pos?.longitude,
        width: dims.width.round(), height: dims.height.round(), kind: widget.kind,
      ));
    } catch (e) {
      if (mounted) setState(() { busy = false; error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(t.takePhoto)),
      body: error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(error!)))
          : cam == null || !cam!.value.isInitialized
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  Expanded(child: CameraPreview(cam!)),
                  Padding(padding: const EdgeInsets.all(16), child: FilledButton.icon(onPressed: busy ? null : _snap, icon: const Icon(Icons.camera_alt, size: 32), label: Text(t.takePhoto))),
                ]),
    );
  }
}
