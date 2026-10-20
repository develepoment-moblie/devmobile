import '../models/priority.dart';

// Optional contract for the Manager's priority list on the home screen.
abstract interface class PriorityBoard {
  Future<List<Priority>> priorities();
  Future<void> savePriority(
    Priority? original, {
    required String icon,
    required String title,
    required String subtitle,
    required String colorType,
  });
  Future<void> deletePriority(Priority original);
}
