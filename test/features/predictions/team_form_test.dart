import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/predictions/team_form.dart';
import 'package:my_football/models/fixture.dart';

Fixture _event({
  required int id,
  required DateTime dateUtc,
  required int homeId,
  required int awayId,
  int? homeGoals,
  int? awayGoals,
  String status = 'Match Finished',
}) {
  return Fixture(
    id: id,
    dateUtc: dateUtc,
    statusShort: status,
    statusLong: '',
    elapsed: null,
    homeId: homeId,
    homeName: 'Home $homeId',
    homeLogo: '',
    awayId: awayId,
    awayName: 'Away $awayId',
    awayLogo: '',
    homeGoals: homeGoals,
    awayGoals: awayGoals,
  );
}

void main() {
  group('standingsFormOrder', () {
    test('stays unknown until TASK-019 confirms the strForm letter order', () {
      // Pinned on purpose: TASK-019 must record evidence in the plan before
      // this value changes, and this test must be updated in the same
      // change. A wrong order silently reverses the form curve (RISK-006).
      expect(standingsFormOrder, FormOrder.unknown);
    });
  });

  group('recentForm', () {
    const team = 1;

    test('returns W/D/L newest first from finished fixtures with a score', () {
      final events = [
        _event(
          id: 1,
          dateUtc: DateTime.utc(2025, 8, 1),
          homeId: team,
          awayId: 2,
          homeGoals: 2,
          awayGoals: 0,
        ),
        _event(
          id: 2,
          dateUtc: DateTime.utc(2025, 8, 8),
          homeId: 3,
          awayId: team,
          homeGoals: 1,
          awayGoals: 1,
        ),
        _event(
          id: 3,
          dateUtc: DateTime.utc(2025, 8, 15),
          homeId: team,
          awayId: 4,
          homeGoals: 0,
          awayGoals: 3,
        ),
      ];
      expect(recentForm(team, events), ['L', 'D', 'W']);
    });

    test('ignores unfinished fixtures and finished ones without a score', () {
      final events = [
        _event(
          id: 1,
          dateUtc: DateTime.utc(2025, 8, 1),
          homeId: team,
          awayId: 2,
          homeGoals: 1,
          awayGoals: 0,
        ),
        _event(
          id: 2,
          dateUtc: DateTime.utc(2025, 8, 8),
          homeId: team,
          awayId: 3,
          status: 'NS',
        ),
        _event(
          id: 3,
          dateUtc: DateTime.utc(2025, 8, 15),
          homeId: team,
          awayId: 4,
          status: 'PPD',
          homeGoals: null,
          awayGoals: null,
        ),
        _event(
          id: 4,
          dateUtc: DateTime.utc(2025, 8, 22),
          homeId: 5,
          awayId: team,
          homeGoals: 2,
          awayGoals: 1,
        ),
      ];
      expect(recentForm(team, events), ['L', 'W']);
    });

    test('applies the limit to the newest matches', () {
      final events = [
        for (var i = 0; i < 7; i++)
          _event(
            id: i + 1,
            dateUtc: DateTime.utc(2025, 8, i + 1),
            homeId: team,
            awayId: 100 + i,
            homeGoals: 1,
            awayGoals: 0,
          ),
      ];
      final form = recentForm(team, events);
      expect(form, ['W', 'W', 'W', 'W', 'W']);
      // Newest five means fixtures 3..7 are used; verify by mixing results.
      final mixed = [
        for (var i = 0; i < 7; i++)
          _event(
            id: i + 1,
            dateUtc: DateTime.utc(2025, 8, i + 1),
            homeId: team,
            awayId: 100 + i,
            homeGoals: i < 3 ? 0 : 1,
            awayGoals: i < 3 ? 2 : 0,
          ),
      ];
      // Newest five only: fixtures 3-7 → W W W W L (the two oldest losses
      // are dropped).
      expect(recentForm(team, mixed), ['W', 'W', 'W', 'W', 'L']);
    });

    test('excludes matches at or after the cutoff (strict before, UTC)', () {
      final kickoff = DateTime.utc(2025, 8, 15, 14);
      final events = [
        _event(
          id: 1,
          dateUtc: DateTime.utc(2025, 8, 1),
          homeId: team,
          awayId: 2,
          homeGoals: 1,
          awayGoals: 0,
        ),
        // Kicks off exactly at the cutoff: must be excluded.
        _event(
          id: 2,
          dateUtc: kickoff,
          homeId: team,
          awayId: 3,
          homeGoals: 5,
          awayGoals: 0,
        ),
        _event(
          id: 3,
          dateUtc: DateTime.utc(2025, 8, 20),
          homeId: team,
          awayId: 4,
          homeGoals: 5,
          awayGoals: 0,
        ),
      ];
      expect(recentForm(team, events, before: kickoff), ['W']);
    });

    test('breaks date ties by fixture id, newest first', () {
      final sameDay = DateTime.utc(2025, 8, 10, 12);
      final events = [
        _event(
          id: 7,
          dateUtc: sameDay,
          homeId: team,
          awayId: 2,
          homeGoals: 1,
          awayGoals: 1,
        ),
        _event(
          id: 3,
          dateUtc: sameDay,
          homeId: team,
          awayId: 3,
          homeGoals: 2,
          awayGoals: 0,
        ),
      ];
      expect(recentForm(team, events), ['D', 'W']);
    });

    test('includes matches strictly before a later cutoff instant', () {
      final events = [
        _event(
          id: 1,
          dateUtc: DateTime.utc(2025, 8, 14, 14),
          homeId: team,
          awayId: 2,
          homeGoals: 1,
          awayGoals: 0,
        ),
        _event(
          id: 2,
          dateUtc: DateTime.utc(2025, 8, 15, 14),
          homeId: team,
          awayId: 3,
          homeGoals: 0,
          awayGoals: 1,
        ),
      ];
      // 2025-08-15T16:00Z is after both kick-offs: both count.
      final cutoff = DateTime.utc(2025, 8, 15, 16);
      expect(recentForm(team, events, before: cutoff), ['L', 'W']);
    });
  });

  group('parseStandingForm', () {
    test('accepts plain and lowercase W/D/L runs', () {
      expect(parseStandingForm('WWDWW')!.results, ['W', 'W', 'D', 'W', 'W']);
      expect(parseStandingForm('wdl')!.results, ['W', 'D', 'L']);
    });

    test('ignores other characters inside the value', () {
      expect(parseStandingForm('W, D, L')!.results, ['W', 'D', 'L']);
      expect(parseStandingForm('W1D2L3')!.results, ['W', 'D', 'L']);
    });

    test('rejects empty and over-long values', () {
      expect(parseStandingForm(''), isNull);
      expect(parseStandingForm('   '), isNull);
      expect(parseStandingForm('---'), isNull);
      expect(parseStandingForm('WWWWWDL'), isNull); // 7 letters
    });

    test('reports unordered while standingsFormOrder is unknown', () {
      final parsed = parseStandingForm('WDL');
      expect(parsed, isNotNull);
      expect(parsed!.ordered, isFalse);
      expect(parsed.results, ['W', 'D', 'L']); // returned as they appear
    });
  });

  group('currentStreak', () {
    test('returns the leading run when it is at least 2', () {
      expect(currentStreak(['W', 'W', 'W', 'L', 'L']), 3);
      expect(currentStreak(['L', 'L']), 2);
      expect(currentStreak(['D', 'D', 'W']), 2);
    });

    test('returns 0 for runs shorter than 2 and for empty lists', () {
      expect(currentStreak(['W', 'D', 'W']), 0);
      expect(currentStreak(['W']), 0);
      expect(currentStreak([]), 0);
    });
  });
}
