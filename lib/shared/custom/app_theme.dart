import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFFF7F3EA);
  static const primary = Color(0xFF183C35);
  static const accent = Color(0xFFC66F55);
  static const ink = Color(0xFF25322F);
  static const muted = Color(0xFF77837F);
  static const border = Color(0xFFE1E5E3);
  static const tabs = Color(0xFFE9EAE5);
  static const gold = Color(0xFFE9D5AD);
  static const red = Color(0xFFBA5D51);
  static const redLight = Color(0xFFF5E4E0);
  static const orange = Color(0xFFC88945);
  static const orangeLight = Color(0xFFF7EBDC);
  static const green = Color(0xFF5E8D75);
  static const greenLight = Color(0xFFE5EFE8);
  static const gray = Color(0xFF697570);
  static const grayLight = Color(0xFFECEFED);
}

ThemeData novaTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Manrope',
  scaffoldBackgroundColor: AppColors.background,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    secondary: AppColors.accent,
    surface: AppColors.background,
  ),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(color: AppColors.ink, fontSize: 13),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.background,
    foregroundColor: AppColors.ink,
    surfaceTintColor: Colors.transparent,
    titleTextStyle: TextStyle(
      fontFamily: 'Manrope',
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.all(16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: AppColors.border),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.accent,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: Colors.white,
      minimumSize: const Size(0, 46),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      textStyle: const TextStyle(
        fontFamily: 'Manrope',
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  ),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: AppColors.primary,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  ),
  scrollbarTheme: const ScrollbarThemeData(
    thumbColor: WidgetStatePropertyAll(AppColors.muted),
  ),
);
