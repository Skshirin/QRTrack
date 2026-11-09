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

/// In-app camera ONLY with review and retake support.
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
  PhotoDraft? previewDraft;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        if (mounted) setState(() => error = 'No camera found on this device');
        return;
      }
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      cam = CameraController(back, ResolutionPreset.high, enableAudio: false);
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
    final d = await ui.ImageDescriptor.encoded(buf);
    final s = ui.Size(d.width.toDouble(), d.height.toDouble());
    d.dispose();
    buf.dispose();
    return s;
  }

  Future<void> _snap() async {
    if (busy || cam == null || !cam!.value.isInitialized) return;
    setState(() => busy = true);
    try {
      final gpsF = Gps.read();
      final shot = await cam!.takePicture();
      final takenAt = DateTime.now().toUtc();
      final pos = await gpsF;

      final src = await _size(shot.path);
      final scale = min(1.0, 1600 / max(src.width, src.height));
      final id = svc.repo.newId();
      final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'photos'));
      await dir.create(recursive: true);
      final target = p.join(dir.path, '$id.jpg');
      final out = await FlutterImageCompress.compressAndGetFile(
        shot.path,
        target,
        minWidth: (src.width * scale).round(),
        minHeight: (src.height * scale).round(),
        quality: 80,
        format: CompressFormat.jpeg,
      );
      final outPath = out?.path ?? shot.path;
      final bytes = await File(outPath).readAsBytes();
      final dims = await _size(outPath);
      if (outPath != shot.path) {
        await File(shot.path).delete().catchError((_) => File(shot.path));
      }

      final draft = PhotoDraft(
        id: id,
        path: outPath,
        sha256: sha256.convert(bytes).toString(),
        takenAt: takenAt,
        lat: pos?.latitude,
        lng: pos?.longitude,
        width: dims.width.round(),
        height: dims.height.round(),
        kind: widget.kind,
      );

      if (mounted) {
        setState(() {
          previewDraft = draft;
          busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '$e';
        });
      }
    }
  }

  String _kindTitle() {
    switch (widget.kind) {
      case 'after':
        return 'After-Repair Evidence Photo';
      case 'evidence':
        return 'Issue Evidence Photo';
      default:
        return 'Inspection Photo';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    // 1. Photo Review Screen (after capturing)
    if (previewDraft != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Review Photo'),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.check, color: Colors.greenAccent),
              label: const Text('Use Photo', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
              onPressed: () => Navigator.pop(context, previewDraft),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Center(
                child: Image.file(
                  File(previewDraft!.path),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Container(
              color: Colors.grey.shade900,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      icon: const Icon(Icons.refresh),
                      label: Text(t.retake),
                      onPressed: () => setState(() => previewDraft = null),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Use This Photo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      onPressed: () => Navigator.pop(context, previewDraft),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 2. Camera Viewfinder Screen
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_kindTitle(), style: const TextStyle(fontSize: 17)),
      ),
      body: error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 12),
                    Text(error!, style: const TextStyle(color: Colors.white, fontSize: 16), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        setState(() => error = null);
                        _init();
                      },
                      child: const Text('Retry Camera'),
                    ),
                  ],
                ),
              ),
            )
          : cam == null || !cam!.value.isInitialized
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text('Starting camera...', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(child: CameraPreview(cam!)),
                    // Guide overlay at top
                    Positioned(
                      top: 16,
                      left: 20,
                      right: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          widget.kind == 'after'
                              ? 'Point at the repaired item and tap the shutter'
                              : 'Frame the control point clearly',
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    // Shutter button at bottom
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 30,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: busy ? null : _snap,
                            child: Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 4),
                              ),
                              padding: const EdgeInsets.all(4),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: busy ? Colors.grey : Colors.white,
                                ),
                                child: busy
                                    ? const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                      )
                                    : const Icon(Icons.camera_alt, color: Colors.black, size: 30),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'TAP TO CAPTURE',
                            style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
