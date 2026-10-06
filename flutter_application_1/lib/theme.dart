import 'package:flutter/material.dart';

/// Brand palette: red / black / white.
class Brand {
  static const red = Color(0xFFC8102E); // 5.9:1 on white
  static const redDark = Color(0xFF9E0B22);
  static const redOnDark = Color(0xFFFF5A6E); // readable red on black
  static const black = Color(0xFF111111);
  static const ink = Color(0xFF1C1C1C);
  static const white = Color(0xFFFFFFFF);
  static const paper = Color(0xFFFAFAF7);
  static const grey = Color(0xFF6B6B6B);
  static const line = Color(0xFFE6E3DE);

  /// System serif (Noto Serif on Android): zero bytes added to the APK.
  static const serif = 'serif';
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: Brand.red,
    onPrimary: Brand.white,
    secondary: dark ? Brand.redOnDark : Brand.redDark,
    onSecondary: Brand.white,
    error: dark ? Brand.redOnDark : Brand.redDark,
    onError: Brand.white,
    surface: dark ? const Color(0xFF0E0E0E) : Brand.paper,
    onSurface: dark ? const Color(0xFFEDEDED) : Brand.ink,
    surfaceContainerHighest: dark ? const Color(0xFF222222) : const Color(0xFFF0EEEA),
    surfaceContainer: dark ? const Color(0xFF181818) : Brand.white,
    onSurfaceVariant: dark ? const Color(0xFFA8A8A8) : Brand.grey,
    outline: dark ? const Color(0xFF3A3A3A) : Brand.line,
    outlineVariant: dark ? const Color(0xFF2A2A2A) : Brand.line,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: Brand.black,
      foregroundColor: Brand.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: Brand.serif,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Brand.white,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Brand.black,
      indicatorColor: Brand.red,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? Brand.white : const Color(0xFFBDBDBD),
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? Brand.white : const Color(0xFFBDBDBD),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Brand.red,
        foregroundColor: Brand.white,
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: dark ? Brand.white : Brand.black,
        minimumSize: const Size(48, 48),
        side: BorderSide(color: dark ? const Color(0xFF555555) : Brand.black),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outline, space: 1, thickness: 1),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Brand.black,
      contentTextStyle: TextStyle(color: Brand.white),
      actionTextColor: Brand.redOnDark,
      behavior: SnackBarBehavior.floating,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Brand.white : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Brand.red : null,
      ),
    ),
  );
}
