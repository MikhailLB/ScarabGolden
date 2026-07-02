import 'package:flutter/material.dart';

class AppColors {
  static const gold = Color(0xFFE9BE55);
  static const goldLight = Color(0xFFFFD979);
  static const goldDark = Color(0xFF9B7B26);
  static const darkNavy = Color(0xFF0B1A3A);
  static const lapis = Color(0xFF1B3B7F);
  static const water = Color(0xFF2FCBE0);
  static const stone = Color(0xFFBE9852);
  static const parchment = Color(0xFFEDD9AF);
}

class AppTextStyles {
  static const TextStyle title = TextStyle(
    color: AppColors.goldLight,
    fontSize: 32,
    fontWeight: FontWeight.bold,
    letterSpacing: 2,
    shadows: [
      Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(1, 2)),
    ],
  );

  static const TextStyle button = TextStyle(
    color: AppColors.goldLight,
    fontSize: 20,
    fontWeight: FontWeight.bold,
    letterSpacing: 1.2,
    shadows: [
      Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(1, 1)),
    ],
  );

  static const TextStyle body = TextStyle(
    color: AppColors.parchment,
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle loading = TextStyle(
    color: AppColors.goldLight,
    fontSize: 22,
    fontWeight: FontWeight.bold,
    letterSpacing: 2,
    shadows: [
      Shadow(color: Colors.black, blurRadius: 6, offset: Offset(1, 2)),
    ],
  );
}
