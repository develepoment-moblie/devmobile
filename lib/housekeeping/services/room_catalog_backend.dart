import '../models/room.dart';
import '../models/supply.dart';
import 'inspection_scoring.dart';

enum RoomCatalogAction {
  create,
  createRange,
  update,
  archive,
  restore,
  renameFloor,
  setCategoryTasks,
  setCategoryEstimate,
  setInspectionRules,
  saveMinibarItem,
  deleteMinibarItem,
}

/// A category's default task list, applied to its new and idle rooms.
class CategoryTasks {
  final String category;
  final List<String> labels;
  final int version;
  const CategoryTasks(this.category, this.labels, this.version);
}

class RoomCatalogSnapshot {
  final List<Room> rooms, archivedRooms;

  /// Floor names by floor number; floors without a name use "Étage N".
  final Map<int, String> floorNames;
  final Map<int, int> floorVersions;
  final Map<String, CategoryTasks> categoryTasks;

  /// Estimated cleaning minutes per category, with their versions.
  final Map<String, ({int minutes, int version})> estimates;

  /// Inspection threshold and item weights per category.
  final Map<String, InspectionRules> inspectionRules;

  /// The minibar catalog: items with their sale price.
  final List<Supply> minibarItems;
  InspectionRules rulesFor(String category) =>
      inspectionRules[category] ?? const InspectionRules();
  const RoomCatalogSnapshot(
    this.rooms,
    this.archivedRooms, {
    this.floorNames = const {},
    this.floorVersions = const {},
    this.categoryTasks = const {},
    this.estimates = const {},
    this.inspectionRules = const {},
    this.minibarItems = const [],
  });

  String floorName(int floor) => floorNames[floor] ?? 'Étage $floor';

  /// Floors that have active rooms or a name, in order.
  List<int> get floors =>
      {...rooms.map((r) => r.floor), ...floorNames.keys}.toList()..sort();

  /// Categories in use or with a task list, sorted.
  List<String> get categories => {
    ...rooms.map((r) => r.category),
    ...archivedRooms.map((r) => r.category),
    ...categoryTasks.keys,
    ...estimates.keys,
  }.toList()..sort();

  factory RoomCatalogSnapshot.fromMap(Map<String, dynamic> map) {
    List<Room> parse(List? source) =>
        (source ?? [])
            .map((r) => Room.fromMap(Map<String, dynamic>.from(r as Map)))
            .toList()
          ..sort((a, b) => a.number.compareTo(b.number));
    final floors = (map['floors'] as List? ?? []).cast<Map>();
    return RoomCatalogSnapshot(
      parse(map['rooms'] as List),
      parse(map['archivedRooms'] as List?),
      floorNames: {
        for (final f in floors) f['number'] as int: f['name'] as String,
      },
      floorVersions: {
        for (final f in floors) f['number'] as int: f['version'] as int,
      },
      categoryTasks: {
        for (final e in (map['categoryTasks'] as Map? ?? {}).entries)
          e.key as String: CategoryTasks(
            e.key as String,
            (e.value['tasks'] as List).cast<String>(),
            e.value['version'] as int,
          ),
      },
      minibarItems: [
        for (final m in map['minibarItems'] as List? ?? [])
          Supply.fromMap(m as Map),
      ],
      inspectionRules: {
        for (final e in (map['inspectionRules'] as Map? ?? {}).entries)
          e.key as String: InspectionRules.fromMap(e.value as Map),
      },
      estimates: {
        for (final e in (map['estimates'] as Map? ?? {}).entries)
          e.key as String: (
            minutes: e.value['minutes'] as int,
            version: e.value['version'] as int,
          ),
      },
    );
  }
}

abstract class RoomCatalogBackend {
  Future<RoomCatalogSnapshot> snapshot();
  Future<void> mutate(RoomCatalogAction action, Map<String, dynamic> body);
}
