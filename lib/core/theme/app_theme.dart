import 'package:flutter/material.dart';

import '../widgets/app_route.dart';
import '../../data/models.dart';

class AppTheme {
  static ThemeData forRole(UserRole? role, Brightness brightness) {
    final seedColor = switch (role) {
      UserRole.superAdmin => const Color(0xFF7C3AED),
      UserRole.director => const Color(0xFF2563EB),
      UserRole.admin => const Color(0xFF0F766E),
      UserRole.worker => const Color(0xFFB45309),
      _ => const Color(0xFF047857),
    };
    final scheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
    final base = brightness == Brightness.dark ? dark() : light();
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: base.appBarTheme.copyWith(backgroundColor: scheme.surface, foregroundColor: scheme.onSurface),
      navigationBarTheme: base.navigationBarTheme.copyWith(backgroundColor: scheme.surface, indicatorColor: scheme.primaryContainer),
      cardTheme: base.cardTheme.copyWith(color: scheme.surfaceContainerLow, surfaceTintColor: scheme.primary),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(fillColor: scheme.surfaceContainerLow),
      snackBarTheme: base.snackBarTheme.copyWith(backgroundColor: scheme.inverseSurface, contentTextStyle: TextStyle(color: scheme.onInverseSurface)),
    );
  }

  static const Color seed = Color(0xFFD6A84F);
  static const Color gold = Color(0xFFD6A84F);
  static const Color deepNavy = Color(0xFF07111F);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      primary: const Color(0xFF9A6A12),
      secondary: const Color(0xFF7A5A22),
      tertiary: const Color(0xFF0F766E),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFFFFBF2),
      fontFamily: 'Roboto',
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: SmoothPageTransitionsBuilder(),
          TargetPlatform.iOS: SmoothPageTransitionsBuilder(),
          TargetPlatform.macOS: SmoothPageTransitionsBuilder(),
          TargetPlatform.windows: SmoothPageTransitionsBuilder(),
          TargetPlatform.linux: SmoothPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: const Color(0xFFFFFBF2),
        foregroundColor: scheme.onSurface,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white.withValues(alpha: .96),
        indicatorColor: gold.withValues(alpha: .24),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w800, color: scheme.onSurface),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: gold.withValues(alpha: .08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: gold.withValues(alpha: .16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        filled: true,
        fillColor: Colors.white,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFE7C16B),
        contentTextStyle: const TextStyle(color: Color(0xFF07111F), fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      primary: const Color(0xFFE7C16B),
      secondary: const Color(0xFFD6A84F),
      tertiary: const Color(0xFF2DD4BF),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: deepNavy,
      fontFamily: 'Roboto',
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: SmoothPageTransitionsBuilder(),
          TargetPlatform.iOS: SmoothPageTransitionsBuilder(),
          TargetPlatform.macOS: SmoothPageTransitionsBuilder(),
          TargetPlatform.windows: SmoothPageTransitionsBuilder(),
          TargetPlatform.linux: SmoothPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: deepNavy,
        foregroundColor: scheme.onSurface,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF0B1728),
        indicatorColor: gold.withValues(alpha: .22),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w800, color: scheme.onSurface),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: const Color(0xFF101B2E),
        surfaceTintColor: gold.withValues(alpha: .08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: gold.withValues(alpha: .16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        filled: true,
        fillColor: const Color(0xFF111D31),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFE7C16B),
        contentTextStyle: const TextStyle(color: Color(0xFF07111F), fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
    );
  }
}
