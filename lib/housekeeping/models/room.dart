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

  /// The supervisor's comment when a cleaning was refused.
  String? feedback;

  /// Occupied room with a requested daily cleaning (recouche).
  bool stayover = false;

  /// Cleaning priority: normal, checkout, vip or early (check-in).
  String priority = 'normal';

  /// The cleaning timer, once started: 'running', 'paused' or 'stopped'.
  String? timerState;
  Duration timerClosed = Duration.zero;
  DateTime? timerRunningSince;

  /// Actual working time, once the timer is stopped.
  Duration? timerDuration;

  /// Time worked so far, pauses excluded, counting a running timer up to [now].
  Duration elapsed([DateTime? now]) => timerRunningSince == null
      ? timerClosed
      : timerClosed + (now ?? DateTime.now()).difference(timerRunningSince!);

  void applyTimer(Object? source) {
    final t = source is Map ? source : null;
    timerState = t?['state'] as String?;
    timerClosed = Duration(milliseconds: (t?['closedMs'] as int?) ?? 0);
    timerRunningSince = t?['runningSince'] == null
        ? null
        : DateTime.parse(t!['runningSince'] as String);
    timerDuration = t?['durationMs'] == null
        ? null
        : Duration(milliseconds: t!['durationMs'] as int);
  }

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
          employeeId == null);
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
    room.feedback = map['feedback'] as String?;
    room.stayover = map['stayover'] == true;
    room.priority = map['priority'] as String? ?? 'normal';
    room.applyTimer(map['timer']);
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

  bool get needsCleaning =>
      status == RoomStatus.dirty || (status == RoomStatus.occupied && stayover);
  String get statusLabel => switch (status) {
    RoomStatus.ready => 'Libre',
    RoomStatus.occupied => stayover ? 'Occupée · recouche' : 'Occupée',
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
