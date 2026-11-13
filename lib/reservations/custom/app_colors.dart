import 'package:flutter/material.dart';

class AppColors {
  static const navy = Color(0xFF1B365D);
  static const gold = Color(0xFFC9A24D);
  static const background = Color(0xFFF7F4EE);
  static const muted = Color(0xFF6B7280);
  static const success = Color(0xFF3F7D5C);
  static const danger = Color(0xFFB5483A);
}

String fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';