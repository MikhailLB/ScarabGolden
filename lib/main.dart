import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/aegis_store.dart';
import 'core/device_agent.dart';
import 'core/herald_pipe.dart';
import 'core/net_sensor.dart';
import 'core/portal_pipe.dart';
import 'core/tracker_link.dart';
import 'stage/boot_stage.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase + App Check init.  If the operator hasn't dropped a
  // `google-services.json` yet, both calls throw silently and the
  // app still works (arena users don't need Firebase).
  try {
    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
    );
  } catch (_) {}

  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.darkNavy,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  await deviceAgent.primeUserAgent();

  final store = AegisStore();
  await store.warmUp();

  final sensor = NetSensor();
  final tracker = TrackerLink();
  final pipe = PortalPipe(store);
  final herald = HeraldPipe(store);

  runApp(ScarabGoldenApp(
    store: store,
    sensor: sensor,
    tracker: tracker,
    pipe: pipe,
    herald: herald,
  ));
}

class ScarabGoldenApp extends StatelessWidget {
  final AegisStore store;
  final NetSensor sensor;
  final TrackerLink tracker;
  final PortalPipe pipe;
  final HeraldPipe herald;

  const ScarabGoldenApp({
    super.key,
    required this.store,
    required this.sensor,
    required this.tracker,
    required this.pipe,
    required this.herald,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scarab Golden',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: AppColors.gold,
        scaffoldBackgroundColor: AppColors.darkNavy,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.darkNavy,
          foregroundColor: AppColors.goldLight,
        ),
        fontFamily: 'Roboto',
      ),
      home: BootStage(
        store: store,
        sensor: sensor,
        tracker: tracker,
        pipe: pipe,
        herald: herald,
      ),
    );
  }
}
