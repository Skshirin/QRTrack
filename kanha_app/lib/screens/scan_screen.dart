import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/app_localizations.dart';

class ScanResult {
  ScanResult(this.code, this.method);
  final String code;
  final String method; // qr | manual  (manual is flagged for the supervisor)
}

final _tagPattern = RegExp(r'^KSV-[A-Z0-9]{6}$');

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish(ScanResult r) async {
    if (_done) return;
    _done = true;
    try {
      await _controller.stop();
    } catch (_) {}
    if (mounted) Navigator.pop(context, r);
  }

  Future<void> _manual() async {
    final t = AppLocalizations.of(context)!;
    final c = TextEditingController(text: 'KSV-');
    final code = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t.manualCode),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.characters, style: const TextStyle(fontSize: 24)),
        actions: [TextButton(onPressed: () => Navigator.pop(context, c.text.trim().toUpperCase()), child: Text(t.ok))],
      ),
    );
    if (code != null && _tagPattern.hasMatch(code)) {
      await _finish(ScanResult(code, 'manual'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(t.scanTag)),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            for (final b in capture.barcodes) {
              final v = b.rawValue;
              if (v != null && _tagPattern.hasMatch(v)) {
                _finish(ScanResult(v, 'qr'));
                return;
              }
            }
          },
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(backgroundColor: Colors.white),
            onPressed: _manual,
            child: Text(t.manualCode),
          ),
        ),
      ]),
    );
  }
}
