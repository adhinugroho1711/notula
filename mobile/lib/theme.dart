import 'package:flutter/material.dart';

/// Design system Notula — modern, bersih, dengan aksen ungu-indigo.
class AppTheme {
  static const Color primary = Color(0xFF6366F1); // indigo
  static const Color primaryDark = Color(0xFF4F46E5);
  static const Color accent = Color(0xFF8B5CF6); // violet
  static const Color bg = Color(0xFFF6F6FB);
  static const Color surface = Colors.white;

  static const Color statusRecorded = Color(0xFF6366F1);
  static const Color statusProcessing = Color(0xFFF59E0B); // amber
  static const Color statusDone = Color(0xFF10B981); // emerald
  static const Color statusFailed = Color(0xFFEF4444); // red

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
  );

  static const LinearGradient recordGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFB7185), Color(0xFFEF4444)],
  );

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      surface: surface,
    ).copyWith(surfaceContainerLowest: bg);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Color(0xFF1E1B2E),
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: Color(0xFF1E1B2E)),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Shadow lembut untuk kartu.
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: const Color(0xFF6366F1).withValues(alpha: 0.08),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}
