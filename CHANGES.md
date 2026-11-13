# Changes

Updated after each change in this chat. Latest changes first.

## 2026-11-13 Menu item input validation
- Added field feedback during editing, stricter whole-minute validation, and specific save errors. Matched text-length checks to the form’s character counters.

## 2026-11-13 Room-service currency picker
- Added common currencies and custom currency codes to the menu and cart. Checkout stays in euros.
- SQLite caches rates per currency and preserves the previous TND rate during migration.

## 2026-11-12 Restaurant booking without predefined slots
- Guests and management choose a future date and time directly. New restaurant bookings reserve the selected table for two hours, with overlap checks in SQLite.
- Removed restaurant slots from management. Spa keeps its appointment slots, and existing restaurant bookings retain their saved times.
- Validation: 45 targeted tests passed, including direct booking, overlapping table protection, and seating without a predefined slot.

## 2026-11-12 Guest services web APIs
- Added the Frankfurter EUR-to-TND estimate to the menu and cart, with a dated SQLite cache and euro checkout totals.
- Added optional restaurant confirmation emails through the hotel server and Brevo. Reception can retry a failed email without changing the confirmed booking.

## 2026-11-12 Shorter restaurant booking
- Added a dedicated Réserver une table action. The form asks for the time, party size and table, with an optional note.
- Added a booking summary with the selected table, party size and start time.

## 2026-11-12 User-management role picker
- Added Cuisine and Réceptionniste to account creation, editing and quick role changes. The form and account list show the shared French role labels.

## 2026-11-12 Services clients navigation
- Added labeled shortcuts for clients, reception, management and kitchen. Floor agents open their delivery list directly.
- Restaurant, Spa and Demandes shortcuts open the matching category. Mes commandes opens order tracking directly.
- Validation: 42 targeted tests passed, including role-specific shortcuts and the Spa route.

## 2026-11-12 StayingAPI search button
- Restored the external hotel search button. Android debug builds load the test key from the ignored local JSON file when no explicit Dart define is supplied.

## 2026-11-12 StayingAPI setup and error state
- The external hotel search appears when `STAYING_API_KEY` is configured. Nova Paris room search stays available in builds without a key.
- Added request timeouts and a readable error message. Documented a Git-ignored local configuration for Android Studio.

## 2026-11-12 Réservations integration
- Imported the room search, booking, confirmation and stays screens from `origin/Gestion-reservation` at `250e5e4` and registered their four room images.
- Connected the imported screens to the existing Réservations tile. The optional StayingAPI integration reads `STAYING_API_KEY` from the build configuration.
- The imported booking service keeps reservations in memory. All 41 targeted app-shell and guest-services tests passed.

## 2026-11-12 Sign-out fix
- Clear the active account immediately and finish removing the remembered session before the login screen restores a session.

## 2026-11-12 Maintenance integration
- Imported Maintenance and its tests from `origin/Gestion-chambres` at `20cf2be`, including intervention tracking, weather alerts, translation and configurable photo diagnosis.
- Updated the app-shell test to open the imported dashboard. All 56 targeted tests passed.

## 2026-11-12 Chambres and Utilisateurs integration
- Imported Chambres, Utilisateurs and the Chambres sync server from `origin/Gestion-chambres` at `20cf2be`.
- Kept the current Services clients et restauration work and combined the incoming Firebase password-reset changes with the local email normalization fix.
- Validation: 237 tests passed. Two Chambres screenshot comparisons failed. The app was not launched.

## 2026-11-12 Email sign-in
- Email sign-in and local password recovery ignore case and surrounding spaces. Existing account IDs and passwords are preserved.
- New accounts store normalized email addresses and reject case or spacing duplicates.

## 2026-11-11 Restaurant bookings for outside visitors
- Management can book a table under a visitor’s name without a hotel account or stay.
- The booking form links to slot management when no upcoming restaurant slot is available and reloads after returning.

## 2026-11-11 Fixed restaurant layout and table suggestions
- Replaced layout editing with nine numbered tables in fixed positions. The room uses round, square and rectangular tables with 2, 4, 6 or 8 seats.
- Clients and management share the booking plan for the selected slot. Management can confirm a reservation for an existing client account.
- The suggestion highlights the smallest suitable available table with a short pulse, then leaves it highlighted until the guest chooses.
- SQLite schema version 9 preserves previous bookings and seating history while opening the fixed layout for new reservations.
- Validation: 40 targeted Flutter tests passed, including the suggestion and management booking for a client. App not launched.

## 2026-11-11 Restaurant floor status colors
- Matched the reference with a light tiled background, larger table names, color-coded tables and chairs, and a status legend.

## 2026-11-11 Illustrated restaurant floor
- Replaced table cards on the shared floor plan with round tables and chairs on a wood floor. Table labels show capacity and status.
- Empty positions appear as small markers in edit mode and highlight when a table is dragged over them.

## 2026-11-11 Floor plan row sizing
- Dropping a table in the last row keeps the grid the same size. Use « Ajouter une rangée » to extend the plan during editing.

## 2026-11-11 Drag-and-drop restaurant layout
- Added an editing mode for management. Long-press a table and drag it to a highlighted free cell, or select the table and tap a free cell.
- Each move saves to the existing SQLite layout and shows confirmation. Occupied cells cannot receive a drop.
- Validation: 40 targeted Flutter tests passed, including a phone-sized drag gesture that checks the saved position. App not launched.

