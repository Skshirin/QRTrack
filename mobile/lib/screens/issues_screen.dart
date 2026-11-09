import 'package:flutter/material.dart';

import '../core/repo.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';
import 'capture_screen.dart';
import 'scan_screen.dart';

class IssuesScreen extends StatefulWidget {
  const IssuesScreen({super.key});
  @override
  State<IssuesScreen> createState() => _IssuesScreenState();
}

class _IssuesScreenState extends State<IssuesScreen> {
  List<Map<String, dynamic>> issues = [];
  Map<String, String> assetNames = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final i = await svc.repo.myIssues();
    final names = {for (final a in await svc.local.all('asset')) a['id'] as String: a['name'] as String};
    if (mounted) setState(() { issues = i; assetNames = names; });
  }

  /// Whoever fixes it scans the SAME tag, then takes the after-photo.
  Future<void> _fix(Map<String, dynamic> issue) async {
    final t = AppLocalizations.of(context)!;
    final scan = await Navigator.push<ScanResult>(context, MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (scan == null || !mounted) return;
    final tag = await svc.repo.tag(scan.code);
    if (tag == null || tag['asset_id'] != issue['asset_id']) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.wrongTag)));
      return;
    }
    final photo = await Navigator.push<PhotoDraft>(context, MaterialPageRoute(builder: (_) => const CaptureScreen(kind: 'after')));
    if (photo == null) return;
    await svc.repo.submitIssueFix(issue, photo);
    await svc.sync.refreshCount();
    svc.sync.run();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(t.issues)),
      body: ListView(children: [
        for (final i in issues)
          ListTile(
            minVerticalPadding: 14,
            leading: Icon(Icons.warning_amber, color: i['severity'] == 'high' ? Colors.red : Colors.orange, size: 32),
            title: Text('${assetNames[i['asset_id']] ?? ''} - ${i['type']}', style: const TextStyle(fontSize: 18)),
            subtitle: Text('${i['status']}'),
            trailing: ['open', 'assigned'].contains(i['status']) ? const Icon(Icons.build) : null,
            onTap: ['open', 'assigned'].contains(i['status']) ? () => _fix(i) : null,
          ),
      ]),
      bottomNavigationBar: Padding(padding: const EdgeInsets.all(12), child: Text(t.fixIssue, textAlign: TextAlign.center)),
    );
  }
}
