class Supply {
  final String name;
  final String unit;
  final int minimum;
  int quantity;
  String id = '';
  int version = 1;
  Supply(this.name, this.quantity, this.unit, this.minimum);
  bool get isLow => quantity <= minimum;
}
