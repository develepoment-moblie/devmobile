# Scope of this project

The merged course application owns user management, authentication, profiles and
roles, rooms and housekeeping: room status, cleaning assignments, checklists,
approval, notifications, linen and supplies. Reservation management, maintenance
interventions, billing, restaurant and other unmerged modules belong to teammates.
Do not implement those modules here. Preserve the friend's original source folder.

Normal main() uses sqflite and nova_paris.db with fresh fictional sample accounts
and data. Keep data persistent across launches. No automatic external import or
synchronization. The user authorized removing all old cloud integration code,
configuration, dependencies, setup files and documentation on 16 October 2026.
Do not delete or modify any remote account or project.

lib/main.dart bootstraps one MaterialApp. lib/app owns session routing and shared
navigation. lib/user_management/{models,screens,services} owns user management.
lib/housekeeping/{models,custom,screens,services} owns rooms and housekeeping.
lib/shared owns SQLite infrastructure, shared contracts, branding, widgets and
errors. Feature modules must not depend on each other or on app/demo; app composes
them using UserRepository, HousekeepingBackend, RoomCatalogBackend and
LocalSessionStore. The public housekeeping entry is lib/housekeeping/housekeeping.dart;
lib/housekeeping.dart remains a compatibility export.

Preserve the professor's models/custom/screens structure, setState, Form,
TextFormField and Navigator, the supplied Figma reference and the user's logo.
Keep code suitable for the course. Do not add another MaterialApp inside a module.

Manager/admin manages users and room metadata, including reversible archive.
They do not gain cleaning approval or stock permissions. Only supervisors assign,
approve cleaning and manage stock. Agents change only their assigned tasks.
Created/restored rooms need cleaning. Archive is blocked for occupancy, maintenance
and active/assigned tasks. Keep version checks and atomic SQLite transactions.
Permissions are local application rules, not server security. See SQLITE.md and
ROOM_MANAGEMENT.md. Never store plaintext passwords or silently reset unreadable data.

lib/demo holds isolated demonstration adapters. LOCAL_JSON_DEMO=true selects the
legacy persistent JSON demo; HOUSEKEEPING_DEMO=true selects the in-memory demo.
The demo role switch is a test aid, not user management. The standalone Node/SQLite
backend remains available for the original housekeeping demonstration. Keep its
development credentials private and separate. See OFFLINE.md and backend/README.md.

System Back is coordinated centrally in lib/app/back_navigation.dart. Delegate to
the authenticated navigator with maybePop (preserving DraftGuard), then unwind
MainScreen tab history. Only the application root offers a two-second double-back
exit hint and calls SystemNavigator.pop on Android. Reset the exit confirmation
after navigation, interaction, session changes and backgrounding. Preserve tab
state and the native Material transitions. See UX-CONTRACT.md and navigation_test.dart.

SQLite remembers only the signed-in profile ID in metadata; logout clears it.
Always reload the current role and reject deleted profiles. App composes the
Manager/admin-only backup screen via an injected builder. BackupRepository is a
shared contract; feature modules remain independent. External .nova-backup files
are password-encrypted, exclude sessions, and are validated before transactional
replacement. Restore requires an explicit preview and replacement confirmation,
then logs out. Never silently merge, reset, export plaintext credentials, or
replace live data during tests. See SQLITE.md and backup_session_test.dart.

The authenticated staff role opens the personal housekeeping workspace:
AgentDashboardScreen and AgentRoomsScreen, composed by app/MainScreen. Filter
assignments with HotelData.canClean (account ID for connected data), never names
for authenticated ownership. AgentWorkload describes current assignments, not
dated shifts or lifetime scores. Keep supervisor permissions and workspace.
Account/profile/authentication remain in user_management; housekeeping must not
import it. See UX-CONTRACT.md and agent_dashboard_test.dart.

User authorized photo evidence per task and supervisor-created room tasks.
SQLite schema v2 stores variable tasks in rooms.tasks and normalized JPEGs in
task_photos; snapshots contain references only. Checking a task must commit its
photo atomically; submission/approval require every task and its photo. Only the
assigned agent can complete tasks; supervisor can add tasks and view evidence.
New tasks reopen review; ready rooms become dirty and reset checks/evidence.
Occupied/maintenance rooms retain their status. Reassignment/restoration reset
evidence but preserve task definitions. Legacy demos remain isolated and unchanged.
The user permits resetting test data: v1 migration clears unverified dirty-room
checklists. Backups v2 include photos (64 MiB); v1 import normalizes old controls.
See SQLITE.md, task_evidence_test.dart and task_photo_screen_test.dart.
