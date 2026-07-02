import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/loading_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Loading screen allows all orientations. Once loading finishes the app
  // locks to portrait for the actual game (handled in LoadingScreen).
  SystemChrome.setPreferredOrientations([
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
  runApp(const ScarabGoldenApp());
}

class ScarabGoldenApp extends StatelessWidget {
  const ScarabGoldenApp({super.key});

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
      home: const LoadingScreen(),
    );
  }
}
