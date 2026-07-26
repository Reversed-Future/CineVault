
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static final lightTheme = ThemeData(
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF15803D),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFBBF7C5),
      onPrimaryContainer: Color(0xFF002106),
      secondary: Color(0xFF82C91E),
      onSecondary: Color(0xFFFFFFFF),
      surface: Color(0xFFFFFBFE),
      onSurface: Color(0xFF1C1B1F),
      surfaceContainerHighest: Color(0xFFE7E0EC),
      surfaceContainerHigh: Color(0xFFEDE8E8),
      surfaceContainer: Color(0xFFF3EDF7),
      surfaceContainerLow: Color(0xFFF9F6FD),
      onSurfaceVariant: Color(0xFF49454F),
      surfaceVariant: Color(0xFFE7E0EC),
      tertiaryContainer: Color(0xFFFFF3CD),
      onTertiaryContainer: Color(0xFF4A3800),
    ),
    scaffoldBackgroundColor: const Color(0xFFFAFAFA),
    useMaterial3: true,
    textTheme: GoogleFonts.interTextTheme(
      ThemeData.light().textTheme,
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFFFFFFFF),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
    ),
  );
}
