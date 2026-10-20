class Supply {
  String name;
  String unit;
  int minimum;
  int quantity;
  String id = '';
  int version = 1;
  Supply(this.name, this.quantity, this.unit, this.minimum);
  bool get isLow => quantity <= minimum;
}
