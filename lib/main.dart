import 'package:flutter/material.dart';
import 'reservations/custom/app_colors.dart';
import 'reservations/reservations_module.dart';

void main() => runApp(const HotelApp());

class HotelApp extends StatelessWidget {
  const HotelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nova Paris',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.navy,
          primary: AppColors.navy,
          secondary: AppColors.gold,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.navy,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: const ReservationsModule(),
    );
  }
}