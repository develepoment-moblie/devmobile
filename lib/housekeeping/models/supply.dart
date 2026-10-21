class Supply {
  String name;

  /// linge, accueil, entretien or minibar.
  String category = 'entretien';

  /// Sale price of a minibar item.
  int? priceCents;
  String unit;
  int minimum;
  int quantity;
  String id = '';
  int version = 1;
  Supply(this.name, this.quantity, this.unit, this.minimum);
  bool get isLow => quantity <= minimum;
  bool get isMinibar => category == 'minibar';

  factory Supply.fromMap(Map m) =>
      Supply(
          m['name'] as String,
          m['quantity'] as int,
          m['unit'] as String,
          m['minimum'] as int,
        )
        ..id = m['id'] as String
        ..version = m['version'] as int
        ..category = m['category'] as String? ?? 'entretien'
        ..priceCents = m['priceCents'] as int?;
}

const supplyTypeLabels = {
  'linge': 'Linge',
  'accueil': 'Produits d’accueil',
  'entretien': 'Produits d’entretien',
  'minibar': 'Minibar',
};

/// Parses "4,50" or "4.5" into cents.
int? parseEuros(String text) {
  final match = RegExp(r'^(\d{1,4})(?:[.,](\d{1,2}))?$')
      .firstMatch(text.trim().replaceAll('€', '').trim());
  if (match == null) return null;
  final cents = (match.group(2) ?? '').padRight(2, '0');
  return int.parse(match.group(1)!) * 100 + int.parse(cents);
}

/// 450 → "4,50" (for an editable price field).
String centsText(int cents) =>
    '${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')}';

String euros(int cents) {
  final sign = cents < 0 ? '−' : '';
  final abs = cents.abs();
  return '$sign${abs ~/ 100},${(abs % 100).toString().padLeft(2, '0')} €';
}
