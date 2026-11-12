import 'package:flutter/material.dart';

/// Converts a stored icon name (from the database) into a real Flutter IconData.
///
/// Example:
///   iconFromString('ac_unit')  ->  Icons.ac_unit
///   iconFromString('calendar') ->  Icons.calendar_today_outlined
IconData iconFromString(String name) {
  switch (name) {
    case 'ac_unit':
      return Icons.ac_unit;
    case 'calendar':
      return Icons.calendar_today_outlined;
    case 'bed':
      return Icons.king_bed_outlined;
    case 'warning':
      return Icons.warning_amber_rounded;
    case 'cleaning':
      return Icons.cleaning_services_outlined;
    case 'people':
      return Icons.people_outline;
    case 'star':
      return Icons.star_outline;
    case 'wrench':
      return Icons.build_outlined;
    case 'coffee':
      return Icons.coffee_outlined;
    case 'restaurant':
      return Icons.restaurant_outlined;
    case 'spa':
      return Icons.spa_outlined;
    case 'event':
      return Icons.celebration_outlined;
    default:
      return Icons.info_outline;
  }
}