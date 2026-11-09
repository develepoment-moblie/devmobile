# Changes

Updated after each change in this chat. Latest changes first.

## 2026-11-09 Users and Housekeeping integration
- Merged merge-user-chambres into gestion-clients and kept both the Cuisine and Administrateur test accounts.
- Account creation and role changes now use the shared role list, including Reception, Kitchen and floor agents.
- Existing demo IDs and guest-services data are retained; real accounts have separate identities and require their own room associations.

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


