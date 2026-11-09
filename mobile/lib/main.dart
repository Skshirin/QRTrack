import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:workmanager/workmanager.dart';

import 'core/api.dart';
import 'core/db.dart';
import 'core/repo.dart';
import 'core/sync.dart';
import 'l10n/app_localizations.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

class Services {
  Services(this.local, this.api, this.repo, this.sync);
  final LocalDb local;
  final Api api;
  final Repo repo;
  final SyncService sync;
}

late Services svc;
final localeNotifier = ValueNotifier<Locale>(const Locale('en'));

Future<Services> buildServices() async {
  final local = await LocalDb.open();
  final api = Api();
  final repo = Repo(local);
  return Services(local, api, repo, SyncService(local, api, repo));
}

/// Android background sync (every ~15 min when online). Runs in its own isolate.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    final s = await buildServices();
    await s.sync.run();
    return true;
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  svc = await buildServices();
  final lang = await svc.local.kvGet('lang');
  if (lang != null) localeNotifier.value = Locale(lang);
  await svc.sync.refreshCount();
  Connectivity().checkConnectivity().then((r) {
    if (!r.contains(ConnectivityResult.none)) svc.sync.run();
  });
  Connectivity().onConnectivityChanged.listen((r) {
    if (!r.contains(ConnectivityResult.none)) svc.sync.run();
  });
  if (Platform.isAndroid) {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask('kanha-sync', 'kanha-sync',
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep);
  }
  runApp(const KanhaApp());
}

class KanhaApp extends StatefulWidget {
  const KanhaApp({super.key});
  @override
  State<KanhaApp> createState() => _KanhaAppState();
}

class _KanhaAppState extends State<KanhaApp> {
  bool? loggedIn;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final ok = await svc.api.hasSession() && await svc.repo.me() != null;
    if (ok) svc.sync.run();
    setState(() => loggedIn = ok);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (_, locale, __) => MaterialApp(
        title: 'Kanha QR',
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF166534),
          useMaterial3: true,
          // big touch targets: gloves + sunlight
          filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64), textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
          outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(64), textStyle: const TextStyle(fontSize: 20))),
        ),
        home: loggedIn == null
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : loggedIn!
                ? HomeScreen(onLogout: () => setState(() => loggedIn = false))
                : LoginScreen(onDone: () => setState(() => loggedIn = true)),
      ),
    );
  }
}

/// Picks the label for the current language from {"en":..,"te":..,"hi":..}
String tr(BuildContext context, dynamic m) {
  if (m is! Map) return m?.toString() ?? '';
  final lang = Localizations.localeOf(context).languageCode;
  return (m[lang] ?? m['en'] ?? '').toString();
}
