class Room {
  final String id;
  final String name;
  final String type;
  final String description;
  final int capacity;
  final int surface;
  final double pricePerNight;
  final String imagePath;

  const Room({
    required this.id,
    required this.name,
    required this.type,
    required this.description,
    required this.capacity,
    required this.surface,
    required this.pricePerNight,
    required this.imagePath,
  });
}