## 2026-11-11 Restaurant table selection
- Added an interactive top-down grid. Management can move a table to a free position.
- Guests select a suitable table for a restaurant time slot. The booking transaction checks table capacity and overlapping reservations.
- Reception sees the reserved table and can install the group there or choose another eligible table. Existing bookings without a table can still be seated at arrival.
- SQLite schema version 8 adds floor positions and links reservations to tables.
- Validation: 39 targeted tests passed, including phone-size table selection and overlapping booking rejection. Static analysis is clean. App not launched.

## 2026-11-11 Restaurant floor service
- Management can configure tables and seating capacity. Reception can register arrivals, place parties at suitable tables, and release tables when service ends.
- The floor screen shows available and occupied tables and keeps arrived parties visible until seated.
- SQLite schema version 7 records seating history, prevents overlapping occupancy, and releases tables on completion or cancellation.
- Validation: 38 guest-services and app-shell tests passed, including the seating workflow. App not launched.

## 2026-11-09 Smart dispatch and kitchen planning
- Reception sees the recommended floor agent and each agent’s open delivery count. The receptionist retains the choice.
- Kitchen sees a deadline-ordered preparation plan, starts one recorded preparation at a time, and sees estimated ready times and missed targets.
- Forecasts recalculate as the queue changes. Missing estimates or an overrun leave downstream times unconfirmed.
- Validation: targeted static analysis clean; 37 guest-services and app-shell tests passed. App not launched.

## 2026-11-09 Users and Housekeeping integration
- Merged merge-user-chambres into gestion-clients and kept both the Cuisine and Administrateur test accounts.
- Account creation and role changes now use the shared role list, including Reception, Kitchen and floor agents.
- Existing demo IDs and guest-services data are retained; real accounts have separate identities and require their own room associations.
- Verified account roles and directory filtering with real SQLite accounts in an isolated test database. Analysis clean; 183 tests passed, with two Housekeeping golden tests reporting rounded-edge pixel differences. App not launched.

## 2026-11-07 Kitchen preparation queue
- Kitchen sees accepted orders and preparation notes, marks orders ready for delivery, and still has access to stock.
- Reception, guests, and assigned agents see the ready status. Delivery confirmation is gated on kitchen readiness for the current workflow.
- Fixed stock-screen refresh feedback after saving portions.
- Validation: targeted static analysis clean; all 32 guest-services and app-shell tests passed. App not launched.

## 2026-11-07 Delivery feedback and reception order sorting
- Fixed a refresh error that displayed a failure message after a successful delivery.
- Reception shows active orders first and recent deliveries ahead of older completed orders.
- Added regression coverage for the success message, agent attribution, and recent delivery placement.

## 2026-11-07 Floor-agent delivery confirmation
- Reception chooses a floor agent at acceptance and can reassign an active order.
- Floor agents see their own deliveries and only the assigned agent can confirm the handoff.
- Reception sees the agent’s name and delivery time. Existing deliveries retain their history; unassigned active orders can be assigned.
- Delivery updates use the same device’s database.
- Validation: targeted static analysis clean; 32 guest-services and app-shell tests passed. App not launched.

## 2026-11-07 Kitchen stock and quicker reception
- Added a dedicated Cuisine role and screen for available portions and service pauses; managers still own the menu.
- Checkout reserves portions atomically. Pending cancellations return reserved portions; later cancellations do not.
- Reception accepts and marks delivered from one queue; exceptional cancellation with a reason is in the overflow menu.
- Schema v5 preserves existing orders. Existing dishes start with zero free portions until kitchen staff enter a count.
- Stock is local to this device. The app was not launched.
- Validation: targeted static analysis clean; 32 guest-services and app-shell tests passed.

## 2026-10-28 Service desk and reservations
- Added persistent restaurant/spa slots, bookings, special requests, complaints and conversations.
- Added manager slot CRUD, capacity checks and client appointment conflict prevention.
- Added role-checked lifecycle, customer edits/cancellation, staff archive/restore, messages and service reviews.
- Added staff assignment, audit records, booking snapshots and stale-write protection.
- Added category CRUD and category rename propagation; menu edits reject stale versions.
- Removed automatic sample rooms and menu data on new installations. Reception now verifies room associations with an expiry date.
- Upgrades preserve existing menu/orders and deactivate automatic room associations.
- Validation: 29 module and app integration tests passed, including concurrent capacity, guest isolation, room verification, stale writes and phone-sized forms. Static analysis clean. App not launched.
- Integration limits: authentication/directory still come from Users; cross-device synchronization, external notifications and Billing remain unconnected. Room association is manually verified by reception.

## Reception dashboard and delay alerts
- Added pending/active/overdue counts and average delivery time for orders delivered today.
- Added overdue filter, priority sorting and elapsed-time labels; refreshes elapsed time every minute.
- Alerts: pending for 5 minutes; active beyond the longest saved preparation estimate plus 10 minutes.
- New orders save preparation estimates. Legacy orders without estimates only get pending alerts.
- All data and alerts stay local. No external notifications or automatic billing.
- Validation: static analysis clean; 16 guest-service and app integration tests passed. App not launched.

## Earlier work
- Added manager menu CRUD with archive/restore and price/availability checks.
- Added reception order processing and client status tracking with demo room 305.
- Added client menu, saved cart and order history; changed home modules to a responsive grid.
- Installed Android build dependencies and disabled Kotlin incremental compilation for split-drive builds.


