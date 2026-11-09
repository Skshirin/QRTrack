import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../core/gps.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';
import 'scan_screen.dart';

/// Journey 3: create the asset where you stand (GPS captured here) and link a fresh tag by scanning it.
class NewAssetScreen extends StatefulWidget {
  const NewAssetScreen({super.key});
  @override
  State<NewAssetScreen> createState() => _NewAssetScreenState();
}

class _NewAssetScreenState extends State<NewAssetScreen> {
  final name = TextEditingController();
  List<Map<String, dynamic>> types = [], zones = [];
  Map<String, dynamic>? type, zone;
  Position? pos;
  String? tagCode;

  @override
  void initState() {
    super.initState();
    () async {
      final ty = await svc.local.all('asset_type');
      final zo = await svc.local.all('zone');
      if (mounted) setState(() { types = ty; zones = zo; });
      final p = await Gps.read();
      if (mounted) setState(() => pos = p);
    }();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final ready = type != null && zone != null && name.text.trim().isNotEmpty && pos != null && tagCode != null;
    return Scaffold(
      appBar: AppBar(title: Text(t.newAsset)),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        TextField(controller: name, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: t.assetName, border: const OutlineInputBorder())),
        const SizedBox(height: 16),
        DropdownButtonFormField<Map<String, dynamic>>(
          decoration: InputDecoration(labelText: t.chooseType, border: const OutlineInputBorder()),
          items: [for (final x in types) DropdownMenuItem(value: x, child: Text(tr(context, x['name'])))],
          onChanged: (v) => setState(() => type = v)),
        const SizedBox(height: 16),
        DropdownButtonFormField<Map<String, dynamic>>(
          decoration: InputDecoration(labelText: t.chooseZone, border: const OutlineInputBorder()),
          items: [for (final x in zones) DropdownMenuItem(value: x, child: Text(x['name']))],
          onChanged: (v) => setState(() => zone = v)),
        const SizedBox(height: 16),
        ListTile(leading: const Icon(Icons.my_location), title: Text(pos == null ? '…GPS' : '${pos!.latitude.toStringAsFixed(5)}, ${pos!.longitude.toStringAsFixed(5)}  (±${pos!.accuracy.round()} m)')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(tagCode ?? t.scanTag),
          onPressed: () async {
            final r = await Navigator.push<ScanResult>(context, MaterialPageRoute(builder: (_) => const ScanScreen()));
            if (r != null) setState(() => tagCode = r.code);
          }),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: !ready ? null : () async {
            await svc.repo.createAsset(type: type!, zoneId: zone!['id'], name: name.text.trim(), lat: pos!.latitude, lng: pos!.longitude, tagCode: tagCode!);
            await svc.sync.refreshCount();
            svc.sync.run();
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(t.save)),
      ]),
    );
  }
}
