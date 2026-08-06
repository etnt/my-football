import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/models/fixture.dart';

Fixture _finished({
  required int homeId,
  required int awayId,
  required int homeGoals,
  required int awayGoals,
}) {
  return Fixture.fromJson({
    'idEvent': '1',
    'strTimestamp': '2023-08-11T19:00:00',
    'strStatus': 'FT',
    'idHomeTeam': '$homeId',
    'strHomeTeam': 'Home',
    'strHomeTeamBadge': '',
    'idAwayTeam': '$awayId',
    'strAwayTeam': 'Away',
    'strAwayTeamBadge': '',
    'intHomeScore': '$homeGoals',
    'intAwayScore': '$awayGoals',
  });
}

void main() {
  group('Fixture.resultFor', () {
    test('win/draw/loss from the home team perspective', () {
      final win = _finished(homeId: 10, awayId: 20, homeGoals: 2, awayGoals: 0);
      final draw = _finished(homeId: 10, awayId: 20, homeGoals: 1, awayGoals: 1);
      final loss = _finished(homeId: 10, awayId: 20, homeGoals: 0, awayGoals: 3);

      expect(win.resultFor(10), 'W');
      expect(draw.resultFor(10), 'D');
      expect(loss.resultFor(10), 'L');
    });

    test('is inverted for the away team', () {
      final f = _finished(homeId: 10, awayId: 20, homeGoals: 2, awayGoals: 0);

      expect(f.resultFor(20), 'L');
    });

    test('returns null for unfinished matches', () {
      final upcoming = Fixture.fromJson({
        'idEvent': '2',
        'strTimestamp': '2023-08-19T14:00:00',
        'strStatus': 'NS',
        'idHomeTeam': '10',
        'strHomeTeam': 'Home',
        'idAwayTeam': '20',
        'strAwayTeam': 'Away',
        'intHomeScore': null,
        'intAwayScore': null,
      });

      expect(upcoming.isFinished, isFalse);
      expect(upcoming.resultFor(10), isNull);
    });

    test('parses the UTC timestamp without a zone suffix', () {
      final f = _finished(homeId: 10, awayId: 20, homeGoals: 1, awayGoals: 0);

      expect(f.dateUtc.isUtc, isTrue);
      expect(f.dateUtc, DateTime.utc(2023, 8, 11, 19));
    });

    test('survives a cache round-trip', () {
      final original =
          _finished(homeId: 10, awayId: 20, homeGoals: 3, awayGoals: 1);
      final restored = Fixture.fromJson(original.toJson());

      expect(restored.homeId, 10);
      expect(restored.awayId, 20);
      expect(restored.resultFor(10), 'W');
    });
  });

  group('Fixture.fromV2Json', () {
    test('maps the livescore payload including progress', () {
      final f = Fixture.fromV2Json({
        'idEvent': '500',
        'strTimestamp': '2026-08-06T19:00:00',
        'strStatus': '2H',
        'strProgress': '67',
        'idHomeTeam': '40',
        'strHomeTeam': 'Arsenal',
        'strHomeTeamBadge': 'a.png',
        'idAwayTeam': '34',
        'strAwayTeam': 'Chelsea',
        'strAwayTeamBadge': 'c.png',
        'intHomeScore': '1',
        'intAwayScore': '0',
      });

      expect(f.id, 500);
      expect(f.homeName, 'Arsenal');
      expect(f.awayName, 'Chelsea');
      expect(f.homeLogo, 'a.png');
      expect(f.homeGoals, 1);
      expect(f.awayGoals, 0);
      expect(f.progress, '67');
      expect(f.hasScore, isTrue);
      expect(f.dateUtc.isUtc, isTrue);
    });
  });

  group('Fixture round', () {
    test('parses intRound and survives a cache round-trip', () {
      final f = Fixture.fromJson({
        'idEvent': '900',
        'strTimestamp': '2026-05-24T15:00:00',
        'strStatus': 'FT',
        'idHomeTeam': '10',
        'strHomeTeam': 'Home',
        'idAwayTeam': '20',
        'strAwayTeam': 'Away',
        'intHomeScore': '2',
        'intAwayScore': '1',
        'intRound': '38',
      });

      expect(f.round, 38);
      expect(Fixture.fromJson(f.toJson()).round, 38);
    });

    test('leaves round null when absent', () {
      final f = Fixture.fromJson({
        'idEvent': '901',
        'strTimestamp': '2026-05-24T15:00:00',
        'strStatus': 'NS',
        'idHomeTeam': '10',
        'strHomeTeam': 'Home',
        'idAwayTeam': '20',
        'strAwayTeam': 'Away',
        'intHomeScore': null,
        'intAwayScore': null,
      });

      expect(f.round, isNull);
    });
  });
}


