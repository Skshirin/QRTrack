import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../main.dart';
import 'checklist_screen.dart';
import 'issues_screen.dart';
import 'new_asset_screen.dart';
import 'scan_screen.dart';
import '../core/gps.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onLogout});
  final VoidCallback onLogout;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> due = [];
  Map<String, dynamic>? me;
  Map<String, Map<String, dynamic>> types = {};

  @override
  void initState() {
    super.initState();
    _load();
    svc.sync.pending.addListener(_load); // list refreshes after every sync
    WidgetsBinding.instance.addPostFrameCallback((_) => _notice());
  }

  @override
  void dispose() {
    svc.sync.pending.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final d = await svc.repo.dueToday();
    final u = await svc.repo.me();
    final t = {for (final x in await svc.local.all('asset_type')) x['id'] as String: x};
    if (mounted) setState(() { due = d; me = u; types = t; });
  }

  Future<void> _notice() async {
    if (await svc.local.kvGet('notice_ack') != null || !mounted) return; // DPDP notice on first login
    final t = AppLocalizations.of(context)!;
    await showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(
      title: Text(t.noticeTitle), content: Text(t.noticeBody, style: const TextStyle(fontSize: 18)),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(t.ok))]));
    await svc.local.kvSet('notice_ack', DateTime.now().toIso8601String());
  }

  Future<void> _scan() async {
    final t = AppLocalizations.of(context)!;
    final res = await Navigator.push<ScanResult>(context, MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (res == null || !mounted) return;
    final scannedAt = DateTime.now().toUtc();
    final gps = Gps.read(); // started now, i.e. at scan time
    final tag = await svc.repo.tag(res.code);
    if (tag != null && tag['active'] == false) {
      await showDialog(context: context, builder: (_) => AlertDialog(content: Text(t.tagInactive, style: const TextStyle(fontSize: 18)), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(t.ok))]));
      return;
    }
    final asset = tag?['asset_id'] != null ? await svc.repo.asset(tag!['asset_id']) : null;
    if (asset == null) {
      // unknown tag while offline: keep the scan, the server resolves it on sync
      await svc.repo.submitInspection(tagCode: res.code, answers: {}, scanMethod: res.method, scannedAt: scannedAt, pos: await gps);
      await svc.sync.refreshCount();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.saved)));
      return;
    }
    final template = await svc.repo.templateFor(asset['type_id']);
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ChecklistScreen(asset: asset, template: template, scan: res, scannedAt: scannedAt, gps: gps)));
    await svc.sync.refreshCount();
    _load();
    svc.sync.run();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final canCreate = me != null && ['supervisor', 'admin'].contains(me!['role']);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.dueToday),
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: svc.sync.pending,
            builder: (_, n, __) => ActionChip(
              avatar: Icon(n == 0 ? Icons.cloud_done : Icons.cloud_upload),
              label: Text(n == 0 ? t.allSynced : t.waitingUpload(n)),
              onPressed: () => svc.sync.run(),
              tooltip: t.syncNow,
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'logout') return _logout();
              await svc.local.kvSet('lang', v);
              localeNotifier.value = Locale(v);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'en', child: Text('English')),
              const PopupMenuItem(value: 'te', child: Text('తెలుగు')),
              const PopupMenuItem(value: 'hi', child: Text('हिन्दी')),
              PopupMenuItem(value: 'logout', child: Text(t.logout)),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async { await svc.sync.run(); await _load(); },
        child: due.isEmpty
            ? ListView(children: [Padding(padding: const EdgeInsets.all(48), child: Center(child: Text(t.nothingDue, style: const TextStyle(fontSize: 20))))])
            : ListView.separated(
                itemCount: due.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final a = due[i];
                  final overdue = DateTime.parse(a['next_due_at']).isBefore(DateTime.now());
                  return ListTile(
                    minVerticalPadding: 14,
                    leading: Icon(Icons.place, color: overdue ? Colors.red : Colors.amber[800], size: 32),
                    title: Text(a['name'], style: const TextStyle(fontSize: 20)),
                    subtitle: Text(tr(context, types[a['type_id']]?['name'])),
                  );
                }),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FilledButton.icon(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner, size: 32), label: Text(t.scanTag)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IssuesScreen())).then((_) => _load()), child: Text(t.issues))),
              if (canCreate) ...[
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewAssetScreen())).then((_) => _load()), child: Text(t.newAsset))),
              ],
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await svc.sync.run();
    final left = svc.sync.pending.value;
    if (left > 0 && mounted) {
      final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
        title: Text('$left not uploaded'), content: const Text('Logging out deletes data that has not been uploaded. Connect to the internet and sync first.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log out anyway'))]));
      if (ok != true) return;
    }
    await svc.local.wipe(); // local DB is cleared on logout
    await svc.api.clearTokens();
    await svc.sync.refreshCount();
    widget.onLogout();
  }
}
