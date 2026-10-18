// Public feature API. Authentication and application navigation live outside
// this module; every screen accepts its HotelData dependency explicitly.
export 'models/hotel_data.dart';
export 'models/room.dart';
export 'models/supply.dart';
export 'screens/housekeeping_screen.dart';
export 'screens/assign_task_screen.dart';
export 'screens/details_screen.dart';
export 'screens/rooms_screen.dart';
export 'screens/notifications_screen.dart';
export 'screens/supplies_screen.dart';
export 'screens/staff_screen.dart';
export 'screens/agent_dashboard_screen.dart';
export 'screens/agent_rooms_screen.dart';
export 'models/agent_workload.dart';
export 'services/housekeeping_api.dart';
export 'services/housekeeping_backend.dart';
export 'services/sqlite_housekeeping.dart';
export 'services/room_catalog_backend.dart';
export 'services/sqlite_room_catalog.dart';
export 'screens/manage_rooms_screen.dart';
