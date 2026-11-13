class MenuItem {
  final String id, name, description, category, symbol, allergens;
  final int priceCents, minutes;
  final int version;
  final int? portions;
  final bool vegetarian, available;
  Map<String, Object?> toRow() => {
    "id": id,
    "name": name,
    "description": description,
    "category": category,
    "symbol": symbol,
    "price_cents": priceCents,
    "minutes": minutes,
    "allergens": allergens,
    "vegetarian": vegetarian ? 1 : 0,
    "available": available ? 1 : 0,
  };
  factory MenuItem.fromRow(Map<String, Object?> row) => MenuItem(
    row["id"] as String,
    row["name"] as String,
    row["description"] as String,
    row["category"] as String,
    row["symbol"] as String,
    row["price_cents"] as int,
    row["minutes"] as int,
    row["allergens"] as String,
    portions: row["portions"] as int?,
    version: row["version"] as int? ?? 1,
    vegetarian: row["vegetarian"] == 1,
    available:
        row["available"] == 1 &&
        row["archived"] != 1 &&
        (row["portions"] as int? ?? 1) > 0,
  );
  const MenuItem(
    this.id,
    this.name,
    this.description,
    this.category,
    this.symbol,
    this.priceCents,
    this.minutes,
    this.allergens, {
    this.version = 1,
    this.portions,
    this.vegetarian = false,
    this.available = true,
  });
}

String euros(int cents) =>
    '${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')} €';

const roomServiceMenu = [
  MenuItem(
    'breakfast',
    'Le petit-déjeuner parisien',
    'Croissant, pain frais, confiture, jus d’orange et café.',
    'Petit-déjeuner',
    '🥐',
    1800,
    20,
    'Gluten, lait',
    vegetarian: true,
  ),
  MenuItem(
    'pancakes',
    'Pancakes aux fruits rouges',
    'Pancakes moelleux, fruits rouges et sirop d’érable.',
    'Petit-déjeuner',
    '🥞',
    1400,
    20,
    'Gluten, lait, œufs',
    vegetarian: true,
  ),
  MenuItem(
    'salad',
    'Salade du jardin',
    'Jeunes pousses, tomates, avocat et vinaigrette au citron.',
    'Plats',
    '🥗',
    1600,
    25,
    'Moutarde',
    vegetarian: true,
  ),
  MenuItem(
    'burger',
    'Burger Nova',
    'Bœuf grillé, comté, oignons confits et pommes de terre dorées.',
    'Plats',
    '🍔',
    2400,
    30,
    'Gluten, lait, œufs, moutarde',
  ),
  MenuItem(
    'pasta',
    'Linguine aux champignons',
    'Champignons poêlés, crème légère, parmesan et herbes fraîches.',
    'Plats',
    '🍝',
    2200,
    30,
    'Gluten, lait, œufs',
    vegetarian: true,
  ),
  MenuItem(
    'cake',
    'Douceur au chocolat',
    'Fondant au chocolat et crème à la vanille.',
    'Desserts',
    '🍫',
    1000,
    15,
    'Gluten, lait, œufs',
    vegetarian: true,
  ),
  MenuItem(
    'fruit',
    'Assiette de fruits frais',
    'Une sélection de fruits de saison, préparés à la commande.',
    'Desserts',
    '🍓',
    900,
    15,
    'À confirmer auprès de la réception',
    vegetarian: true,
  ),
  MenuItem(
    'juice',
    'Orange fraîchement pressée',
    'Un grand verre de jus d’orange, sans sucre ajouté.',
    'Boissons',
    '🍊',
    700,
    10,
    'À confirmer auprès de la réception',
    vegetarian: true,
  ),
  MenuItem(
    'coffee',
    'Café de la maison',
    'Café fraîchement moulu, servi avec un carré de chocolat.',
    'Boissons',
    '☕',
    500,
    10,
    'Lait possible dans le chocolat',
    vegetarian: true,
  ),
  MenuItem(
    'tart',
    'Tarte du jour',
    'Selon l’inspiration de notre pâtissier.',
    'Desserts',
    '🥧',
    1100,
    20,
    'Gluten, lait, œufs',
    available: false,
  ),
];

class CartLine {
  final String itemId, note;
  final int quantity;
  final MenuItem? snapshot;
  const CartLine(this.itemId, this.quantity, this.note, [this.snapshot]);
  MenuItem get item =>
      snapshot ?? roomServiceMenu.firstWhere((item) => item.id == itemId);
  int get total => item.priceCents * quantity;
  Map<String, Object?> toJson() => {
    'itemId': itemId,
    'quantity': quantity,
    'note': note,
    'snapshot': {...item.toRow(), 'portions': item.portions},
  };
  factory CartLine.fromJson(Map<String, dynamic> json) => CartLine(
    json['itemId'] as String,
    json['quantity'] as int,
    json['note'] as String,
    json['snapshot'] == null
        ? null
        : MenuItem.fromRow(Map<String, Object?>.from(json['snapshot'] as Map)),
  );
}

const orderStatusLabels = <String, String>{
  'placed': 'Enregistrée · en attente',
  'accepted': 'Acceptée',
  'preparing': 'En préparation',
  'kitchen_started': 'Préparation démarrée',
  'ready': 'Prête à livrer',
  'out_for_delivery': 'En livraison',
  'delivered': 'Livrée',
  'assigned': 'Agent attribué',
  'rejected': 'Refusée',
  'cancelled': 'Annulée',
};
const nextOrderStatus = <String, String>{
  'placed': 'preparing',
  'accepted': 'delivered',
  'preparing': 'ready',
  'ready': 'delivered',
  'out_for_delivery': 'delivered',
};
