import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/reminders/match_reminder.dart';
import 'package:my_football/features/reminders/reminder_notification_service.dart';
import 'package:my_football/features/reminders/reminder_sheet.dart';
import 'package:my_football/features/reminders/reminder_store.dart';
import 'package:my_football/features/reminders/reminders_providers.dart';
import 'package:my_football/models/fixture.dart';
import 'package:my_football/providers/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records schedule/cancel calls instead of touching the OS.
class _FakeNotifications extends ReminderNotificationService {
  final scheduled = <MatchReminder>[];
  final cancelled = <int>[];
  bool allowed = true;

  @override
  Future<bool> ensureReady() async => allowed;

  @override
  Future<void> schedule(MatchReminder reminder) async =>
      scheduled.add(reminder);

  @override
  Future<void> cancel(int fixtureId) async => cancelled.add(fixtureId);
}

Fixture _upcoming() {
  return Fixture(
    id: 42,
    dateUtc: DateTime.now().toUtc().add(const Duration(days: 2)),
    statusShort: 'NS',
    statusLong: '',
    elapsed: null,
    homeId: 1,
    homeName: 'Arsenal',
    homeLogo: '',
    awayId: 2,
    awayName: 'Chelsea',
    awayLogo: '',
    homeGoals: null,
    awayGoals: null,
  );
}

Widget _host(Fixture fixture, _FakeNotifications notifications,
    SharedPreferences prefs) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      reminderNotificationServiceProvider.overrideWithValue(notifications),
    ],
    child: MaterialApp(
      home: Consumer(
        builder: (context, ref, _) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showReminderSheet(context, ref, fixture),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<ListTile> tileOf(WidgetTester tester, String label) async {
  await tester.pump();
  return tester.widget<ListTile>(
    find.ancestor(of: find.text(label), matching: find.byType(ListTile)).first,
  );
}

void main() {
  testWidgets('pre-selects 15 minutes by default and saves it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final notifications = _FakeNotifications();
    final fixture = _upcoming();

    await tester.pumpWidget(_host(fixture, notifications, prefs));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final fifteen = await tileOf(tester, '15 min before');
    expect((fifteen.leading as Icon).icon, Icons.radio_button_checked);
    final off = await tileOf(tester, 'Off');
    expect((off.leading as Icon).icon, Icons.radio_button_unchecked);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(notifications.scheduled, hasLength(1));
    expect(notifications.scheduled.single.fixtureId, 42);
    expect(notifications.scheduled.single.leadMinutes, 15);
    expect(notifications.cancelled, isEmpty);

    // The choice is persisted.
    final store = ReminderStore(prefs);
    final all = await store.load();
    expect(all.single.fixtureId, 42);
    expect(all.single.leadMinutes, 15);
  });

  testWidgets('choosing Off cancels a stored reminder and removes it',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final notifications = _FakeNotifications();
    final fixture = _upcoming();

    // Seed a stored reminder so the sheet starts with it selected.
    final store = ReminderStore(prefs);
    await store.upsert(
      MatchReminder(
        fixtureId: 42,
        kickoffUtc: fixture.dateUtc,
        homeName: fixture.homeName,
        awayName: fixture.awayName,
        leadMinutes: 30,
      ),
    );

    await tester.pumpWidget(_host(fixture, notifications, prefs));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final thirty = await tileOf(tester, '30 min before');
    expect((thirty.leading as Icon).icon, Icons.radio_button_checked);

    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(notifications.cancelled, [42]);
    expect(notifications.scheduled, isEmpty);
    expect(await store.load(), isEmpty);
  });
}
