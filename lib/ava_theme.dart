import 'package:flutter/material.dart';

abstract final class AvaColors {
  static const canvas = Color(0xFFF4F2EC);
  static const surface = Color(0xFFFFFEFB);
  static const ink = Color(0xFF21312B);
  static const muted = Color(0xFF56665F);
  static const primary = Color(0xFF245C4A);
  static const primaryPressed = Color(0xFF194638);
  static const sage = Color(0xFFE2EBE4);
  static const border = Color(0xFFD7DED8);
  static const amber = Color(0xFF8A531D);
  static const amberWash = Color(0xFFF4E9D8);
  static const danger = Color(0xFF9C3C35);
  static const dangerWash = Color(0xFFF9E9E6);
}

ThemeData buildAvaTheme() {
  const scheme = ColorScheme.light(
    primary: AvaColors.primary,
    onPrimary: Colors.white,
    secondary: AvaColors.amber,
    onSecondary: Colors.white,
    error: AvaColors.danger,
    onError: Colors.white,
    surface: AvaColors.surface,
    onSurface: AvaColors.ink,
    outline: AvaColors.border,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AvaColors.canvas,
    appBarTheme: const AppBarTheme(
      backgroundColor: AvaColors.canvas,
      foregroundColor: AvaColors.ink,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AvaColors.ink,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: AvaColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AvaColors.border),
      ),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AvaColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFBEC9C1),
        disabledForegroundColor: AvaColors.muted,
        minimumSize: const Size(48, 56),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AvaColors.surface,
      labelStyle: const TextStyle(color: AvaColors.muted),
      hintStyle: const TextStyle(color: AvaColors.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AvaColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AvaColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AvaColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AvaColors.danger),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AvaColors.ink,
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AvaColors.primary,
      selectionColor: Color(0x553A7B65),
      selectionHandleColor: AvaColors.primary,
    ),
  );
}
