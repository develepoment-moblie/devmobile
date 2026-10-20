abstract class HousekeepingBackend {
  Future<Map<String, dynamic>> snapshot();
  Future<void> mutate(String path, Map<String, dynamic> body);
  void close();
}

abstract interface class TaskPhotoBackend {
  Future<String> taskPhoto(String roomNumber, String taskId);
}
