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
  bool loading = true;
  String filter = 'open'; // 'open', 'fixed', 'all'
  List<Map<String, dynamic>> allIssues = [];
  Map<String, Map<String, dynamic>> assets = {};
  Map<String, String> zoneNames = {};
  Map<String, Map<String, dynamic>> assetTypes = {};

  @override
  void initState() {
    super.initState();
    _load();
    // Also trigger sync to fetch fresh issues from the server if online
    svc.sync.run().then((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final issuesList = await svc.repo.myIssues();
    final assetList = await svc.local.all('asset');
    final zoneList = await svc.local.all('zone');
    final typeList = await svc.local.all('asset_type');

    if (mounted) {
      setState(() {
        allIssues = issuesList;
        assets = {for (final a in assetList) a['id'] as String: a};
        zoneNames = {for (final z in zoneList) z['id'] as String: z['name'] as String};
        assetTypes = {for (final t in typeList) t['id'] as String: t};
        loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get filteredIssues {
    if (filter == 'open') {
      return allIssues.where((i) => i['status'] == 'open' || i['status'] == 'assigned').toList();
    }
    if (filter == 'fixed') {
      return allIssues.where((i) => i['status'] == 'fixed').toList();
    }
    return allIssues;
  }

  String _formatType(String raw) {
    switch (raw) {
      case 'standing_water':
        return 'Standing Water Detected';
      case 'mat_in_place':
        return 'Mat Missing / Displaced';
      case 'mat_condition':
        return 'Mat Damaged / Torn';
      case 'water_present':
        return 'No Water in Pot';
      case 'sticks_cleaned':
        return 'Sticks Not Cleaned';
      case 'in_good_condition':
        return 'Condition Fault Reported';
      case 'manual':
        return 'Field Hazard / Issue';
      default:
        return raw.replaceAll('_', ' ').split(' ').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');
    }
  }

  Color _severityColor(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'high':
        return Colors.red.shade700;
      case 'low':
        return Colors.blue.shade700;
      default:
        return Colors.orange.shade800;
    }
  }

  Color _statusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'fixed':
        return Colors.green.shade700;
      case 'assigned':
        return Colors.blue.shade700;
      case 'verified':
        return Colors.teal.shade700;
      default:
        return Colors.amber.shade900;
    }
  }

  Future<void> _fix(Map<String, dynamic> issue) async {
    final t = AppLocalizations.of(context)!;
    final asset = assets[issue['asset_id']];
    final assetName = asset?['name'] ?? 'this control point';

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${t.issues}: Fix Verification'),
        content: Text(
          'To verify the fix for "$assetName":\n\n'
          '1. Walk to the control point and scan its QR tag.\n'
          '2. Capture an after-repair photo showing the resolved issue.',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.back)),
          FilledButton.icon(
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(t.scanTag),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (proceed != true || !mounted) return;

    final scan = await Navigator.push<ScanResult>(context, MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (scan == null || !mounted) return;

    final tag = await svc.repo.tag(scan.code);
    if (tag == null || tag['asset_id'] != issue['asset_id']) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Wrong QR Tag'),
            content: Text(t.wrongTag, style: const TextStyle(fontSize: 16)),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(t.ok))],
          ),
        );
      }
      return;
    }

    final photo = await Navigator.push<PhotoDraft>(context, MaterialPageRoute(builder: (_) => const CaptureScreen(kind: 'after')));
    if (photo == null || !mounted) return;

    await svc.repo.submitIssueFix(issue, photo);
    await svc.sync.refreshCount();
    svc.sync.run();
    await _load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.issueFixedSuccess)));
    }
  }

  Future<void> _reportIssueDialog() async {
    final t = AppLocalizations.of(context)!;
    final assetList = assets.values.toList();
    if (assetList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No assets loaded yet. Please sync first.')));
      return;
    }

    String selectedAssetId = assetList.first['id'] as String;
    String selectedCategory = 'damaged_point';
    String selectedSeverity = 'medium';
    final noteController = TextEditingController();
    PhotoDraft? photoDraft;

    final categories = [
      {'key': 'standing_water', 'label': 'Standing Water'},
      {'key': 'damaged_point', 'label': 'Damaged / Broken Structure'},
      {'key': 'missing_parts', 'label': 'Missing Cover / Mat / Sticks'},
      {'key': 'clogged_drain', 'label': 'Clogged Drain / Overflow'},
      {'key': 'mosquito_larvae', 'label': 'Mosquito Larvae Spotted'},
      {'key': 'other', 'label': 'Other Issue'},
    ];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(t.reportIssue, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),

                  // Asset selector
                  Text(t.selectAsset, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedAssetId,
                    isExpanded: true,
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    items: [
                      for (final a in assetList)
                        DropdownMenuItem(
                          value: a['id'] as String,
                          child: Text('${a['name']} (${zoneNames[a['zone_id']] ?? ''})', overflow: TextOverflow.ellipsis),
                        )
                    ],
                    onChanged: (v) {
                      if (v != null) setModalState(() => selectedAssetId = v);
                    },
                  ),
                  const SizedBox(height: 14),

                  // Category selector
                  Text(t.issueCategory, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategory,
                    isExpanded: true,
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    items: [
                      for (final c in categories)
                        DropdownMenuItem(value: c['key'], child: Text(c['label']!))
                    ],
                    onChanged: (v) {
                      if (v != null) setModalState(() => selectedCategory = v);
                    },
                  ),
                  const SizedBox(height: 14),

                  // Severity selector
                  const Text('Priority / Severity', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'low', label: Text('Low')),
                      ButtonSegment(value: 'medium', label: Text('Medium')),
                      ButtonSegment(value: 'high', label: Text('High')),
                    ],
                    selected: {selectedSeverity},
                    onSelectionChanged: (s) {
                      setModalState(() => selectedSeverity = s.first);
                    },
                  ),
                  const SizedBox(height: 14),

                  // Description
                  Text(t.issueDescription, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Enter observation details or location landmark...',
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Photo evidence
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: Icon(photoDraft == null ? Icons.camera_alt : Icons.check_circle, color: photoDraft != null ? Colors.green : null),
                          label: Text(photoDraft == null ? t.takePhoto : 'Photo Attached'),
                          onPressed: () async {
                            final p = await Navigator.push<PhotoDraft>(context, MaterialPageRoute(builder: (_) => const CaptureScreen(kind: 'evidence')));
                            if (p != null) setModalState(() => photoDraft = p);
                          },
                        ),
                      ),
                      if (photoDraft != null)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => setModalState(() => photoDraft = null),
                        )
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Submit button
                  FilledButton.icon(
                    icon: const Icon(Icons.send),
                    label: Text(t.submit),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await svc.repo.reportIssue(
                        assetId: selectedAssetId,
                        type: selectedCategory,
                        severity: selectedSeverity,
                        note: noteController.text.trim().isNotEmpty ? noteController.text.trim() : null,
                        photo: photoDraft,
                      );
                      await svc.sync.refreshCount();
                      svc.sync.run();
                      await _load();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.issueReportedSuccess)));
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final issues = filteredIssues;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.issues),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_alert),
            tooltip: t.reportIssue,
            onPressed: _reportIssueDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              setState(() => loading = true);
              await svc.sync.run();
              await _load();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  label: Text('${t.filterOpen} (${allIssues.where((i) => i['status'] == 'open' || i['status'] == 'assigned').length})'),
                  selected: filter == 'open',
                  onSelected: (_) => setState(() => filter = 'open'),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text('${t.filterFixed} (${allIssues.where((i) => i['status'] == 'fixed').length})'),
                  selected: filter == 'fixed',
                  onSelected: (_) => setState(() => filter = 'fixed'),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text('${t.filterAll} (${allIssues.length})'),
                  selected: filter == 'all',
                  onSelected: (_) => setState(() => filter = 'all'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Main Body
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await svc.sync.run();
                await _load();
              },
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : issues.isEmpty
                      ? _buildEmptyState(t)
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: issues.length,
                          itemBuilder: (context, idx) {
                            final i = issues[idx];
                            return _buildIssueCard(i, t);
                          },
                        ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(top: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 20, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.fixInstruction,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations t) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_turned_in_outlined, size: 72, color: Colors.green.shade600),
            const SizedBox(height: 16),
            Text(
              filter == 'open' ? t.noIssues : 'No issues match this filter',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              filter == 'open'
                  ? 'All control points in your zones are operating normally. If you notice a hazard, report an issue below.'
                  : 'Change filters or report an issue if you spot a hazard.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.add_alert),
                  label: Text(t.reportIssue),
                  onPressed: _reportIssueDialog,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh / Sync'),
                  onPressed: () async {
                    setState(() => loading = true);
                    await svc.sync.run();
                    await _load();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIssueCard(Map<String, dynamic> i, AppLocalizations t) {
    final asset = assets[i['asset_id']];
    final assetName = asset?['name'] ?? 'Point ${i['asset_id']?.toString().substring(0, 6) ?? ''}';
    final zoneName = asset != null ? (zoneNames[asset['zone_id']] ?? '') : '';
    final typeName = asset != null && assetTypes[asset['type_id']] != null ? (assetTypes[asset['type_id']]!['name']?['en'] ?? '') : '';
    final severity = (i['severity'] as String?) ?? 'medium';
    final status = (i['status'] as String?) ?? 'open';
    final canFix = status == 'open' || status == 'assigned';
    final openedAt = i['opened_at'] != null ? DateTime.tryParse(i['opened_at'])?.toLocal() : null;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Asset Name and Severity Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(assetName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      if (zoneName.isNotEmpty || typeName.isNotEmpty)
                        Text(
                          [zoneName, typeName].where((s) => s.isNotEmpty).join(' • '),
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _severityColor(severity).withAlpha(30),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _severityColor(severity).withAlpha(100)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber, size: 14, color: _severityColor(severity)),
                      const SizedBox(width: 4),
                      Text(
                        severity.toUpperCase(),
                        style: TextStyle(color: _severityColor(severity), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Issue Title & Notes
            Row(
              children: [
                Icon(Icons.report_problem_outlined, size: 18, color: Colors.grey.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _formatType(i['type'] as String? ?? 'issue'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (i['note'] != null && (i['note'] as String).trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Text(
                  i['note'] as String,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade800, fontStyle: FontStyle.italic),
                ),
              ),
            ],
            const SizedBox(height: 12),

            // Bottom Row: Date, Status Badge, and Fix Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _statusColor(status).withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _statusColor(status)),
                      ),
                    ),
                    if (openedAt != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${openedAt.day}/${openedAt.month} ${openedAt.hour.toString().padLeft(2, '0')}:${openedAt.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ]
                  ],
                ),
                if (canFix)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      backgroundColor: Colors.teal.shade700,
                    ),
                    icon: const Icon(Icons.build, size: 16),
                    label: const Text('Fix Issue', style: TextStyle(fontSize: 13)),
                    onPressed: () => _fix(i),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
