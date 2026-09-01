---
goal: Match kick-off reminder alerts configured by double-tapping an upcoming fixture
version: 1.0
date_created: 2026-09-01
owner: my-football maintainers
status: 'Planned'
tags: [feature, notifications, fixtures, reminders]
---

# Introduction

![Status: Planned](https://img.shields.io/badge/status-Planned-blue)

This plan adds **kick-off reminders** to the my-football Flutter app. When a
user double-taps an upcoming match (in the Fixtures tab or a team's "next
fixtures" list), a modal sheet opens where they can configure a reminder. The
default lead time is **15 minutes before kick-off**. At kick-off minus the
chosen lead time, the app fires a local notification via the already-included
`flutter_local_notifications` plugin, following the same wrapper pattern as the
existing `GoalNotificationService`.

## 1. Requirements & Constraints

- **REQ-001**: Double-tapping an upcoming fixture row opens a reminder
  configuration pop-up (modal bottom sheet).
- **REQ-002**: The sheet pre-selects a lead time of **15 minutes before
  kick-off** as the default.
- **REQ-003**: The sheet offers these options only: Off, 15 min, 30 min,
  60 min, 120 min before kick-off, plus a Save action.
- **REQ-004**: On Save, an OS notification is scheduled at
  `kickoffUtc - leadTime` and fires even when the app is not running.
- **REQ-005**: Saved reminders persist across app restarts
  (`shared_preferences`, already a direct dependency).
- **REQ-006**: Reminders can only be configured for upcoming matches whose
  kick-off is in the future; finished/live/postponed rows do not offer the
  double-tap affordance.
- **REQ-007**: Selecting "Off" cancels a previously scheduled reminder for
  that fixture.
- **SEC-001**: All reminder data stays on-device (SharedPreferences + local
  notifications); no new network calls and no new permissions beyond what the
  app already holds (plus `RECEIVE_BOOT_COMPLETED`, see CON-002).
- **CON-001**: Android is the target platform for manual verification; the
  Dart code is cross-platform but iOS behaviour is not verified in this plan.
- **CON-002**: Scheduling uses `AndroidScheduleMode.inexactAllowWhileIdle` so
  no Android 12+ exact-alarm permission is required; `RECEIVE_BOOT_COMPLETED`
  is added so the plugin's boot receiver can re-register pending alarms.
- **CON-003**: Only already-present or minimal new packages may be added:
  `timezone` (promote from transitive) and `flutter_timezone` (IANA timezone
  lookup). No backend changes.
- **GUD-001**: New code lives in `lib/features/reminders/` following the
  existing feature-folder convention (`view`, `providers`, repository/store).
- **GUD-002**: Tests mirror the `lib/` structure under `test/`, as done for
  `test/features/live/`.
- **PAT-001**: Follow the Riverpod patterns used in
  `lib/features/fixtures/fixtures_providers.dart`
  (`Provider`/`Notifier` + `sharedPreferencesProvider`).
- **PAT-002**: Follow the notification-wrapper pattern of
  `lib/features/live/goal_notification_service.dart`
  (thin service class, `ensureReady()`, injectable plugin for testing).

## 2. Implementation Steps


### Implementation Phase 1

- **GOAL-001**: Add the reminder domain model, persistence store, and Riverpod
  wiring so reminders survive restarts.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-001 | Add `timezone: ^0.10.1` and `flutter_timezone: ^4.1.0` (latest stable at implementation time; `timezone` is already in `pubspec.lock` as a transitive dep) to `dependencies` in `pubspec.yaml`, then run `flutter pub get`. | | |
| TASK-002 | Create `lib/features/reminders/match_reminder.dart`: immutable `MatchReminder` class with fields `fixtureId` (int), `kickoffUtc` (DateTime, UTC), `homeName` (String), `awayName` (String), `leadMinutes` (int); a static `const defaultLeadMinutes = 15`; `static const allowedLeadMinutes = [15, 30, 60, 120]`; `DateTime get notifyAtUtc => kickoffUtc.subtract(Duration(minutes: leadMinutes))`; `bool get isExpired => DateTime.now().toUtc().isAfter(kickoffUtc)`; `toJson()`/`fromJson()` serialising `kickoffUtc` as ISO-8601 UTC string. | | |
| TASK-003 | Create `lib/features/reminders/reminder_store.dart`: `ReminderStore` taking a `SharedPreferences` (constructed from `sharedPreferencesProvider` like `CacheStore` in `lib/core/storage/cache_store.dart`). Persists a JSON list under key `'match_reminders'`. Methods: `Future<List<MatchReminder>> load()`, `Future<void> upsert(MatchReminder reminder)` (replace by `fixtureId`), `Future<void> remove(int fixtureId)`, `Future<void> removeExpired()`, `MatchReminder? forFixture(List<MatchReminder> list, int fixtureId)`. | | |
| TASK-004 | Create `lib/features/reminders/reminders_providers.dart`: `reminderStoreProvider` (`Provider<ReminderStore>` built from `sharedPreferencesProvider`, mirroring `fixturesRepositoryProvider` in `lib/features/fixtures/fixtures_providers.dart`), and `remindersProvider` (`Notifier<AsyncValue<List<MatchReminder>>>`) that loads once on build and exposes `setLead(Fixture fixture, int? leadMinutes)` — `null` meaning Off — which persists via the store and returns the resulting list. | | |
| TASK-005 | Create `test/features/reminders/match_reminder_test.dart`: JSON round-trip, `notifyAtUtc` math for the 15-minute default, `isExpired` true/false cases. | | |
| TASK-006 | Create `test/features/reminders/reminder_store_test.dart` using `SharedPreferences.setMockInitialValues({})`: upsert inserts and replaces by `fixtureId`, remove deletes, removeExpired keeps only future kick-offs, load returns empty list on fresh storage. | | |

### Implementation Phase 2

- **GOAL-002**: Implement the notification scheduling service that turns a
  saved reminder into a scheduled OS notification.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-007 | Create `lib/features/reminders/reminder_notification_service.dart`: `ReminderNotificationService` with an optional injectable `FlutterLocalNotificationsPlugin` (per PAT-002). `ensureReady()` calls `tz.initializeTimeZones()` once, resolves the device IANA name via `flutter_timezone`'s `FlutterTimezone.getLocalTimezone()` with a `UTC` fallback, sets `tz.setLocalLocation`, then reuses the plugin-initialise/permission-request structure from `GoalNotificationService.ensureReady()`. `schedule(MatchReminder reminder)` computes `final scheduled = tz.TZDateTime.from(reminder.notifyAtUtc, tz.local);` skips (no-op) when `scheduled.isBefore(DateTime.now())`, and otherwise calls `zonedSchedule` with id derived from `reminder.fixtureId` (e.g. `100000 + fixtureId`), a dedicated Android channel `match_reminders` ("Match reminders") with `Importance.high`/`Priority.high`, title `'{homeName} vs {awayName}'`, body `'Kick-off in {leadMinutes} minutes'`, and `AndroidScheduleMode.inexactAllowWhileIdle`. `cancel(int fixtureId)` cancels the same derived id. | | |
| TASK-008 | In `android/app/src/main/AndroidManifest.xml`, add `<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>` next to the existing `POST_NOTIFICATIONS` permission so the plugin's boot receiver can re-register pending reminders after reboot. | | |
| TASK-009 | Create `test/features/reminders/reminder_notification_service_test.dart` with a mocked/fake plugin: verifies `schedule()` is called once with the correct derived id, is not called for a kick-off already in the past, and `cancel()` targets the derived id. | | |


### Implementation Phase 3

- **GOAL-003**: Add the double-tap affordance and the reminder configuration
  sheet, wired to the providers and service.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-010 | Extend `lib/features/fixtures/widgets/fixture_tile.dart`: add `final VoidCallback? onDoubleTap;` to `FixtureTile` and pass it to the existing `InkWell` as `onDoubleTap:`. No other behavioural change; all existing callers remain valid. | | |
| TASK-011 | Create `lib/features/reminders/reminder_sheet.dart`: `Future<void> showReminderSheet(BuildContext context, WidgetRef ref, Fixture fixture)` showing a modal bottom sheet (`showModalBottomSheet`) with the match names and local kick-off time, a `RadioListTile` list built from `['Off', ...MatchReminder.allowedLeadMinutes]`, pre-selecting the stored value or 15 minutes (REQ-002) when none exists, and Save/Cancel buttons. On Save with a lead time: persist via `remindersProvider` and schedule via `ReminderNotificationService`; on Save with "Off": persist removal and call `cancel`. Then pop the sheet and show a `SnackBar` confirming the choice. | | |
| TASK-012 | Wire `lib/features/fixtures/fixtures_view.dart`: in `_MatchweekSection`, pass `onDoubleTap` to `FixtureTile` for fixtures where `!f.isFinished && !f.isLive && f.dateUtc.isAfter(DateTime.now())` (REQ-006), opening the sheet. | | |
| TASK-013 | Wire `lib/features/team/team_detail_screen.dart` the same way for the "next fixtures" list (pass a fixture-dependent `onDoubleTap` to `FixtureTile`). | | |
| TASK-014 | Create `test/features/reminders/reminder_sheet_test.dart`: pump the sheet inside a `ProviderScope` with overridden providers; assert the 15-minute option is pre-selected by default; assert selecting "Off" invokes store removal and `cancel`. | | |

### Implementation Phase 4

- **GOAL-004**: Handle permissions gracefully and keep the reminder list tidy
  over time.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-015 | In `showReminderSheet` (TASK-011), call `ensureReady()` before scheduling. If notification permission is denied, still persist the choice but show a SnackBar explaining that reminders will be silent until notifications are enabled in system settings. | | |
| TASK-016 | On app start in `lib/main.dart` (after `SharedPreferences.getInstance()`), call `ReminderStore(prefs).removeExpired()` so stale reminders are pruned; already-fired past alarms are dropped by the OS anyway. | | |

### Implementation Phase 5

- **GOAL-005**: Validate the feature end-to-end.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-017 | Run `flutter analyze` with zero new warnings and `flutter test` with all tests passing. | | |
| TASK-018 | Manual Android verification: build and run on a device/emulator; double-tap an upcoming fixture; confirm 15-minute default; set a 15-minute reminder on a fixture kicking off within ~20 minutes; background/kill the app; verify the notification fires near the expected time; double-tap again, choose Off, verify no notification arrives; force-stop the app and reboot the device with a reminder still pending to verify boot re-registration. | | |

## 3. Alternatives

- **ALT-001**: Background polling with `workmanager` (periodic background task
  that checks whether a match is about to start and posts the notification).
  Rejected: heavier (extra dependency, battery), less precise timing, and
  unnecessary given `flutter_local_notifications` supports scheduled
  notifications natively.
- **ALT-002**: Exact alarms (`AndroidScheduleMode.exactAllowWhileIdle` with
  `SCHEDULE_EXACT_ALARM`). Rejected: on Android 12+ this needs an extra
  system-settings permission flow; a football kick-off reminder tolerates
  minute-level inexactness, so CON-002 uses inexact scheduling.
- **ALT-003**: Write to the device calendar instead of app-local
  notifications. Rejected: requires an invasive `READ/WRITE_CALENDAR`
  permission and device-dependent behaviour; overkill for this feature.
- **ALT-004**: Long-press instead of double-tap to open the configuration
  sheet. Rejected per the requested interaction (double-tap); long-press can
  be added later as an accessibility improvement.

## 4. Dependencies

- **DEP-001**: `flutter_local_notifications` 22.3.0 — already a direct
  dependency; provides `zonedSchedule` and the Android boot receiver.
- **DEP-002**: `timezone` — already resolved transitively in `pubspec.lock`;
  promoted to a direct dependency by TASK-001 for `tz.TZDateTime`.
- **DEP-003**: `flutter_timezone` — new direct dependency (TASK-001) to look
  up the device's IANA timezone for correct local scheduling.
- **DEP-004**: `shared_preferences` — already a direct dependency; backs the
  persistent reminder store.
- **DEP-005**: `flutter_riverpod` — already a direct dependency; used for the
  reminders providers per PAT-001.

## 5. Files

- **FILE-001**: `pubspec.yaml` — add `timezone` and `flutter_timezone`
  (TASK-001).
- **FILE-002**: `lib/features/reminders/match_reminder.dart` — new reminder
  model (TASK-002).
- **FILE-003**: `lib/features/reminders/reminder_store.dart` — new
  SharedPreferences-backed store (TASK-003).
- **FILE-004**: `lib/features/reminders/reminders_providers.dart` — new
  Riverpod providers (TASK-004).
- **FILE-005**: `lib/features/reminders/reminder_notification_service.dart` —
  new scheduling service (TASK-007).
- **FILE-006**: `android/app/src/main/AndroidManifest.xml` — add
  `RECEIVE_BOOT_COMPLETED` permission (TASK-008).
- **FILE-007**: `lib/features/fixtures/widgets/fixture_tile.dart` — add
  `onDoubleTap` support (TASK-010).
- **FILE-008**: `lib/features/reminders/reminder_sheet.dart` — new
  configuration sheet (TASK-011).
- **FILE-009**: `lib/features/fixtures/fixtures_view.dart` — wire double-tap
  on upcoming fixtures (TASK-012).
- **FILE-010**: `lib/features/team/team_detail_screen.dart` — wire double-tap
  on next fixtures (TASK-013).
- **FILE-011**: `lib/main.dart` — prune expired reminders at startup
  (TASK-016).
- **FILE-012**: `test/features/reminders/match_reminder_test.dart` — model
  tests (TASK-005).
- **FILE-013**: `test/features/reminders/reminder_store_test.dart` — store
  tests (TASK-006).
- **FILE-014**: `test/features/reminders/reminder_notification_service_test.dart`
  — service tests (TASK-009).
- **FILE-015**: `test/features/reminders/reminder_sheet_test.dart` — sheet
  widget tests (TASK-014).

## 6. Testing

- **TEST-001**: `MatchReminder` model tests: JSON round-trip, default 15-minute
  lead, `notifyAtUtc` computation, `isExpired` boundaries (TASK-005).
- **TEST-002**: `ReminderStore` tests with mocked `SharedPreferences`: upsert
  replaces by fixture id, remove, removeExpired, empty initial load
  (TASK-006).
- **TEST-003**: `ReminderNotificationService` tests with a fake plugin:
  correct scheduled date/id, no scheduling for past kick-offs, cancel targets
  the right id (TASK-009).
- **TEST-004**: `ReminderSheet` widget tests: 15-minute pre-selection, Save
  persists and schedules, "Off" cancels (TASK-014).
- **TEST-005**: Existing suite regression: `flutter analyze` clean and
  `flutter test` fully green, including `test/widget_test.dart` (TASK-017).
- **TEST-006**: Manual on-device scenario matrix from TASK-018 (fire, cancel,
  reboot persistence).

## 7. Risks & Assumptions

- **RISK-001**: Inexact scheduling (CON-002) may fire the notification a few
  minutes late under Doze/battery optimisation. Accepted; kick-off reminders
  tolerate small drift. Exact alarms remain an upgrade path (ALT-002).
- **RISK-002**: `flutter_timezone`'s IANA lookup could fail or return an
  unknown zone on some devices; the `UTC` fallback in TASK-007 plus
  `TZDateTime.from` from a UTC instant keeps notifications correct even if
  the local-zone label is wrong.
- **RISK-003**: Cached fixture kick-off times can change (postponements); the
  scheduled reminder fires at the originally saved time. Mitigation is out of
  scope for v1; users can re-set the reminder after a refresh.
- **RISK-004**: Reboot re-registration depends on the plugin's boot receiver
  and `RECEIVE_BOOT_COMPLETED`; covered by the manual scenario in TASK-018.
- **ASSUMPTION-001**: The existing `Fixture.dateUtc` is reliable for upcoming
  matches in the Fixtures and team "next" lists (free-tier data may be
  limited, but that does not change the reminder mechanics).
- **ASSUMPTION-002**: A single reminder per fixture is sufficient for v1; no
  multiple concurrent leads per match.
- **ASSUMPTION-003**: `RECEIVE_BOOT_COMPLETED` is an acceptable additional
  permission, given the app already posts notifications.

## 8. Related Specifications / Further Reading

- Existing plan: `plan/premium-plan.md` (API tiering context that affects how
  many upcoming fixtures are visible on the free key).
- `lib/features/live/goal_notification_service.dart` — notification wrapper
  pattern reused by this feature (PAT-002).
- https://pub.dev/packages/flutter_local_notifications — scheduling and
  Android configuration (`zonedSchedule`, schedule modes, boot receiver).
- https://pub.dev/packages/flutter_timezone — device timezone lookup.
- https://developer.android.com/develop/background-work/services/alarms —
  Android exact vs inexact alarms.

