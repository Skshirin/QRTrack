import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../core/repo.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';
import 'capture_screen.dart';
import 'scan_screen.dart';

/// One question per screen, big buttons. Answers are evaluated again on the server (fail => issue).
class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen({super.key, required this.asset, required this.template, required this.scan, required this.scannedAt, required this.gps});
  final Map<String, dynamic> asset;
  final Map<String, dynamic>? template;
  final ScanResult scan;
  final DateTime scannedAt;
  final Future<Position?> gps;
  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  int step = 0;
  final answers = <String, dynamic>{};
  final photos = <PhotoDraft>[];
  bool saving = false;

  List<Map<String, dynamic>> get questions => ((widget.template?['questions'] as List?) ?? []).cast<Map<String, dynamic>>();

  void _answer(String key, dynamic v) => setState(() { answers[key] = v; step++; });

  Future<void> _photo() async {
    final p = await Navigator.push<PhotoDraft>(context, MaterialPageRoute(builder: (_) => const CaptureScreen()));
    if (p != null) setState(() { photos.clear(); photos.add(p); });
  }

  Future<void> _submit() async {
    setState(() => saving = true);
    await svc.repo.submitInspection(
      tagCode: widget.scan.code, asset: widget.asset, answers: answers, scanMethod: widget.scan.method, scannedAt: widget.scannedAt,
      pos: await widget.gps, templateVersion: widget.template?['version'], photos: photos);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final qs = questions;
    final finished = step >= qs.length;
    return Scaffold(
      appBar: AppBar(title: Text(widget.asset['name']), bottom: PreferredSize(preferredSize: const Size.fromHeight(4), child: LinearProgressIndicator(value: qs.isEmpty ? 1 : (step / qs.length).clamp(0, 1)))),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: finished ? _summary(t, qs) : _question(t, qs[step]),
      ),
    );
  }

  Widget _question(AppLocalizations t, Map<String, dynamic> q) {
    final label = Text(tr(context, q['label']), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600));
    final back = step > 0 ? TextButton(onPressed: () => setState(() => step--), child: Text(t.back)) : const SizedBox();
    switch (q['type']) {
      case 'yesno':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          label, const SizedBox(height: 32),
          FilledButton(onPressed: () => _answer(q['key'], 'yes'), child: Text(t.yes)), const SizedBox(height: 16),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.blueGrey), onPressed: () => _answer(q['key'], 'no'), child: Text(t.no)),
          const Spacer(), back,
        ]);
      case 'choice':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          label, const SizedBox(height: 32),
          for (final o in (q['options'] as List)) ...[
            FilledButton(onPressed: () => _answer(q['key'], o['value']), child: Text(tr(context, o['label']))), const SizedBox(height: 16),
          ],
          const Spacer(), back,
        ]);
      default: // photo
        final required = q['required'] == true;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          label, const SizedBox(height: 24),
          OutlinedButton.icon(onPressed: _photo, icon: const Icon(Icons.camera_alt, size: 32), label: Text(photos.isEmpty ? t.takePhoto : t.retake)),
          const SizedBox(height: 16),
          if (photos.isNotEmpty) const Icon(Icons.check_circle, color: Colors.green, size: 64) else if (required) Center(child: Text(t.photoRequired, style: const TextStyle(color: Colors.red, fontSize: 18))),
          const Spacer(),
          FilledButton(onPressed: (required && photos.isEmpty) ? null : () => setState(() => step++), child: Text(t.next)), back,
        ]);
    }
  }

  Widget _summary(AppLocalizations t, List<Map<String, dynamic>> qs) {
    final fails = qs.where((q) {
      final failVals = (q['fail_values'] as List?)?.cast<String>() ?? [];
      final ans = answers[q['key']]?.toString();
      return ans != null && failVals.contains(ans);
    }).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (fails.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade700),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.amber.shade900),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${fails.length} fault(s) detected. An issue will be opened in the Issues section upon submission.',
                  style: TextStyle(fontSize: 13, color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      Expanded(child: ListView(children: [
        for (final q in qs.where((q) => q['type'] != 'photo')) ListTile(title: Text(tr(context, q['label'])), trailing: Text('${answers[q['key']] ?? '-'}', style: const TextStyle(fontSize: 18))),
        ListTile(leading: const Icon(Icons.photo_camera), title: Text('${photos.length} photo')),
      ])),
      TextButton(onPressed: () => setState(() => step = 0), child: Text(t.back)),
      FilledButton(onPressed: saving ? null : _submit, child: saving ? const CircularProgressIndicator() : Text(t.submit)),
    ]);
  }
}
