import 'dart:convert';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onDone});
  final VoidCallback onDone;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final phone = TextEditingController(text: '+91');
  final code = TextEditingController();
  String? error;
  bool busy = false;

  Future<void> _otp() async {
    try {
      final r = await svc.api.requestOtp(phone.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r['dev_otp'] != null ? 'DEV code: ${r['dev_otp']}' : 'Code sent')));
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  Future<void> _login() async {
    setState(() { busy = true; error = null; });
    try {
      final u = await svc.api.login(phone.text.trim(), code.text.trim());
      await svc.local.kvSet('user', jsonEncode(u));
      await svc.local.kvSet('lang', u['language'] ?? 'en');
      localeNotifier.value = Locale(u['language'] ?? 'en');
      await svc.sync.run(); // first pull (needs signal once; after that the app works offline)
      widget.onDone();
    } catch (e) {
      setState(() => error = 'Login failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 40),
          Text(t.appTitle, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 32),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: t.phone, border: const OutlineInputBorder())),
          const SizedBox(height: 16),
          TextField(controller: code, obscureText: true, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t.pinOrOtp, border: const OutlineInputBorder())),
          const SizedBox(height: 8),
          TextButton(onPressed: _otp, child: Text(t.sendOtp)),
          if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 16),
          FilledButton(onPressed: busy ? null : _login, child: busy ? const CircularProgressIndicator() : Text(t.signIn)),
        ]),
      ),
    );
  }
}
