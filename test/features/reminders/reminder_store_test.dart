import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/reminders/match_reminder.dart';
import 'package:my_football/features/reminders/reminder_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

MatchReminder _reminder({
  required int fixtureId,
  required DateTime kickoffUtc,
  int lead = 15,
}) {
  return MatchReminder(
    fixtureId: fixtureId,
    kickoffUtc: kickoffUtc,
    homeName: 'Arsenal',
    awayName: 'Chelsea',
    leadMinutes: lead,
  );
}

void main() {
  late SharedPreferences prefs;
  late ReminderStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = ReminderStore(prefs);
  });

  final kickoff = DateTime.utc(2026, 9, 5, 15);

  test('load returns an empty list on fresh storage', () async {
    expect(await store.load(), isEmpty);
  });

  test('upsert inserts a reminder', () async {
    await store.upsert(_reminder(fixtureId: 1, kickoffUtc: kickoff));

    final all = await store.load();
    expect(all, hasLength(1));
    expect(all.single.fixtureId, 1);
  });

  test('upsert replaces by fixture id instead of duplicating', () async {
    await store.upsert(_reminder(fixtureId: 1, kickoffUtc: kickoff));
    await store.upsert(
      _reminder(fixtureId: 1, kickoffUtc: kickoff, lead: 60),
    );
    await store.upsert(_reminder(fixtureId: 2, kickoffUtc: kickoff));

    final all = await store.load();
    expect(all, hasLength(2));
    expect(
      ReminderStore.forFixture(all, 1)?.leadMinutes,
      60,
      reason: 'the newer lead time must win',
    );
  });

  test('remove deletes only the matching fixture', () async {
    await store.upsert(_reminder(fixtureId: 1, kickoffUtc: kickoff));
    await store.upsert(_reminder(fixtureId: 2, kickoffUtc: kickoff));

    await store.remove(1);

    final all = await store.load();
    expect(all, hasLength(1));
    expect(all.single.fixtureId, 2);
  });

  test('remove is a no-op for an unknown fixture', () async {
    await store.upsert(_reminder(fixtureId: 1, kickoffUtc: kickoff));

    await store.remove(99);

    expect(await store.load(), hasLength(1));
  });

  test('removeExpired keeps only future kick-offs', () async {
    final past = _reminder(
      fixtureId: 1,
      kickoffUtc: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
    );
    final future = _reminder(fixtureId: 2, kickoffUtc: kickoff);
    await store.upsert(past);
    await store.upsert(future);

    await store.removeExpired();

    final all = await store.load();
    expect(all.map((r) => r.fixtureId), [2]);
  });

  test('forFixture returns null when the fixture has no reminder', () {
    final list = [_reminder(fixtureId: 1, kickoffUtc: kickoff)];

    expect(ReminderStore.forFixture(list, 1)?.leadMinutes, 15);
    expect(ReminderStore.forFixture(list, 2), isNull);
  });
}
