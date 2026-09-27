import 'package:flutter/material.dart';

/// App color palette matching the frontend design
/// Gradient: from-indigo-900 via-purple-900 to-pink-800
class AppColors {
  // Background gradient colors
  static const Color indigo900 = Color(0xFF1E1B4B); // indigo-900
  static const Color purple900 = Color(0xFF581C87); // purple-900
  static const Color pink800 = Color(0xFF9F1239); // pink-800

  // Primary accent colors
  static const Color pink400 = Color(0xFFF472B6); // pink-400
  static const Color pink500 = Color(0xFFEC4899); // pink-500
  static const Color pink600 = Color(0xFFDB2777); // pink-600

  // Secondary colors
  static const Color purple200 = Color(0xFFE9D5FF); // purple-200
  static const Color purple300 = Color(0xFFD8B4FE); // purple-300
  static const Color purple600 = Color(0xFF9333EA); // purple-600

  // Status colors
  static const Color green500 = Color(0xFF22C55E); // green-500
  static const Color green300 = Color(0xFF86EFAC); // green-300
  static const Color yellow500 = Color(0xFFEAB308); // yellow-500
  static const Color yellow300 = Color(0xFFFDE047); // yellow-300
  static const Color red500 = Color(0xFFEF4444); // red-500
  static const Color red300 = Color(0xFFFCA5A5); // red-300
  static const Color orange500 = Color(0xFFF97316); // orange-500 (e.g. cancelled by shop)
  static const Color blue500 = Color(0xFF3B82F6); // blue-500

  // Neutral colors
  static const Color white = Color(0xFFFFFFFF);
  static const Color white10 = Color(0x1AFFFFFF); // white/10
  static const Color white20 = Color(0x33FFFFFF); // white/20
  static const Color white30 = Color(0x4DFFFFFF); // white/30
  static const Color white50 = Color(0x80FFFFFF); // white/50
  static const Color white70 = Color(0xB3FFFFFF); // white/70

  // Background gradient
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [indigo900, purple900, pink800],
  );

  // Primary button gradient
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [pink500, purple600],
  );

  // Card background (glassmorphism)
  static Color cardBackground = white10;
  static Color cardBorder = white20;
}
