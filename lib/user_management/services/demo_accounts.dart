// Optional contract for the local demonstration. Login screens can display
// fictional accounts without importing the application's storage adapter.
abstract interface class DemoAccounts {
  Map<String, String> get demoAccounts;
  String get demoAccountPassword;
}
