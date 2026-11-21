import 'package:flutter/material.dart';

/// Same palette as the web app: warm paper light theme, calm dark theme, one blue accent.
class AppTheme {
  static const _accentLight = Color(0xFF3A5BD9);
  static const _accentDark = Color(0xFF7D97FF);

  static ThemeData light() => _base(
        ColorScheme.fromSeed(seedColor: _accentLight, brightness: Brightness.light).copyWith(
          primary: _accentLight,
          surface: const Color(0xFFFFFDF9),
          surfaceContainerLowest: const Color(0xFFF5F3EF),
          surfaceContainerHighest: const Color(0xFFEFECE6),
          outlineVariant: const Color(0xFFE2DDD4),
          onSurface: const Color(0xFF1D1B18),
          onSurfaceVariant: const Color(0xFF5B5650),
        ),
      );

  static ThemeData dark() => _base(
        ColorScheme.fromSeed(seedColor: _accentDark, brightness: Brightness.dark).copyWith(
          primary: _accentDark,
          onPrimary: const Color(0xFF0D1020),
          surface: const Color(0xFF1A1C1F),
          surfaceContainerLowest: const Color(0xFF131416),
          surfaceContainerHighest: const Color(0xFF23262A),
          outlineVariant: const Color(0xFF2F3338),
          onSurface: const Color(0xFFECEBE8),
          onSurfaceVariant: const Color(0xFFB4B1AB),
        ),
      );

  static ThemeData _base(ColorScheme c) => ThemeData(
        colorScheme: c,
        useMaterial3: true,
        scaffoldBackgroundColor: c.surfaceContainerLowest,
        appBarTheme: AppBarTheme(backgroundColor: c.surface, surfaceTintColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0.5),
        cardTheme: CardThemeData(
          color: c.surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(6),
            ),
            side: BorderSide(color: c.outlineVariant),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: c.surfaceContainerLowest,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.outlineVariant)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.outlineVariant)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.primary, width: 1.5)),
        ),
        navigationBarTheme: NavigationBarThemeData(backgroundColor: c.surface, indicatorColor: c.primary.withValues(alpha: 0.14), height: 64),
      );
}
