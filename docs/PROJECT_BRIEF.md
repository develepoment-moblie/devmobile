# Nova Paris: project brief

A description of how the app is built, to hand to another developer or AI.

## What it is
A Flutter mobile app for hotel management, built as a **school group project**. The brief has 5 modules (reservations, rooms & housekeeping, maintenance, guest services & restaurant, billing & reports, with user management inside the last one), and each team member owns one. The UI is **in French**. Data is stored **locally on the phone in SQLite**: there's no server, no cloud and no sync yet. The main test device is a Xiaomi running Android 14.

- **Repo:** github.com/develepoment-moblie/devmobile. `main` holds the merged team app. The housekeeping owner works on the `Gestion-chambres` branch.
- **Stack:** Flutter 3.47 / Dart 3.
  - Storage: `sqflite` (desktop tests use `sqflite_common_ffi`).
  - Photos: `image_picker` and `image`; `pointycastle` creates photo IDs.
  - QR codes: `qr_flutter` to show them, `mobile_scanner` to scan them.
  - Phone notifications: `flutter_local_notifications`.
  - No state-management library. The course requires `setState`, `Form`, `TextFormField` and `Navigator`, plus `ChangeNotifier` controllers.

## Architecture: one shell, independent modules
```
lib/
  main.dart            opens the database, builds AppSession, attaches modules, runs the app
  app/                 shared shell: the single MaterialApp, login routing, home screen, module list
  shared/              used by every module
    models/            AppUser, AppRole (guest, receptionist, staff, supervisor, maintenance, manager, admin), NovaModule
    services/          AppDatabase (one SQLite file, per-module schemas), AppSession, AppEvents, StaffDirectory
    custom/            theme (AppColors, gradients, shadows), animations, HeroHeader, logo, shared widgets
  <module>/            reservations, housekeeping, maintenance, guest_services, billing, user_management
    <module>_module.dart   entry point: title, roles that see it, schema, attach(), first screen
    models/ custom/ screens/ services/
test/app/              shell tests + architecture test (a module may not import another module or lib/app)
test/<module>/         each module's tests
integration_test/      screen tour run on the real phone (own throwaway database)
```
**Rules:**
- A module only touches its own folder.
- Modules communicate only through `AppSession`, which gives them:
  - `session.user`: the signed-in person;
  - `session.database`: the shared SQLite database;
  - `session.staff`: the staff list (a temporary fictional team for now);
  - `session.events`: typed events between modules.
- **Database:** one file, `nova_paris_hotel.db`. Each module declares a `ModuleSchema` with its own version number and an in-place migration. Table names start with the module name (`housekeeping_rooms`…).
- **Events** (`shared/services/app_events.dart`): `GuestCheckedIn`, `GuestCheckedOut`, `RoomReady`, `MaintenanceRequested`, `MaintenanceResolved`, `ExtraCharged`.

## Status of each module
- **Housekeeping (rooms & cleaning):** complete; details below.
- **User management:** only a temporary test login (pick a fictional person, no password) and a profile screen. Its owner has to build the real accounts.
- **Reservations, maintenance, guest services, billing:** placeholder screens ("Module en construction"), not started.

## The housekeeping module
Layers:
- **Screens:** they use a `HotelData` controller (a `ChangeNotifier`) built from a snapshot returned by a backend interface.
- **Rules:** `services/sqlite_housekeeping.dart`, which handles mutation paths such as `/v1/rooms/<n>/<action>`, `/v1/supplies/<id|new>/<action>`, `/v1/lost/...` and `/v1/notifications/read`.
- **Room catalog rules:** `services/sqlite_room_catalog.dart`, used by the Manager.
- **Storage:** `services/housekeeping_store.dart` loads the module's tables into a state map and runs each change in **one SQLite transaction**.
- **Every action** checks the role, who owns the room and a version number, so an out-of-date change is refused with a 409-style error.

Roles:
- **Agent** (`staff`): only the rooms assigned to them.
- **Supervisor** (gouvernante): assigns, approves or refuses cleanings, manages stock, items found, statistics.
- **Manager/admin:** floors and rooms catalog.

Features:
- room statuses (free, occupied, to clean, maintenance);
- assignment, checklist with a **required photo per task**, submission, approval, and refusal with a comment;
- scored inspection: each item rated OK / partiel / non conforme with a weight, score out of 100 against a per-category threshold, "Renvoyer en nettoyage" back to the same agent with the failed items, inspection history per room, score stored in the cleaning log;
- recouche (cleaning an occupied room);
- task lists per room category;
- stock items with automatic low-stock alerts;
- lost and found with photos;
- notifications, plus Android notifications;
- statistics from a cleaning log;
- QR code per room door and a scanner;
- Manager floor view (floors → room grid → room sheet), creating many rooms at once, archive and restore;
- reacting to other modules' events.

Database: `housekeeping_*` tables, at version 4 (rooms, photos, supplies, notifications, cleaning log, lost items, category tasks, floors, and more).

In progress: a cleaning timer per room (start, pause, resume, stop; survives restarts) and automatic assignment of rooms to housekeepers, as a separate testable module.

## Quality and conventions
- **Tests:** about 54 automated tests covering business rules on a real SQLite database, widget tests (some use an in-memory store that runs the real rules) and screenshot (golden) tests. On-phone check: `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/screen_tour_test.dart -d <device>`.
- **Before every commit:** `flutter analyze` must report no issues and `flutter test` must pass.
- **Design:** dark green `#183C35`, terracotta `#C66F55`, gold, Manrope font. Animations play once and respect Android's "remove animations" setting.
- **Build options:** `--dart-define=HOUSEKEEPING_SAMPLE_DATA=false` makes a new install start with an empty hotel.
- **Constraints for any AI working on it:**
  - French UI text with correct grammar;
  - stay within the module you're asked about;
  - don't create a second MaterialApp;
  - passwords are never stored in plain text;
  - no AI attribution in commits.

## Known gaps and good targets for new prompts
- Real accounts and login (user management), remembered between launches.
- The four teammate modules, and wiring their events (checkout → housekeeping, and so on).
- Offline sync and a server: planned next. New mutations carry a client UUID and timestamp for this.
- Database backup and restore.
- Testing the camera flows on the phone: photos, QR scanning, notifications.
