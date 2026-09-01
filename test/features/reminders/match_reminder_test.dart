import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/reminders/match_reminder.dart';
import 'package:my_football/models/fixture.dart';

Fixture _fixture({
  required String status,
  DateTime? kickoffUtc,
  bool postponed = false,
}) {
  return Fixture(
    id: 42,
    dateUtc: kickoffUtc ?? DateTime.now().toUtc().add(const Duration(days: 2)),
    statusShort: status,
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
    postponed: postponed,
  );
}

MatchReminder _reminder({required DateTime kickoffUtc, int lead = 15}) {
  return MatchReminder(
    fixtureId: 42,
    kickoffUtc: kickoffUtc,
    homeName: 'Arsenal',
    awayName: 'Chelsea',
    leadMinutes: lead,
  );
}

void main() {
  test('defaults are 15 minutes and the allowed options match the plan', () {
    expect(MatchReminder.defaultLeadMinutes, 15);
    expect(MatchReminder.allowedLeadMinutes, [15, 30, 60, 120]);
  });

  test('notifyAtUtc subtracts the lead time from kick-off', () {
    final kickoff = DateTime.utc(2026, 9, 5, 15);
    final reminder = _reminder(kickoffUtc: kickoff, lead: 15);

    expect(reminder.notifyAtUtc, DateTime.utc(2026, 9, 5, 14, 45));
  });

  test('JSON round-trips all fields and keeps kick-off in UTC', () {
    final kickoff = DateTime.utc(2026, 9, 5, 15);
    final reminder = _reminder(kickoffUtc: kickoff, lead: 60);

    final restored = MatchReminder.fromJson(reminder.toJson());

    expect(restored.fixtureId, 42);
    expect(restored.kickoffUtc, kickoff);
    expect(restored.kickoffUtc.isUtc, isTrue);
    expect(restored.homeName, 'Arsenal');
    expect(restored.awayName, 'Chelsea');
    expect(restored.leadMinutes, 60);
    expect(restored.notifyAtUtc, reminder.notifyAtUtc);
  });

  test('isExpired is true after kick-off and false before', () {
    final past = _reminder(
      kickoffUtc: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
    );
    final future = _reminder(
      kickoffUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );

    expect(past.isExpired, isTrue);
    expect(future.isExpired, isFalse);
  });

  group('canRemind', () {
    test('allows a not-started future match', () {
      expect(MatchReminder.canRemind(_fixture(status: 'NS')), isTrue);
    });

    test('rejects a finished match', () {
      expect(MatchReminder.canRemind(_fixture(status: 'FT')), isFalse);
    });

    test('rejects a live match', () {
      expect(MatchReminder.canRemind(_fixture(status: '2H')), isFalse);
    });

    test('rejects a postponed match even if kick-off is in the future', () {
      expect(
        MatchReminder.canRemind(_fixture(status: 'NS', postponed: true)),
        isFalse,
      );
    });

    test('rejects a match whose kick-off has passed', () {
      expect(
        MatchReminder.canRemind(
          _fixture(
            status: 'NS',
            kickoffUtc: DateTime.now().toUtc().subtract(
              const Duration(hours: 1),
            ),
          ),
        ),
        isFalse,
      );
    });
  });
}
