import 'task_schema.dart';

enum RoomStatus { ready, occupied, dirty, maintenance }

enum CleaningStatus { waiting, inProgress, review, completed }

class RoomTask {
  final String id, label;
  String? photoId;
  RoomTask(this.id, this.label, {this.photoId});
}

class Room {
  final String number;
  String category;
  RoomStatus status;
  CleaningStatus cleaning;
  String? employee;
  String? employeeId;
  String? approvedBy;
  int version = 1;
  String note;
  bool urgent;
  final List<bool> checklist;
  final List<RoomTask> tasks = TaskSchema.defaults()
      .map((t) => RoomTask(t['id'] as String, t['label'] as String))
      .toList();
  bool requiresPhotos = false;
  bool get checklistComplete =>
      checklist.isNotEmpty &&
      !checklist.contains(false) &&
      (!requiresPhotos || tasks.every((t) => t.photoId != null));
  final List<String> history;

  Room(
    this.number, {
    this.category = 'Chambre Deluxe',
    this.status = RoomStatus.dirty,
    this.cleaning = CleaningStatus.waiting,
    this.employee,
    this.note = '',
    this.urgent = false,
  }) : checklist = List.filled(
         4,
         cleaning == CleaningStatus.completed,
         growable: true,
       ),
       history = ['Chambre ajoutée au planning du matin'];

  int get floor => int.parse(number.substring(0, 1));
  bool get canArchive =>
      (status == RoomStatus.ready && cleaning == CleaningStatus.completed) ||
      (status == RoomStatus.dirty &&
          cleaning == CleaningStatus.waiting &&
          employeeId == null &&
          employee == null);
  factory Room.fromMap(Map<String, dynamic> map) {
    final room = Room(
      map['number'] as String,
      category: map['category'] as String,
      status: RoomStatus.values.byName(map['status'] as String),
      cleaning: CleaningStatus.values.byName(map['cleaning'] as String),
      note: map['note'] as String? ?? '',
      urgent: map['urgent'] as bool? ?? false,
    );
    room.version = map['version'] as int;
    room.employeeId = map['employeeId'] as String?;
    room.approvedBy = map['approvedBy'] as String?;
    room.checklist
      ..clear()
      ..addAll((map['checklist'] as List).cast<bool>());
    room.applyTasks(map['tasks'] as List?);
    room.history
      ..clear()
      ..addAll((map['history'] as List).cast<String>());
    return room;
  }
  void applyTasks(List? source) {
    requiresPhotos = source != null;
    if (source == null) return;
    tasks
      ..clear()
      ..addAll(
        source.map(
          (t) => RoomTask(
            t['id'] as String,
            t['label'] as String,
            photoId: t['photoId'] as String?,
          ),
        ),
      );
  }

  bool get needsCleaning => status == RoomStatus.dirty;
  String get statusLabel => switch (status) {
    RoomStatus.ready => 'Libre',
    RoomStatus.occupied => 'Occupée',
    RoomStatus.dirty => 'À nettoyer',
    RoomStatus.maintenance => 'Maintenance',
  };
  String get cleaningLabel => switch (cleaning) {
    CleaningStatus.waiting => urgent ? 'Urgent' : 'En attente',
    CleaningStatus.inProgress => 'En cours',
    CleaningStatus.review => 'À valider',
    CleaningStatus.completed => 'Terminée',
  };
  String get subtitle {
    if (cleaning == CleaningStatus.completed) {
      return 'Validée par ${approvedBy ?? 'Amina'}';
    }
    if (urgent && note.isNotEmpty) return note;
    if (employee != null) return 'Assignée à $employee';
    return note.isEmpty ? 'En attente d’attribution' : note;
  }
}
