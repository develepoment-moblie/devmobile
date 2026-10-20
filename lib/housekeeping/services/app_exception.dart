// Common service failure contract. Feature modules do not import each other
// merely to display an error or inspect its HTTP status.
class AppServiceException implements Exception {
  final String message;
  final int? status;
  const AppServiceException(this.message, [this.status]);
  @override
  String toString() => message;
}

// Retained for consumers of the original housekeeping public API.
typedef HousekeepingException = AppServiceException;
