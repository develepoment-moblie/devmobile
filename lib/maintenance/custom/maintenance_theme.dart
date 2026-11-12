import 'package:flutter/material.dart';

import '../models/intervention.dart';

/// Couleurs du module Maintenance (alignées sur la palette du projet).
class MC {
  MC._();

  static const cream = Color(0xFFF6F1EA);
  static const dark = Color(0xFF1B3A32);
  static const text = Color(0xFF1E1E1E);
  static const muted = Color(0xFF8B8378);
  static const subtitle = Color(0xFF6F7FA6);
  static const border = Color(0xFFE6DFD3);
  static const dashed = Color(0xFFC9C2B6);

  static const terra = Color(0xFFC4704F);
  static const maintenanceCard = Color(0xFF9B4E3C);
  static const accent = Color(0xFFD9694B);

  static const urgentBg = Color(0xFFF7E1DA);
  static const urgentFg = Color(0xFFC4553F);
  static const highBg = Color(0xFFF9EAD7);
  static const highFg = Color(0xFFCB8A3A);
  static const normalBg = Color(0xFFECEBE8);
  static const normalFg = Color(0xFF6B6B6B);
  static const readyBg = Color(0xFFE3EDE3);
  static const readyFg = Color(0xFF5B8A5F);

  static const white16 = Color(0x29FFFFFF);
  static const white65 = Color(0xA6FFFFFF);
}

/// Raccourci pour les styles de texte du module.
TextStyle mt(
  double size, {
  FontWeight weight = FontWeight.w500,
  Color color = MC.text,
  double? letterSpacing,
  double? height,
}) => TextStyle(
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: letterSpacing,
  height: height,
);

/// Décoration des champs de saisie (carte blanche, bord arrondi).
InputDecoration mcInput(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: mt(13, color: MC.muted),
  filled: true,
  fillColor: Colors.white,
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  border: _border(MC.border),
  enabledBorder: _border(MC.border),
  focusedBorder: _border(MC.dark),
  errorBorder: _border(MC.urgentFg),
  focusedErrorBorder: _border(MC.urgentFg),
);

OutlineInputBorder _border(Color c) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(14),
  borderSide: BorderSide(color: c),
);

extension InterventionPriorityStyle on InterventionPriority {
  Color get background => switch (this) {
    InterventionPriority.urgent => MC.urgentBg,
    InterventionPriority.high => MC.highBg,
    InterventionPriority.normal => MC.normalBg,
  };

  Color get foreground => switch (this) {
    InterventionPriority.urgent => MC.urgentFg,
    InterventionPriority.high => MC.highFg,
    InterventionPriority.normal => MC.normalFg,
  };
}

extension InterventionStatusStyle on InterventionStatus {
  Color get background => switch (this) {
    InterventionStatus.pending => MC.normalBg,
    InterventionStatus.inProgress => MC.highBg,
    InterventionStatus.resolved => MC.readyBg,
  };

  Color get foreground => switch (this) {
    InterventionStatus.pending => MC.normalFg,
    InterventionStatus.inProgress => MC.highFg,
    InterventionStatus.resolved => MC.readyFg,
  };
}

extension InterventionCategoryStyle on InterventionCategory {
  IconData get icon => switch (this) {
    InterventionCategory.climatisation => Icons.ac_unit,
    InterventionCategory.plomberie => Icons.water_drop_outlined,
    InterventionCategory.electricite => Icons.bolt_outlined,
    InterventionCategory.television => Icons.tv_outlined,
    InterventionCategory.autre => Icons.build_outlined,
  };
}
